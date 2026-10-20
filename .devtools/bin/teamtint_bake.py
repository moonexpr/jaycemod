#!/usr/bin/env python3
"""Bake Team Tint's team textures, and the addon's own (addons/teamtint).

A material with no tint mask takes its team from a baked copy of its base
texture: inside a hand-painted mask, each pixel takes the team's hue and
saturation at its own value (lifted, so dark armour can read as a team), and
outside it, and in the alpha, nothing changes. The copy goes where
teamtint_catalog's BakedTexture looks: materials/teamtint/<team>/<base>.vtf.

  teamtint_bake.py decode SOURCE OUT.png         a texture as a PNG, to paint a mask over
  teamtint_bake.py mask SOURCE OUT.png [--hue 180-260] [--sat 0-1] [--val 0-1]
                                                 a starting mask: white where every range holds
  teamtint_bake.py bake SOURCE BASE MASK.png [--tuning tuning.json] [--addon DIR]
                       [--value-gain G] [--value-bias B] [--saturation S] [--teams red,blu]
                                                 the team textures of BASE (its $basetexture)
  teamtint_bake.py builtins [--addon DIR]        the light warp, white, black and a flat normal map

SOURCE is a .vtf file, or VPK:TEXTURE (a pak's _dir.vpk and a texture path
in it, e.g. hl2_textures_dir.vpk:models/combine_soldier/combinesoldiersheet).
The team colours are the tuning's (teamtint_export's tuning.json), else TF2's.

VTFs are read in 7.2 and the 7.3+ resource layout, DXT1/DXT3/DXT5 (decoded
and encoded by Pillow's DDS codec: a DDS header on the same blocks) and the
8-bit uncompressed formats; they are written as 7.2, DXT1 (no alpha) or DXT5,
with every mip and a DXT1 thumbnail.
"""
from __future__ import annotations

import argparse
import colorsys
import io
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np
from PIL import Image

from vpk import Vpk

# VTF image formats (VTFImageFormat)
RGBA8888, ABGR8888, RGB888, BGR888 = 0, 1, 2, 3
ARGB8888, BGRA8888, DXT1, DXT3, DXT5, BGRX8888 = 11, 12, 13, 14, 15, 16
NO_FORMAT = 0xFFFFFFFF

# channel order of the uncompressed formats, as Pillow names them
UNCOMPRESSED = {RGBA8888: "RGBA", ABGR8888: "ABGR", RGB888: "RGB", BGR888: "BGR",
                ARGB8888: "ARGB", BGRA8888: "BGRA", BGRX8888: "BGRX"}
DXT = {DXT1: (b"DXT1", 8), DXT3: (b"DXT3", 16), DXT5: (b"DXT5", 16)}

# texture flags
CLAMPS, CLAMPT, NOMIP, NOLOD, EIGHTBITALPHA = 0x4, 0x8, 0x100, 0x200, 0x2000

HEADER_SIZE = 80  # 7.2's
THUMBNAIL = 16
RESOURCE_LOW, RESOURCE_HIGH = b"\x01\0\0", b"\x30\0\0"

# TF2's Team Spirit: teamtint_tuning's defaults
DEFAULT_COLORS = {"red": (184, 56, 59), "blu": (88, 133, 162)}

# The light warp's keys, half Lambert (0..1) -> colour, before the shader's
# doubling (the paper's Fig. 7): a cool gradient in shadow, a reddish
# terminator, a grey ramp ending just over mid-grey.
WARP_KEYS = [
    (0.00, (0.09, 0.10, 0.16)),
    (0.35, (0.17, 0.17, 0.24)),
    (0.50, (0.30, 0.22, 0.21)),
    (0.62, (0.40, 0.38, 0.37)),
    (1.00, (0.56, 0.56, 0.56)),
]
WARP_SIZE = (256, 4)


class BakeError(Exception):
    pass


@dataclass(frozen=True)
class Header:
    version: Tuple[int, int]
    header_size: int
    width: int
    height: int
    flags: int
    format: int
    mips: int
    thumb_format: int
    thumb_width: int
    thumb_height: int
    image_offset: int  # where the high-res mips start, smallest first


def mip_bytes(fmt: int, width: int, height: int) -> int:
    if fmt in DXT:
        return max(1, (width + 3) // 4) * max(1, (height + 3) // 4) * DXT[fmt][1]
    if fmt in UNCOMPRESSED:
        return width * height * len(UNCOMPRESSED[fmt])
    raise BakeError(f"VTF format {fmt} is not one this tool reads")


def read_header(data: bytes) -> Header:
    if len(data) < 64 or data[:4] != b"VTF\0":
        raise BakeError("not a VTF")
    major, minor, header_size = struct.unpack_from("<2II", data, 4)
    width, height, flags = struct.unpack_from("<HHI", data, 16)
    fmt, mips, thumb_format, thumb_w, thumb_h = struct.unpack_from("<IBIBB", data, 52)
    if thumb_format == NO_FORMAT:
        thumb_w = thumb_h = 0
    if (major, minor) >= (7, 3):
        count, = struct.unpack_from("<I", data, 68)
        offset = None
        for i in range(count):
            tag, _, value = struct.unpack_from("<3sBI", data, 80 + 8 * i)
            if tag == RESOURCE_HIGH:
                offset = value
        if offset is None:
            raise BakeError("a VTF without an image resource")
    else:
        offset = header_size + (mip_bytes(thumb_format, thumb_w, thumb_h) if thumb_w else 0)
    return Header((major, minor), header_size, width, height, flags, fmt, mips,
                  thumb_format, thumb_w, thumb_h, offset)


def _decode(fmt: int, width: int, height: int, blocks: bytes) -> Image.Image:
    if fmt in UNCOMPRESSED:
        return Image.frombytes("RGBA" if len(UNCOMPRESSED[fmt]) == 4 else "RGB", (width, height), blocks,
                               "raw", UNCOMPRESSED[fmt]).convert("RGBA")
    four_cc, _ = DXT[fmt]
    dds = _dds_header(width, height, four_cc, len(blocks)) + blocks
    image = Image.open(io.BytesIO(dds))
    image.load()
    return image.convert("RGBA")


def read_vtf(data: bytes) -> Image.Image:
    """The largest mip, as RGBA."""
    header = read_header(data)
    at = header.image_offset
    for level in range(header.mips - 1, 0, -1):  # every smaller mip comes first
        at += mip_bytes(header.format, max(1, header.width >> level), max(1, header.height >> level))
    size = mip_bytes(header.format, header.width, header.height)
    if at + size > len(data):
        raise BakeError("a VTF shorter than its header says")
    return _decode(header.format, header.width, header.height, data[at:at + size])


def _dds_header(width: int, height: int, four_cc: bytes, size: int) -> bytes:
    pixel_format = struct.pack("<II4s5I", 32, 0x4, four_cc, 0, 0, 0, 0, 0)
    return (b"DDS " + struct.pack("<7I", 124, 0x1007 | 0x80000, height, width, size, 0, 1)
            + b"\0" * 44 + pixel_format + struct.pack("<5I", 0x1000, 0, 0, 0, 0))


def _encode(image: Image.Image, fmt: int) -> bytes:
    if fmt in UNCOMPRESSED:
        mode = "RGBA" if len(UNCOMPRESSED[fmt]) == 4 else "RGB"
        return image.convert(mode).tobytes("raw", UNCOMPRESSED[fmt])
    out = io.BytesIO()
    image.convert("RGBA").save(out, "DDS", pixel_format=DXT[fmt][0].decode())
    data = out.getvalue()
    return data[128:128 + mip_bytes(fmt, *image.size)]


def _mip_chain(image: Image.Image) -> List[Image.Image]:
    chain = [image]
    while chain[-1].size != (1, 1):
        w, h = chain[-1].size
        chain.append(chain[-1].resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS))
    return chain


def write_vtf(image: Image.Image, fmt: int, mips: bool = True, flags: int = 0) -> bytes:
    """A 7.2 VTF of image: every mip (unless mips is False), smallest first, after a DXT1 thumbnail."""
    image = image.convert("RGBA")
    width, height = image.size
    chain = _mip_chain(image) if mips else [image]
    if not mips:
        flags |= NOMIP | NOLOD
    if fmt == DXT5:
        flags |= EIGHTBITALPHA
    thumb = image.resize((min(THUMBNAIL, width), min(THUMBNAIL, height)), Image.LANCZOS)
    header = bytearray(HEADER_SIZE)
    struct.pack_into("<4s2II", header, 0, b"VTF\0", 7, 2, HEADER_SIZE)
    struct.pack_into("<HHI", header, 16, width, height, flags)
    struct.pack_into("<HH", header, 24, 1, 0)
    struct.pack_into("<3f", header, 32, *(c / 255 for c in image.convert("RGB").resize((1, 1)).getpixel((0, 0))))
    struct.pack_into("<f", header, 48, 1.0)
    struct.pack_into("<IBIBBH", header, 52, fmt, len(chain), DXT1, thumb.size[0], thumb.size[1], 1)
    body = _encode(thumb, DXT1) + b"".join(_encode(level, fmt) for level in reversed(chain))
    return bytes(header) + body


def recolor(image: Image.Image, mask: Image.Image, team: Tuple[int, int, int],
            value_gain: float = 1.0, value_bias: float = 0.1, saturation: float = 1.0) -> Image.Image:
    """image with, inside mask (white), each pixel at the team's hue and
    saturation (times saturation) and its own value times value_gain plus
    value_bias, the mask's grey blending it with the original; alpha kept."""
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float64) / 255.0
    weight = np.asarray(mask.convert("L").resize(image.size, Image.BILINEAR), dtype=np.float64)[..., None] / 255.0
    rgb = rgba[..., :3]
    value = np.clip(rgb.max(axis=-1) * value_gain + value_bias, 0.0, 1.0)
    hue, sat, _ = colorsys.rgb_to_hsv(*(c / 255.0 for c in team))
    sat = min(1.0, sat * saturation)
    target = np.array(colorsys.hsv_to_rgb(hue, sat, 1.0))
    # value is the largest channel: the team colour scaled to it, so shading and detail stay
    painted = target[None, None, :] * value[..., None]
    out = rgb * (1.0 - weight) + painted * weight
    result = np.concatenate([out, rgba[..., 3:]], axis=-1)
    return Image.fromarray(np.round(result * 255.0).astype(np.uint8), "RGBA")


def parse_range(text: str) -> Tuple[float, float]:
    low, sep, high = text.partition("-")
    if not sep:
        raise ValueError(f"a range is LOW-HIGH, not {text!r}")
    return float(low), float(high)


def auto_mask(image: Image.Image, hue=(0.0, 360.0), sat=(0.0, 1.0), val=(0.0, 1.0)) -> Image.Image:
    """White where the pixel's hue (degrees), saturation and value all fall in
    their ranges: a start for the artist to clean, never a finished mask."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64) / 255.0
    hsv = np.asarray(image.convert("RGB").convert("HSV"), dtype=np.float64) / 255.0
    h = hsv[..., 0] * 360.0
    s = hsv[..., 1]
    v = rgb.max(axis=-1)
    keep = (h >= hue[0]) & (h <= hue[1]) & (s >= sat[0]) & (s <= sat[1]) & (v >= val[0]) & (v <= val[1])
    return Image.fromarray((keep * 255).astype(np.uint8), "L")


def lightwarp() -> Image.Image:
    width, height = WARP_SIZE
    row = []
    for x in range(width):
        t = x / (width - 1)
        for (t0, c0), (t1, c1) in zip(WARP_KEYS, WARP_KEYS[1:]):
            if t0 <= t <= t1:
                f = (t - t0) / (t1 - t0)
                row.append(tuple(round(255 * (a + (b - a) * f)) for a, b in zip(c0, c1)))
                break
    image = Image.new("RGB", (width, height))
    for y in range(height):
        for x, color in enumerate(row):
            image.putpixel((x, y), color)
    return image.convert("RGBA")


def write_builtins(addon: Path) -> List[Path]:
    folder = addon / "materials" / "teamtint"
    folder.mkdir(parents=True, exist_ok=True)
    files = {
        "lightwarp.vtf": write_vtf(lightwarp(), BGR888, mips=False, flags=CLAMPS | CLAMPT),
        "white.vtf": write_vtf(Image.new("RGBA", (4, 4), (255, 255, 255, 255)), BGR888, mips=False),
        "black.vtf": write_vtf(Image.new("RGBA", (4, 4), (0, 0, 0, 255)), BGR888, mips=False),
        # a normal map facing straight out, its alpha (the phong mask) full:
        # VertexLitGeneric's phong path, where the warp and the rim live, wants one
        "flat_normal.vtf": write_vtf(Image.new("RGBA", (4, 4), (128, 128, 255, 255)), BGRA8888, mips=False),
    }
    written = []
    for name, data in files.items():
        (folder / name).write_bytes(data)
        written.append(folder / name)
    return written


def team_colors(tuning: Optional[Path]) -> Dict[str, Tuple[int, int, int]]:
    colors = dict(DEFAULT_COLORS)
    if tuning:
        base = json.loads(tuning.read_text()).get("base", {})
        for team in colors:
            value = base.get(f"{team}_color")
            if isinstance(value, list) and len(value) == 3:
                colors[team] = tuple(int(c) for c in value)
    return colors


def _has_alpha(image: Image.Image) -> bool:
    return image.getchannel("A").getextrema()[0] < 255


def baked_path(addon: Path, team: str, base: str) -> Path:
    """teamtint_catalog's BakedTexture, as a file."""
    name = base.lower().replace("\\", "/")
    for prefix in ("materials/",):
        if name.startswith(prefix):
            name = name[len(prefix):]
    if name.endswith(".vtf"):
        name = name[:-4]
    return addon / "materials" / "teamtint" / team / (name + ".vtf")


def bake_teams(source: bytes, base: str, mask: Image.Image, colors: Dict[str, Tuple[int, int, int]], addon: Path,
               teams: Iterable[str] = ("red", "blu"), **adjust) -> List[Path]:
    image = read_vtf(source)
    fmt = DXT5 if _has_alpha(image) else DXT1
    written = []
    for team in teams:
        path = baked_path(addon, team, base)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(write_vtf(recolor(image, mask, colors[team], **adjust), fmt))
        written.append(path)
    return written


def load_source(spec: str) -> bytes:
    if ":" in spec and spec.split(":", 1)[0].endswith(".vpk"):
        pak, texture = spec.split(":", 1)
        name = "materials/" + texture.lower().strip("/")
        if not name.endswith(".vtf"):
            name += ".vtf"
        return Vpk.open(Path(pak)).read(name)
    return Path(spec).read_bytes()


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="action", required=True)
    decode = sub.add_parser("decode")
    decode.add_argument("source")
    decode.add_argument("out", type=Path)
    mask = sub.add_parser("mask")
    mask.add_argument("source")
    mask.add_argument("out", type=Path)
    mask.add_argument("--hue", default="0-360")
    mask.add_argument("--sat", default="0-1")
    mask.add_argument("--val", default="0-1")
    run = sub.add_parser("bake")
    run.add_argument("source")
    run.add_argument("base", help="the material's $basetexture")
    run.add_argument("mask", type=Path)
    run.add_argument("--tuning", type=Path)
    run.add_argument("--addon", type=Path, default=Path("addons/teamtint"))
    run.add_argument("--teams", default="red,blu")
    run.add_argument("--value-gain", type=float, default=1.0)
    run.add_argument("--value-bias", type=float, default=0.1)
    run.add_argument("--saturation", type=float, default=1.0)
    builtins = sub.add_parser("builtins")
    builtins.add_argument("--addon", type=Path, default=Path("addons/teamtint"))
    args = parser.parse_args(argv)

    try:
        if args.action == "decode":
            read_vtf(load_source(args.source)).save(args.out)
            written = [args.out]
        elif args.action == "mask":
            image = read_vtf(load_source(args.source))
            auto_mask(image, parse_range(args.hue), parse_range(args.sat), parse_range(args.val)).save(args.out)
            written = [args.out]
        elif args.action == "bake":
            written = bake_teams(load_source(args.source), args.base, Image.open(args.mask), team_colors(args.tuning),
                                 args.addon, args.teams.split(","), value_gain=args.value_gain,
                                 value_bias=args.value_bias, saturation=args.saturation)
        else:
            written = write_builtins(args.addon)
    except (BakeError, OSError, ValueError, KeyError) as error:
        print(f"teamtint_bake: {error}", file=sys.stderr)
        return 1
    for path in written:
        print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
