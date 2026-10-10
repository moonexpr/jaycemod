"""Run one in-game check on the server srcds.py already started, and print its record.

  ingame_one.py capture_cleanup      deploy the runner and checks, run it, print the JSON

For a quick red/green loop on a single check; ingame_tests.py runs the plan
and writes the report.
"""
from __future__ import annotations

import sys
import time

import ingame_tests as it
import srcds

RESULT_TIMEOUT = 120
RUNNING = "gm_construct"  # a placeholder: the map only matters to start, which this never calls


def main(check: str) -> int:
    server = srcds.make_server(RUNNING, srcds.started_port(srcds.DEFAULT_PORT))
    data_root = server.install.data_dir / it.DATA_NAME
    it.deploy(data_root)
    server.rcon(it.BOOT)
    run_id = f"one{int(time.time())}"
    server.rcon(f'lua_run WS_TESTS.Run("{check}", "{run_id}")')
    results = data_root / "results"
    deadline = time.time() + RESULT_TIMEOUT
    while time.time() < deadline:
        found = list(results.glob(f"*{run_id}*"))
        if found:
            time.sleep(it.POLL_SECONDS)
            print(found[0].read_text())
            return 0
        time.sleep(it.POLL_SECONDS)
    print(f"no record for {check} after {RESULT_TIMEOUT} s", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
