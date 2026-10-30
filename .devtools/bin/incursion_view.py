#!/usr/bin/env python3
"""Draw each team's incursion routes over a dumped map's rooms, the baseline traffic.

    python3 .devtools/bin/incursion_view.py .devtools/artifacts/rooms/MAP.graph.json

Each level from above, as rooms_view.py draws it: every area tinted by the
side whose walk reaches it first (the front, incursion.Front), the rooms'
blocks outlined, each team's spawn areas marked, and each team's routes to
the enemy's spawn areas drawn as smooth curves (a quadratic Bézier in each
area, from the edge in to the edge out, bent through its middle), wider
where more of them share a piece. The picture goes to <map>.incursion.png beside the
graph, and a summary is printed: the routes' lengths, the share of the map
each side reaches first, and the rooms and corridors the most routes cross.
"""
import argparse
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import incursion
import rooms_view
from rooms_view import MARGIN, TITLE

# The front's margin: within a twentieth of the walk between the spawns of
# both teams' reach, an area is no one's.
FRONT_SHARE = 0.05
SIDE_FILL = {"RED": (255, 214, 214), "BLU": (214, 226, 255), None: (255, 244, 186)}
TEAM_LINE = {"RED": (200, 0, 0), "BLU": (0, 60, 220)}
TEAM_OFFSET = {"RED": -2, "BLU": 2}       # pixels, so the two teams' routes on one step both show
SPAWN_FILL = {"RED": (120, 0, 0), "BLU": (0, 30, 130)}
AREA_EDGE, BLOCK_EDGE, UNREACHED = (200, 200, 200), (70, 70, 70), (255, 255, 255)
LINE_MIN, LINE_MAX = 2, 9
BEZIER_SAMPLES = 12
KEY = [("RED first", "RED's walk from its spawns reaches the area first", SIDE_FILL["RED"]),
       ("BLU first", "BLU's walk reaches it first", SIDE_FILL["BLU"]),
       ("the front", f"both walks reach it within {FRONT_SHARE:.0%} of the walk between the spawns", SIDE_FILL[None]),
       ("RED's routes", "RED's shortest walks to each of BLU's spawn areas; wider, more of them", TEAM_LINE["RED"]),
       ("BLU's routes", "BLU's to each of RED's", TEAM_LINE["BLU"]),
       ("spawn areas", "where each team's spawns stand, dark in its colour", SPAWN_FILL["RED"])]
KEY_LINE = 22
KEY_HEIGHT = TITLE + KEY_LINE * ((len(KEY) + 1) // 2) + MARGIN


def AreaLevels(dump, found) -> dict:
    """Each area's level: its space's, or for a space spanning levels the one its floor is nearest."""
    heights = {}
    for aid, space in found.region.items():
        if space.level == space.top:
            heights.setdefault(space.level, []).append(dump.areas[aid].z)
    middle = {level: statistics.median(zs) for level, zs in heights.items()}
    level = {}
    for aid, space in found.region.items():
        span = [l for l in space.levels if l in middle] or [space.level]
        level[aid] = min(span, key=lambda l: abs(middle.get(l, 0) - dump.areas[aid].z))
    return level


def Bezier(start: tuple, control: tuple, end: tuple, samples: int = BEZIER_SAMPLES) -> list:
    """A quadratic Bézier curve from start to end, pulled toward control, as samples + 1 points."""
    def At(t):
        return tuple((1 - t) ** 2 * s + 2 * (1 - t) * t * c + t ** 2 * e for s, c, e in zip(start, control, end))
    return [At(i / samples) for i in range(samples + 1)]


def Pieces(areas: tuple) -> list:
    """A route's pieces, one an area it passes through: (the area before or None, the area, the one after
    or None). Each is drawn from the edge it comes in by to the edge it leaves by, curving through the
    area's middle, so the pieces join smoothly; a route's ends start and stop at its end areas' middles."""
    if len(areas) < 2:
        return []
    padded = (None,) + tuple(areas) + (None,)
    return [padded[i - 1:i + 2] for i in range(1, len(padded) - 1)]


def Separation(fields: dict, spawns: dict) -> float:
    """The shortest walk from one team's spawns to the other's."""
    return min(f.distance.get(a, float("inf")) for team, f in fields.items()
               for enemy, areas in spawns.items() if enemy != team for a in areas)


def Draw(dump, found, fields, routes, side, out: Path) -> None:
    count = max(found.levels, 1)
    x0, x1, y0, y1, scale = rooms_view.Frame(dump.areas)
    w, h = int((x1 - x0) * scale) + 2 * MARGIN, rooms_view.PanelHeight(dump.areas)
    image = Image.new("RGB", (w * count, h + KEY_HEIGHT), (255, 255, 255))
    pen = ImageDraw.Draw(image)
    font, small = ImageFont.load_default(size=13), ImageFont.load_default(size=10)
    levels = AreaLevels(dump, found)

    def At(level, x, y):
        return (level - 1) * w + MARGIN + (x - x0) * scale, TITLE + MARGIN + (y1 - y) * scale

    for level in range(1, count + 1):
        pen.text(((level - 1) * w + MARGIN, 4), f"{dump.map}: level {level}, incursion routes", fill=(0, 0, 0),
                 font=font)
        pen.line([((level - 1) * w, 0), ((level - 1) * w, h)], fill=(0, 0, 0))
    blocks = {}
    for area in sorted(dump.areas.values(), key=lambda a: a.z):
        if area.id not in levels:
            continue
        level = levels[area.id]
        box = [At(level, area.lo[0], area.hi[1]), At(level, area.hi[0], area.lo[1])]
        pen.rectangle(box, fill=SIDE_FILL[side[area.id]] if area.id in side else UNREACHED, outline=AREA_EDGE)
        space = found.region[area.id]
        if found.rooms.get(space.id) is space:
            (ax, ay), (bx, by) = box
            b = blocks.get((space.id, level), (ax, ay, bx, by))
            blocks[(space.id, level)] = (min(b[0], ax), min(b[1], ay), max(b[2], bx), max(b[3], by))
    for (rid, level), box in blocks.items():
        pen.rectangle(box, outline=BLOCK_EDGE, width=2)
        room = found.rooms[rid]
        tag = ("S" if room.kind == "stairwell" else "O" if room.outdoor else "R") + str(rid)
        pen.text((box[0] + 3, box[1] + 2), tag, fill=BLOCK_EDGE, font=small)
    for team, areas in dump.spawns.items():
        for aid in areas:
            if aid in levels:
                a = dump.areas[aid]
                pen.rectangle([At(levels[aid], a.lo[0], a.hi[1]), At(levels[aid], a.hi[0], a.lo[1])],
                              fill=SPAWN_FILL[team])
    pieces = {}
    for route in routes:
        for piece in Pieces(route.areas):
            pieces[(route.team,) + piece] = pieces.get((route.team,) + piece, 0) + 1
    most = max(pieces.values(), default=1)

    def Middle(a, b):
        m = next(l["middle"] for l in dump.graph[a]["links"] if l["to"] == b)
        return m["x"], m["y"]

    for (team, before, area, after), n in sorted(pieces.items(), key=lambda kv: kv[1]):
        if area not in levels:
            continue
        c = dump.graph[area]["center"]
        middle = (c["x"], c["y"])
        start = Middle(before, area) if before is not None else middle
        end = Middle(area, after) if after is not None else middle
        d = TEAM_OFFSET[team]
        curve = [At(levels[area], x, y) for x, y in Bezier(start, middle, end)]
        pen.line([(x + d, y + d) for x, y in curve], fill=TEAM_LINE[team],
                 width=round(LINE_MIN + (LINE_MAX - LINE_MIN) * n / most), joint="curve")
    pen.line([(0, h), (w * count, h)], fill=(0, 0, 0))
    pen.text((MARGIN, h + 4), "Key", fill=(0, 0, 0), font=font)
    column = w * count // 2
    for i, (name, means, colour) in enumerate(KEY):
        x, y = MARGIN + (i % 2) * column, h + TITLE + (i // 2) * KEY_LINE
        pen.rectangle([x, y + 2, x + 28, y + KEY_LINE - 6], fill=colour, outline=(0, 0, 0))
        pen.text((x + 36, y + 2), f"{name}: {means}", fill=(0, 0, 0), font=font)
    image.save(out)


def Summary(dump, found, fields, routes, side) -> list:
    lines = []
    for team in sorted(fields):
        mine = sorted(r.length for r in routes if r.team == team)
        if mine:
            lines.append(f"{team}: {len(mine)} routes from {len(set(dump.spawns[team]))} spawn areas, "
                         f"{mine[0]:.0f} to {mine[-1]:.0f} units long (median {statistics.median(mine):.0f})")
    shares = {}
    for s in side.values():
        shares[s] = shares.get(s, 0) + 1
    lines.append("reached first: " + ", ".join(f"{k or 'the front'} {n} areas" for k, n in
                                              sorted(shares.items(), key=lambda kv: str(kv[0]))))
    crossed = {}
    for route in routes:
        for space in {found.region[a] for a in route.areas if a in found.region}:
            key = ("S" if space.kind == "stairwell" else "C" if space.kind == "corridor" else
                   "O" if space.outdoor else "R") + str(space.id)
            counts = crossed.setdefault(key, {})
            counts[route.team] = counts.get(route.team, 0) + 1
    busiest = sorted(crossed.items(), key=lambda kv: -sum(kv[1].values()))[:12]
    lines.append("most crossed: " + ", ".join(
        f"{k} ({' '.join(f'{t} {n}' for t, n in sorted(c.items()))})" for k, c in busiest))
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("graph", type=Path)
    args = parser.parse_args()
    dump = rooms_view.LoadDump(args.graph)
    found = rooms_view.Partition(dump)
    edges = incursion.Edges(dump.graph)
    fields = incursion.Fields(edges, dump.spawns)
    routes = incursion.Routes(edges, dump.spawns, fields)
    side = incursion.Front(fields, FRONT_SHARE * Separation(fields, dump.spawns))
    out = args.graph.with_name(f"{dump.map}.incursion.png")
    Draw(dump, found, fields, routes, side, out)
    print("\n".join(Summary(dump, found, fields, routes, side)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
