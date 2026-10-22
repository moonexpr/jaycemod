#!/usr/bin/env python3
"""Move foundation.core's generic modules into foundation's namespaces.

docs/foundation-game-split-plan.md, stage 1: each module (and its test) moves
with `git mv`, and every Lua file under addons/, tests/ and .devtools/bin/ has
the old name rewritten, dotted (foundation.core.structs.heap) and slashed
(core/structs/heap). A second run finds nothing to move and nothing to
rewrite, so it can run again over files merged in later.

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
FOUNDATION = Path("addons/sandcastle/gamemodes/sandcastle/gamemode/foundation")
TESTS = Path("tests")
SEARCHED = ("addons", "tests", ".devtools/bin")


@dataclass(frozen=True)
class Move:
    """A module's path under foundation/, before and after, without .lua."""

    old: str
    new: str

    def __post_init__(self) -> None:
        for path in (self.old, self.new):
            if not re.fullmatch(r"[a-z_][a-z0-9_]*(/[a-z_][a-z0-9_]*)*", path):
                raise ValueError(f"not a module path: {path!r}")

    @property
    def files(self) -> tuple[Path, Path]:
        return FOUNDATION / f"{self.old}.lua", FOUNDATION / f"{self.new}.lua"

    @property
    def tests(self) -> tuple[Path, Path]:
        def test(path: str) -> Path:
            return TESTS / f"{path.replace('/', '_')}_test.lua"

        return test(self.old), test(self.new)

    def rewrite(self, text: str) -> str:
        dotted_old, dotted_new = (p.replace("/", ".") for p in (self.old, self.new))
        test_old, test_new = (p.stem for p in self.tests)
        text = re.sub(rf"(?<![\w]){re.escape(test_old)}(?![\w])", test_new, text)
        text = re.sub(
            rf"\bfoundation\.{re.escape(dotted_old)}(?![\w])",
            f"foundation.{dotted_new}",
            text,
        )
        return re.sub(
            rf"(?<![\w.])(foundation/)?{re.escape(self.old)}(?![\w/])",
            lambda m: (m.group(1) or "") + self.new,
            text,
        )


MOVES = tuple(
    Move(old, new)
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
        ("core/transaction", "transaction"),
    )
)


class Conflict(Exception):
    """A move whose destination is taken, or whose source is gone with no destination."""


def planned_moves() -> list[tuple[Path, Path]]:
    pairs = []
    for move in MOVES:
        for old, new in (move.files, move.tests):
            source, target = REPO / old, REPO / new
            if source.exists() and target.exists():
                raise Conflict(f"{new} exists; {old} cannot move there")
            if source.exists():
                pairs.append((old, new))
            elif not target.exists() and old.suffix == ".lua" and old.parent != TESTS:
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
        for directory in sorted((REPO / FOUNDATION / "core").rglob("*"), reverse=True):
            if directory.is_dir() and not any(directory.iterdir()):
                directory.rmdir()
    print(f"{len(moves)} moved, {len(changed)} rewritten")
    return 0


if __name__ == "__main__":
    sys.exit(main())
