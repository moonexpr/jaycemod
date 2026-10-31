#!/usr/bin/env python3
"""Class a dumped map's rooms from the incursion (classes.py) and draw them from above.

    python3 .devtools/bin/classes_view.py .devtools/artifacts/rooms/MAP.graph.json

Each level from above: every room filled by its class (rooms_view.py's
colours), a stronghold or commons paler the farther down its gradient
toward the highways it lies, corridors grey; the junction rooms carved
around the incursion forks outlined in black and hatched; and each team's
incursion tree over the spaces, a line from each space's entry to the
entry of the space it hangs from. The picture goes to <map>.classes.png
beside the graph, and the classes, the junctions and each team's tree are
summed up.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import classes
import incursion
import incursion_view
import places
import rooms_view
from rooms_view import MARGIN, TITLE

# The front's margin and how far is far, as shares of the walk between the
# spawns; the forks the junctions are carved around (each way a twentieth
# of the map), the reach of a junction and the floor it needs (a quarter
# of a room's least).
FRONT_SHARE, FAR_SHARE, FORK_SHARE = 0.05, 0.2, 0.05
JUNCTION_REACH, JUNCTION_FLOOR = 256, 10000
TREE_LINE = {"RED": (200, 0, 0), "BLU": (0, 60, 220)}
TREE_OFFSET = {"RED": -2, "BLU": 2}
CORRIDOR_FILL, AREA_EDGE, JUNCTION_EDGE = (175, 175, 175), (210, 210, 210), (0, 0, 0)
KEY_LINE = 22


def Pale(colour: tuple, gradient: float) -> tuple:
    """colour faded toward white as gradient falls from 1 to 0, never below a third."""
    keep = 1 / 3 + 2 / 3 * max(0.0, min(1.0, gradient))
    return tuple(round(255 - (255 - c) * keep) for c in colour)


def Fill(placed: classes.Classed) -> tuple:
    colour = rooms_view.ClassFill(places.Placed(placed.cls, placed.team))
    if placed.cls in (classes.STRONGHOLD, classes.COMMONS):
        return Pale(colour, placed.gradient if placed.cls == classes.STRONGHOLD else 1 - placed.gradient)
    return colour


def Run(dump, found):
    """Every stage: classed, junctions, trees (team -> classes.Branches), highways."""
    rooms, passages = rooms_view.Spaces(found)
    keyed = {team: rooms_view.Keyed(found, ids) for team, ids in dump.spawns.items()}
    room_edges = places.Graph(rooms, passages)
    restricted = places.Restricted(room_edges, {t: [k for k in ks if k in room_edges] for t, ks in keyed.items()},
                                   dump.seals)
    region = {aid: ("room" if found.rooms.get(space.id) is space else "passage", space.id)
              for aid, space in found.region.items()}
    edges = incursion.Edges(dump.graph, dump.windows)
    fields = incursion.Fields(edges, dump.spawns)
    routes = incursion.Routes(edges, dump.spawns, fields)
    highways = classes.Highways(routes, region, dump.objectives, restricted, dump.spawns)
    trees = {team: incursion.Grow(field, team, dump.graph) for team, field in fields.items()}
    branches = {team: classes.SpaceTree(tree, region) for team, tree in trees.items()}
    owner = {key: place.owner for place in places.Places(rooms, passages, keyed) for key in place.members}
    separation = incursion_view.Separation(fields, dump.spawns)
    outdoor = {("room", r.id) for r in found.rooms.values() if r.outdoor}
    classed = classes.Classify(edges, region, fields, restricted, highways, owner, outdoor,
                               FRONT_SHARE * separation, FAR_SHARE * separation)
    forks = sorted({a for tree in trees.values() for a in tree.Forks(FORK_SHARE)})
    junctions = classes.Junctions(forks, dump.graph, edges, region, classed, JUNCTION_REACH, JUNCTION_FLOOR)
    return classed, junctions, branches, highways


def Draw(dump, found, classed: dict, junctions: list, branches: dict, out: Path) -> None:
    count = max(found.levels, 1)
    x0, x1, y0, y1, scale = rooms_view.Frame(dump.areas)
    w, h = int((x1 - x0) * scale) + 2 * MARGIN, rooms_view.PanelHeight(dump.areas)
    image = Image.new("RGB", (w * count, h + TITLE + KEY_LINE * 5 + MARGIN), (255, 255, 255))
    pen = ImageDraw.Draw(image)
    font, small = ImageFont.load_default(size=13), ImageFont.load_default(size=10)
    levels = incursion_view.AreaLevels(dump, found)

    def At(level, x, y):
        return (level - 1) * w + MARGIN + (x - x0) * scale, TITLE + MARGIN + (y1 - y) * scale

    def Box(level, area):
        return [At(level, area.lo[0], area.hi[1]), At(level, area.hi[0], area.lo[1])]

    for level in range(1, count + 1):
        pen.text(((level - 1) * w + MARGIN, 4), f"{dump.map}: level {level}, room classes from the incursion",
                 fill=(0, 0, 0), font=font)
        pen.line([((level - 1) * w, 0), ((level - 1) * w, h)], fill=(0, 0, 0))
    blocks = {}
    for area in sorted(dump.areas.values(), key=lambda a: a.z):
        if area.id not in levels:
            continue
        space = found.region[area.id]
        is_room = found.rooms.get(space.id) is space
        box = Box(levels[area.id], area)
        pen.rectangle(box, fill=Fill(classed[("room", space.id)]) if is_room else CORRIDOR_FILL, outline=AREA_EDGE)
        if is_room:
            (ax, ay), (bx, by) = box
            b = blocks.get((space.id, levels[area.id]), (ax, ay, bx, by))
            blocks[(space.id, levels[area.id])] = (min(b[0], ax), min(b[1], ay), max(b[2], bx), max(b[3], by))
    for (rid, level), box in blocks.items():
        pen.rectangle(box, outline=(60, 60, 60), width=2)
    for junction in junctions:
        for aid in junction.areas:
            if aid in levels:
                box = Box(levels[aid], dump.areas[aid])
                rooms_view.Hatch(pen, box)
                pen.rectangle(box, outline=JUNCTION_EDGE, width=2)

    def Entry(space, branch):
        c = dump.graph[branch.entry[space]]["center"]
        return levels.get(branch.entry[space]), (c["x"], c["y"])

    for team, branch in sorted(branches.items()):
        d = TREE_OFFSET[team]
        for space, up in branch.parent.items():
            (la, pa), (lb, pb) = Entry(up, branch), Entry(space, branch)
            if la is None or lb is None:
                continue
            if la == lb:
                (ax, ay), (bx, by) = At(la, *pa), At(lb, *pb)
                pen.line([(ax + d, ay + d), (bx + d, by + d)], fill=TREE_LINE[team], width=2)
            pen.ellipse([At(lb, *pb)[0] - 3 + d, At(lb, *pb)[1] - 3 + d, At(lb, *pb)[0] + 3 + d,
                         At(lb, *pb)[1] + 3 + d], fill=TREE_LINE[team])
    for room in found.rooms.values():
        placed = classed[("room", room.id)]
        tag = ("S" if room.kind == "stairwell" else "O" if room.outdoor else "R") + str(room.id)
        name = placed.cls + (f" {placed.team}" if placed.team else "")
        if placed.cls in (classes.STRONGHOLD, classes.COMMONS) and placed.gradient < 1:
            name += f" {placed.gradient:.2f}"
        for level in room.levels:
            px, py = At(level, *room.center[:2])
            pen.text((px, py - 6), tag, fill=(0, 0, 0), font=font, anchor="mm", stroke_width=2,
                     stroke_fill=(255, 255, 255))
            pen.text((px, py + 7), name, fill=(0, 0, 0), font=small, anchor="mm", stroke_width=2,
                     stroke_fill=(255, 255, 255))
    top = h
    pen.line([(0, top), (w * count, top)], fill=(0, 0, 0))
    lines = [
        "Key: rooms filled by class (rooms_view's colours): restricted dark, highway orange, stronghold in its team's "
        "colour, commons yellow, unoccupied grey-green, wilds green; corridors grey",
        "stronghold and commons: a gradient from 1 at the team's buildings to 0 on the highways, d_highway / "
        "(d_highway + d_building); 0.5 or more a stronghold, the paler the lower; commons the paler the higher",
        "red and blue lines: each team's incursion tree over the rooms and corridors, from the entry of each to "
        "the entry of the space its walk enters it from (dots: entries)",
        f"black hatched: junction rooms, carved around incursion forks (each way {FORK_SHARE:.0%} of the map) in "
        f"corridors or unoccupied ground, the floor within {JUNCTION_REACH} units of the fork",
    ]
    for i, text in enumerate(lines):
        pen.text((MARGIN, top + 4 + i * KEY_LINE), text, fill=(0, 0, 0), font=font)
    image.save(out)


def Summary(found, classed: dict, junctions: list, branches: dict, highways: set) -> list:
    def Name(space):
        if space[0] == "passage":
            return f"C{space[1]}"
        room = found.rooms[space[1]]
        return ("S" if room.kind == "stairwell" else "O" if room.outdoor else "R") + str(room.id)
    counts = {}
    for placed in classed.values():
        name = placed.cls + (f" {placed.team}" if placed.team else "")
        counts[name] = counts.get(name, 0) + 1
    lines = ["classes: " + ", ".join(f"{n} {k}" for k, n in sorted(counts.items())),
             "highways: " + ", ".join(sorted(Name(s) for s in highways))]
    lines.append(f"junctions: {len(junctions)}: " + ", ".join(
        f"{len(j.areas)} areas of {Name(j.space)}" for j in junctions))
    for team, branch in sorted(branches.items()):
        forks = sorted((Name(s), len(k)) for s, k in branch.children.items() if len(k) >= 3)
        lines.append(f"{team}'s tree: {len(branch.entry)} spaces from {', '.join(Name(r) for r in branch.roots)}; "
                     "spaces it branches three ways or more from: " + ", ".join(f"{n} ({k})" for n, k in forks))
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("graph", type=Path)
    args = parser.parse_args()
    dump = rooms_view.LoadDump(args.graph)
    found = rooms_view.Partition(dump)
    classed, junctions, branches, highways = Run(dump, found)
    out = args.graph.with_name(f"{dump.map}.classes.png")
    Draw(dump, found, classed, junctions, branches, out)
    print("\n".join(Summary(found, classed, junctions, branches, highways)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
