#!/usr/bin/env python3
"""Draw the gamemode's placeholder menu art: a sandcastle silhouette.

  gamemode_art.py            write icon24.png and logo.png into the gamemode folder

GMod's main menu and server browser show gamemodes/<name>/icon24.png (24x24,
up to 32x32) and logo.png (128 high, up to 1024 wide; the default is 288x128)
(wiki: Gamemode_Creation). Replace them with real art when there is some;
this keeps the tile from being blank until then.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

GAMEMODE = Path(__file__).resolve().parents[2] / "addons" / "sandcastle" / "gamemodes" / "sandcastle"
SAND = (224, 186, 120, 255)
SHADE = (176, 132, 72, 255)
FLAG = (189, 59, 59, 255)
INK = (240, 228, 205, 255)
ICON_SIZE = 24
LOGO_SIZE = (288, 128)
SCALE = 8  # drawn large, then shrunk, so the edges are smooth


def castle(draw: ImageDraw.ImageDraw, x: float, y: float, w: float, h: float) -> None:
    """A castle whose base spans x..x+w at y+h, h tall."""
    tower_w, keep_w = w * 0.26, w * 0.44
    merlon = tower_w / 3
    # the two towers, their merlons, and the keep between them
    for left in (x, x + w - tower_w):
        top = y + h * 0.28
        draw.rectangle([left, top, left + tower_w, y + h], fill=SAND)
        for i in (0, 2):
            draw.rectangle([left + i * merlon, top - merlon, left + (i + 1) * merlon, top], fill=SAND)
    keep_left = x + (w - keep_w) / 2
    keep_top = y + h * 0.12
    draw.rectangle([keep_left, keep_top, keep_left + keep_w, y + h], fill=SAND)
    for i in (0, 2, 4):
        step = keep_w / 5
        draw.rectangle([keep_left + i * step, keep_top - step, keep_left + (i + 1) * step, keep_top], fill=SAND)
    # the gate, and a flag on the keep
    gate_w = keep_w * 0.36
    gate_left = x + (w - gate_w) / 2
    draw.rectangle([gate_left, y + h * 0.62, gate_left + gate_w, y + h], fill=SHADE)
    draw.ellipse([gate_left, y + h * 0.62 - gate_w / 2, gate_left + gate_w, y + h * 0.62 + gate_w / 2], fill=SHADE)
    pole_x = x + w / 2
    draw.line([pole_x, keep_top - keep_w / 5, pole_x, y], fill=SHADE, width=max(1, int(w / 40)))
    draw.polygon([(pole_x, y), (pole_x + w * 0.18, y + h * 0.06), (pole_x, y + h * 0.12)], fill=FLAG)


def icon() -> Image.Image:
    big = ICON_SIZE * SCALE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    castle(ImageDraw.Draw(image), big * 0.06, big * 0.06, big * 0.88, big * 0.88)
    return image.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)


def logo() -> Image.Image:
    w, h = LOGO_SIZE[0] * SCALE, LOGO_SIZE[1] * SCALE
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    castle(draw, h * 0.08, h * 0.12, h * 0.8, h * 0.78)
    left, room = h * 0.98, w - h * 0.98 - h * 0.06
    size = int(h * 0.3)
    while True:
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", size)
        except OSError:
            font = ImageFont.load_default(size=size)
        if draw.textlength("Sandcastle", font=font) <= room:
            break
        size -= SCALE
    draw.text((left, h * 0.5), "Sandcastle", font=font, fill=INK, anchor="lm",
              stroke_width=int(size * 0.07), stroke_fill=SHADE)
    return image.resize(LOGO_SIZE, Image.LANCZOS)


def main() -> int:
    icon().save(GAMEMODE / "icon24.png")
    logo().save(GAMEMODE / "logo.png")
    print(f"wrote {GAMEMODE / 'icon24.png'} and {GAMEMODE / 'logo.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
