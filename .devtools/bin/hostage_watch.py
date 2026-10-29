"""Follow a hostage rescue match on a dev server, printing one line a sample:
the round state, the winner, each team's survivors and the hostages' states,
and with --members each soldier's squad, hostage group, stage and place.

    python3 .devtools/bin/hostage_watch.py --instance 2 --every 15 --samples 12

It runs hostage_status.lua through `dt lua`, so the server must be up on a
hostage map.
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

SCRIPT = Path(__file__).with_name("hostage_status.lua")
ROUND_STATES = {5: "team win", 7: "running"}


def sample(instance: int) -> dict:
    out = subprocess.run(["dt", "lua", "--instance", str(instance), "-f", str(SCRIPT)], capture_output=True, text=True, timeout=60)
    line = out.stdout.strip().splitlines()[-1] if out.stdout.strip() else ""
    if not line.startswith("=>"):
        raise RuntimeError(f"no status: {line or out.stderr.strip()}")
    return json.loads(line[3:])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--instance", type=int, default=1)
    ap.add_argument("--every", type=float, default=15)
    ap.add_argument("--samples", type=int, default=10)
    ap.add_argument("--members", action="store_true")
    args = ap.parse_args()
    for _ in range(args.samples):
        try:
            d = sample(args.instance)
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            print(f"-- {e}")
            time.sleep(args.every)
            continue
        states = ",".join(h.split()[1] for h in d.get("hostages", []))
        print(f"{time.strftime('%H:%M:%S')} {ROUND_STATES.get(d['state'], d['state'])} winner={d.get('winner')} alive={d['alive']} hostages={states}")
        if args.members:
            for m in d["members"]:
                print("   ", m)
        sys.stdout.flush()
        time.sleep(args.every)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
