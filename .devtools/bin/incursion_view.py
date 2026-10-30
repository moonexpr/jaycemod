#!/usr/bin/env python3
"""Draw each team's incursion routes over a dumped map's rooms, the baseline traffic.

    python3 .devtools/bin/incursion_view.py .devtools/artifacts/rooms/MAP.graph.json

Each level from above, as rooms_view.py draws it: every area tinted by the
side whose walk reaches it first (the front, incursion.Front), the rooms'
blocks outlined, each team's spawn areas marked, and each team's routes to
the enemy's spawn areas (highways bold, other options pale) drawn as smooth curves (a quadratic Bézier in each
area, from the edge in to the edge out, bent through its middle), wider
where more of them share a piece. The picture goes to <map>.incursion.png beside the
graph, and a summary is printed: the routes' lengths, the share of the map
each side reaches first, and the rooms and corridors the most routes cross.

Beside it, <map>.tree.png draws each team's incursion tree (incursion.Grow)
in a row of its own: every area joined to the one the team's walk reaches
it from, wider the more floor is reached through it, the forks where a
branch splits into ways each reaching FORK_SHARE of the map ringed, and
over it the team's breaching paths (incursion.Breaches): the fewest paths
from its spawns along the tree covering COVER_SHARE of the map, ground
within COVER_REACH of a path tinted, each numbered at its end in the
order taken; the summary names the forks and each breach's end and gain.

And <map>.ambush.png, a row a defending team: the enemy's highways and
breaches, the entrances they make into rooms (ambush.Entrances), and the
hiding spots that cover each (ambush.Ambushes), joined to the entrance.
"""
import argparse
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import ambush
import incursion
import rooms_view
from rooms_view import MARGIN, TITLE

# The front's margin: within a twentieth of the walk between the spawns of
# both teams' reach, an area is no one's.
FRONT_SHARE = 0.05
SIDE_FILL = {"RED": (255, 214, 214), "BLU": (214, 226, 255), None: (255, 244, 186)}
TEAM_LINE = {"RED": (200, 0, 0), "BLU": (0, 60, 220)}
OPTION_LINE = {"RED": (240, 130, 130), "BLU": (120, 160, 245)}
TEAM_OFFSET = {"RED": -2, "BLU": 2}       # pixels, so the two teams' routes on one step both show
SPAWN_FILL = {"RED": (120, 0, 0), "BLU": (0, 30, 130)}
AREA_EDGE, BLOCK_EDGE, UNREACHED = (200, 200, 200), (70, 70, 70), (255, 255, 255)
LINE_MIN, LINE_MAX, OPTION_MAX = 2, 9, 5
BEZIER_SAMPLES = 12
WINDOW_FILL, WINDOW_MARK = (0, 220, 255), 7
KEY = [("RED first", "RED's walk from its spawns reaches the area first", SIDE_FILL["RED"]),
       ("BLU first", "BLU's walk reaches it first", SIDE_FILL["BLU"]),
       ("the front", f"both walks reach it within {FRONT_SHARE:.0%} of the walk between the spawns", SIDE_FILL[None]),
       ("RED's highways", "RED's shortest walks to each of BLU's spawn areas; wider, more of them", TEAM_LINE["RED"]),
       ("RED's other options", "its other ways, each new and at most half again as long", OPTION_LINE["RED"]),
       ("BLU's highways", "BLU's to each of RED's", TEAM_LINE["BLU"]),
       ("BLU's other options", "its other ways", OPTION_LINE["BLU"]),
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


def BrokenWindows(pen, at, crossings: dict, levels: dict, areas: tuple) -> None:
    """A diamond where a path breaks through a window."""
    for a, b in zip(areas, areas[1:]):
        step = crossings[(a, b)]
        if step.window and b in levels:
            x, y = at(levels[b], *step.via[:2])
            pen.polygon([(x, y - WINDOW_MARK), (x + WINDOW_MARK, y), (x, y + WINDOW_MARK), (x - WINDOW_MARK, y)],
                        fill=WINDOW_FILL, outline=(0, 0, 0))


def Draw(dump, found, fields, routes, side, crossings: dict, out: Path) -> None:
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
            key = (route.alternative, route.team) + piece
            pieces[key] = pieces.get(key, 0) + 1
    most = max(pieces.values(), default=1)

    def Middle(a, b):
        return crossings[(a, b)].via[:2]

    # the other options beneath, the highways over them
    for (option, team, before, area, after), n in sorted(pieces.items(), key=lambda kv: (not kv[0][0], kv[1])):
        if area not in levels:
            continue
        c = dump.graph[area]["center"]
        middle = (c["x"], c["y"])
        start = Middle(before, area) if before is not None else middle
        end = Middle(area, after) if after is not None else middle
        d = TEAM_OFFSET[team]
        curve = [At(levels[area], x, y) for x, y in Bezier(start, middle, end)]
        top = OPTION_MAX if option else LINE_MAX
        pen.line([(x + d, y + d) for x, y in curve], fill=(OPTION_LINE if option else TEAM_LINE)[team],
                 width=round(LINE_MIN + (top - LINE_MIN) * n / most), joint="curve")
    for route in routes:
        BrokenWindows(pen, At, crossings, levels, route.areas)
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
        mine = sorted(r.length for r in routes if r.team == team and not r.alternative)
        options = [r for r in routes if r.team == team and r.alternative]
        if mine:
            lines.append(f"{team}: {len(mine)} highways from {len(set(dump.spawns[team]))} spawn areas, "
                         f"{mine[0]:.0f} to {mine[-1]:.0f} units long (median {statistics.median(mine):.0f}), "
                         f"and {len(options)} other options")
    highway = {a for r in routes if not r.alternative for a in r.areas}
    every = {a for r in routes for a in r.areas}
    lines.append(f"covered: highways {len(highway)} areas, with the other options {len(every)} of {len(side)}")
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


TREE_MIN, TREE_MAX = 1, 10
# The breaching paths: the fewest from a team's spawns covering COVER_SHARE
# of the map, an area covered within COVER_REACH (about a room's depth) of
# a path's.
COVER_SHARE, COVER_REACH = 0.9, 256
BREACH_WIDTH = 4
COVERED_FILL = {"RED": (255, 226, 226), "BLU": (226, 234, 255)}
# A fork: a branch splitting into ways each carrying a tenth of the tree's floor.
FORK_SHARE = 0.1
FORK_RADIUS = 7
TREE_KEY = [("breach", f"the fewest paths from the spawns along the tree covering {COVER_SHARE:.0%} of the map, "
             f"numbered at their ends in the order taken; ground within {COVER_REACH} units of one is tinted", None),
            ("branch", "pale: each area joined to the one its team's walk reaches it from; wider, the more floor is "
             "reached through it (the square root of its share)", None),
            ("window", f"a breakable window or brush a breach breaks through ({incursion.WINDOW_COST} units' "
             "walk to break and climb over)", None),
            ("fork", f"where a branch splits into ways each reaching {FORK_SHARE:.0%} of the map or more", None),
            ("spawn areas", "the tree's roots, dark in the team's colour", None)]


def DrawTrees(dump, found, trees: dict, breaches: dict, covered: dict, crossings: dict, out: Path) -> None:
    """Each team's tree in a row of its own, one panel a level, its breaching paths over it."""
    count = max(found.levels, 1)
    x0, x1, y0, y1, scale = rooms_view.Frame(dump.areas)
    w, h = int((x1 - x0) * scale) + 2 * MARGIN, rooms_view.PanelHeight(dump.areas)
    teams = sorted(trees)
    key_top = h * len(teams)
    image = Image.new("RGB", (w * count, key_top + TITLE + KEY_LINE * len(TREE_KEY) + MARGIN), (255, 255, 255))
    pen = ImageDraw.Draw(image)
    font, small = ImageFont.load_default(size=13), ImageFont.load_default(size=10)
    levels = AreaLevels(dump, found)

    def Middle(a, b):
        return crossings[(a, b)].via[:2]

    def Centre(a):
        c = dump.graph[a]["center"]
        return c["x"], c["y"]

    for row, team in enumerate(teams):
        tree, top = trees[team], row * h

        def At(level, x, y):
            return (level - 1) * w + MARGIN + (x - x0) * scale, top + TITLE + MARGIN + (y1 - y) * scale

        for level in range(1, count + 1):
            pen.text(((level - 1) * w + MARGIN, top + 4), f"{dump.map}: level {level}, {team}'s incursion tree",
                     fill=(0, 0, 0), font=font)
            pen.line([((level - 1) * w, top), ((level - 1) * w, top + h)], fill=(0, 0, 0))
        pen.line([(0, top), (w * count, top)], fill=(0, 0, 0))
        blocks = {}
        for area in dump.areas.values():
            if area.id not in levels:
                continue
            level = levels[area.id]
            box = [At(level, area.lo[0], area.hi[1]), At(level, area.hi[0], area.lo[1])]
            fill = COVERED_FILL[team] if area.id in covered[team] else (250, 250, 250)
            pen.rectangle(box, fill=fill if area.id in tree.weight else UNREACHED, outline=AREA_EDGE)
            space = found.region[area.id]
            if found.rooms.get(space.id) is space:
                (ax, ay), (bx, by) = box
                b = blocks.get((space.id, level), (ax, ay, bx, by))
                blocks[(space.id, level)] = (min(b[0], ax), min(b[1], ay), max(b[2], bx), max(b[3], by))
        for (rid, level), box in blocks.items():
            pen.rectangle(box, outline=BLOCK_EDGE, width=1)
            room = found.rooms[rid]
            tag = ("S" if room.kind == "stairwell" else "O" if room.outdoor else "R") + str(rid)
            pen.text((box[0] + 3, box[1] + 2), tag, fill=BLOCK_EDGE, font=small)
        for aid in tree.roots:
            if aid in levels:
                a = dump.areas[aid]
                pen.rectangle([At(levels[aid], a.lo[0], a.hi[1]), At(levels[aid], a.hi[0], a.lo[1])],
                              fill=SPAWN_FILL[team])
        total = sum(tree.weight[r] for r in tree.roots)
        for area, parent in sorted(tree.parent.items(), key=lambda kv: tree.weight[kv[0]]):
            if area not in levels or parent not in levels:
                continue
            width = round(TREE_MIN + (TREE_MAX - TREE_MIN) * (tree.weight[area] / total) ** 0.5)
            start, middle, end = Centre(parent), Middle(parent, area), Centre(area)
            if levels[area] == levels[parent]:
                pen.line([At(levels[area], x, y) for x, y in Bezier(start, middle, end)], fill=OPTION_LINE[team],
                         width=width, joint="curve")
            else:
                pen.line([At(levels[parent], *start), At(levels[parent], *middle)], fill=OPTION_LINE[team],
                         width=width)
                pen.line([At(levels[area], *middle), At(levels[area], *end)], fill=OPTION_LINE[team], width=width)
        for number, breach in enumerate(breaches[team], 1):
            for before, area, after in Pieces(breach.areas):
                if area not in levels:
                    continue
                start = Middle(before, area) if before is not None else Centre(area)
                end = Middle(area, after) if after is not None else Centre(area)
                pen.line([At(levels[area], x, y) for x, y in Bezier(start, Centre(area), end)], fill=TEAM_LINE[team],
                         width=BREACH_WIDTH, joint="curve")
            BrokenWindows(pen, At, crossings, levels, breach.areas)
            leaf = breach.areas[-1]
            if leaf in levels:
                pen.text(At(levels[leaf], *Centre(leaf)), str(number), fill=(0, 0, 0), font=font, anchor="mm",
                         stroke_width=2, stroke_fill=(255, 255, 255))
        for aid in tree.Forks(FORK_SHARE):
            if aid in levels:
                x, y = At(levels[aid], *Centre(aid))
                pen.ellipse([x - FORK_RADIUS, y - FORK_RADIUS, x + FORK_RADIUS, y + FORK_RADIUS], outline=(0, 0, 0),
                            width=2)
    pen.line([(0, key_top), (w * count, key_top)], fill=(0, 0, 0))
    pen.text((MARGIN, key_top + 4), "Key: one tree a team, from its spawns", fill=(0, 0, 0), font=font)
    for i, (name, means, _) in enumerate(TREE_KEY):
        y = key_top + TITLE + i * KEY_LINE
        if name == "breach":
            pen.line([(MARGIN, y + 8), (MARGIN + 14, y + 8)], fill=TEAM_LINE["RED"], width=BREACH_WIDTH)
            pen.line([(MARGIN + 14, y + 8), (MARGIN + 28, y + 8)], fill=TEAM_LINE["BLU"], width=BREACH_WIDTH)
        elif name == "branch":
            pen.line([(MARGIN, y + 8), (MARGIN + 14, y + 8)], fill=OPTION_LINE["RED"], width=6)
            pen.line([(MARGIN + 14, y + 8), (MARGIN + 28, y + 8)], fill=OPTION_LINE["BLU"], width=2)
        elif name == "window":
            pen.polygon([(MARGIN + 14, y + 1), (MARGIN + 21, y + 8), (MARGIN + 14, y + 15), (MARGIN + 7, y + 8)],
                        fill=WINDOW_FILL, outline=(0, 0, 0))
        elif name == "fork":
            pen.ellipse([MARGIN + 7, y + 1, MARGIN + 21, y + 15], outline=(0, 0, 0), width=2)
        else:
            pen.rectangle([MARGIN, y + 2, MARGIN + 14, y + 14], fill=SPAWN_FILL["RED"])
            pen.rectangle([MARGIN + 14, y + 2, MARGIN + 28, y + 14], fill=SPAWN_FILL["BLU"])
        pen.text((MARGIN + 36, y + 2), f"{name}: {means}", fill=(0, 0, 0), font=font)
    image.save(out)


def TreeSummary(found, trees: dict, breaches: dict) -> list:
    """Each tree's forks, by the room or corridor each stands in."""
    def Name(aid):
        space = found.region.get(aid)
        if space is None:
            return f"area {aid}"
        return ("S" if space.kind == "stairwell" else "C" if space.kind == "corridor" else
                "O" if space.outdoor else "R") + str(space.id)
    lines = []
    for team, tree in sorted(trees.items()):
        total = sum(tree.weight[r] for r in tree.roots)
        forks = []
        for aid in tree.Forks(FORK_SHARE):
            ways = sorted((tree.weight[k] / total for k in tree.children[aid] if tree.weight[k] >= FORK_SHARE * total),
                          reverse=True)
            forks.append(f"{Name(aid)} ({' / '.join(f'{s:.0%}' for s in ways)})")
        lines.append(f"{team}'s tree: {len(tree.weight)} areas from {len(tree.roots)} spawn areas; forks: "
                     + (", ".join(forks) or "none"))
        mine = breaches[team]
        shares = []
        for breach in mine:
            shares.append(breach.gain / total)
        ends = ", ".join(f"{i} to {Name(b.areas[-1])} +{s:.0%}" for i, (b, s) in enumerate(zip(mine, shares), 1))
        lines.append(f"{team}'s breaches: {len(mine)} paths cover {sum(shares):.0%} (within {COVER_REACH}): {ends}")
    return lines


# Ambush hints: the enemy's highways and breaches make the entrances; the
# approach is the last APPROACH of the walk up to one; a marking is a hiding
# spot between AMBUSH_NEAR and AMBUSH_FAR of the entrance (and AMBUSH_NEAR
# off the squad's line), up to AMBUSH_KEEP the entrance, nearest first.
APPROACH, AMBUSH_NEAR, AMBUSH_FAR, AMBUSH_KEEP = 384, 96, 768, 3
ENTRANCE_RADIUS, SPOT_SIZE = 9, 7
AMBUSH_KEY = [("enemy path", "the enemy's highways and breaches, pale in its colour", None),
              ("entrance", "where an enemy path steps into a room, ringed in the enemy's colour; the number, "
               "how many paths come through", None),
              ("ambush", f"a hiding spot for the defenders, joined to the entrance it covers: it sees just inside, "
               f"a player crouched at it is out of sight of the last {APPROACH} units of the approach, it lies "
               f"{AMBUSH_NEAR}-{AMBUSH_FAR} units off, and the defenders reach it before the enemy reaches the "
               f"entrance; up to {AMBUSH_KEEP} an entrance", None)]


def DrawAmbushes(dump, found, paths: list, entrances: list, ambushes: list, crossings: dict, out: Path) -> None:
    """A row for each defending team: the enemy's paths, its entrances and the markings covering them."""
    count = max(found.levels, 1)
    x0, x1, y0, y1, scale = rooms_view.Frame(dump.areas)
    w, h = int((x1 - x0) * scale) + 2 * MARGIN, rooms_view.PanelHeight(dump.areas)
    teams = sorted({a.team for a in ambushes} | {t for t, _ in paths})
    key_top = h * len(teams)
    image = Image.new("RGB", (w * count, key_top + TITLE + KEY_LINE * (len(AMBUSH_KEY) + 1) + MARGIN),
                      (255, 255, 255))
    pen = ImageDraw.Draw(image)
    font, small = ImageFont.load_default(size=13), ImageFont.load_default(size=10)
    levels = AreaLevels(dump, found)

    def Centre(a):
        c = dump.graph[a]["center"]
        return c["x"], c["y"]

    for row, team in enumerate(teams):
        top = row * h
        enemy = next(t for t in teams if t != team)

        def At(level, x, y):
            return (level - 1) * w + MARGIN + (x - x0) * scale, top + TITLE + MARGIN + (y1 - y) * scale

        for level in range(1, count + 1):
            pen.text(((level - 1) * w + MARGIN, top + 4),
                     f"{dump.map}: level {level}, {team} lying in wait for {enemy}", fill=(0, 0, 0), font=font)
            pen.line([((level - 1) * w, top), ((level - 1) * w, top + h)], fill=(0, 0, 0))
        pen.line([(0, top), (w * count, top)], fill=(0, 0, 0))
        blocks = {}
        for area in dump.areas.values():
            if area.id not in levels:
                continue
            level = levels[area.id]
            box = [At(level, area.lo[0], area.hi[1]), At(level, area.hi[0], area.lo[1])]
            pen.rectangle(box, fill=(250, 250, 250), outline=AREA_EDGE)
            space = found.region[area.id]
            if found.rooms.get(space.id) is space:
                (ax, ay), (bx, by) = box
                b = blocks.get((space.id, level), (ax, ay, bx, by))
                blocks[(space.id, level)] = (min(b[0], ax), min(b[1], ay), max(b[2], bx), max(b[3], by))
        for (rid, level), box in blocks.items():
            pen.rectangle(box, outline=BLOCK_EDGE, width=1)
            room = found.rooms[rid]
            tag = ("S" if room.kind == "stairwell" else "O" if room.outdoor else "R") + str(rid)
            pen.text((box[0] + 3, box[1] + 2), tag, fill=BLOCK_EDGE, font=small)
        for side, areas in dump.spawns.items():
            for aid in areas:
                if aid in levels:
                    a = dump.areas[aid]
                    pen.rectangle([At(levels[aid], a.lo[0], a.hi[1]), At(levels[aid], a.hi[0], a.lo[1])],
                                  fill=SPAWN_FILL[side])
        drawn = set()
        for walker, areas in paths:
            if walker != enemy:
                continue
            for a, b in zip(areas, areas[1:]):
                if (a, b) in drawn or a not in levels or b not in levels:
                    continue
                drawn.add((a, b))
                via = crossings[(a, b)].via[:2]
                pen.line([At(levels[a], *Centre(a)), At(levels[a], *via)], fill=OPTION_LINE[enemy], width=3)
                pen.line([At(levels[b], *via), At(levels[b], *Centre(b))], fill=OPTION_LINE[enemy], width=3)
        mine = [m for m in ambushes if m.team == team]
        for mark in mine:
            door, spot = mark.entrance, mark.spot
            if door.inside not in levels or spot.area not in levels:
                continue
            sx, sy = At(levels[spot.area], *spot.pos[:2])
            pen.line([(sx, sy), At(levels[door.inside], *door.via[:2])], fill=TEAM_LINE[team], width=1)
        for door in {m.entrance for m in mine} | {e for e in entrances_of(entrances, enemy)}:
            if door.inside not in levels:
                continue
            x, y = At(levels[door.inside], *door.via[:2])
            pen.ellipse([x - ENTRANCE_RADIUS, y - ENTRANCE_RADIUS, x + ENTRANCE_RADIUS, y + ENTRANCE_RADIUS],
                        outline=TEAM_LINE[enemy], width=3)
            pen.text((x + ENTRANCE_RADIUS + 2, y - ENTRANCE_RADIUS), str(door.paths), fill=TEAM_LINE[enemy], font=small)
        for mark in mine:
            spot = mark.spot
            if spot.area in levels:
                x, y = At(levels[spot.area], *spot.pos[:2])
                pen.polygon([(x, y - SPOT_SIZE), (x + SPOT_SIZE, y + SPOT_SIZE), (x - SPOT_SIZE, y + SPOT_SIZE)],
                            fill=TEAM_LINE[team], outline=(0, 0, 0))
    pen.line([(0, key_top), (w * count, key_top)], fill=(0, 0, 0))
    pen.text((MARGIN, key_top + 4), "Key: one row a defending team", fill=(0, 0, 0), font=font)
    for i, (name, means, _) in enumerate(AMBUSH_KEY):
        y = key_top + TITLE + i * KEY_LINE
        if name == "enemy path":
            pen.line([(MARGIN, y + 8), (MARGIN + 28, y + 8)], fill=OPTION_LINE["BLU"], width=3)
        elif name == "entrance":
            pen.ellipse([MARGIN + 6, y, MARGIN + 22, y + 16], outline=TEAM_LINE["BLU"], width=3)
        else:
            pen.polygon([(MARGIN + 14, y + 1), (MARGIN + 21, y + 15), (MARGIN + 7, y + 15)], fill=TEAM_LINE["RED"],
                        outline=(0, 0, 0))
        pen.text((MARGIN + 36, y + 2), f"{name}: {means}", fill=(0, 0, 0), font=font)
    image.save(out)


def entrances_of(entrances: list, team: str) -> list:
    return [e for e in entrances if e.team == team]


def Kept(ambushes: list) -> list:
    """Up to AMBUSH_KEEP markings an entrance and defending team, nearest first."""
    kept, count = [], {}
    for mark in ambushes:
        key = (mark.team, mark.entrance)
        if count.get(key, 0) < AMBUSH_KEEP:
            kept.append(mark)
            count[key] = count.get(key, 0) + 1
    return kept


def AmbushSummary(found, entrances: list, ambushes: list) -> list:
    def Name(space):
        return ("S" if space.kind == "stairwell" else "O" if space.outdoor else "R") + str(space.id)
    lines = []
    for team in sorted({a.team for a in ambushes}):
        mine = [m for m in ambushes if m.team == team]
        doors = {}
        for mark in mine:
            doors.setdefault(mark.entrance, []).append(mark)
        enemy_doors = [e for e in entrances if e.team != team]
        busiest = sorted(doors, key=lambda d: -d.paths)[:8]
        lines.append(f"{team} lying in wait: {len(mine)} markings at {len(doors)} of the enemy's "
                     f"{len(enemy_doors)} entrances; busiest: " + ", ".join(
                         f"{Name(found.region[d.inside])} ({d.paths} paths, {len(doors[d])} spots, nearest "
                         f"{doors[d][0].distance:.0f})" for d in busiest))
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("graph", type=Path)
    args = parser.parse_args()
    dump = rooms_view.LoadDump(args.graph)
    found = rooms_view.Partition(dump)
    edges = incursion.Edges(dump.graph, dump.windows)
    crossings = incursion.Crossings(edges)
    fields = incursion.Fields(edges, dump.spawns)
    routes = incursion.Routes(edges, dump.spawns, fields)
    side = incursion.Front(fields, FRONT_SHARE * Separation(fields, dump.spawns))
    out = args.graph.with_name(f"{dump.map}.incursion.png")
    Draw(dump, found, fields, routes, side, crossings, out)
    trees = {team: incursion.Grow(field, team, dump.graph) for team, field in fields.items()}
    near = incursion.Near(edges, COVER_REACH)
    breaches = {team: incursion.Breaches(tree, COVER_SHARE, near) for team, tree in trees.items()}
    covered = {team: {c for b in found_ for a in b.areas for c in near[a]} for team, found_ in breaches.items()}
    tree_out = args.graph.with_name(f"{dump.map}.tree.png")
    DrawTrees(dump, found, trees, breaches, covered, crossings, tree_out)
    paths = [(r.team, r.areas) for r in routes if not r.alternative] + \
        [(team, b.areas) for team, mine in breaches.items() for b in mine]
    region = {aid: ("room" if found.rooms.get(space.id) is space else "passage", space.id)
              for aid, space in found.region.items()}
    entrances = ambush.Entrances(paths, crossings, region, APPROACH)
    marks = Kept(ambush.Ambushes(entrances, dump.hiding, fields, AMBUSH_NEAR, AMBUSH_FAR))
    ambush_out = args.graph.with_name(f"{dump.map}.ambush.png")
    DrawAmbushes(dump, found, paths, entrances, marks, crossings, ambush_out)
    print("\n".join(Summary(dump, found, fields, routes, side) + TreeSummary(found, trees, breaches)
                    + AmbushSummary(found, entrances, marks)))
    print(out)
    print(tree_out)
    print(ambush_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
