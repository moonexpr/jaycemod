#!/usr/bin/env python3
"""Render the gamemode's menu art from its SVG master.

  gamemode_art.py            write icon24.png and logo.png from icon.svg

The master is gamemodes/sandcastle/icon.svg: a 16 unit icon in the style of
FamFamFam Silk as SVG (CC BY 4.0), the vector remake of Mark James's Silk
icons. GMod's main menu and server browser show gamemodes/<name>/icon24.png
(24x24, up to 32x32) and logo.png (128 high, up to 1024 wide; the default is
288x128) (wiki: Gamemode_Creation). Both are the master rendered as a vector
at their size: icon24.png fills its 24x24, and logo.png has it beside the
title.

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
ICON_SIZE = 24
LOGO_SIZE = (288, 128)
LOGO_ICON_SIZE = 96  # the logo's icon, six times the master's 16
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


def logo(mark: Image.Image) -> Image.Image:
    w, h = LOGO_SIZE
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    side = mark.width
    margin = (h - side) // 2
    image.alpha_composite(mark, (margin, margin))
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
    render(MASTER, ICON_SIZE).save(GAMEMODE / "icon24.png")
    logo(render(MASTER, LOGO_ICON_SIZE)).save(GAMEMODE / "logo.png")
    print(f"rendered {MASTER.name} into {GAMEMODE / 'icon24.png'} and {GAMEMODE / 'logo.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
