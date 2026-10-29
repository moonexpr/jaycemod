"""Play the AI war's hostage rescue on each CS:S map for a while and record
how it went, for comparing maps and finding the places they need hotfixes:
each round's winner, reason and the hostages at its end, the nav areas where
soldiers were stranded (the hazards module's), the Lua errors, and whether the
map changed under it (a forced closure, a game over).

    python3 .devtools/bin/hostage_survey.py --instance 2 --minutes 8 cs_italy cs_havana

Writes .devtools/artifacts/hostage_survey/<map>.json and prints a line a map.
The server must be up, running the worktree's gamemode, with the war's bots.
"""
import argparse
import json
import re
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATUS = HERE / "hostage_status.lua"
OUT = HERE.parent / "artifacts" / "hostage_survey"
TEAM_WIN = 5
REASONS = {2: "opponents dead", 13: "hostages rescued", 14: "hostages not rescued"}
TEAMS = {2: "RED", 3: "BLU"}
LOAD_SECONDS = 60
SAMPLE_SECONDS = 10


def dt(instance: int, *args: str, timeout: int = 60) -> str:
    out = subprocess.run(["dt", *args[:1], "--instance", str(instance), *args[1:]], capture_output=True, text=True, timeout=timeout)
    return out.stdout + out.stderr


def lua(instance: int, code: str) -> str:
    return dt(instance, "lua", code).strip().splitlines()[-1]


def status(instance: int) -> dict | None:
    line = dt(instance, "lua", "-f", str(STATUS)).strip().splitlines()
    if not line or not line[-1].startswith("=>"):
        return None
    return json.loads(line[-1][3:])


def survey(instance: int, name: str, minutes: float) -> dict:
    dt(instance, "rcon", f"changelevel {name}")
    time.sleep(LOAD_SECONDS)
    dt(instance, "rcon", "ns_hazards_clear all")
    result = {"map": name, "rounds": [], "left_map": None}
    before = lua(instance, "return game.GetMap()")
    if name not in before:
        result["left_map"] = before
        return result
    end = time.time() + minutes * 60
    last_state = None
    while time.time() < end:
        try:
            d = status(instance)
        except subprocess.TimeoutExpired:
            d = None
        if d is None:
            current = lua(instance, "return game.GetMap()")
            if name not in current:
                result["left_map"] = current
                break
            time.sleep(SAMPLE_SECONDS)
            continue
        if d["state"] == TEAM_WIN and last_state != TEAM_WIN:
            result["rounds"].append({
                "winner": TEAMS.get(d.get("winner"), d.get("winner")),
                "reason": REASONS.get(d.get("reason"), d.get("reason")),
                "hostages": [h.split()[1] for h in d["hostages"]],
            })
        last_state = d["state"]
        time.sleep(SAMPLE_SECONDS)
    hazards = dt(instance, "rcon", "ns_hazards_print")
    result["stranded"] = [re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", l).strip() for l in hazards.splitlines() if "area " in l]
    errors = subprocess.run(["dt", "gmod", "lua_errors", f"instance={instance}"], capture_output=True, text=True, timeout=60)
    result["lua_errors"] = errors.stdout.count("error ")
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("maps", nargs="+")
    ap.add_argument("--instance", type=int, default=1)
    ap.add_argument("--minutes", type=float, default=8)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for name in args.maps:
        r = survey(args.instance, name, args.minutes)
        (OUT / f"{name}.json").write_text(json.dumps(r, indent=1))
        wins = {}
        for rnd in r["rounds"]:
            key = f"{rnd['winner']} ({rnd['reason']})"
            wins[key] = wins.get(key, 0) + 1
        print(f"{name}: rounds {len(r['rounds'])} {wins} stranded {len(r.get('stranded', []))} "
              f"lua errors {r.get('lua_errors')} left for {r['left_map']}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
