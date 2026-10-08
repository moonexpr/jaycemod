#!/usr/bin/env python3
"""Run game-events-v2 research probes on the dedicated server srcds.py started,
or on the clients that joined it.

  gev2_probe.py run <probe> [<probe> ...]                     on the server
  gev2_probe.py run --client [--label L] <probe> [<probe> ...]  on every joined client

Each probe is copied to garrysmod/data/wetsand_tests/gev2/<probe>.txt.

- On the server it runs with lua_run RunString(...), and writes its findings
  to data/wetsand_tests/gev2/out/<probe>.txt, which this prints and copies to
  .devtools/artifacts/gev2-research/live/<probe>.txt.
- With --client the server SendLua's every human player a one-line loader
  that RunString's the probe from the client's data folder (the client and
  the server share one garrysmod/, so the copy is already there; this works
  with sv_allowcslua 0). The client writes
  data/wetsand_tests/gev2/client_out/<probe>.txt, which this prints and copies
  to .devtools/artifacts/gev2-research/client/<probe>.txt, or
  <probe>-<L>.txt with --label, so each step of a session keeps its own.

Writes nothing else in the GMod install. Start the server first (srcds.py
start --map ...), and for --client the client (gmod_client.py start).
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path
from typing import Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gmod_client  # noqa: E402
import srcds  # noqa: E402

PROBES = Path(__file__).resolve().parent / "gev2"
DATA_NAME = "wetsand_tests/gev2"
LIVE = srcds.ARTIFACTS / "gev2-research" / "live"
CLIENT = srcds.ARTIFACTS / "gev2-research" / "client"
CLIENT_OUT = "client_out"
RESULT_TIMEOUT = 120
LABEL = re.compile(r"^[A-Za-z0-9_-]+$")


class ProbeFailed(Exception):
    pass


def _copy_probe(server: srcds.Server, name: str, probes: Path) -> Path:
    data = server.install.data_dir / DATA_NAME
    data.mkdir(parents=True, exist_ok=True)
    (data / f"{name}.txt").write_text((probes / f"{name}.lua").read_text())
    return data


def _wait_for(out: Path, timeout: float, what: str) -> str:
    deadline = time.monotonic() + timeout
    while not out.exists():
        if time.monotonic() > deadline:
            raise ProbeFailed(what)
        time.sleep(0.5)
    time.sleep(0.5)  # the probe writes once, at its end
    return out.read_text()


def run(server: srcds.Server, name: str) -> str:
    data = _copy_probe(server, name, PROBES)
    out = data / "out" / f"{name}.txt"
    (data / "out").mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    reply = server.rcon(f'lua_run RunString(file.Read("{DATA_NAME}/{name}.txt", "DATA"), "{DATA_NAME}/{name}")')
    text = _wait_for(out, RESULT_TIMEOUT, f"{name} wrote no result; rcon said: {reply!r}")
    LIVE.mkdir(parents=True, exist_ok=True)
    (LIVE / f"{name}.txt").write_text(text)
    return text


def client_loader(name: str) -> str:
    """The server command that has every human player run the probe: one
    console line, with no `;` (the console splits there), whose SendLua
    text stays under SendLua's 255 bytes."""
    load = f'RunString(file.Read("{DATA_NAME}/{name}.txt", "DATA"), "{DATA_NAME}/{name}")'
    return f"lua_run for _, p in ipairs(player.GetHumans()) do p:SendLua([[{load}]]) end"


def run_on_clients(server: srcds.Server, name: str, probes: Path = PROBES, dest: Path = CLIENT,
                   label: Optional[str] = None, timeout: float = RESULT_TIMEOUT) -> str:
    if label is not None and not LABEL.match(label):
        raise ProbeFailed(f"a label is letters, digits, _ and -: {label!r}")
    joined = gmod_client.players(server.rcon("status"))
    if not joined:
        raise ProbeFailed("no client has joined the server; start one with gmod_client.py start")
    data = _copy_probe(server, name, probes)
    out = data / CLIENT_OUT / f"{name}.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    reply = server.rcon(client_loader(name))
    text = _wait_for(out, timeout, f"no client wrote {name}'s result; rcon said: {reply!r}")
    dest.mkdir(parents=True, exist_ok=True)
    (dest / (f"{name}-{label}.txt" if label else f"{name}.txt")).write_text(text)
    return text


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    r = sub.add_parser("run")
    r.add_argument("--client", action="store_true", help="run on every joined client, not the server")
    r.add_argument("--label", help="with --client: save as <probe>-<label>.txt")
    r.add_argument("probes", nargs="+")
    args = ap.parse_args()
    if args.label and not args.client:
        ap.error("--label goes with --client")
    server =srcds.make_server("gm_construct", srcds.started_port(srcds.DEFAULT_PORT))
    try:
        for name in args.probes:
            print(f"===== {name}" + (" (client)" if args.client else ""))
            print(run_on_clients(server, name, label=args.label) if args.client else run(server, name))
    except (ProbeFailed, srcds.ServerDown, srcds.AuthFailed, OSError) as e:
        print(f"gev2_probe: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
