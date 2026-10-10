#!/usr/bin/env python3
"""Follow the events a dedicated server pushes (server_root/sandcastle_watch.lua).

  server_watch.py [--instance N]                  every event from now on
  server_watch.py [--instance N] --until NAME     until the wait NAME ends:
                                                  exit 0 when it is met, 1 on
                                                  its timeout or error

Set the watches up with server_lua.py, e.g. Watch.Until("stage3", 1, 60,
function() return ok, report end); then follow them here, under Claude Code's
Monitor (each line an event) or a background Bash for one wait. Events are
lines "<time> <name> <kind> <text>" in the instance's data/sandcastle_watch.txt;
only lines written after the follower starts are printed.
"""
from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from server_root import MAIN_INSTANCE, WATCH_LOG, Instance

POLL_SECONDS = 0.2
MET, FAILED = 0, 1
FAILURES = ("timeout", "error")


def log_path(instance: Instance) -> Path:
    return instance.root / "garrysmod" / "data" / WATCH_LOG


@dataclass(frozen=True)
class WatchLine:
    time: float
    name: str
    kind: str
    text: str

    @classmethod
    def parse(cls, line: str) -> Optional["WatchLine"]:
        parts = line.split(" ", 3)
        if len(parts) < 3:
            return None
        try:
            at = float(parts[0])
        except ValueError:
            return None
        return cls(at, parts[1], parts[2], parts[3] if len(parts) > 3 else "")


def verdict(line: WatchLine, until: str) -> Optional[int]:
    """The exit code the line ends the follow with, waiting for `until`, or None."""
    if line.name != until:
        return None
    if line.kind == "met":
        return MET
    if line.kind in FAILURES:
        return FAILED
    return None


def follow(log: Path, until: Optional[str], emit: Callable[[str], None], wait: Callable[[], None],
           polls: Optional[int] = None) -> Optional[int]:
    """Emits each line written to `log` after the start; returns the verdict
    on `until`, or None once `polls` waits pass (forever when None)."""
    position = log.stat().st_size if log.exists() else 0
    pending = ""
    while polls is None or polls >= 0:
        if log.exists():
            size = log.stat().st_size
            if size < position:  # the log was cleared: read it from the start
                position = 0
            with log.open("r", errors="replace") as f:
                f.seek(position)
                pending += f.read()
                position = f.tell()
            *lines, pending = pending.split("\n")
            for text in lines:
                emit(text)
                line = WatchLine.parse(text)
                code = verdict(line, until) if line and until else None
                if code is not None:
                    return code
        if polls is not None:
            polls -= 1
        wait()
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--instance", type=int, default=MAIN_INSTANCE, help="which server (srcds.py --instance)")
    ap.add_argument("--until", help="the wait (Watch.Until) whose end ends the follow")
    args = ap.parse_args()
    log = log_path(Instance(args.instance))
    code = follow(log, args.until, lambda text: print(text, flush=True), lambda: time.sleep(POLL_SECONDS))
    return MET if code is None else code


if __name__ == "__main__":
    sys.exit(main())
