#!/usr/bin/env python3
"""Render the gamemode's menu art from its SVG master.

  gamemode_art.py            write icon24.png and logo.png from icon.svg

The master is gamemodes/sandcastle/icon.svg: a 16x16 icon in the style of
the Silk icon set (CC BY 2.5, Mark James), every shape on whole pixels.
GMod's main menu and server browser show gamemodes/<name>/icon24.png (24x24,
up to 32x32) and logo.png (128 high, up to 1024 wide; the default is
288x128) (wiki: Gamemode_Creation). Silk icons are drawn for 16 pixels, so
icon24.png is the 16x16 render centred on GMod's 24x24 canvas, sharp as
Silk's are at their size, not blurred by a scale of 1.5. logo.png is the
same render enlarged by whole pixels beside the title.

Needs rsvg-convert (Homebrew's librsvg) and Pillow.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GAMEMODE = Path(__file__).resolve().parents[2] / "addons" / "sandcastle" / "gamemodes" / "sandcastle"
MASTER = GAMEMODE / "icon.svg"
GRID = 16  # the master's pixel grid
ICON_SIZE = 24
LOGO_SIZE = (288, 128)
LOGO_ICON_SCALE = 6  # the logo's icon: the master's pixels, each 6x6
TITLE = "Sandcastle"
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
# Silk's box.png: its light sand for the title, its outline for the title's edge
INK = (244, 204, 143, 255)
EDGE = (120, 77, 21, 255)


def render(svg: Path, size: int) -> Image.Image:
    """The SVG rendered at size x size by rsvg-convert."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "render.png"
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg), "-o", str(out)], check=True)
        return Image.open(out).convert("RGBA")


def icon(master: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    offset = (ICON_SIZE - GRID) // 2
    canvas.alpha_composite(master, (offset, offset))
    return canvas


def logo(master: Image.Image) -> Image.Image:
    w, h = LOGO_SIZE
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    side = GRID * LOGO_ICON_SCALE
    big = master.resize((side, side), Image.NEAREST)
    margin = (h - side) // 2
    image.alpha_composite(big, (margin, margin))
    draw = ImageDraw.Draw(image)
    left = margin * 2 + side
    room = w - left - margin
    size = h // 3
    while True:
        font = ImageFont.truetype(FONT, size)
        if draw.textlength(TITLE, font=font) <= room:
            break
        size -= 1
    draw.text((left, h // 2), TITLE, font=font, fill=INK, anchor="lm", stroke_width=max(1, size // 14), stroke_fill=EDGE)
    return image


def main() -> int:
    master = render(MASTER, GRID)
    icon(master).save(GAMEMODE / "icon24.png")
    logo(master).save(GAMEMODE / "logo.png")
    print(f"rendered {MASTER.name} into {GAMEMODE / 'icon24.png'} and {GAMEMODE / 'logo.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
