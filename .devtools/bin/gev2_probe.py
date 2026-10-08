#!/usr/bin/env python3
"""Run game-events-v2 research probes on the dedicated server srcds.py started.

  gev2_probe.py run <probe> [<probe> ...]   run .devtools/bin/gev2/<probe>.lua

Each probe is copied to garrysmod/data/wetsand_tests/gev2/<probe>.txt, run
with lua_run RunString(...), and writes its findings to
data/wetsand_tests/gev2/out/<probe>.txt, which this prints and copies to
.devtools/artifacts/gev2-research/live/<probe>.txt. Writes nothing else in
the GMod install. Start the server first (srcds.py start --map ...).
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import srcds  # noqa: E402

PROBES = Path(__file__).resolve().parent / "gev2"
DATA_NAME = "wetsand_tests/gev2"
LIVE = srcds.ARTIFACTS / "gev2-research" / "live"
RESULT_TIMEOUT = 120


class ProbeFailed(Exception):
    pass


def run(server: srcds.Server, name: str) -> str:
    source = PROBES / f"{name}.lua"
    data = server.install.data_dir / DATA_NAME
    out = data / "out" / f"{name}.txt"
    (data / "out").mkdir(parents=True, exist_ok=True)
    (data / f"{name}.txt").write_text(source.read_text())
    out.unlink(missing_ok=True)
    reply = server.rcon(f'lua_run RunString(file.Read("{DATA_NAME}/{name}.txt", "DATA"), "{DATA_NAME}/{name}")')
    deadline = time.monotonic() + RESULT_TIMEOUT
    while not out.exists():
        if time.monotonic() > deadline:
            raise ProbeFailed(f"{name} wrote no result; rcon said: {reply!r}")
        time.sleep(0.5)
    time.sleep(0.5)  # the probe writes once, at its end
    text = out.read_text()
    LIVE.mkdir(parents=True, exist_ok=True)
    (LIVE / f"{name}.txt").write_text(text)
    return text


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    r = sub.add_parser("run")
    r.add_argument("probes", nargs="+")
    args = ap.parse_args()
    server = srcds.make_server("gm_construct", srcds.started_port(srcds.DEFAULT_PORT))
    try:
        for name in args.probes:
            print(f"===== {name}")
            print(run(server, name))
    except (ProbeFailed, srcds.ServerDown, srcds.AuthFailed, OSError) as e:
        print(f"gev2_probe: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
