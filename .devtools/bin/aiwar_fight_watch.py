#!/usr/bin/env python3
"""How much the AI war's soldiers fight, over a span of the war.

  aiwar_fight_watch.py                                     pl_upward, 180 s
  aiwar_fight_watch.py --map koth_viaduct --seconds 120
  aiwar_fight_watch.py --instance 2

Changes map (the server must be running: srcds.py start), waits for the
war's soldiers, then counts while it runs: the shots
they fire, the hits they take and their damage, their deaths, and at the end how many there
are, how many have an enemy, and whether the server went idle (the war
stood still). Prints one line of JSON; the counting hooks remove
themselves at the end.

An empty server goes idle sv_idle_delay seconds into a map (ws/sv_idle.lua)
and the war stands still from then, so once the map is up (its server.cfg
puts the defaults back) the watch sets the delay to a day, and puts the
old value back after, failed or not.

A soldier is an entity the war drives (its NSBrain).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import server_lua
from server_root import Instance

BIN = Path(__file__).resolve().parent
WAR_UP_SOLDIERS = 10
NEVER_IDLE = 86400

# Counts from the moment it runs; Fights() reads them and stops counting.
COUNT_LUA = """
local W = { shots = 0, hits = 0, damage = 0, deaths = 0, start = CurTime() }
NSFightWatch = W
hook.Add("EntityFireBullets", "ns_fight_watch", function(ent) if ent.NSBrain then W.shots = W.shots + 1 end end)
hook.Add("PostEntityTakeDamage", "ns_fight_watch", function(ent, dmg, took)
	if took and ent.NSBrain then W.hits = W.hits + 1 W.damage = W.damage + dmg:GetDamage() end
end)
hook.Add("OnNPCKilled", "ns_fight_watch", function(ent) if ent.NSBrain then W.deaths = W.deaths + 1 end end)
return W.start
"""

READ_LUA = """
local W = NSFightWatch
for _, name in ipairs({ "EntityFireBullets", "PostEntityTakeDamage", "OnNPCKilled" }) do hook.Remove(name, "ns_fight_watch") end
local soldiers, enemies = 0, 0
for _, e in ipairs(ents.GetAll()) do
	if e.NSBrain then
		soldiers = soldiers + 1
		if e:HasEnemy() then enemies = enemies + 1 end
	end
end
return util.TableToJSON({ seconds = CurTime() - W.start, shots = W.shots, hits = W.hits, damage = W.damage, deaths = W.deaths,
	soldiers = soldiers, enemies = enemies, idle = WS.ServerIdle() })
"""

SOLDIERS_LUA = "local n = 0 for _, e in ipairs(ents.GetAll()) do if e.NSBrain then n = n + 1 end end return n"


@dataclass(frozen=True)
class Fights:
    map: str
    seconds: float
    shots: int
    hits: int
    damage: float
    deaths: int
    soldiers: int
    enemies: int
    idle: bool

    @classmethod
    def parse(cls, map_name: str, text: str) -> "Fights":
        data = json.loads(text)
        return cls(map_name, round(float(data["seconds"]), 1), int(data["shots"]), int(data["hits"]),
                   round(float(data["damage"]), 1), int(data["deaths"]), int(data["soldiers"]), int(data["enemies"]), bool(data["idle"]))


@dataclass(frozen=True)
class Server:
    instance: int

    def rcon(self, command: str) -> None:
        subprocess.run([sys.executable, str(BIN / "srcds.py"), "--instance", str(self.instance), "rcon", command],
                       check=True, capture_output=True, text=True, timeout=30)

    def lua(self, code: str) -> str:
        reply = server_lua.run(server_lua.Realm.SERVER, code, server_lua.address(self.instance), timeout=30)
        if reply.error:
            raise RuntimeError(reply.error)
        return reply.returns[0] if reply.returns else ""

    def soldiers(self) -> int:
        try:
            return int(self.lua(SOLDIERS_LUA))
        except (server_lua.BridgeDown, server_lua.NoReply, OSError, ValueError):
            return 0  # the map is still loading


def watch(server: Server, map_name: str, seconds: float, wait: float) -> Fights:
    server.rcon(f"changelevel {map_name}")
    time.sleep(15)
    deadline = time.monotonic() + wait
    while server.soldiers() < WAR_UP_SOLDIERS:
        if time.monotonic() > deadline:
            raise TimeoutError(f"no war of {WAR_UP_SOLDIERS} soldiers on {map_name} after {wait:.0f} s")
        time.sleep(5)
    idle_delay = server.lua('return GetConVarString("sv_idle_delay")')
    server.rcon(f"sv_idle_delay {NEVER_IDLE}")
    try:
        return counted(server, map_name, seconds)
    finally:
        server.rcon(f"sv_idle_delay {idle_delay}")


def counted(server: Server, map_name: str, seconds: float) -> Fights:
    if server.lua("return WS.ServerIdle()") == "true":
        raise RuntimeError(f"{map_name} went idle before the count began")
    server.lua(COUNT_LUA)
    time.sleep(seconds)
    return Fights.parse(map_name, server.lua(READ_LUA))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--map", default="pl_upward")
    parser.add_argument("--seconds", type=float, default=180)
    parser.add_argument("--wait", type=float, default=240, help="seconds to wait for the war after the map loads")
    parser.add_argument("--instance", type=int, default=1)
    args = parser.parse_args()
    Instance(args.instance)  # refuses an instance that does not exist
    fights = watch(Server(args.instance), args.map, args.seconds, args.wait)
    print(json.dumps(fights.__dict__))
    return 0


if __name__ == "__main__":
    sys.exit(main())
