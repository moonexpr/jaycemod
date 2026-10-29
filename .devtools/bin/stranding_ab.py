"""How often the AI war's soldiers get stuck, gamemode against gamemode: a full
war on one map for a set time, every recovery (a soldier stranded, off the
mesh or out of the world, put back) counted by its reason, once with each
checkout's gamemode. Same map, convars and time each leg; the server is
restarted between legs so each runs its own gamemode (server_root's
SANDCASTLE_GAMEMODE).

    python3 .devtools/bin/stranding_ab.py --instance 3 --port 27045 --map cp_sunshine --minutes 10 \\
        main=/path/to/main/gamemodes/sandcastle worktree=/path/to/worktree/gamemodes/sandcastle

Writes .devtools/artifacts/stranding_ab-<map>-<time>.json and prints a line a leg.
"""
import argparse
import json
import os
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ARTIFACTS = REPO / ".devtools" / "artifacts"
WARMUP = 60
CONVARS = {"tf_bot_quota": "0", "mp_aiwar_team_size": "8", "ns_soldiers_actor": "bot", "tf_bot_join_after_player": "0", "sv_idle_delay": "86400"}

# Counts every recovery by reason, from now on: wraps the war's Recover.
COUNT = """
local c = WS.Feature("aiwar")
StrandingAB = { reasons = {}, total = 0, since = CurTime() }
c.wsRecoverOriginal = c.wsRecoverOriginal or c.Recover
c.Recover = function(self, ent, entry, reason, pos)
	StrandingAB.total = StrandingAB.total + 1
	StrandingAB.reasons[reason] = (StrandingAB.reasons[reason] or 0) + 1
	return c.wsRecoverOriginal(self, ent, entry, reason, pos)
end
return "counting"
"""
REPORT = """
local alive = 0
for ent in pairs(WS.Feature("aiwar").soldiers or {}) do if IsValid(ent) and ent:Alive() then alive = alive + 1 end end
return util.TableToJSON({ total = StrandingAB.total, reasons = StrandingAB.reasons, minutes = (CurTime() - StrandingAB.since) / 60, map = game.GetMap(), alive = alive })
"""


def run(*args: str, env=None, timeout: int = 600) -> str:
    out = subprocess.run(list(args), capture_output=True, text=True, timeout=timeout, env=env)
    return (out.stdout + out.stderr).strip()


def lua(instance: int, code: str) -> str:
    return run("dt", "lua", "--instance", str(instance), code).splitlines()[-1]


def leg(instance: int, port: int, name: str, gamemode: str, map_name: str, minutes: float) -> dict:
    run("dt", "srcds", "--instance", str(instance), "stop")
    time.sleep(5)
    env = dict(os.environ, SANDCASTLE_GAMEMODE=gamemode)
    print(run("dt", "srcds", "--instance", str(instance), "start", "--map", map_name, "--port", str(port), env=env).splitlines()[-1], flush=True)
    for convar, value in CONVARS.items():
        run("dt", "rcon", "--instance", str(instance), f"{convar} {value}")
    run("dt", "rcon", "--instance", str(instance), f"changelevel {map_name}")
    time.sleep(WARMUP)
    lua(instance, COUNT)
    time.sleep(minutes * 60)
    line = lua(instance, REPORT)
    result = json.loads(line[3:]) if line.startswith("=>") else {"error": line}
    result["leg"], result["gamemode"] = name, gamemode
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("legs", nargs="+", help="name=gamemode folder")
    ap.add_argument("--instance", type=int, required=True)
    ap.add_argument("--port", type=int, required=True, help="a free game port for the instance")
    ap.add_argument("--map", default="cp_sunshine")
    ap.add_argument("--minutes", type=float, default=10)
    args = ap.parse_args()
    results = []
    for spec in args.legs:
        name, gamemode = spec.split("=", 1)
        r = leg(args.instance, args.port, name, gamemode, args.map, args.minutes)
        results.append(r)
        print(f"{name}: {r.get('total')} recoveries in {r.get('minutes', 0):.1f} min on {r.get('map')} {r.get('reasons')}", flush=True)
    out = ARTIFACTS / f"stranding_ab-{args.map}-{time.strftime('%Y%m%d-%H%M%S')}.json"
    out.write_text(json.dumps(results, indent=1))
    print(f"report: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
