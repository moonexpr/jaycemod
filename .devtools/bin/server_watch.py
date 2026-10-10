#!/usr/bin/env python3
"""Follow the events a dedicated server pushes (server_root/sandcastle_watch.lua).

  server_watch.py [--instance N]                  every event from now on
  server_watch.py [--instance N] --until NAME     until the wait NAME ends:
                                                  exit 0 when it is met, 1 on
                                                  its timeout or error
  server_watch.py --listen NAME [--run CMD]       arm the listener
                                                  listeners/NAME.lua, run the
                                                  console command CMD (RCON),
                                                  and follow until NAME ends

Set the watches up with server_lua.py, e.g. Watch.Until("stage3", 1, 60,
function() return ok, report end); then follow them here, under Claude Code's
Monitor (each line an event) or a background Bash for one wait. Events are
lines "<time> <name> <kind> <text>" in the instance's data/sandcastle_watch.txt;
only lines written after the follower starts are printed.

A listener is a Lua file in listeners/ that calls Watch.Task (or other
Watch calls) under its own name: one file per long-running command, so a
new command gets a listener by writing one. --listen notes where the log
ends, arms the listener, runs --run's command, and prints from that point,
so nothing the command does is missed.
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
LISTENERS = Path(__file__).resolve().parent / "listeners"
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


def log_end(log: Path) -> int:
    return log.stat().st_size if log.exists() else 0


def follow(log: Path, until: Optional[str], emit: Callable[[str], None], wait: Callable[[], None],
           polls: Optional[int] = None, start: Optional[int] = None) -> Optional[int]:
    """Emits each line written to `log` after `start` (by default, where it
    ends now); returns the verdict on `until`, or None once `polls` waits
    pass (forever when None)."""
    position = log_end(log) if start is None else start
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


class UnknownListener(Exception):
    pass


def listener_source(directory: Path, name: str) -> str:
    path = directory / f"{name}.lua"
    if not path.exists():
        known = ", ".join(sorted(p.stem for p in directory.glob("*.lua")))
        raise UnknownListener(f"no listener {name} in {directory} (there are: {known})")
    return path.read_text()


def listen(name: str, source: str, command: Optional[str], log: Path, arm: Callable[[str], None],
           run: Callable[[str], None], emit: Callable[[str], None], wait: Callable[[], None],
           polls: Optional[int] = None) -> Optional[int]:
    """Arms the listener, runs its command, and follows from before both until `name` ends."""
    start = log_end(log)
    arm(source)
    if command:
        run(command)
    return follow(log, name, emit, wait, polls, start)


class ArmFailed(Exception):
    pass


def arm_on(instance: Instance) -> Callable[[str], None]:
    from server_lua import Realm, address, run

    def arm(source: str) -> None:
        reply = run(Realm.SERVER, source, address(instance.number))
        if reply.error:
            raise ArmFailed(f"the listener did not arm: {reply.error}")
    return arm


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--instance", type=int, default=MAIN_INSTANCE, help="which server (srcds.py --instance)")
    ap.add_argument("--until", help="the wait (Watch.Until) whose end ends the follow")
    ap.add_argument("--listen", help="the listener (listeners/NAME.lua) to arm and follow to its end")
    ap.add_argument("--run", help="with --listen: the console command to run once it is armed")
    args = ap.parse_args()
    instance = Instance(args.instance)
    log = log_path(instance)
    emit, wait = (lambda text: print(text, flush=True)), (lambda: time.sleep(POLL_SECONDS))
    if args.listen:
        from server_lua import BridgeDown, NoReply
        from srcds import rcon_command
        try:
            code = listen(args.listen, listener_source(LISTENERS, args.listen), args.run, log, arm_on(instance),
                          lambda command: print(rcon_command(instance, command), flush=True), emit, wait)
        except (UnknownListener, ArmFailed, BridgeDown, NoReply) as e:
            print(f"server_watch: {e}", file=sys.stderr)
            return 2
        return MET if code is None else code
    code = follow(log, args.until, emit, wait)
    return MET if code is None else code


if __name__ == "__main__":
    sys.exit(main())
