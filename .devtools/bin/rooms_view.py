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
import colorsys
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]

# Lua the harness runs: the graph (a Lua file returning it and the windows)
# partitioned, one line per fact, tab-separated. A door or window carries
# the level it is drawn on: its room's or corridor's.
DRIVER = r"""
local T = dofile("tests/harness.lua")
local given = dofile(arg[1])
local p = wartactics.rooms.Partition(given.graph, nil, given.windows)
local function out(...) io.write(table.concat({ ... }, "\t"), "\n") end
out("levels", #p.levels)
for _, room in ipairs(p.rooms) do
	out("room", room.id, room.kind, tostring(room.outdoor), room.level, room.top, room.center.x, room.center.y)
	for _, id in ipairs(room.areas) do out("in", id, "room", room.id) end
	for _, door in ipairs(room.doors) do out("door", room.level, door.pos.x, door.pos.y) end
	for _, window in ipairs(room.windows) do out("window", room.level, window.pos.x, window.pos.y) end
end
for _, passage in ipairs(p.passages) do
	out("passage", passage.id, passage.kind, passage.level, passage.top)
	for _, id in ipairs(passage.areas) do out("in", id, "passage", passage.id) end
	for _, door in ipairs(passage.doors) do out("door", passage.level, door.pos.x, door.pos.y) end
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
    center: tuple

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


@dataclass(frozen=True)
class Dump:
    map: str
    areas: dict      # id -> Area
    graph: dict      # id -> the area as dumped
    windows: list    # as dumped


def LoadDump(path: Path) -> Dump:
    """The dump, past the server's own lines before its JSON."""
    text = path.read_text()
    data = json.loads(text[text.index("{"):])
    areas = {}
    for key, a in data["areas"].items():
        areas[int(key)] = Area(int(key), (a["lo"]["x"], a["lo"]["y"]), (a["hi"]["x"], a["hi"]["y"]), a["center"]["z"])
    graph = {int(k): v for k, v in data["areas"].items()}
    return Dump(data["map"], areas, graph, data["windows"])


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
    levels, rooms, passages, members, doors, windows = 0, {}, {}, [], [], []
    for line in stdout.splitlines():
        f = line.split("\t")
        if f[0] == "levels":
            levels = int(f[1])
        elif f[0] == "room":
            rooms[int(f[1])] = Space(int(f[1]), f[2], f[3] == "true", int(f[4]), int(f[5]), (float(f[6]), float(f[7])))
        elif f[0] == "passage":
            passages[int(f[1])] = Space(int(f[1]), f[2], False, int(f[3]), int(f[4]), (0.0, 0.0))
        elif f[0] == "in":
            members.append((int(f[1]), f[2], int(f[3])))
        elif f[0] == "door":
            doors.append((int(f[1]), float(f[2]), float(f[3])))
        elif f[0] == "window":
            windows.append((int(f[1]), float(f[2]), float(f[3])))
    region = {area: (rooms if kind == "room" else passages)[sid] for area, kind, sid in members}
    return Found(levels, rooms, passages, region, doors, windows)


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


def RoomColour(room: Space) -> tuple:
    hue = (room.id * 0.6180339887) % 1.0
    light, sat = (0.82, 0.45) if room.outdoor else (0.55, 0.75)
    if room.kind == "stairwell":
        hue, light, sat = 0.13, 0.55, 0.95
    r, g, b = colorsys.hls_to_rgb(hue, light, sat)
    return int(r * 255), int(g * 255), int(b * 255)


CORRIDOR_FILL, LOOSE_EDGE, EDGE = (150, 150, 150), (220, 0, 0), (40, 40, 40)


def Hatch(pen, box) -> None:
    (x0, y0), (x1, y1) = box
    for k in range(int(x0 - (y1 - y0)), int(x1), 6):
        pen.line([(max(k, x0), y0 + max(0, x0 - k)), (min(k + (y1 - y0), x1), y1 - max(0, k + (y1 - y0) - x1))],
                 fill=(120, 80, 0))


def Draw(name: str, areas: dict, found: Found, out: Path) -> None:
    count = max(found.levels, 1)
    xs = [v for a in areas.values() for v in (a.lo[0], a.hi[0])]
    ys = [v for a in areas.values() for v in (a.lo[1], a.hi[1])]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    scale = (PANEL - 2 * MARGIN) / max(x1 - x0, y1 - y0)
    w, h = int((x1 - x0) * scale) + 2 * MARGIN, int((y1 - y0) * scale) + 2 * MARGIN + TITLE
    image = Image.new("RGB", (w * count, h), (255, 255, 255))
    pen = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=13)

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
            pen.rectangle(box, fill=RoomColour(space) if is_room else CORRIDOR_FILL, outline=EDGE)
            if space.kind == "stairwell":
                Hatch(pen, box)
            if is_room:
                (ax, ay), (bx, by) = box
                bx0, by0, bx1, by1 = blocks.get((space.id, level), (ax, ay, bx, by))
                blocks[(space.id, level)] = (min(bx0, ax), min(by0, ay), max(bx1, bx), max(by1, by))
    for (rid, _), box in blocks.items():
        pen.rectangle(box, outline=tuple(c // 2 for c in RoomColour(found.rooms[rid])), width=3)
    for level, x, y in found.doors:
        px, py = At(level, x, y)
        pen.ellipse([px - 3, py - 3, px + 3, py + 3], fill=(0, 0, 0))
    for level, x, y in found.windows:
        px, py = At(level, x, y)
        pen.polygon([(px, py - 6), (px + 6, py), (px, py + 6), (px - 6, py)], fill=(0, 220, 255), outline=(0, 0, 0))
    for room in found.rooms.values():
        tag = ("S" if room.kind == "stairwell" else "O" if room.outdoor else "R") + str(room.id)
        for level in room.levels:
            pen.text(At(level, *room.center), tag, fill=(0, 0, 0), font=font, anchor="mm", stroke_width=2,
                     stroke_fill=(255, 255, 255))
    image.save(out)


def Summary(areas: dict, found: Found) -> list:
    kinds = {}
    for room in found.rooms.values():
        span = f"level {room.level}" if room.level == room.top else f"levels {room.level}-{room.top}"
        key = f"{room.kind} {'outdoors' if room.outdoor else 'indoors'}, {span}"
        kinds[key] = kinds.get(key, 0) + 1
    loose = sum(1 for a in areas if a not in found.region)
    return [f"{found.levels} levels, {len(found.rooms)} rooms: " + "; ".join(f"{n} {k}" for k, n in sorted(kinds.items())),
            f"{len(found.passages)} corridors, {len(found.doors)} doors, {len(found.windows)} windows; "
            f"{loose} of {len(areas)} areas in no room or corridor"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("graph", type=Path)
    args = parser.parse_args()
    dump = LoadDump(args.graph)
    found = Partition(dump)
    out = args.graph.with_name(f"{dump.map}.png")
    Draw(dump.map, dump.areas, found, out)
    print("\n".join(Summary(dump.areas, found)))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
