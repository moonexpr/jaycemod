"""teamtint_bake.py reads and writes VTFs (uncompressed and DXT, 7.2 and the
7.3+ resource layout), recolors a texture inside a mask toward a team colour,
starts a mask from thresholds, and makes the addon's own textures (the light
warp, white, black). The textures are built here, pixel by pixel."""
import json
import struct

import numpy as np
import pytest
from PIL import Image

import teamtint_bake as bake


def solid(size, rgba):
    return Image.new("RGBA", size, rgba)


def test_an_uncompressed_vtf_reads_back_exactly(tmp_path):
    image = Image.new("RGB", (8, 4))
    for x in range(8):
        for y in range(4):
            image.putpixel((x, y), (x * 30, y * 60, 200))
    path = tmp_path / "plain.vtf"
    path.write_bytes(bake.write_vtf(image.convert("RGBA"), bake.BGR888, mips=False))
    back = bake.read_vtf(path.read_bytes())
    assert back.size == (8, 4)
    assert back.getpixel((7, 3))[:3] == (210, 180, 200)


def test_a_dxt5_vtf_keeps_its_colour_and_alpha_and_has_every_mip(tmp_path):
    data = bake.write_vtf(solid((64, 32), (200, 50, 50, 128)), bake.DXT5)
    header = bake.read_header(data)
    assert header.format == bake.DXT5
    assert header.mips == 7  # 64x32 down to 1x1
    r, g, b, a = bake.read_vtf(data).getpixel((10, 10))
    assert abs(r - 200) < 12 and abs(g - 50) < 12 and abs(b - 50) < 12
    assert abs(a - 128) < 4


def test_a_dxt_file_is_its_header_thumbnail_and_mips_exactly():
    data = bake.write_vtf(solid((16, 16), (1, 2, 3, 255)), bake.DXT1)
    header = bake.read_header(data)
    mips = sum(bake.mip_bytes(bake.DXT1, max(1, 16 >> i), max(1, 16 >> i)) for i in range(header.mips))
    thumbnail = bake.mip_bytes(bake.DXT1, header.thumb_width, header.thumb_height)
    assert len(data) == bake.HEADER_SIZE + thumbnail + mips


def test_a_vtf_with_resources_is_read_from_its_image_resource():
    """7.3 and later: the image's offset is in the resource list, not after the header."""
    pixels = bytes([10, 20, 30] * 4)  # 2x2 BGR888
    header = bytearray(bake.HEADER_SIZE + 16)
    struct.pack_into("<4s2II", header, 0, b"VTF\0", 7, 3, len(header))
    struct.pack_into("<HHI", header, 16, 2, 2, 0)
    struct.pack_into("<HH", header, 24, 1, 0)
    struct.pack_into("<I B I B B H", header, 52, bake.BGR888, 1, 0xFFFFFFFF, 0, 0, 1)
    struct.pack_into("<I", header, 68, 2)
    struct.pack_into("<3sBI", header, 80, b"\x01\0\0", 0, 0)  # an empty low-res resource
    struct.pack_into("<3sBI", header, 88, b"\x30\0\0", 0, len(header))
    image = bake.read_vtf(bytes(header) + pixels)
    assert image.getpixel((1, 1))[:3] == (30, 20, 10)


def test_not_a_vtf_is_refused():
    with pytest.raises(bake.BakeError):
        bake.read_vtf(b"DDS nope")


def test_recolor_takes_the_team_hue_inside_the_mask_and_leaves_the_rest():
    image = Image.new("RGBA", (2, 1))
    image.putpixel((0, 0), (90, 100, 110, 77))  # grey-blue armour
    image.putpixel((1, 0), (90, 100, 110, 77))
    mask = Image.new("L", (2, 1))
    mask.putpixel((0, 0), 255)
    out = bake.recolor(image, mask, (184, 56, 59))
    r, g, b, a = out.getpixel((0, 0))
    assert r > g and r > b, "RED inside the mask"
    assert a == 77, "the alpha (a phong mask, say) is kept"
    assert out.getpixel((1, 0)) == (90, 100, 110, 77), "untouched outside"


def test_recolor_keeps_the_texture_detail_as_value():
    image = Image.new("RGBA", (2, 1))
    image.putpixel((0, 0), (40, 40, 40, 255))
    image.putpixel((1, 0), (160, 160, 160, 255))
    out = bake.recolor(image, Image.new("L", (2, 1), 255), (88, 133, 162))
    dark, light = out.getpixel((0, 0)), out.getpixel((1, 0))
    assert sum(light[:3]) > sum(dark[:3]), "light stays lighter"
    assert dark[2] > dark[0] and light[2] > light[0], "both BLU"


def test_value_lift_raises_dark_cloth():
    image = solid((1, 1), (30, 30, 30, 255))
    mask = Image.new("L", (1, 1), 255)
    flat = bake.recolor(image, mask, (184, 56, 59), value_bias=0.0)
    lifted = bake.recolor(image, mask, (184, 56, 59), value_bias=0.2)
    assert sum(lifted.getpixel((0, 0))[:3]) > sum(flat.getpixel((0, 0))[:3])


def test_a_mask_of_another_size_is_fitted_to_the_texture():
    out = bake.recolor(solid((8, 8), (100, 100, 100, 255)), Image.new("L", (2, 2), 255), (184, 56, 59))
    assert out.size == (8, 8)
    assert out.getpixel((7, 7))[0] > out.getpixel((7, 7))[2]


def test_an_automatic_mask_keeps_what_falls_in_every_range():
    image = Image.new("RGB", (3, 1))
    image.putpixel((0, 0), (60, 80, 120))  # blue-grey, saturated a little
    image.putpixel((1, 0), (220, 170, 140))  # skin
    image.putpixel((2, 0), (5, 5, 8))  # near black
    mask = bake.auto_mask(image, hue=(180, 260), sat=(0.1, 0.8), val=(0.1, 1.0))
    assert [mask.getpixel((x, 0)) for x in range(3)] == [255, 0, 0]


def test_a_range_is_read_from_its_text():
    assert bake.parse_range("180-260") == (180.0, 260.0)
    with pytest.raises(ValueError):
        bake.parse_range("180")


def test_the_light_warp_is_cool_in_shadow_reddish_at_the_terminator_and_just_over_mid_grey_lit():
    warp = bake.lightwarp()
    assert warp.size[0] == 256
    shadow, terminator, lit = (warp.getpixel((x, 0)) for x in (10, 128, 255))
    assert shadow[2] > shadow[0], "shadow tends cool"
    assert terminator[0] > terminator[2], "a reddish terminator"
    assert 128 < lit[0] < 160 and lit[0] == lit[1] == lit[2], "lit: grey, just over mid-grey (doubled in the shader)"


def test_the_builtins_are_written_where_the_addon_reads_them(tmp_path):
    written = bake.write_builtins(tmp_path)
    names = {p.relative_to(tmp_path).as_posix() for p in written}
    assert names == {"materials/teamtint/lightwarp.vtf", "materials/teamtint/white.vtf", "materials/teamtint/black.vtf",
                     "materials/teamtint/flat_normal.vtf"}
    flat = bake.read_vtf((tmp_path / "materials/teamtint/flat_normal.vtf").read_bytes())
    assert flat.getpixel((0, 0)) == (128, 128, 255, 255)
    white = bake.read_vtf((tmp_path / "materials/teamtint/white.vtf").read_bytes())
    assert white.getpixel((0, 0))[:3] == (255, 255, 255)
    assert bake.read_header((tmp_path / "materials/teamtint/lightwarp.vtf").read_bytes()).mips == 1, "a warp has no mips"


def test_team_colours_come_from_an_exported_tuning(tmp_path):
    path = tmp_path / "tuning.json"
    path.write_text(json.dumps({"base": {"red_color": [200, 10, 20]}}))
    colors = bake.team_colors(path)
    assert colors["red"] == (200, 10, 20)
    assert colors["blu"] == bake.DEFAULT_COLORS["blu"], "the default where the tuning has none"


def test_baking_a_team_writes_its_texture_where_the_catalog_looks(tmp_path):
    source = tmp_path / "sheet.vtf"
    source.write_bytes(bake.write_vtf(solid((8, 8), (90, 100, 110, 255)), bake.DXT1))
    mask = tmp_path / "mask.png"
    Image.new("L", (8, 8), 255).save(mask)
    out = bake.bake_teams(source.read_bytes(), "Models/Combine_Soldier/CombineSoldierSheet", Image.open(mask),
                          bake.DEFAULT_COLORS, tmp_path / "addon")
    red = tmp_path / "addon/materials/teamtint/red/models/combine_soldier/combinesoldiersheet.vtf"
    assert red in out and red.exists()
    assert bake.read_header(red.read_bytes()).format == bake.DXT1, "no alpha in, none out"
    r, g, b, _ = bake.read_vtf(red.read_bytes()).getpixel((4, 4))
    assert r > b
