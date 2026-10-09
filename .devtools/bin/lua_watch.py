#!/usr/bin/env python3
"""Stand in for GMod's Lua auto refresh, which never fires under CrossOver.

  lua_watch.py            watch addon/ and refresh each edited file in every running game

GMod notices an edit through ReadDirectoryChangesW, which Wine builds on
Linux's inotify; on macOS no change is ever reported, so auto refresh is
dead whatever the folder layout (symlinked or not). lua_refresh_file <path>
still works: it re-runs a file the game already loaded and sends it on to
the clients. This scans addon/ for edited .lua files and sends that command
to the dedicated server srcds.py started (RCON) and to a game you are
playing (luadev's socket, on its server realm). A new file is only
reported: it loads on the next map change.
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List

HERE = Path(__file__).resolve().parent
ADDON = HERE.parents[1] / "addon"
POLL_SECONDS = 0.5
# what a path may hold inside the console command: no quote, separator or newline
SAFE_PATH = re.compile(r"[\w./-]+")

Scan = Dict[Path, int]


class TargetDown(Exception):
    pass


def gmod_path(addon: Path, file: Path) -> str:
    """The path lua_refresh_file knows a file by: gamemodes/... as it is, the
    addon's lua/ folder from inside it."""
    rel = file.relative_to(addon).as_posix()
    path = rel.removeprefix("lua/")
    if not SAFE_PATH.fullmatch(path):
        raise ValueError(f"not a path to send in a console command: {path!r}")
    return path


def scan(addon: Path) -> Scan:
    return {p: p.stat().st_mtime_ns for p in addon.rglob("*.lua")}


@dataclass(frozen=True)
class Changes:
    modified: List[Path]
    added: List[Path]


def scan_changes(before: Scan, after: Scan) -> Changes:
    return Changes(
        modified=sorted(p for p, mtime in after.items() if p in before and before[p] != mtime),
        added=sorted(p for p in after if p not in before),
    )


class Target(ABC):
    name: str

    @abstractmethod
    def refresh(self, path: str) -> None:
        """Runs lua_refresh_file path; TargetDown when the game is not running."""


class DedicatedServer(Target):
    name = "the dedicated server"

    def __init__(self) -> None:
        import srcds
        self.srcds = srcds

    def refresh(self, path: str) -> None:
        server = self.srcds.make_server("gm_construct", self.srcds.started_port(self.srcds.DEFAULT_PORT))
        try:
            server.rcon(f"lua_refresh_file {path}")
        except (OSError, self.srcds.ServerDown) as e:
            raise TargetDown(str(e)) from e


class Game(Target):
    name = "your game"

    def __init__(self) -> None:
        import gmod_lua
        self.gmod_lua = gmod_lua

    def refresh(self, path: str) -> None:
        try:
            self.gmod_lua.send(self.gmod_lua.Realm.SERVER,
                               f'game.ConsoleCommand("lua_refresh_file {path}\\n")', "lua_watch")
        except self.gmod_lua.BridgeDown as e:
            raise TargetDown(str(e)) from e


@dataclass(frozen=True)
class Watcher:
    addon: Path
    targets: List[Target]
    say: Callable[[str], None]

    def apply(self, changes: Changes) -> None:
        for file in changes.added:
            self.say(f"{gmod_path(self.addon, file)} is new; it loads on the next map change")
        for file in changes.modified:
            path = gmod_path(self.addon, file)
            reached = []
            for target in self.targets:
                try:
                    target.refresh(path)
                    reached.append(target.name)
                except TargetDown:
                    pass  # that game is not running: the others still hear of the edit
            if reached:
                self.say(f"refreshed {path} on {', '.join(reached)}")
            else:
                self.say(f"{path} changed; no game is running")

    def run(self) -> None:
        before = scan(self.addon)
        self.say(f"watching {len(before)} Lua files under {self.addon}")
        while True:
            time.sleep(POLL_SECONDS)
            after = scan(self.addon)
            self.apply(scan_changes(before, after))
            before = after


def main() -> int:
    argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter).parse_args()
    try:
        Watcher(ADDON, [DedicatedServer(), Game()], lambda line: print(line, flush=True)).run()
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
