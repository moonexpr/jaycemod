#!/usr/bin/env python3
"""Draw HL2's weapons as TF2 kill icons, in PhotoCraft.

  kill_icons_art.py          draw both sheets and write their layout

Each icon is a side view in TF2's kill icon look (its HUD/d_images): a flat
cream silhouette, muzzle to the right toward the victim, its panel lines cut
in, and a dimmer burst at the muzzle. The designs below are in TF2's units, a
96 x 32 cell, and drawn SCALE times that. PhotoCraft (photocraft-cli, run
headless) draws every icon as a shape layer with an inner shadow, once in the
cream and once in the dark of TF2's dneg_images (the light box of a kill the
player took part in), and keeps each sheet's layered master in
.devtools/artifacts/kill_icons/.

Writes, under the gamemode's content/:
  materials/sandcastle/kill_icons/hl2.png, hl2_neg.png    the sheets
  scripts/sandcastle_kill_icons.txt                        their layout, in
      TF2's scripts/mod_textures.txt format, which foundation.kill_icons reads

Needs photocraft-cli on PATH.
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence, Tuple

ROOT = Path(__file__).resolve().parents[2]
# GMod mounts a gamemode's content/ as game content; the addon's own root is
# not mounted where the server and the game run (server_root.py links the
# gamemode alone)
CONTENT = ROOT / "addons" / "sandcastle" / "gamemodes" / "sandcastle" / "content"
MATERIAL = "sandcastle/kill_icons/hl2"
SHEET = CONTENT / "materials" / f"{MATERIAL}.png"
SHEET_NEG = CONTENT / "materials" / f"{MATERIAL}_neg.png"
LAYOUT = CONTENT / "scripts" / "sandcastle_kill_icons.txt"
MASTERS = ROOT / ".devtools" / "artifacts" / "kill_icons"

UNIT_TALL = 32  # TF2's kill icon height, in the units the designs are drawn in
SCALE = 2
CELL_TALL = UNIT_TALL * SCALE
MARGIN = 4  # pixels either side of an icon in its cell
SHEET_SIZE = 512

# TF2's own: d_images' cream, dneg_images' dark.
CREAM = "#e8e0b8"
DARK = "#383820"
FLASH_OPACITY = 0.5

Point = Tuple[float, float]


class ArtError(Exception):
    pass


@dataclass(frozen=True)
class Part:
    """One subpath: added to the silhouette, or cut out of what is drawn before it."""

    knots: Tuple[Point, ...]
    op: str = "combine"


@dataclass(frozen=True)
class Icon:
    name: str  # the entity class whose kill it marks
    parts: Tuple[Part, ...]
    flash: Tuple[Part, ...] = ()

    def bounds(self) -> Tuple[float, float, float, float]:
        points = [p for part in self.parts + self.flash for p in part.knots]
        xs, ys = [x for x, _ in points], [y for _, y in points]
        return min(xs), min(ys), max(xs), max(ys)


@dataclass(frozen=True)
class Cell:
    """An icon's place on the sheet, in pixels, and how its units map there."""

    icon: Icon
    x: int
    y: int
    w: int
    h: int
    margin: int

    def place(self, p: Point) -> Point:
        left = self.icon.bounds()[0]
        return (self.x + self.margin + (p[0] - left) * SCALE, self.y + p[1] * SCALE)


# Shapes, in units

def rect(x: float, y: float, w: float, h: float) -> Tuple[Point, ...]:
    return ((x, y), (x + w, y), (x + w, y + h), (x, y + h))


def circle(cx: float, cy: float, r: float, n: int = 20) -> Tuple[Point, ...]:
    return tuple((cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n))


def arc(cx: float, cy: float, r: float, start: float, end: float, step: float = 15) -> Tuple[Point, ...]:
    """Points on a circle from start to end degrees (y down, 0 at the right)."""
    count = max(1, round(abs(end - start) / step))
    return tuple(
        (cx + r * math.cos(math.radians(start + (end - start) * i / count)),
         cy + r * math.sin(math.radians(start + (end - start) * i / count)))
        for i in range(count + 1)
    )


def thick(line: Sequence[Point], width: float) -> Tuple[Point, ...]:
    """An open polyline as the outline of a band width across, mitred at its bends."""
    half = width / 2
    left, right = [], []
    for i, (x, y) in enumerate(line):
        normals = []
        if i > 0:
            normals.append(_normal(line[i - 1], line[i]))
        if i < len(line) - 1:
            normals.append(_normal(line[i], line[i + 1]))
        nx, ny = sum(n[0] for n in normals), sum(n[1] for n in normals)
        length = math.hypot(nx, ny)
        nx, ny = nx / length, ny / length
        miter = half / (nx * normals[0][0] + ny * normals[0][1])
        left.append((x + nx * miter, y + ny * miter))
        right.append((x - nx * miter, y - ny * miter))
    return tuple(left + right[::-1])


def _normal(a: Point, b: Point) -> Point:
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    return (-dy / length, dx / length)


def burst(cx: float, cy: float, outer: float, inner: float, spikes: int) -> Tuple[Point, ...]:
    """A muzzle flash: a star, squashed to half its height."""
    points = []
    for i in range(spikes * 2):
        r = outer if i % 2 == 0 else inner
        a = math.pi * i / spikes
        points.append((cx + r * math.cos(a), cy + r * math.sin(a) * 0.5))
    return tuple(points)


def guard(outer: Sequence[Point], hole: Sequence[Point], trigger: Sequence[Point]) -> Tuple[Part, ...]:
    """A trigger guard: its ring, the hole through it and the trigger in the hole."""
    return (Part(tuple(outer)), Part(tuple(hole), "subtract"), Part(thick(trigger, 1.1)))


def cuts(*shapes: Tuple[Point, ...]) -> Tuple[Part, ...]:
    return tuple(Part(s, "subtract") for s in shapes)


def solid(*shapes: Tuple[Point, ...]) -> Tuple[Part, ...]:
    return tuple(Part(s) for s in shapes)


# The icons, in units on TF2's 96 x 32 cell, muzzle right

PISTOL = Icon(
    "weapon_pistol",
    solid(
        rect(14, 8, 44, 7), rect(58, 9, 2, 5), rect(15, 6.5, 3, 1.5), rect(54, 7, 2, 1),
        ((11, 9), (14, 8.5), (14, 12), (12, 12)),
        rect(18, 15, 38, 3),
        ((18, 17), (33, 17), (29, 30), (15, 30)),
    )
    + guard(((33, 17), (44, 17), (43, 21), (39, 23.5), (34, 23.5), (32, 21)),
            ((35, 18.5), (41.5, 18.5), (40.5, 20.5), (38.5, 22), (35.5, 22), (34.5, 20.5)),
            ((37, 18.5), (37.5, 21)))
    + cuts(rect(17, 9, 0.8, 4.5), rect(19, 9, 0.8, 4.5), rect(21, 9, 0.8, 4.5), rect(24, 14.6, 32, 0.7)),
    solid(burst(70, 11.5, 8, 3.5, 7)),
)

MAGNUM = Icon(
    "weapon_357",
    solid(
        rect(42, 8, 34, 5), rect(42, 6.5, 34, 1.5), rect(42, 13, 34, 2.5),
        ((71, 6.5), (74, 4.5), (76, 4.5), (76, 6.5)),
        ((24, 7), (42, 7), (42, 17), (26, 18), (24, 15)),
        ((21, 4), (25, 3.5), (28, 8), (24, 9)),
        ((24, 15), (32, 16), (31, 20), (27, 30), (18, 30), (17.5, 27), (21, 20)),
    )
    + guard(((32, 16), (40, 16), (39, 21), (35, 22.5), (32, 21)),
            ((33.5, 17.3), (38.5, 17.3), (37.8, 20.2), (35, 21.2), (33.3, 20)),
            ((35.5, 17.3), (36, 20)))
    + cuts(*(rect(46 + i * 6, 6.8, 2.5, 0.9) for i in range(5)))
    + cuts(rect(44, 12.7, 32, 0.6), rect(28.5, 8, 0.7, 9.5), rect(41, 8, 0.7, 9.5), rect(30, 12.4, 10, 0.7),
           circle(25.5, 21, 0.9, 10)),
    solid(burst(86, 10.5, 7, 3, 7)),
)

SMG = Icon(
    "weapon_smg1",
    solid(
        ((18, 8), (60, 8), (62, 10), (62, 15), (18, 15)),
        rect(22, 5.5, 34, 2.5), rect(62, 9.5, 9, 3), rect(70, 9, 3, 4),
        ((52, 15), (57, 15), (56.5, 25), (52.5, 25)),
        ((32, 15), (41, 15), (40, 30), (31, 30)),
        rect(8, 9.5, 10, 2), rect(8, 12.5, 10, 1.5), ((4, 7), (8, 7), (8, 17), (5, 17)),
    )
    + guard(((41, 15), (48, 15), (47.5, 19), (41, 19.5)),
            ((42, 15.8), (47, 15.8), (46.5, 18.3), (42, 18.6)),
            ((43.5, 15.8), (44, 18)))
    + cuts(*(rect(24 + i * 4, 5.4, 1.5, 1.2) for i in range(8)))
    + cuts(rect(20, 11.2, 40, 0.6), rect(36, 9.5, 8, 1.5)),
    solid(burst(81, 11, 7, 3, 7)),
)

PULSE_RIFLE = Icon(
    "weapon_ar2",
    solid(
        rect(56, 8.5, 30, 3), rect(84, 7.5, 3, 5),
        ((16, 9), (24, 6), (56, 6), (62, 9), (62, 16), (50, 18), (26, 18), (16, 16)),
        ((56, 12), (74, 12), (74, 14.5), (62, 17)),
        ((16, 9), (16, 16), (9, 23), (3, 23), (3, 19.5), (10, 12)),
        ((36, 18), (43, 18), (41, 28), (34, 28)),
    )
    + cuts(circle(26, 12, 4))
    + solid(circle(26, 12, 2.6))
    + cuts(circle(26, 12, 1.2, 12), rect(32, 11.6, 22, 0.6), rect(42, 7.6, 12, 0.6)),
    solid(burst(92, 10, 6, 2.5, 7)),
)

SHOTGUN = Icon(
    "weapon_shotgun",
    solid(
        ((20, 9), (46, 9), (46, 17), (22, 17), (20, 15)),
        rect(46, 9, 38, 3), rect(46, 12.5, 32, 3), rect(78, 12.5, 2, 3), rect(81, 7.8, 2, 1.2),
        ((52, 11.5), (68, 11.5), (69, 13), (69, 17), (68, 18.5), (52, 18.5), (51, 17), (51, 13)),
        ((22, 16), (31, 16), (26, 28), (15, 28), (16, 25)),
    )
    + guard(((31, 16), (39, 16), (38, 20), (34, 21.5), (30, 20)),
            ((32, 17.2), (37.5, 17.2), (36.8, 19.3), (34, 20.4), (31.8, 19.3)),
            ((34, 17.2), (34.5, 19.5)))
    + cuts(*(rect(54 + i * 3, 12.5, 0.8, 5) for i in range(5)))
    + cuts(rect(22, 12.6, 24, 0.6), rect(30, 10, 8, 1.6)),
    solid(burst(90, 10.5, 6, 2.6, 7)),
)

CROSSBOW = Icon(
    "weapon_crossbow",
    solid(
        ((2, 13), (10, 11), (30, 11.5), (30, 17), (10, 17), (2, 19)),
        rect(30, 11.5, 40, 4.5),
        ((26, 17), (33, 17), (31, 27), (24, 27)),
        rect(40, 16, 12, 4),
        rect(30, 5, 22, 3.5), ((28, 4.5), (30, 5), (30, 8.5), (28, 9)), ((52, 5), (55, 4), (55, 9.5), (52, 8.5)),
        rect(34, 8.5, 2, 3), rect(46, 8.5, 2, 3),
        thick(((70, 13), (71, 9), (70, 5), (67, 2)), 2),
        thick(((70, 14.5), (71, 19), (70, 24), (67, 28)), 2),
        thick(((67, 2), (58, 13.5)), 0.6), thick(((58, 14.5), (67, 28)), 0.6),
        rect(40, 13.2, 48, 1.2), ((88, 12.4), (92, 13.8), (88, 15.2)),
    )
    + cuts(rect(32, 13.8, 6, 0.6), rect(42, 17.6, 8, 0.6)),
)

CROWBAR = Icon(
    "weapon_crowbar",
    solid(thick(((86, 11.5), (80, 15.5)) + arc(14, 10.5, 5, 90, 330), 3))
    + cuts(rect(20, 15.2, 58, 0.5)),
)

STUNSTICK = Icon(
    "weapon_stunstick",
    solid(
        rect(8, 13, 22, 6), rect(6, 13.5, 2, 5), rect(29, 11.5, 3, 9),
        ((32, 14.5), (78, 15), (78, 17), (32, 17.5)),
        ((78, 13.5), (84, 13.5), (86, 15), (86, 17), (84, 18.5), (78, 18.5)),
    )
    + cuts(*(rect(11 + i * 4, 13, 0.9, 6) for i in range(5)))
    + cuts(rect(80, 13.5, 0.8, 5)),
    solid(
        thick(((86, 12), (89, 9), (88, 12), (92, 8)), 1),
        thick(((87, 19.5), (90, 22.5), (89, 20), (93, 23.5)), 1),
        thick(((88, 16), (91, 15), (90, 16.5), (94, 16)), 1),
    ),
)

FRAG = Icon(
    "weapon_frag",
    solid(
        ((41, 10), (42, 8), (54, 8), (55, 10), (55, 28), (54, 29.5), (42, 29.5), (41, 28)),
        rect(43, 5, 10, 3),
        thick(((53, 5.5), (57, 6.5), (57.5, 20)), 1.6),
    )
    + cuts(*(rect(41, 12 + i * 4, 14, 0.8) for i in range(4)))
    + cuts(circle(48, 6.5, 1, 10))
    + solid(circle(39, 5, 2.6))
    + cuts(circle(39, 5, 1.4, 12)),
    solid(burst(68, 19, 9, 4, 9)),
)

RPG = Icon(
    "weapon_rpg",
    solid(
        rect(10, 9, 64, 6),
        ((2, 6.5), (10, 9), (10, 15), (2, 17.5)),
        ((74, 8), (82, 7.5), (82, 16.5), (74, 16)),
        ((32, 15), (39, 15), (37, 26), (30, 26)),
        rect(50, 15, 4, 8), rect(58, 15, 12, 4.5), rect(28, 5, 12, 4),
    )
    + cuts(circle(68, 17.2, 1, 10), rect(30, 6, 3, 2), rect(12, 11.7, 60, 0.6)),
    solid(burst(88, 12, 6, 3, 7)),
)

GRAVITY_GUN = Icon(
    "weapon_physcannon",
    solid(
        ((10, 10), (16, 6), (44, 6), (48, 9), (48, 22), (44, 25), (16, 25), (10, 21)),
        thick(((18, 6.5), (21, 2.5), (40, 2.5), (43, 6.5)), 2),
        ((14, 24), (22, 24), (20, 30), (12, 30)),
        rect(48, 10, 10, 11),
        ((56, 9), (63, 4.5), (80, 5.5), (82, 7.5), (66, 8.5), (58, 12)),
        ((56, 22), (63, 26.5), (80, 25.5), (82, 23.5), (66, 22.5), (58, 19)),
        ((58, 14.5), (78, 14.8), (80, 15.5), (78, 16.2), (58, 16.5)),
    )
    + cuts(circle(30, 15.5, 5.5))
    + solid(circle(30, 15.5, 4))
    + cuts(circle(30, 15.5, 1.5, 12), rect(48, 15.2, 10, 0.6)),
    solid(burst(88, 15.5, 6, 3, 8)),
)


def _pod(cx: float, cy: float) -> Tuple[Point, ...]:
    points = []
    for i in range(30):
        a = 2 * math.pi * i / 30
        r = 8.5 + 1.2 * math.sin(5 * a) + 0.6 * math.cos(3 * a)
        points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return tuple(points)


BUGBAIT = Icon(
    "weapon_bugbait",
    solid(_pod(48, 17))
    + cuts(thick(((44, 13), (47, 11.5), (50, 12)), 0.7), thick(((45, 20), (49, 21.5), (52, 19)), 0.7)),
    solid(circle(60, 10, 1.2, 10), circle(62.5, 15, 0.9, 10), circle(60, 22, 1, 10)),
)

SLAM = Icon(
    "weapon_slam",
    solid(
        ((30, 13), (31, 12), (61, 12), (62, 13), (62, 24), (61, 25), (31, 25), (30, 24)),
        ((34, 12), (36, 9), (56, 9), (58, 12)),
    )
    + cuts(rect(35, 10.8, 22, 0.6), circle(57, 21, 0.9, 10), circle(54, 21, 0.9, 10), rect(31, 16, 30, 0.6)),
    solid(rect(62, 18, 30, 0.8)),
)

ICONS = (PISTOL, MAGNUM, SMG, PULSE_RIFLE, SHOTGUN, CROSSBOW, CROWBAR, STUNSTICK, FRAG, RPG, GRAVITY_GUN, BUGBAIT, SLAM)


# The sheet

def layout(icons: Sequence[Icon], sheet_wide: int) -> Tuple[Cell, ...]:
    """Each icon's cell, its own width and a cell tall, left to right then down."""
    cells, x, y = [], 0, 0
    for icon in icons:
        left, top, right, bottom = icon.bounds()
        if top < 0 or bottom > UNIT_TALL:
            raise ArtError(f"{icon.name} reaches outside its cell's {UNIT_TALL} units: {top}..{bottom}")
        w = math.ceil((right - left) * SCALE) + MARGIN * 2
        if w > sheet_wide:
            raise ArtError(f"{icon.name} is {w} pixels wide, more than the sheet's {sheet_wide}")
        if x + w > sheet_wide:
            x, y = 0, y + CELL_TALL
        cells.append(Cell(icon, x, y, w, CELL_TALL, MARGIN))
        x += w
    return tuple(cells)


def mod_textures(cells: Sequence[Cell], sheet: str, negative: str) -> str:
    """The cells as TF2's scripts/mod_textures.txt gives its kill icons."""
    lines = ['"sandcastle/kill_icons"', "{", "\tTextureData", "\t{"]
    for c in cells:
        lines += [
            f'\t\t"{c.icon.name}"', "\t\t{",
            f'\t\t\t"dfile"\t"{sheet}"', f'\t\t\t"dnegfile"\t"{negative}"',
            f'\t\t\t"x"\t"{c.x}"', f'\t\t\t"y"\t"{c.y}"', f'\t\t\t"width"\t"{c.w}"', f'\t\t\t"height"\t"{c.h}"',
            "\t\t}",
        ]
    return "\n".join(lines + ["\t}", "}", ""])


def commands(cells: Sequence[Cell], color: str) -> list:
    """photocraft-cli run's arguments drawing every cell in color."""
    args = []

    def shape(name: str, parts: Sequence[Part], cell: Cell) -> None:
        path = {
            "fillRule": "nonzero",
            "subpaths": [
                {"closed": True, "op": p.op, "knots": [[round(v, 3) for v in cell.place(k)] for k in p.knots]}
                for p in parts
            ],
        }
        args.extend(["--cmd", "shape.create", "--params",
                     json.dumps({"kind": "path", "path": path, "fill": color, "stroke": None, "name": name})])

    for c in cells:
        shape(c.icon.name, c.icon.parts, c)
        args.extend(["--cmd", "layer.layerStyle.innerShadow", "--params", json.dumps(
            {"color": "#000000", "opacity": 30, "angle": 120, "distance": 1, "choke": 0, "size": 2})])
        if c.icon.flash:
            shape(f"{c.icon.name} flash", c.icon.flash, c)
            args.extend(["--cmd", "layer.setProps", "--params", json.dumps({"opacity": FLASH_OPACITY})])
    return args


def draw(cells: Sequence[Cell], color: str, master: Path, sheet: Path) -> None:
    new = {"width": SHEET_SIZE, "height": SHEET_SIZE, "background": "transparent", "name": master.stem}
    subprocess.run(["photocraft-cli", "run", "--new", json.dumps(new), *commands(cells, color), "--out", str(master)],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["photocraft-cli", "convert", str(master), str(sheet)], check=True, stdout=subprocess.DEVNULL)


def main() -> int:
    cells = layout(ICONS, SHEET_SIZE)
    for path in (SHEET.parent, LAYOUT.parent, MASTERS):
        path.mkdir(parents=True, exist_ok=True)
    draw(cells, CREAM, MASTERS / "hl2.pcraft", SHEET)
    draw(cells, DARK, MASTERS / "hl2_neg.pcraft", SHEET_NEG)
    LAYOUT.write_text(mod_textures(cells, f"{MATERIAL}.png", f"{MATERIAL}_neg.png"))
    for path in (SHEET, SHEET_NEG, LAYOUT):
        print(path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
