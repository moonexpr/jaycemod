#!/usr/bin/env python3
"""Draw an assault's placements on dev_3house's bench, one panel for each enemy position.

Asks the dedicated server on dev_3house for NSRoomBench.Placements() (.devtools/bin/
dev_3house_bench.lua, loaded on the server first): the legs' assault planned on the bench room
for an enemy marked at its centre, rear, front, left and right, no one moving. Each panel is
the room seen from above, north up: its block (grey), its doors (orange) and windows (blue), the
door the squad comes in by (a thicker orange bar), the enemy (a red cross) and the ring the
assault points keep to round it (red, dashed band); and each member's path in a colour of its
own: from its start (hollow circle) to its place in the stack (square), through the door it goes
in by to its assault point (filled circle, numbered as the member is), and on to its place in
the room once it is clear (small dot), that last leg dotted. Paths are straight between those
points: where the member walks, not the steps of its route.

Writes .devtools/artifacts/maps/dev_3house_assault.png.

    python3 .devtools/bin/instances.py dev_3house - < .devtools/bin/dev_3house_bench.lua
    python3 .devtools/bin/assault_view.py [--json FILE] [--out FILE]
"""
import argparse
import json
import math
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / ".devtools" / "artifacts" / "maps" / "dev_3house_assault.png"
# A panel's side in pixels, the margin round what it draws, and the caption's height under it.
PANEL, MARGIN, CAPTION = 420, 24, 28
ROOM_FILL, EDGE = (232, 232, 232), (90, 90, 90)
DOOR, ENTRY, WINDOW = (240, 150, 40), (220, 110, 0), (70, 130, 220)
ENEMY, RING = (215, 40, 40), (235, 150, 150)
# Each member's colour, in turn.
MEMBERS = ((140, 80, 220), (40, 150, 70), (30, 120, 200), (210, 120, 20), (200, 50, 140), (90, 90, 90))
DOT_EVERY = 8
# How far round the room's block a panel reaches beyond what it holds, in world units.
PAD = 48


@dataclass(frozen=True)
class Member:
    start: tuple
    stage: tuple | None
    point: tuple | None
    place: tuple | None


@dataclass(frozen=True)
class Case:
    name: str
    lo: tuple
    hi: tuple
    entry: tuple
    enemy: tuple | None
    ring: float
    band: float
    members: tuple


@dataclass(frozen=True)
class Placements:
    map: str
    doors: tuple
    windows: tuple
    cases: tuple


def _xy(value):
    return None if value is None else (value["x"], value["y"])


def Parse(stdout: str) -> Placements:
    """The bench's answer, the line of JSON among what the server printed."""
    for line in stdout.splitlines():
        line = line.strip().removeprefix("=> ")
        if line.startswith("{"):
            data = json.loads(line)
            cases = tuple(Case(c["name"], _xy(c["lo"]), _xy(c["hi"]), _xy(c["entry"]), _xy(c.get("enemy")), c["ring"],
                               c["band"], tuple(Member(_xy(m["start"]), _xy(m.get("stage")), _xy(m.get("point")),
                                                       _xy(m.get("place"))) for m in c["members"]))
                          for c in data["cases"])
            return Placements(data["map"], tuple(map(_xy, data["doors"])), tuple(map(_xy, data["windows"])), cases)
    raise ValueError("no placements in the server's answer: " + stdout[-300:])


def Reach(case: Case) -> tuple:
    """The corners of what a panel shows: the room and every member's points, PAD round them."""
    points = [case.lo, case.hi, case.entry] + [p for m in case.members for p in (m.start, m.stage, m.point, m.place) if p]
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return (min(xs) - PAD, min(ys) - PAD), (max(xs) + PAD, max(ys) + PAD)


def Dotted(pen, a: tuple, b: tuple, colour: tuple) -> None:
    """A dotted line from a to b."""
    length = math.dist(a, b)
    for k in range(int(length // DOT_EVERY) + 1):
        t = k * DOT_EVERY / length if length else 0
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        pen.ellipse((x - 1.5, y - 1.5, x + 1.5, y + 1.5), fill=colour)


def _panel(placements: Placements, case: Case) -> Image.Image:
    image = Image.new("RGB", (PANEL, PANEL + CAPTION), (255, 255, 255))
    pen = ImageDraw.Draw(image)
    lo, hi = Reach(case)
    scale = (PANEL - 2 * MARGIN) / max(hi[0] - lo[0], hi[1] - lo[1])

    def At(p):  # north up: world y grows up the page
        return MARGIN + (p[0] - lo[0]) * scale, PANEL - MARGIN - (p[1] - lo[1]) * scale

    (x0, y1), (x1, y0) = At(case.lo), At(case.hi)
    pen.rectangle((x0, y0, x1, y1), fill=ROOM_FILL, outline=EDGE, width=2)
    for door in placements.doors:
        x, y = At(door)
        pen.ellipse((x - 5, y - 5, x + 5, y + 5), fill=DOOR)
    x, y = At(case.entry)
    pen.ellipse((x - 8, y - 8, x + 8, y + 8), outline=ENTRY, width=3)
    for window in placements.windows:
        x, y = At(window)
        pen.rectangle((x - 4, y - 4, x + 4, y + 4), fill=WINDOW)
    if case.enemy:
        ex, ey = At(case.enemy)
        for radius in (case.ring - case.band, case.ring + case.band):
            r = radius * scale
            for k in range(0, 360, 12):
                pen.arc((ex - r, ey - r, ex + r, ey + r), k, k + 6, fill=RING)
        r = case.ring * scale
        pen.ellipse((ex - r, ey - r, ex + r, ey + r), outline=RING)
        pen.line((ex - 9, ey - 9, ex + 9, ey + 9), fill=ENEMY, width=4)
        pen.line((ex - 9, ey + 9, ex + 9, ey - 9), fill=ENEMY, width=4)
    for i, member in enumerate(case.members, 1):
        colour = MEMBERS[(i - 1) % len(MEMBERS)]
        way = [At(p) for p in (member.start, member.stage) if p]
        if member.point:
            way += [At(case.entry), At(member.point)]
        if len(way) > 1:
            pen.line(way, fill=colour, width=2, joint="curve")
        if member.point and member.place:
            Dotted(pen, At(member.point), At(member.place), colour)
        x, y = At(member.start)
        pen.ellipse((x - 5, y - 5, x + 5, y + 5), outline=colour, width=2)
        if member.stage:
            sx, sy = At(member.stage)
            pen.rectangle((sx - 5, sy - 5, sx + 5, sy + 5), fill=colour)
        if member.place:
            x, y = At(member.place)
            pen.ellipse((x - 3, y - 3, x + 3, y + 3), fill=colour)
        if member.point:
            px, py = At(member.point)
            pen.ellipse((px - 8, py - 8, px + 8, py + 8), fill=colour)
            pen.text((px - 3, py - 6), str(i), fill=(255, 255, 255))
    gap = ""
    if case.enemy:
        angles = sorted(math.atan2(m.point[1] - case.enemy[1], m.point[0] - case.enemy[0]) for m in case.members if m.point)
        if angles:
            widest = max([angles[0] + 2 * math.pi - angles[-1]] + [b - a for a, b in zip(angles, angles[1:])])
            gap = f", widest gap round it {math.degrees(widest):.0f}°"
    pen.text((MARGIN, PANEL + 6), f"enemy at the {case.name}{gap}", fill=(0, 0, 0))
    return image


def Draw(placements: Placements, out: Path) -> None:
    panels = [_panel(placements, case) for case in placements.cases]
    sheet = Image.new("RGB", (PANEL * len(panels), PANEL + CAPTION), (255, 255, 255))
    for i, panel in enumerate(panels):
        sheet.paste(panel, (i * PANEL, 0))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", type=Path, help="draw a saved answer instead of asking the server")
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    if args.json:
        text = args.json.read_text()
    else:
        done = subprocess.run([sys.executable, str(REPO / ".devtools/bin/instances.py"), "dev_3house",
                               "return NSRoomBench.Placements()"], capture_output=True, text=True, cwd=REPO)
        text = done.stdout + done.stderr
    Draw(Parse(text), args.out)
    print(f"drew {args.out}")


if __name__ == "__main__":
    main()
