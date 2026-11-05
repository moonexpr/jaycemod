#!/usr/bin/env python3
"""cp_dustbowl's second stage on a leased server: does BLU take its second point on its own?

Captures stage 1's two points and stage 2's first by hand, with the map rotation held off, then
only watches: how many of BLU's bots find a route to cap_red_4, how many move, how near the nearest
is, and who owns the point. Each line goes to stdout and the whole to
.devtools/artifacts/benches/cp_dustbowl_stage2/<time>.txt.

    python3 .devtools/bin/dustbowl_stage2_bench.py [--seconds 300] [--blu 8] [--red 8] [--instance N ...]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path

import instances
from server_root import Instance

REPO = Path(__file__).resolve().parents[2]
MAP = "cp_dustbowl"
STAGE_1 = ("cap_red_1", "cap_red_2")
FIRST_OF_STAGE_2, TARGET = "cap_red_3", "cap_red_4"
POLL, SAMPLE = 3, 15
OPEN_TIMEOUT = 240

# The limits a round's end would change map by, held off on the server for as long as the lease,
# since each round's start may set them again.
SETUP = """
timer.Create("dustbowl_stage2_limits", 1, 0, function()
	RunConsoleCommand("mp_winlimit", "0")
	RunConsoleCommand("mp_timelimit", "0")
	RunConsoleCommand("mp_maxrounds", "0")
end)
local War = WS.Feature("aiwar")
War:SetSlotCount(WS.TEAM_RED, %(red)d)
War:SetSlotCount(WS.TEAM_BLUE, %(blu)d)
RunConsoleCommand("ns_hazards_clear", "all")
return true
"""
TEARDOWN = 'timer.Remove("dustbowl_stage2_limits") return true'

ROUND = 'local round = WS.Feature("capture"):CurrentRound() return round and round:GetName() or "none"'
OPEN = 'return WS.State() == 4 and WS.Feature("capture").rounds:PointsMayBeCaptured() and "yes" or "no"'
CAPTURE = """
local ok, why = WS.Feature("capture"):CapturePoint(ents.FindByName(%(point)s)[1], WS.TEAM_BLUE)
return util.TableToJSON({ ok = ok and true or false, why = tostring(why) })
"""
SAMPLE_BLU = """
local Capture, War = WS.Feature("capture"), WS.Feature("aiwar")
local point = ents.FindByName(%(point)s)[1]
local goal = point:GetPos()
local alive, found, moving, nearest = 0, 0, 0, math.huge
for bot, entry in pairs(War.soldiers) do
	if IsValid(bot) and bot:Team() == WS.TEAM_BLUE and bot:Alive() then
		alive = alive + 1
		local cost = entry.soldier:RouteCost()
		if cost then
			local _, ok = entry.soldier:Navigator():PlanRoute(goal, cost)
			if ok then found = found + 1 end
		end
		if bot:GetVelocity():Length2D() > 50 then moving = moving + 1 end
		nearest = math.min(nearest, bot:GetPos():Distance(goal))
	end
end
local round = Capture:CurrentRound()
return util.TableToJSON({
	map = game.GetMap(), state = WS.State(), round = round and round:GetName() or "none",
	alive = alive, found = found, moving = moving, nearest = nearest < math.huge and math.floor(nearest) or -1,
	owner = Capture:Owner(point), blue = WS.TEAM_BLUE, red = team.NumPlayers(WS.TEAM_RED),
})
"""


async def returned(server, code: str) -> str:
    return (await server.lua(code)).returns[0]


async def wait_until_open(server, deadline_seconds: float) -> None:
    deadline = time.monotonic() + deadline_seconds
    while await returned(server, OPEN) != "yes":
        if time.monotonic() > deadline:
            raise TimeoutError(f"points not capturable in {deadline_seconds:g} s")
        await asyncio.sleep(POLL)


async def wait_for_next_round(server, name: str, deadline_seconds: float) -> None:
    deadline = time.monotonic() + deadline_seconds
    while await returned(server, ROUND) == name:
        if time.monotonic() > deadline:
            raise TimeoutError(f"still in {name} after {deadline_seconds:g} s")
        await asyncio.sleep(POLL)


async def capture(server, point: str, say) -> None:
    await wait_until_open(server, OPEN_TIMEOUT)
    answer = json.loads(await returned(server, CAPTURE % {"point": json.dumps(point)}))
    say(f"captured {point}: {answer}")
    if not answer["ok"]:
        raise RuntimeError(f"{point} refused: {answer['why']}")


async def run(server, seconds: float, blu: int, red: int, say) -> bool:
    await server.lua(SETUP % {"red": red, "blu": blu})
    try:
        await wait_until_open(server, OPEN_TIMEOUT)
        stage_1 = await returned(server, ROUND)
        say(f"stage 1 is {stage_1}")
        for point in STAGE_1:
            await capture(server, point, say)
        await wait_for_next_round(server, stage_1, OPEN_TIMEOUT)
        await capture(server, FIRST_OF_STAGE_2, say)
        began = time.monotonic()
        while time.monotonic() - began < seconds:
            sample = json.loads(await returned(server, SAMPLE_BLU % {"point": json.dumps(TARGET)}))
            say(f"{time.monotonic() - began:5.0f} s {json.dumps(sample)}")
            if sample["owner"] == sample["blue"]:
                say(f"BLU TOOK {TARGET} on its own")
                return True
            await asyncio.sleep(SAMPLE)
        say(f"BLU did not take {TARGET} in {seconds:g} s")
        return False
    finally:
        await server.lua(TEARDOWN)


async def main_async(args: argparse.Namespace) -> int:
    folder = REPO / ".devtools/artifacts/benches/cp_dustbowl_stage2"
    folder.mkdir(parents=True, exist_ok=True)
    report = folder / f"{time.strftime('%Y%m%d-%H%M%S')}.txt"

    def say(text: str) -> None:
        print(text, flush=True)
        with report.open("a") as out:
            out.write(text + "\n")

    usable = tuple(Instance(n) for n in args.instance) or (Instance(instances.MAIN_INSTANCE),)
    pool = instances.InstanceManager.default(usable)
    async with pool.lease(MAP, owner="dustbowl_stage2_bench") as server:
        say(f"leased instance {server.instance.number} on {await server.current_map()}")
        took = await run(server, args.seconds, args.blu, args.red, say)
    return 0 if took else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=300)
    parser.add_argument("--blu", type=int, default=8)
    parser.add_argument("--red", type=int, default=8)
    parser.add_argument("--instance", type=int, action="append", default=[])
    args = parser.parse_args()
    return asyncio.run(main_async(args))


if __name__ == "__main__":
    sys.exit(main())
