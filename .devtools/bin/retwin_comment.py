#!/usr/bin/env python3
"""Mark foundation modules as Lua twins once their native twin lands.

For each module name given (list.queue, world.grid, transaction), the
module's file under gamemode/foundation/ loses its "Core-rule exception:
stays Lua" comment block, and gains, just above its first line of code, the
note that it is the Lua twin a server with native/foundation replaces. A
file that already carries the note is left alone.

    python3 .devtools/bin/retwin_comment.py world.pairmap world.lease
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
FOUNDATION = ROOT / "addons/sandcastle/gamemodes/sandcastle/gamemode/foundation"
NOTE = [
    "-- This is the Lua twin, which clients run; a server with native/foundation",
    "-- has the native one in its place, which keeps this contract.",
]


def retwin(module: str) -> str:
    path = FOUNDATION / (module.replace(".", "/") + ".lua")
    lines = path.read_text().split("\n")
    if NOTE[0] in lines:
        return f"{module}: already the Lua twin"
    kept, skipping = [], False
    for line in lines:
        if line.startswith("-- Core-rule exception"):
            skipping = True
            continue
        if skipping and line.startswith("-- "):
            continue
        skipping = False
        kept.append(line)
    first_code = next(i for i, line in enumerate(kept) if not line.startswith("--"))
    kept[first_code:first_code] = NOTE
    path.write_text("\n".join(kept))
    return f"{module}: marked"


if __name__ == "__main__":
    for name in sys.argv[1:]:
        print(retwin(name))
