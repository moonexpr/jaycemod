#!/usr/bin/env python3
"""Move modules between foundation's namespaces and game/.

docs/foundation-game-split-plan.md: each module (and its test) moves with
`git mv`, and every Lua file under addons/, tests/ and .devtools/bin/ has the
old name rewritten, dotted (foundation.core.structs.heap) and slashed
(foundation/core/structs/heap, and core/structs/heap for a move within
foundation, as the layers test names modules). Moves run in order, so a name
moved twice (core/pathfinder, then npc/pathfinder) reaches its last place. A
second run finds nothing to move and nothing to rewrite, so it can run again
over files merged in later.

    foundation_rename.py [--dry-run]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GAMEMODE = Path("addons/sandcastle/gamemodes/sandcastle/gamemode")
FOUNDATION = "foundation/"
TESTS = Path("tests")
SEARCHED = ("addons", "tests", ".devtools/bin")


@dataclass(frozen=True)
class Move:
    """A module's path under gamemode/, before and after, without .lua."""

    old: str
    new: str

    def __post_init__(self) -> None:
        for path in (self.old, self.new):
            if not re.fullmatch(r"(foundation|game)(/[a-z_][a-z0-9_]*)+", path):
                raise ValueError(f"not a module path under foundation/ or game/: {path!r}")

    @property
    def files(self) -> tuple[Path, Path]:
        return GAMEMODE / f"{self.old}.lua", GAMEMODE / f"{self.new}.lua"

    @property
    def tests(self) -> tuple[Path, Path]:
        """foundation/<path> is tested in <path>_test.lua, game/<path> in game_<path>_test.lua."""

        def test(path: str) -> Path:
            name = path.removeprefix(FOUNDATION)
            return TESTS / f"{name.replace('/', '_')}_test.lua"

        return test(self.old), test(self.new)

    @property
    def within_foundation(self) -> bool:
        return self.old.startswith(FOUNDATION) and self.new.startswith(FOUNDATION)

    def rewrite(self, text: str) -> str:
        test_old, test_new = (p.stem for p in self.tests)
        text = re.sub(rf"(?<![\w]){re.escape(test_old)}(?![\w])", test_new, text)
        dotted_old, dotted_new = (p.replace("/", ".") for p in (self.old, self.new))
        text = re.sub(rf"(?<![\w.]){re.escape(dotted_old)}(?![\w])", dotted_new, text)
        text = re.sub(rf"(?<![\w.]){re.escape(self.old)}(?![\w/])", self.new, text)
        if self.within_foundation:
            bare_old, bare_new = (p.removeprefix(FOUNDATION) for p in (self.old, self.new))
            text = re.sub(rf"(?<![\w./]){re.escape(bare_old)}(?![\w/])", bare_new, text)
        return text


def within_foundation(old: str, new: str) -> Move:
    return Move(FOUNDATION + old, FOUNDATION + new)


MOVES = tuple(
    within_foundation(old, new)
    for old, new in (
        ("core/meta/class", "core/class"),
        ("core/meta/port", "core/port"),
        ("core/meta/constants", "core/constants"),
        ("core/meta/enum", "core/enum"),
        ("core/math/geometry", "math/geometry"),
        ("core/math/scalar", "math/scalar"),
        ("core/math/stats", "math/stats"),
        ("core/math/random", "math/weighted"),
        ("core/math/polynomial", "math/polynomial"),
        ("core/math/matrix", "math/matrix"),
        ("core/structs/polyline", "math/polyline"),
        ("core/structs/queue", "list/queue"),
        ("core/structs/ring", "list/ring"),
        ("core/structs/chain", "list/chain"),
        ("core/structs/slots", "list/slots"),
        ("core/scheduler", "list/schedule"),
        ("core/structs/heap", "tree/heap"),
        ("core/structs/tree", "tree/avl"),
        ("core/structs/sets", "map/sets"),
        ("core/structs/pairmap", "map/pairmap"),
        ("core/structs/grid", "map/grid"),
        ("core/structs/lease", "map/lease"),
        ("core/graph", "graph/search"),
        ("core/structs/cache", "cache/base"),
        ("core/structs/lru", "cache/lru"),
        ("core/structs/expiring", "cache/expiring"),
        ("core/structs/memo", "cache/memo"),
        ("core/cfsm", "generator/state_machine"),
        ("core/parsers/cursor", "encoding/cursor"),
        ("core/parsers/utf16", "encoding/utf16"),
        ("core/parsers/keyvalues", "encoding/keyvalues"),
        ("core/parsers/consolecfg", "encoding/consolecfg"),
        ("core/parsers/cvarfile", "encoding/cvarfile"),
        ("core/gma", "encoding/gma"),
        ("core/buffer", "file/buffer"),
        ("core/analytics", "analysis/analytics"),
        ("core/memory", "analysis/memory"),
        ("core/pathfinder", "npc/pathfinder"),
        ("npc/pathfinder", "graph/pathfinder"),
        ("core/transaction", "transaction"),
    )
) + tuple(
    Move(old, new)
    for old, new in (
        ("foundation/core/drawlist", "game/list/drawlist"),
        ("foundation/core/map_io", "game/world/io"),
        ("foundation/core/snapshot", "game/world/snapshot"),
        ("foundation/core/tactics", "game/gameplay/tactics"),
        ("foundation/core/hfsm", "game/generator/hfsm"),
        ("foundation/pathfinder/astar", "game/npc/astar"),
    )
)


class Conflict(Exception):
    """A move whose destination is taken, or whose module is nowhere."""


def planned_moves() -> list[tuple[Path, Path]]:
    """The git moves to make, in order, each seeing the moves before it."""
    moved_in: set[Path] = set()
    moved_out: set[Path] = set()

    def exists(path: Path) -> bool:
        return path in moved_in or ((REPO / path).exists() and path not in moved_out)

    pairs = []
    for move in MOVES:
        for (old, new), is_module in ((move.files, True), (move.tests, False)):
            if exists(old) and exists(new):
                raise Conflict(f"{new} exists; {old} cannot move there")
            if exists(old):
                pairs.append((old, new))
                moved_out.add(old)
                moved_in.add(new)
            elif is_module and not exists(new) and not any(
                later.old == move.new for later in MOVES
            ):
                raise Conflict(f"neither {old} nor {new} exists")
    return pairs


def lua_files() -> list[Path]:
    return sorted(p for root in SEARCHED for p in (REPO / root).rglob("*.lua"))


def rewrite_all(dry_run: bool) -> list[Path]:
    changed = []
    for path in lua_files():
        text = path.read_text()
        new = text
        for move in MOVES:
            new = move.rewrite(new)
        if new != text:
            changed.append(path.relative_to(REPO))
            if not dry_run:
                path.write_text(new)
    return changed


def remove_empty_dirs() -> None:
    for root in (REPO / GAMEMODE / "foundation", REPO / GAMEMODE / "game"):
        for directory in sorted(root.rglob("*"), reverse=True):
            if directory.is_dir() and not any(directory.iterdir()):
                directory.rmdir()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        moves = planned_moves()
    except Conflict as e:
        print(f"refused: {e}", file=sys.stderr)
        return 1
    for old, new in moves:
        print(f"move {old} -> {new}")
        if not args.dry_run:
            (REPO / new).parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "mv", str(old), str(new)], cwd=REPO, check=True)
    changed = rewrite_all(args.dry_run)
    for path in changed:
        print(f"rewrite {path}")
    if not args.dry_run:
        remove_empty_dirs()
    print(f"{len(moves)} moved, {len(changed)} rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
