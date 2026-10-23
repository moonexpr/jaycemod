#!/usr/bin/env python3
"""Read published modules by their globals, not by require.

A module foundation's indexes or games' inits publish (shared_loader.lua) is
read by its global: `local Geometry = math.geometry`, not
`require("foundation.math.geometry")`, `WS.require(...)` or the test
harness's `T.require(...)`. A module's own parts, features' and ws/'s
modules are not published and keep require.

Every Lua file under addons/, tests/ and .devtools/bin/ is rewritten, except
the loader, the indexes and the test harness (the tests' loader). A site is
left as it is when the global's first name could be
shadowed there: at a file's top level, by a top-level local of that name
declared above it; inside a function, by any local, parameter or loop
variable of that name in the file. A second run finds nothing to rewrite.

    foundation_globals.py [--dry-run] [--kept]
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GAMEMODE = REPO / "addons/sandcastle/gamemodes/sandcastle/gamemode"
LOADER = GAMEMODE / "shared_loader.lua"

INDEX_CALL = re.compile(r'Index\(\s*"([\w/.]+)"\s*\)')
NAMESPACE = re.compile(r'local\s+(\w+)\s*=\s*Namespace\(\s*"(\w+)"\s*\)')
EXPORT = re.compile(r'Export\(\s*(\w+)\s*,\s*"(\w+)"\s*,\s*require\(\s*"([\w.]+)"\s*\)\s*\)')
DEFER = re.compile(r'Defer\(\s*(\w+)\s*,\s*"(\w+)"\s*,\s*"([\w.]+)"\s*\)')
SITE = re.compile(r'(?<![\w.])(?:[A-Za-z_]\w*\.)?require\(\s*["\']([\w.]+)["\']\s*\)')
SEARCHED = ("addons", "tests", ".devtools/bin")
HARNESS = REPO / "tests/harness.lua"
DECLARED = re.compile(
    r'\blocal\s+function\s+(\w+)'
    r'|\blocal\s+([\w\s,]+?)\s*(?==|\n|$)'
    r'|\bfunction\b[\w\s.:]*\(([^)]*)\)'
    r'|\bfor\s+([\w\s,]+?)\s+(?:in|=)\b',
    re.M,
)


def published() -> dict[str, str]:
    """module name -> its global, read from the indexes the loader runs."""
    names: dict[str, str] = {}
    for path in INDEX_CALL.findall(LOADER.read_text()):
        text = (GAMEMODE / path).read_text()
        spaces = {"_G": ""} | {var: name + "." for var, name in NAMESPACE.findall(text)}
        for var, key, module in EXPORT.findall(text) + DEFER.findall(text):
            names[module] = spaces[var] + key
    return names


def declared_names(text: str) -> set[str]:
    """Every name the file declares anywhere: locals, parameters, loop variables."""
    names: set[str] = set()
    for groups in DECLARED.findall(text):
        for group in groups:
            names |= {n.strip() for n in group.split(",") if n.strip()}
    return names


def top_level_locals_before(text: str, offset: int) -> set[str]:
    """The names top-level `local` statements above offset declare."""
    names: set[str] = set()
    for line in text[:offset].splitlines():
        m = re.match(r'local\s+(?:function\s+(\w+)|([\w\s,]+?)\s*(?:=|$))', line)
        if m:
            names |= {n.strip() for n in (m.group(1) or m.group(2)).split(",") if n.strip()}
    return names


@dataclass(frozen=True)
class Kept:
    path: Path
    line: int
    module: str
    shadow: str


def rewrite(text: str, path: Path, names: dict[str, str], kept: list[Kept]) -> str:
    anywhere = declared_names(text)
    out, last = [], 0
    for m in SITE.finditer(text):
        module = m.group(1)
        if module not in names:
            continue
        global_name = names[module]
        first = global_name.split(".")[0]
        line_start = text.rfind("\n", 0, m.start()) + 1
        top_level = not text[line_start:m.start()].startswith((" ", "\t"))
        shadowed = first in (top_level_locals_before(text, line_start) if top_level else anywhere)
        if shadowed:
            kept.append(Kept(path, text.count("\n", 0, m.start()) + 1, module, first))
            continue
        out.append(text[last:m.start()])
        out.append(global_name)
        last = m.end()
    out.append(text[last:])
    return "".join(out)


def candidates() -> list[Path]:
    skip = {LOADER, HARNESS}
    files = []
    for root in SEARCHED:
        for path in sorted((REPO / root).rglob("*.lua")):
            if path in skip or path.name.endswith(("_index.lua", "_init.lua")):
                continue
            files.append(path)
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--kept", action="store_true", help="list the sites left as require")
    args = parser.parse_args()
    names = published()
    kept: list[Kept] = []
    changed = 0
    for path in candidates():
        text = path.read_text()
        new = rewrite(text, path, names, kept)
        if new != text:
            changed += 1
            if not args.dry_run:
                path.write_text(new)
    if args.kept:
        for k in kept:
            print(f"kept {k.path.relative_to(REPO)}:{k.line}: {k.module} ({k.shadow} is declared there)")
    print(f"{len(names)} published, {changed} files rewritten, {len(kept)} sites kept as require")
    return 0


if __name__ == "__main__":
    sys.exit(main())
