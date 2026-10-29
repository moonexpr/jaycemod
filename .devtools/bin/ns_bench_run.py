#!/usr/bin/env python3
"""Run a navigation bench: its errands, on its map, on a leased server.

A bench map (ns_bench_map.py builds them) holds geometry soldiers fail on.
This runner leases a server on it from the instance manager (instances.py),
which starts, reuses or changes the map of a server as it must, and runs
the bench's errands, each a walk from a start to a goal in a time:

- follower: an npc_pathfollower (NextSoldier's base, no fighting) sent on
  the errand; its own report (failures, recoveries, nudges, marks).
- bot: a bot soldier of the AI war, made unhurtable, set down at the start
  and pinned to the goal (BotSoldier:Pin); sampled every SAMPLE seconds:
  where it is, its speed, its route (RouteWalk's waypoint of how many), the
  point it steers for, and whether its body is stuck. The samples are what
  a stall is told apart by.

A bench map has no nav mesh until the server generates one (the
gamemode's mp_nav_generate, which saves maps/<bench>.nav); the runner has
it generated when the map has none, and waits while it is. The report (every errand's result and samples) is written to
.devtools/artifacts/benches/<bench>/<time>.json and summed up on stdout.

    python3 .devtools/bin/ns_bench_run.py dev_watchtower_ns_locomotion [--kind follower|bot|both]
        [--errand NAME] [--keep-running] [--reload] [--regenerate-nav] [--instance N ...]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import instances
import server_lua
from server_root import Instance

REPO = Path(__file__).resolve().parents[2]
REPORTS = REPO / ".devtools" / "artifacts" / "benches"
OWNER = "ns_bench_run"
ARRIVE = 64  # a bot within this of its goal has arrived (npc_pathfollower's own is 48)
SAMPLE = 0.5  # seconds between a bot's samples
NAV_TIMEOUT = 900  # nav_generate on a bench map
BOT_TIMEOUT = 90  # until the war has a bot soldier
SETTLE_FOR = 3  # seconds the war stays ready before the bot errands begin
HARNESS = "dev.harness"  # saved beside the convars: whether it was on, and suppressing wins
# convar -> its value while the bench runs: the war's soldiers are bots, one a
# team (a team left empty restarts the round), joining with no human on; the
# server never idles
CONVARS = {"tf_bot_join_after_player": "0", "sv_idle_delay": "86400", "ns_soldiers_actor": "bot", "tf_bot_quota": "2"}

Vec = Tuple[float, float, float]


@dataclass(frozen=True)
class Errand:
    name: str
    start: Vec
    goal: Vec
    seconds: float


# arena_watchtower's errands: up the log ramps to the health pack on each
# side's pipe, and from the west pipe across to the point by the stairway.
# dev_watchtower_ns_locomotion keeps the map's coordinates, so the same
# errands run on the bench and on the map itself (its own mesh).
WATCHTOWER = (
    Errand("west pack, up the logs", (-1213, 13, 16), (-1250, 8, 832), 60),
    Errand("east pack, up the logs", (1212, 12, 24), (1238, -16, 816), 60),
    Errand("west pipe to the point", (-1250, 8, 848), (-2, 1, 760), 45),
)
# cp_sunshine's errands, the pathfinder's bench (operator, 2026-10-29): plain
# geometry a body of the right hull walks without trouble. Area 425, the
# corner outside RED's spawn on the way to its second point, is where bots
# stuck and the hazards disabled a valid area while their walks were swept 26
# wide for a 48-wide body. Each team's ways out, and the long ways to the middle.
SUNSHINE = (
    Errand("round the corner at area 425", (-2800, 2387, -63), (-2950, 2650, -63), 20),
    Errand("RED spawn to its second point", (-3529, 2693, -44), (-3560, 3672, 132), 45),
    Errand("RED spawn to the middle point", (-3529, 2693, -44), (-5632, 5248, 68), 90),
    Errand("BLU spawn to its second point", (-7731, 7795, -44), (-7704, 6824, 132), 45),
    Errand("BLU spawn to the middle point", (-7731, 7795, -44), (-5632, 5248, 68), 90),
)
BENCHES = {
    "dev_watchtower_ns_locomotion": WATCHTOWER,
    "arena_watchtower": WATCHTOWER,
    "cp_sunshine": SUNSHINE,
}
def vector(p: Vec) -> str:
    return "Vector(%g, %g, %g)" % p


def returned(reply: server_lua.Reply) -> object:
    return json.loads(reply.returns[0]) if reply.returns and reply.returns[0] not in ("", "nil") else None


# Lua --------------------------------------------------------------------------------

NAV_AREAS = "return navmesh.IsLoaded() and navmesh.GetNavAreaCount() or 0"

SEND_FOLLOWER = """
NSBench = NSBench or {}
hook.Add("NSPathFollowerDone", "ns_bench_run", function(follower, report)
	NSBench[follower.nsBenchKey or ""] = util.TableToJSON(report)
end)
local follower = ents.Create("npc_pathfollower")
follower:SetPos(%(start)s)
follower:Spawn()
follower.nsBenchKey = %(key)s
NSBench[%(key)s] = false
follower:NSErrand(%(goal)s, %(seconds)g)
return follower:EntIndex()
"""

FOLLOWER_REPORT = "return NSBench and NSBench[%(key)s] or ''"

# The bench's bot is kept by its entity (NSBenchBot); its soldier is asked of
# the war each time, as a new round enlists every bot afresh.
BENCH_BOT = """
local function BenchBot()
	local ent = NSBenchBot
	local entry = IsValid(ent) and WS.Feature("aiwar").soldiers[ent]
	return ent, entry and entry.soldier
end
"""

# One bot soldier for the errands; every other made unhurtable and pinned
# where it stands, so no one fights, falls or wins a round meanwhile.
FIND_BOT = BENCH_BOT + """
local chosen = BenchBot()
chosen = IsValid(chosen) and chosen:Alive() and chosen or nil
for ent, entry in pairs(WS.Feature("aiwar").soldiers or {}) do
	if IsValid(ent) and ent:IsPlayer() and ent:Alive() and entry.soldier.Pin then
		if not chosen then
			chosen = ent
		elseif ent ~= chosen then
			ent:GodEnable()
			local pos = ent:GetPos()
			entry.soldier:Pin({ x = pos.x, y = pos.y, z = pos.z })
		end
	end
end
NSBenchBot = chosen
return chosen and chosen:Nick() or ''
"""

# Whether the war is ready for errands: a round running, every bot soldier
# the quota asks for alive.
SETTLED = """
local alive = 0
for ent in pairs(WS.Feature("aiwar").soldiers or {}) do
	if IsValid(ent) and ent:IsPlayer() and ent:Alive() then alive = alive + 1 end
end
return tostring(WS.State() == %(running)d and alive >= GetConVarNumber("tf_bot_quota"))
"""
ROUND_RUNNING = 4  # gamerules_roundstate_t's GR_STATE_RND_RUNNING (games.gameplay.rounds.state)

# Every bot soldier unpinned and hurtable again.
RELEASE_ALL = """
for ent, entry in pairs(WS.Feature("aiwar").soldiers or {}) do
	if IsValid(ent) and ent:IsPlayer() and entry.soldier.Unpin then
		entry.soldier:Unpin()
		ent:GodDisable()
	end
end
NSBenchBot = nil
return true
"""

SEND_BOT = BENCH_BOT + """
local bot, soldier = BenchBot()
bot:GodEnable()
bot:SetPos(%(start)s)
bot:SetVelocity(-bot:GetVelocity())
soldier:Pin({ x = %(gx)g, y = %(gy)g, z = %(gz)g })
return true
"""

SAMPLE_BOT = BENCH_BOT + """
local bot, soldier = BenchBot()
if not (IsValid(bot) and bot:Alive() and soldier) then
	return util.TableToJSON({ gone = true, why = not IsValid(bot) and "left" or (bot:Alive() and "unenlisted" or "died") })
end
local pos, walk, steer, body = bot:GetPos(), soldier.walk, soldier.steer, soldier.body
local function P(v) return v and { math.Round(v.x), math.Round(v.y), math.Round(v.z) } end
return util.TableToJSON({
	pos = P(pos),
	speed = math.Round(bot:GetVelocity():Length2D()),
	ground = bot:IsOnGround(),
	crouch = bot:Crouching(),
	waypoint = walk and walk.index or nil,
	waypoints = walk and #walk.points or nil,
	done = walk and walk:Done() or nil,
	steer = steer and { math.Round(steer.x), math.Round(steer.y), math.Round(steer.z) } or nil,
	stuck = body and body.stuckSince ~= nil or false,
	area = (function() local area = navmesh.GetNearestNavArea(pos, false, 64) return area and area:GetID() or nil end)(),
	planned = soldier.planned ~= nil,
	pinned = soldier.pin ~= nil,
	round = WS.State(),
	enemy = (function() local e = soldier.vision:Contact() return IsValid(e) and e:EntIndex() or nil end)(),
	distance = math.Round(pos:Distance(%(goal)s)),
})
"""

RELEASE_BOT = BENCH_BOT + """
local bot, soldier = BenchBot()
if IsValid(bot) then
	if soldier then soldier:Unpin() end
	bot:GodDisable()
end
return true
"""


# The errands ------------------------------------------------------------------------


async def ensure_nav(server: instances.GameServer) -> int:
    """The map's nav area count, having the server generate a mesh when it has none."""
    areas = int((await server.lua(NAV_AREAS)).returns[0])
    if areas:
        return areas
    print("no nav mesh: mp_nav_generate (a few minutes)")
    # the gamemode's, which starts none while one is under way (ws/sv_nav.lua); a
    # console command run from Lua returns at once, where RCON waits on the busy server
    await server.lua('RunConsoleCommand("mp_nav_generate") return true')
    deadline = time.monotonic() + NAV_TIMEOUT
    while time.monotonic() < deadline:
        await asyncio.sleep(5)
        try:
            areas = int((await server.lua(NAV_AREAS, timeout=5)).returns[0])
        except (server_lua.BridgeDown, server_lua.NoReply, OSError):
            continue  # generating, or the map reloading
        if areas:
            return areas
    raise instances.NoInstance(f"nav_generate made no mesh in {NAV_TIMEOUT} s")


async def run_follower(server: instances.GameServer, errand: Errand) -> dict:
    key = json.dumps(errand.name)
    await server.lua(SEND_FOLLOWER % {"start": vector(errand.start), "goal": vector(errand.goal),
                                      "seconds": errand.seconds, "key": key})
    deadline = time.monotonic() + errand.seconds + 15
    while time.monotonic() < deadline:
        await asyncio.sleep(1)
        report = returned(await server.lua(FOLLOWER_REPORT % {"key": key}))
        if report:
            return report
    return {"status": "no report", "seconds": errand.seconds}


async def run_bot(server: instances.GameServer, errand: Errand) -> dict:
    gx, gy, gz = errand.goal
    await server.lua(SEND_BOT % {"start": vector(errand.start), "gx": gx, "gy": gy, "gz": gz})
    began = time.monotonic()
    samples: List[dict] = []
    nearest, status = None, "timed out"
    try:
        while time.monotonic() - began < errand.seconds:
            await asyncio.sleep(SAMPLE)
            sample = returned(await server.lua(SAMPLE_BOT % {"goal": vector(errand.goal)}))
            if sample.get("gone"):
                status = f"bot {sample['why']}"
                break
            sample["at"] = round(time.monotonic() - began, 1)
            samples.append(sample)
            nearest = sample["distance"] if nearest is None else min(nearest, sample["distance"])
            if sample["distance"] <= ARRIVE:
                status = "arrived"
                break
    finally:
        await server.lua(RELEASE_BOT)
    return {"status": status, "seconds": round(time.monotonic() - began, 1), "nearest": nearest,
            "stalls": stalls(samples), "samples": samples}


def stalls(samples: List[dict], slow: float = 20, least: int = 4) -> List[dict]:
    """Runs of at least `least` samples under `slow` speed: where, how long, and
    what the bot's own state said (no route, route done, stuck body, airborne)."""
    runs, run = [], []
    for sample in samples + [{"speed": slow}]:
        if sample["speed"] < slow:
            run.append(sample)
            continue
        if len(run) >= least:
            first, last = run[0], run[-1]
            runs.append({
                "from": first["at"], "to": last["at"], "pos": first["pos"],
                "route": "none" if first.get("waypoints") is None else
                         ("done" if first.get("done") else f"{first['waypoint']}/{first['waypoints']}"),
                "steer": first.get("steer"),
                "stuck": any(s.get("stuck") for s in run),
                "airborne": not all(s.get("ground") for s in run),
            })
        run = []
    return runs


async def setup(server: instances.GameServer) -> dict:
    """The bench's settings, and what they were. Rounds are not won while it
    runs (the gamerules harness drops every win): a round won ends the
    errand's round, and a match won reloads the map."""
    saved = {}
    for name, value in CONVARS.items():
        saved[name] = (await server.lua(f"return GetConVarString({json.dumps(name)})")).returns[0]
        await server.rcon(f"{name} {value}")
    harness = returned(await server.lua("return util.TableToJSON(dev.harness.status())"))
    saved[HARNESS] = (harness["on"], harness["suppress_wins"])
    await server.lua("dev.harness.enable(true) dev.harness.suppress_wins(true) return true")
    return saved


async def teardown(server: instances.GameServer, saved: dict) -> None:
    on, suppress = saved.pop(HARNESS)
    await server.lua(f"dev.harness.suppress_wins({str(suppress).lower()}) dev.harness.enable({str(on).lower()}) return true")
    for convar, value in saved.items():
        await server.rcon(f"{convar} {value}")


async def settle(server: instances.GameServer) -> bool:
    """Puts the round running and waits until the war is ready for errands
    (SETTLED) for SETTLE_FOR seconds running: the round running, every bot
    enlisted."""
    if (await server.lua("return WS.Feature('aiwar').war ~= nil")).returns[0] != "true":
        await server.rcon("mp_aiwar_start")
    # the round put running as a restore does (no pre-round freeze): one left
    # won or stalemated (arena stalemates again after a restart) never runs again
    await server.lua(f"dev.harness.set_round_state({ROUND_RUNNING}) return true")
    deadline, since = time.monotonic() + BOT_TIMEOUT, None
    while time.monotonic() < deadline:
        ready = (await server.lua(SETTLED % {"running": ROUND_RUNNING})).returns[0] == "true"
        now = time.monotonic()
        since = (since or now) if ready else None
        if since is not None and now - since >= SETTLE_FOR:
            return True
        await asyncio.sleep(1)
    return False


async def find_bot(server: instances.GameServer) -> Optional[str]:
    deadline = time.monotonic() + BOT_TIMEOUT
    while time.monotonic() < deadline:
        name = (await server.lua(FIND_BOT)).returns[0]
        if name:
            return name
        await asyncio.sleep(2)
    return None


async def bench(name: str, kinds: List[str], only: Optional[str], pool: instances.InstanceManager,
                keep_running: bool, regenerate_nav: bool = False, reload: bool = False) -> dict:
    errands = [e for e in BENCHES[name] if only is None or e.name == only]
    report = {"bench": name, "started": time.strftime("%Y-%m-%dT%H:%M:%S"), "errands": []}
    async with pool.lease(name, OWNER, keep_running=keep_running) as server:
        report["instance"] = server.instance.number
        if reload or regenerate_nav:
            await server.change_map(name)  # the gamemode's Lua loaded afresh
        if regenerate_nav:
            await server.lua("navmesh.Reset() return true")
        report["nav_areas"] = await ensure_nav(server)
        saved = await setup(server)
        try:
            if "follower" in kinds:
                for errand in errands:
                    result = await run_follower(server, errand)
                    report["errands"].append({"kind": "follower", "errand": asdict(errand), "result": result})
            if "bot" in kinds:
                report["settled"] = await settle(server)
                for errand in errands:
                    bot = await find_bot(server)  # afresh: one may fall between errands
                    result = await run_bot(server, errand) if bot else {"status": "no bot soldier"}
                    report["errands"].append({"kind": "bot", "bot": bot, "errand": asdict(errand), "result": result})
                await server.lua(RELEASE_ALL)
        finally:
            await teardown(server, saved)
    return report


def summary(report: dict) -> str:
    lines = [f"{report['bench']} on instance {report['instance']}, {report['nav_areas']} nav areas"]
    for entry in report["errands"]:
        result = entry["result"]
        line = f"  {entry['kind']:8} {entry['errand']['name']:28} {result['status']:12} {result.get('seconds', '')} s"
        if "nearest" in result:
            line += f", nearest {result['nearest']}"
        for kind in ("failures", "recoveries", "nudges"):
            if result.get(kind):
                line += f", {len(result[kind])} {kind}"
        for stall in result.get("stalls", []):
            line += f"\n{'':40}stalled {stall['from']}-{stall['to']} s at {stall['pos']}: route {stall['route']}" \
                    f"{', body stuck' if stall['stuck'] else ''}{', airborne' if stall['airborne'] else ''}"
        lines.append(line)
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("bench", choices=sorted(BENCHES))
    parser.add_argument("--kind", choices=("follower", "bot", "both"), default="both")
    parser.add_argument("--errand", help="one errand's name, else every one")
    parser.add_argument("--keep-running", action="store_true", help="leave a server this run started running")
    parser.add_argument("--reload", action="store_true", help="reload the map (and the gamemode's Lua) first")
    parser.add_argument("--regenerate-nav", action="store_true",
                        help="reload the map (and the gamemode's Lua), drop its mesh and generate a new one")
    parser.add_argument("--instance", type=int, nargs="+", default=[1], help="the instances the run may lease")
    args = parser.parse_args()
    kinds = ["follower", "bot"] if args.kind == "both" else [args.kind]
    pool = instances.InstanceManager.default([Instance(n) for n in args.instance])
    report = asyncio.run(bench(args.bench, kinds, args.errand, pool, args.keep_running, args.regenerate_nav, args.reload))
    folder = REPORTS / args.bench
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (time.strftime("%Y%m%d-%H%M%S") + ".json")
    path.write_text(json.dumps(report, indent=1))
    print(summary(report))
    print(f"report: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
