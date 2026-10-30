#!/usr/bin/env python3
"""Partition a dumped room graph with wartactics.rooms and draw it from above.

The graph is what rooms_dump.lua prints on the server (the AI war
controller's RoomGraph and the map's windows). LuaJIT runs the gamemode's
own Partition on it through the test harness, so the picture is what the
game would find; then each of the map's levels is drawn from above, side by
side: every area filled by its room's colour (pale outdoors), stairwells
hatched and drawn on each level they span, corridors grey, areas in nothing
white with a red edge, each room's block (its areas' extent) outlined, and
each room labelled (R indoors, O outdoors, S a stairwell) with the doors as
black dots and the windows as cyan diamonds.

    dt lua -f .devtools/bin/rooms_dump.lua > .devtools/artifacts/rooms/MAP.graph.json
    python3 .devtools/bin/rooms_view.py .devtools/artifacts/rooms/MAP.graph.json

The picture goes to .devtools/artifacts/rooms/<map>.png beside the graph,
and a summary of what was found is printed.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import places

REPO = Path(__file__).resolve().parents[2]

# Lua the harness runs: the graph (a Lua file returning it and the windows)
# partitioned, one line per fact, tab-separated. A door carries the level it
# is drawn on (its room's or corridor's), whose it is, the corridor it goes
# through and the rooms it leads to; a window its level.
DRIVER = r"""
local T = dofile("tests/harness.lua")
local given = dofile(arg[1])
local p = wartactics.rooms.Partition(given.graph, nil, given.windows)
local function out(...) io.write(table.concat({ ... }, "\t"), "\n") end
out("levels", #p.levels)
for _, room in ipairs(p.rooms) do
	out("room", room.id, room.kind, tostring(room.outdoor), room.level, room.top, room.center.x, room.center.y,
		room.center.z)
	for _, id in ipairs(room.areas) do out("in", id, "room", room.id) end
	for _, door in ipairs(room.doors) do
		out("door", room.level, door.pos.x, door.pos.y, door.pos.z, "room", room.id, door.passage or "",
			table.concat(door.leads, ","))
	end
	for _, window in ipairs(room.windows) do out("window", room.level, window.pos.x, window.pos.y) end
end
for _, passage in ipairs(p.passages) do
	out("passage", passage.id, passage.kind, passage.level, passage.top, passage.center.x, passage.center.y,
		passage.center.z)
	for _, id in ipairs(passage.areas) do out("in", id, "passage", passage.id) end
	for _, door in ipairs(passage.doors) do
		out("door", passage.level, door.pos.x, door.pos.y, door.pos.z, "passage", passage.id, door.passage or "",
			table.concat(door.leads, ","))
	end
end
os.exit(0)
"""

PANEL = 1100            # each level's picture, its longer side in pixels
MARGIN = 24
TITLE = 20


@dataclass(frozen=True)
class Area:
    id: int
    lo: tuple
    hi: tuple
    z: float


@dataclass(frozen=True)
class Space:
    """A room or a corridor: what it is, and the levels from its foot to its head."""
    id: int
    kind: str
    outdoor: bool
    level: int
    top: int
    center: tuple    # x, y, z

    @property
    def levels(self) -> range:
        return range(self.level, self.top + 1)


@dataclass(frozen=True)
class Found:
    levels: int
    rooms: dict      # id -> Space
    passages: dict   # id -> Space
    region: dict     # area id -> the Space it is in
    doors: list      # (level, x, y)
    windows: list    # (level, x, y)
    ways: dict       # ("room" | "passage", id) -> its doors as places.Door, for the room graph


@dataclass(frozen=True)
class Dump:
    map: str
    areas: dict      # id -> Area
    graph: dict      # id -> the area as dumped
    windows: list    # as dumped
    spawns: dict     # team name -> its spawn area ids
    objectives: list # the objectives' area ids


def LoadDump(path: Path) -> Dump:
    """The dump, past the server's own lines before its JSON."""
    text = path.read_text()
    data = json.loads(text[text.index("{"):])
    areas = {}
    for key, a in data["areas"].items():
        areas[int(key)] = Area(int(key), (a["lo"]["x"], a["lo"]["y"]), (a["hi"]["x"], a["hi"]["y"]), a["center"]["z"])
    graph = {int(k): v for k, v in data["areas"].items()}
    return Dump(data["map"], areas, graph, data["windows"], data["spawns"], data["objectives"])


def LuaValue(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "{" + ",".join(LuaValue(v) for v in value) + "}"
    return "{" + ",".join(f"[{LuaValue(k)}]={LuaValue(v)}" for k, v in value.items()) + "}"


def Parse(stdout: str) -> Found:
    """The driver's lines as what was found."""
    levels, rooms, passages, members, doors, windows, ways = 0, {}, {}, [], [], [], {}
    for line in stdout.splitlines():
        f = line.split("\t")
        if f[0] == "levels":
            levels = int(f[1])
        elif f[0] == "room":
            rooms[int(f[1])] = Space(int(f[1]), f[2], f[3] == "true", int(f[4]), int(f[5]),
                                     (float(f[6]), float(f[7]), float(f[8])))
        elif f[0] == "passage":
            passages[int(f[1])] = Space(int(f[1]), f[2], False, int(f[3]), int(f[4]),
                                        (float(f[5]), float(f[6]), float(f[7])))
        elif f[0] == "in":
            members.append((int(f[1]), f[2], int(f[3])))
        elif f[0] == "door":
            doors.append((int(f[1]), float(f[2]), float(f[3])))
            pos = (float(f[2]), float(f[3]), float(f[4]))
            leads = tuple(int(i) for i in f[8].split(",") if i)
            ways.setdefault((f[5], int(f[6])), []).append(places.Door(pos, leads, int(f[7]) if f[7] else None))
        elif f[0] == "window":
            windows.append((int(f[1]), float(f[2]), float(f[3])))
    region = {area: (rooms if kind == "room" else passages)[sid] for area, kind, sid in members}
    return Found(levels, rooms, passages, region, doors, windows, ways)


def Partition(dump: Dump) -> Found:
    with tempfile.TemporaryDirectory() as tmp:
        lua = Path(tmp) / "graph.lua"
        lua.write_text("return " + LuaValue({"graph": dump.graph, "windows": dump.windows}))
        driver = Path(tmp) / "driver.lua"
        driver.write_text(DRIVER)
        done = subprocess.run(["luajit", str(driver), str(lua)], cwd=REPO, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("Partition failed:\n" + done.stderr[-3000:])
    return Parse(done.stdout)


def Classes(dump: Dump, found: Found) -> dict:
    """Each room's starting class (places.Start): room id -> places.Placed. The dump's spawn and
    objective areas count by the rooms they are in."""
    def RoomsOf(area_ids):
        return sorted({found.region[a].id for a in area_ids
                       if a in found.region and found.rooms.get(found.region[a].id) is found.region[a]})
    def Spaces(spaces, kind):
        return [places.Space(s.id, kind == "room", s.center, found.ways.get((kind, s.id), [])) for s in spaces.values()]
    spawns = {team: RoomsOf(ids) for team, ids in dump.spawns.items()}
    return places.Start(Spaces(found.rooms, "room"), Spaces(found.passages, "passage"), spawns,
                        RoomsOf(dump.objectives))


# Each starting class's fill: a team's own ground in its colour, darkest
# where the enemy may not go; the rest by what passes through them.
CLASS_FILL = {
    (places.RESTRICTED, "RED"): (150, 25, 35), (places.RESTRICTED, "BLU"): (25, 55, 150),
    (places.STRONGHOLD, "RED"): (235, 125, 125), (places.STRONGHOLD, "BLU"): (125, 155, 235),
    (places.OUTPOST, "RED"): (245, 195, 175), (places.OUTPOST, "BLU"): (175, 205, 245),
    (places.HIGHWAY, None): (245, 150, 25), (places.COMMONS, None): (240, 220, 80),
    (places.UNOCCUPIED, None): (205, 205, 185), (places.WILDS, None): (115, 175, 95),
}
CLASS_MEANS = {
    places.RESTRICTED: "a team's spawns and what lies behind them: the enemy may not enter while the round is played",
    places.STRONGHOLD: "a team's protected ground its own soldiers commute through",
    places.OUTPOST: "ground a team claims far from its spawns (none at the start: an outpost needs a claim)",
    places.HIGHWAY: "an objective's room, or most of both teams' ways, or of one team's own, pass through",
    places.COMMONS: "both teams' ways cross it, moderately",
    places.UNOCCUPIED: "off every way, far from both teams' spawns",
    places.WILDS: "any room the other classes did not take",
}
CORRIDOR_FILL, LOOSE_EDGE, EDGE = (150, 150, 150), (220, 0, 0), (40, 40, 40)
WINDOW_FILL, DOOR_FILL = (0, 220, 255), (0, 0, 0)


def ClassFill(placed: places.Placed) -> tuple:
    return CLASS_FILL[(placed.cls, placed.team)]


def ClassName(placed: places.Placed) -> str:
    return placed.cls + (f" {placed.team}" if placed.team else "")


def Hatch(pen, box) -> None:
    (x0, y0), (x1, y1) = box
    for k in range(int(x0 - (y1 - y0)), int(x1), 6):
        pen.line([(max(k, x0), y0 + max(0, x0 - k)), (min(k + (y1 - y0), x1), y1 - max(0, k + (y1 - y0) - x1))],
                 fill=(60, 40, 0))


def Door(pen, x: float, y: float) -> None:
    pen.ellipse([x - 3, y - 3, x + 3, y + 3], fill=DOOR_FILL)


def Window(pen, x: float, y: float) -> None:
    pen.polygon([(x, y - 6), (x + 6, y), (x, y + 6), (x - 6, y)], fill=WINDOW_FILL, outline=(0, 0, 0))


@dataclass(frozen=True)
class KeyEntry:
    """One line of the picture's key: its sample, drawn in a box, and what it means."""
    name: str
    means: str
    sample: object  # sample(pen, box)


def Middle(box) -> tuple:
    (x0, y0), (x1, y1) = box
    return (x0 + x1) / 2, (y0 + y1) / 2


def Swatch(fill):
    return lambda pen, box: pen.rectangle(box, fill=fill, outline=EDGE)


KEY = [KeyEntry(f"{cls}{' ' + team if team else ''}", CLASS_MEANS[cls], Swatch(fill))
       for (cls, team), fill in CLASS_FILL.items()] + [
    KeyEntry("stairwell", "hatched over its class: a room between levels, drawn on each it joins",
             lambda pen, box: (pen.rectangle(box, fill=CLASS_FILL[(places.WILDS, None)], outline=EDGE), Hatch(pen, box))),
    KeyEntry("corridor", "a hallway or alley between rooms, no room's",
             lambda pen, box: pen.rectangle(box, fill=CORRIDOR_FILL, outline=EDGE)),
    KeyEntry("area in no room", "a nav area left out: a bug to report",
             lambda pen, box: pen.rectangle(box, fill=(255, 255, 255), outline=LOOSE_EDGE)),
    KeyEntry("room's block", "the outline round all of a room's areas: the room as the war sees it",
             lambda pen, box: pen.rectangle(box, outline=(60, 60, 60), width=3)),
    KeyEntry("door", "where a room meets another room or a corridor",
             lambda pen, box: Door(pen, *Middle(box))),
    KeyEntry("window", "breakable glass or an areaportal window between rooms",
             lambda pen, box: Window(pen, *Middle(box))),
    KeyEntry("R3 / O9 / S18", "a room's label: R indoors, O outdoors, S a stairwell, its id; its class beneath",
             lambda pen, box: None),
]
KEY_LINE, KEY_SAMPLE, KEY_COLUMNS = 22, 28, 2
KEY_HEIGHT = TITLE + KEY_LINE * ((len(KEY) + KEY_COLUMNS - 1) // KEY_COLUMNS) + MARGIN


def Frame(areas: dict) -> tuple:
    """The map's extent and the scale a level's panel draws it at."""
    xs = [v for a in areas.values() for v in (a.lo[0], a.hi[0])]
    ys = [v for a in areas.values() for v in (a.lo[1], a.hi[1])]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    return x0, x1, y0, y1, (PANEL - 2 * MARGIN) / max(x1 - x0, y1 - y0)


def PanelHeight(areas: dict) -> int:
    _, _, y0, y1, scale = Frame(areas)
    return int((y1 - y0) * scale) + 2 * MARGIN + TITLE


def DrawKey(pen, font, top: int, width: int) -> None:
    pen.line([(0, top), (width, top)], fill=(0, 0, 0))
    pen.text((MARGIN, top + 4), "Key: rooms filled by their class when a round starts", fill=(0, 0, 0), font=font)
    column = width // KEY_COLUMNS
    for i, entry in enumerate(KEY):
        x = MARGIN + (i % KEY_COLUMNS) * column
        y = top + TITLE + (i // KEY_COLUMNS) * KEY_LINE
        entry.sample(pen, [(x, y + 2), (x + KEY_SAMPLE, y + KEY_LINE - 6)])
        pen.text((x + KEY_SAMPLE + 8, y + 2), f"{entry.name}: {entry.means}", fill=(0, 0, 0), font=font)


def Draw(name: str, areas: dict, found: Found, classes: dict, out: Path) -> None:
    count = max(found.levels, 1)
    x0, x1, y0, y1, scale = Frame(areas)
    w, h = int((x1 - x0) * scale) + 2 * MARGIN, PanelHeight(areas)
    image = Image.new("RGB", (w * count, h + KEY_HEIGHT), (255, 255, 255))
    pen = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=13)
    small = ImageFont.load_default(size=10)

    def At(level: int, x: float, y: float) -> tuple:
        return (level - 1) * w + MARGIN + (x - x0) * scale, TITLE + MARGIN + (y1 - y) * scale

    def Box(level: int, area: Area) -> list:
        return [At(level, area.lo[0], area.hi[1]), At(level, area.hi[0], area.lo[1])]

    for level in range(1, count + 1):
        pen.text(((level - 1) * w + MARGIN, 4), f"{name}: level {level}", fill=(0, 0, 0), font=font)
        pen.line([((level - 1) * w, 0), ((level - 1) * w, h)], fill=(0, 0, 0))
    blocks = {}
    for area in sorted(areas.values(), key=lambda a: a.z):
        space = found.region.get(area.id)
        if space is None:
            pen.rectangle(Box(1, area), fill=(255, 255, 255), outline=LOOSE_EDGE)
            continue
        is_room = found.rooms.get(space.id) is space
        for level in space.levels:
            box = Box(level, area)
            pen.rectangle(box, fill=ClassFill(classes[space.id]) if is_room else CORRIDOR_FILL, outline=EDGE)
            if space.kind == "stairwell":
                Hatch(pen, box)
            if is_room:
                (ax, ay), (bx, by) = box
                bx0, by0, bx1, by1 = blocks.get((space.id, level), (ax, ay, bx, by))
                blocks[(space.id, level)] = (min(bx0, ax), min(by0, ay), max(bx1, bx), max(by1, by))
    for (rid, _), box in blocks.items():
        pen.rectangle(box, outline=tuple(c // 2 for c in ClassFill(classes[rid])), width=3)
    for level, x, y in found.doors:
        Door(pen, *At(level, x, y))
    for level, x, y in found.windows:
        Window(pen, *At(level, x, y))
    for room in found.rooms.values():
        tag = ("S" if room.kind == "stairwell" else "O" if room.outdoor else "R") + str(room.id)
        for level in room.levels:
            px, py = At(level, *room.center[:2])
            pen.text((px, py - 6), tag, fill=(0, 0, 0), font=font, anchor="mm", stroke_width=2,
                     stroke_fill=(255, 255, 255))
            pen.text((px, py + 7), ClassName(classes[room.id]), fill=(0, 0, 0), font=small, anchor="mm",
                     stroke_width=2, stroke_fill=(255, 255, 255))
    DrawKey(pen, font, h, w * count)
    image.save(out)


def Summary(areas: dict, found: Found, classes: dict) -> list:
    kinds = {}
    for room in found.rooms.values():
        span = f"level {room.level}" if room.level == room.top else f"levels {room.level}-{room.top}"
        key = f"{room.kind} {'outdoors' if room.outdoor else 'indoors'}, {span}"
        kinds[key] = kinds.get(key, 0) + 1
    starting = {}
    for placed in classes.values():
        starting[ClassName(placed)] = starting.get(ClassName(placed), 0) + 1
    loose = sum(1 for a in areas if a not in found.region)
    return [f"{found.levels} levels, {len(found.rooms)} rooms: " + "; ".join(f"{n} {k}" for k, n in sorted(kinds.items())),
            "starting classes: " + ", ".join(f"{n} {k}" for k, n in sorted(starting.items())),
            f"{len(found.passages)} corridors, {len(found.doors)} doors, {len(found.windows)} windows; "
            f"{loose} of {len(areas)} areas in no room or corridor"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("graph", type=Path)
    args = parser.parse_args()
    dump = LoadDump(args.graph)
    found = Partition(dump)
    classes = Classes(dump, found)
    out = args.graph.with_name(f"{dump.map}.png")
    Draw(dump.map, dump.areas, found, classes, out)
    print("\n".join(Summary(dump.areas, found, classes)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
