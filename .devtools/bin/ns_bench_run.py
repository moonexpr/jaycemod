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

A bench map has no nav mesh until the server generates one (nav_generate,
which saves maps/<bench>.nav); the runner has it generated when the map
has none. The report (every errand's result and samples) is written to
.devtools/artifacts/benches/<bench>/<time>.json and summed up on stdout.

    python3 .devtools/bin/ns_bench_run.py ns_bench_watchtower [--kind follower|bot|both]
        [--errand NAME] [--keep-running] [--instance N ...]
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
# convar -> its value while the bench runs: bots join with no human on, the server never idles
CONVARS = {"tf_bot_join_after_player": "0", "sv_idle_delay": "86400"}

Vec = Tuple[float, float, float]


@dataclass(frozen=True)
class Errand:
    name: str
    start: Vec
    goal: Vec
    seconds: float


# arena_watchtower's errands (ns_bench_watchtower keeps its coordinates):
# up the log ramps to the health pack on each side's pipe, and from the
# west pipe across to the point by the stairway.
BENCHES = {
    "ns_bench_watchtower": (
        Errand("west pack, up the logs", (-1213, 13, 16), (-1250, 8, 832), 60),
        Errand("east pack, up the logs", (1212, 12, 24), (1238, -16, 816), 60),
        Errand("west pipe to the point", (-1250, 8, 848), (-2, 1, 760), 45),
    ),
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

FIND_BOT = """
local aiwar = WS.Feature("aiwar")
for ent, entry in pairs(aiwar.soldiers or {}) do
	if IsValid(ent) and ent:IsPlayer() and ent:Alive() and entry.soldier.Pin then
		NSBenchBot = { ent = ent, soldier = entry.soldier }
		return ent:Nick()
	end
end
return ''
"""

SEND_BOT = """
local bot, soldier = NSBenchBot.ent, NSBenchBot.soldier
bot:GodEnable()
bot:SetPos(%(start)s)
bot:SetVelocity(-bot:GetVelocity())
soldier:Pin({ x = %(gx)g, y = %(gy)g, z = %(gz)g })
return true
"""

SAMPLE_BOT = """
local bench = NSBenchBot
local bot, soldier = bench and bench.ent, bench and bench.soldier
if not (IsValid(bot) and bot:Alive()) then return util.TableToJSON({ gone = true }) end
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
	distance = math.Round(pos:Distance(%(goal)s)),
})
"""

RELEASE_BOT = """
local bench = NSBenchBot
if bench and IsValid(bench.ent) then
	bench.soldier:Unpin()
	bench.ent:GodDisable()
end
NSBenchBot = nil
return true
"""


# The errands ------------------------------------------------------------------------


async def ensure_nav(server: instances.GameServer) -> int:
    """The map's nav area count, having the server generate a mesh when it has none."""
    areas = int((await server.lua(NAV_AREAS)).returns[0])
    if areas:
        return areas
    print("no nav mesh: nav_generate (the map reloads when it is done)")
    await server.rcon("nav_generate")
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
                status = "bot gone"
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
    saved = {}
    for name, value in CONVARS.items():
        saved[name] = (await server.lua(f"return GetConVarString({json.dumps(name)})")).returns[0]
        await server.rcon(f"{name} {value}")
    return saved


async def find_bot(server: instances.GameServer) -> Optional[str]:
    if (await server.lua("return WS.Feature('aiwar').war ~= nil")).returns[0] != "true":
        await server.rcon("mp_aiwar_start")
    deadline = time.monotonic() + BOT_TIMEOUT
    while time.monotonic() < deadline:
        name = (await server.lua(FIND_BOT)).returns[0]
        if name:
            return name
        await asyncio.sleep(2)
    return None


async def bench(name: str, kinds: List[str], only: Optional[str], pool: instances.InstanceManager,
                keep_running: bool) -> dict:
    errands = [e for e in BENCHES[name] if only is None or e.name == only]
    report = {"bench": name, "started": time.strftime("%Y-%m-%dT%H:%M:%S"), "errands": []}
    async with pool.lease(name, OWNER, keep_running=keep_running) as server:
        report["instance"] = server.instance.number
        report["nav_areas"] = await ensure_nav(server)
        saved = await setup(server)
        try:
            if "follower" in kinds:
                for errand in errands:
                    result = await run_follower(server, errand)
                    report["errands"].append({"kind": "follower", "errand": asdict(errand), "result": result})
            if "bot" in kinds:
                bot = await find_bot(server)
                for errand in errands:
                    result = await run_bot(server, errand) if bot else {"status": "no bot soldier"}
                    report["errands"].append({"kind": "bot", "bot": bot, "errand": asdict(errand), "result": result})
        finally:
            for convar, value in saved.items():
                await server.rcon(f"{convar} {value}")
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
    parser.add_argument("--instance", type=int, nargs="+", default=[1], help="the instances the run may lease")
    args = parser.parse_args()
    kinds = ["follower", "bot"] if args.kind == "both" else [args.kind]
    pool = instances.InstanceManager.default([Instance(n) for n in args.instance])
    report = asyncio.run(bench(args.bench, kinds, args.errand, pool, args.keep_running))
    folder = REPORTS / args.bench
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (time.strftime("%Y%m%d-%H%M%S") + ".json")
    path.write_text(json.dumps(report, indent=1))
    print(summary(report))
    print(f"report: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
