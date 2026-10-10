"""Run one in-game check on the server srcds.py already started, and print its record.

  ingame_one.py capture_cleanup              deploy the runner and checks, run it, print the JSON
  ingame_one.py aiwar_arena --timeout 900    wait up to 900 s for a long check's record

For a quick red/green loop on a single check; ingame_tests.py runs the plan
and writes the report.
"""
from __future__ import annotations

import argparse
import sys
import time

import ingame_tests as it
import srcds

RESULT_TIMEOUT = 120
RUNNING = "gm_construct"  # a placeholder: the map only matters to start, which this never calls


def main(check: str, timeout: float) -> int:
    server = srcds.make_server(RUNNING, srcds.started_port(srcds.DEFAULT_PORT))
    data_root = server.install.data_dir / it.DATA_NAME
    it.deploy(data_root)
    server.rcon(it.BOOT)
    run_id = f"one{int(time.time())}"
    server.rcon(f'lua_run WS_TESTS.Run("{check}", "{run_id}")')
    results = data_root / "results"
    deadline = time.time() + timeout
    while time.time() < deadline:
        found = list(results.glob(f"*{run_id}*"))
        if found:
            time.sleep(it.POLL_SECONDS)
            print(found[0].read_text())
            return 0
        time.sleep(it.POLL_SECONDS)
    print(f"no record for {check} after {timeout:.0f} s", file=sys.stderr)
    return 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run one in-game check on the running server.")
    parser.add_argument("check")
    parser.add_argument("--timeout", type=float, default=RESULT_TIMEOUT, help="seconds to wait for its record")
    args = parser.parse_args()
    sys.exit(main(args.check, args.timeout))
