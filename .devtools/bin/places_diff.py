"""The rooms whose starting class changes between a revision of places.py and the working tree's, on a dump:
    python3 .devtools/bin/places_diff.py .devtools/artifacts/rooms/<map>.graph.json [REV]
REV is HEAD by default. Each line: room, old class and team, new, its place, level and centre."""
import subprocess
import sys
from pathlib import Path

import places
import rooms_view


def ClassesAt(source: str, dump, found) -> dict:
    module = dict(vars(places))
    exec(compile(source, f"places.py@rev", "exec"), module)
    saved = rooms_view.places
    rooms_view.places = type(places)("places_rev")
    rooms_view.places.__dict__.update(module)
    try:
        return rooms_view.Classes(dump, found)
    finally:
        rooms_view.places = saved


def main() -> int:
    dump = rooms_view.LoadDump(Path(sys.argv[1]))
    rev = sys.argv[2] if len(sys.argv) > 2 else "HEAD"
    here = Path(__file__).resolve().parent
    source = subprocess.run(["git", "show", f"{rev}:./places.py"], cwd=here, capture_output=True, text=True,
                            check=True).stdout
    found = rooms_view.Partition(dump)
    old, new = ClassesAt(source, dump, found), rooms_view.Classes(dump, found)
    place = {key[1]: p for p in rooms_view.Places(dump, found) for key in p.members if key[0] == "room"}
    for rid in sorted(new):
        if (old[rid].cls, old[rid].team) != (new[rid].cls, new[rid].team):
            room, p = found.rooms[rid], place.get(rid)
            where = f"P{p.id} {p.kind} {p.owner}" if p else "-"
            x, y, z = (round(c) for c in room.center)
            print(f"{rid:3} {old[rid].cls} {old[rid].team} -> {new[rid].cls} {new[rid].team} | {where}"
                  f" | level {room.level} {'out' if room.outdoor else 'in'} ({x}, {y}, {z})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
