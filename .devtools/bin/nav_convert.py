#!/usr/bin/env python3
"""Convert TF2 navigation meshes to files Garry's Mod can load.

  nav_convert.py MAP.bsp|MAP.nav...              convert and report; writes nothing
  nav_convert.py MAP.bsp|MAP.nav... --out DIR    also write DIR/<map>.nav and DIR/<map>.tfnav.txt

TF2 saves version 16, sub-version 2: CTFNavArea::Save appends a u32 of TF
attributes to every area (sdk/server/tf/nav_mesh/tf_nav_area.cpp), and
CTFNavMesh adds no mesh data before or after the areas. GMod's loader is the
base CNavArea::Load, which cannot skip that u32. The converted file is the
same mesh at sub-version 0, without the u32s, stamped with the BSP's real size.

The u32s go to a sidecar instead, <map>.tfnav.txt: a "tfnav 1 <size>" line
(the converted mesh's size in bytes, so a mesh generated over it later is
told apart), then
"<area id> <attributes>" for each area with any of TF_NAV_PERSISTENT_ATTRIBUTES
(the ones TF2 saves: sentry and sniper spots, setup gates, one-way doors...),
in id order. The converted mesh keeps every area id, so the ids match; the
gamemode reads it as foundation.nav.tf_attributes.

For a .bsp, the mesh is found where TF2's CNavMesh::GetNavDataFromFile looks:
a loose maps/<map>.nav, then maps/<map>.nav in tf/*_dir.vpk, then the BSP's
pakfile (lump 40) as maps/<map>.nav or maps/embed.nav. A loose .nav takes the
size of the <map>.bsp beside it. GMod reads garrysmod/maps/<map>.nav before any
mesh in a BSP, so --out is normally that directory.
"""
from __future__ import annotations

import argparse
import io
import struct
import sys
import zipfile
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Callable, Dict, Tuple

from tf2_content import Vpk

NAV_MAGIC = 0xFEEDFACE
NAV_VERSION = 16
GMOD_SUB_VERSION = 0
TF_AREA_DATA = {0: 0, 1: 0, 2: 4}  # CTFNavArea::Load: sub-version 2 adds a u32 of TF attributes
NUM_DIRECTIONS = 4
NUM_LADDER_DIRECTIONS = 2
MAX_NAV_TEAMS = 2
NUM_CORNERS = 4
PAKFILE_LUMP = 40
BSP_LUMP_TABLE = 8
BSP_LUMP_SIZE = 16
TF_NAV_SNIPER_SPOT = 0x00200000
TF_NAV_SENTRY_SPOT = 0x00400000
TF_NAV_PERSISTENT_ATTRIBUTES = 0x767FF800  # tf_nav_area.h: what CTFNavArea::Save keeps
SIDECAR_HEADER = "tfnav 1"


class NavError(Exception):
    """The input is not a mesh this tool can convert."""


class Truncated(NavError):
    pass


class TrailingData(NavError):
    pass


class UnsupportedVersion(NavError):
    pass


class EmptyMesh(NavError):
    pass


class NoNavMesh(NavError):
    pass


class MissingBsp(NavError):
    pass


class _Reader:
    def __init__(self, data: bytes):
        self.data, self.pos = data, 0

    def take(self, fmt: str):
        size = struct.calcsize(fmt)
        if self.pos + size > len(self.data):
            raise Truncated(f"file ends at byte {len(self.data)}, reading {size} bytes at {self.pos}")
        values = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += size
        return values

    def one(self, fmt: str):
        return self.take(fmt)[0]

    def raw(self, size: int) -> bytes:
        return self.one(f"{size}s")

    def ids(self, count_fmt: str = "<I") -> Tuple[int, ...]:
        return self.take(f"<{self.one(count_fmt)}I")


class _Writer:
    def __init__(self):
        self.out = bytearray()

    def put(self, fmt: str, *values) -> None:
        self.out += struct.pack(fmt, *values)

    def ids(self, ids: Tuple[int, ...]) -> None:
        self.put(f"<I{len(ids)}I", len(ids), *ids)


Vec = Tuple[float, float, float]


@dataclass(frozen=True)
class Places:
    names: Tuple[bytes, ...]  # each as stored: the name and its NUL
    has_unnamed: int

    @classmethod
    def read(cls, r: _Reader) -> "Places":
        return cls(tuple(r.raw(r.one("<H")) for _ in range(r.one("<H"))), r.one("<B"))

    def write(self, w: _Writer) -> None:
        w.put("<H", len(self.names))
        for name in self.names:
            w.put(f"<H{len(name)}s", len(name), name)
        w.put("<B", self.has_unnamed)


@dataclass(frozen=True)
class HidingSpot:
    id: int
    pos: Vec
    flags: int

    @classmethod
    def read(cls, r: _Reader) -> "HidingSpot":
        return cls(r.one("<I"), r.take("<3f"), r.one("<B"))

    def write(self, w: _Writer) -> None:
        w.put("<I3fB", self.id, *self.pos, self.flags)


@dataclass(frozen=True)
class SpotOrder:
    id: int
    t: int  # 255 * the fraction along the path

    @classmethod
    def read(cls, r: _Reader) -> "SpotOrder":
        return cls(*r.take("<IB"))

    def write(self, w: _Writer) -> None:
        w.put("<IB", self.id, self.t)


@dataclass(frozen=True)
class Encounter:
    from_id: int
    from_dir: int
    to_id: int
    to_dir: int
    spots: Tuple[SpotOrder, ...]

    @classmethod
    def read(cls, r: _Reader) -> "Encounter":
        from_id, from_dir, to_id, to_dir, count = r.take("<IBIBB")
        return cls(from_id, from_dir, to_id, to_dir, tuple(SpotOrder.read(r) for _ in range(count)))

    def write(self, w: _Writer) -> None:
        w.put("<IBIBB", self.from_id, self.from_dir, self.to_id, self.to_dir, len(self.spots))
        for spot in self.spots:
            spot.write(w)


@dataclass(frozen=True)
class VisibleArea:
    id: int
    attributes: int

    @classmethod
    def read(cls, r: _Reader) -> "VisibleArea":
        return cls(*r.take("<IB"))

    def write(self, w: _Writer) -> None:
        w.put("<IB", self.id, self.attributes)


@dataclass(frozen=True)
class Area:
    """One CNavArea as version 16 stores it, then `custom`: the derived class's bytes."""

    id: int
    attributes: int
    nw: Vec
    se: Vec
    ne_z: float
    sw_z: float
    connections: Tuple[Tuple[int, ...], ...]  # north, east, south, west
    hiding_spots: Tuple[HidingSpot, ...]
    encounters: Tuple[Encounter, ...]
    place: int
    ladders: Tuple[Tuple[int, ...], ...]  # up, down
    occupy_times: Tuple[float, ...]
    light: Tuple[float, ...]
    visible: Tuple[VisibleArea, ...]
    inherit_visibility_from: int
    custom: bytes

    @classmethod
    def read(cls, r: _Reader, custom_size: int) -> "Area":
        return cls(
            id=r.one("<I"),
            attributes=r.one("<i"),
            nw=r.take("<3f"),
            se=r.take("<3f"),
            ne_z=r.one("<f"),
            sw_z=r.one("<f"),
            connections=tuple(r.ids() for _ in range(NUM_DIRECTIONS)),
            hiding_spots=tuple(HidingSpot.read(r) for _ in range(r.one("<B"))),
            encounters=tuple(Encounter.read(r) for _ in range(r.one("<I"))),
            place=r.one("<H"),
            ladders=tuple(r.ids() for _ in range(NUM_LADDER_DIRECTIONS)),
            occupy_times=r.take(f"<{MAX_NAV_TEAMS}f"),
            light=r.take(f"<{NUM_CORNERS}f"),
            visible=tuple(VisibleArea.read(r) for _ in range(r.one("<I"))),
            inherit_visibility_from=r.one("<I"),
            custom=r.raw(custom_size),
        )

    def write(self, w: _Writer) -> None:
        w.put("<Ii3f3fff", self.id, self.attributes, *self.nw, *self.se, self.ne_z, self.sw_z)
        for ids in self.connections:
            w.ids(ids)
        w.put("<B", len(self.hiding_spots))
        for spot in self.hiding_spots:
            spot.write(w)
        w.put("<I", len(self.encounters))
        for encounter in self.encounters:
            encounter.write(w)
        w.put("<H", self.place)
        for ids in self.ladders:
            w.ids(ids)
        w.put(f"<{MAX_NAV_TEAMS}f{NUM_CORNERS}fI", *self.occupy_times, *self.light, len(self.visible))
        for visible in self.visible:
            visible.write(w)
        w.put("<I", self.inherit_visibility_from)
        w.out += self.custom


@dataclass(frozen=True)
class Ladder:
    id: int
    width: float
    top: Vec
    bottom: Vec
    length: float
    dir: int
    top_forward: int
    top_left: int
    top_right: int
    top_behind: int
    bottom_area: int

    FORMAT = "<If3f3ffI5I"

    @classmethod
    def read(cls, r: _Reader) -> "Ladder":
        v = r.take(cls.FORMAT)
        return cls(v[0], v[1], v[2:5], v[5:8], v[8], *v[9:])

    def write(self, w: _Writer) -> None:
        w.put(self.FORMAT, self.id, self.width, *self.top, *self.bottom, self.length, self.dir,
              self.top_forward, self.top_left, self.top_right, self.top_behind, self.bottom_area)


@dataclass(frozen=True)
class NavMesh:
    version: int
    sub_version: int
    bsp_size: int
    analyzed: int
    places: Places
    areas: Tuple[Area, ...]
    ladders: Tuple[Ladder, ...]


@dataclass(frozen=True)
class Loader:
    """A game's CNavMesh::Load at version 16; `area_data` maps a sub-version to its bytes per area."""

    name: str
    area_data: Callable[[int], int]

    def parse(self, data: bytes) -> NavMesh:
        r = _Reader(data)
        magic, version = r.take("<II")
        if magic != NAV_MAGIC:
            raise NavError(f"not a nav file (magic {magic:#x})")
        if version != NAV_VERSION:
            raise UnsupportedVersion(f"version {version}; this reads only version {NAV_VERSION}")
        sub_version, bsp_size, analyzed = r.take("<IIB")
        custom_size = self.area_data(sub_version)
        places = Places.read(r)
        count = r.one("<I")
        if count == 0:
            raise EmptyMesh("the mesh has no areas")
        areas = tuple(Area.read(r, custom_size) for _ in range(count))
        ladders = tuple(Ladder.read(r) for _ in range(r.one("<I")))
        if r.pos != len(data):
            raise TrailingData(f"{self.name}'s loader stops at byte {r.pos} of {len(data)}")
        return NavMesh(version, sub_version, bsp_size, analyzed, places, areas, ladders)


def _tf_area_data(sub_version: int) -> int:
    if sub_version not in TF_AREA_DATA:
        raise UnsupportedVersion(f"TF2 sub-version {sub_version}; known: {sorted(TF_AREA_DATA)}")
    return TF_AREA_DATA[sub_version]


TF_LOADER = Loader("TF2", _tf_area_data)
GMOD_LOADER = Loader("GMod", lambda _sub_version: 0)  # base CNavArea::Load reads nothing more


def write_nav(mesh: NavMesh) -> bytes:
    w = _Writer()
    w.put("<IIIIB", NAV_MAGIC, mesh.version, mesh.sub_version, mesh.bsp_size, mesh.analyzed)
    mesh.places.write(w)
    w.put("<I", len(mesh.areas))
    for area in mesh.areas:
        area.write(w)
    w.put("<I", len(mesh.ladders))
    for ladder in mesh.ladders:
        ladder.write(w)
    return bytes(w.out)


def convert(mesh: NavMesh, bsp_size: int) -> NavMesh:
    """The same mesh as GMod's base loader reads it: sub-version 0, no per-area TF data."""
    areas = tuple(replace(a, custom=b"") for a in mesh.areas)
    return replace(mesh, sub_version=GMOD_SUB_VERSION, bsp_size=bsp_size, areas=areas)


def tf_attributes(mesh: NavMesh) -> Dict[int, int]:
    """Area id -> its persistent TF attributes, for the areas that have any."""
    found = {}
    for area in mesh.areas:
        if area.custom:
            kept = struct.unpack("<I", area.custom)[0] & TF_NAV_PERSISTENT_ATTRIBUTES
            if kept:
                found[area.id] = kept
    return found


def write_sidecar(attributes: Dict[int, int], nav_size: int) -> str:
    """nav_size: the converted mesh's bytes, so a mesh made since (mp_nav_generate) is told apart."""
    lines = [f"{SIDECAR_HEADER} {nav_size}\n"] + [f"{i} {attributes[i]}\n" for i in sorted(attributes)]
    return "".join(lines)


# Finding the mesh


@dataclass(frozen=True)
class NavSource:
    map: str
    data: bytes
    bsp_size: int
    origin: str


def _pakfile_nav(bsp: bytes, map_name: str):
    if bsp[:4] != b"VBSP":
        raise NavError("not a VBSP file")
    offset, length = struct.unpack_from("<ii", bsp, BSP_LUMP_TABLE + PAKFILE_LUMP * BSP_LUMP_SIZE)
    with zipfile.ZipFile(io.BytesIO(bsp[offset : offset + length])) as pak:
        by_name = {info.filename.lower(): info for info in pak.infolist()}
        for name in (f"maps/{map_name.lower()}.nav", "maps/embed.nav"):
            if name in by_name:
                return by_name[name].filename, pak.read(by_name[name])
    return None


def load_source(path: Path) -> NavSource:
    map_name = path.stem
    if path.suffix.lower() == ".nav":
        bsp = path.with_suffix(".bsp")
        if not bsp.is_file():
            raise MissingBsp(f"no {bsp.name} beside {path}, so its size is unknown")
        return NavSource(map_name, path.read_bytes(), bsp.stat().st_size, str(path))
    if path.suffix.lower() != ".bsp":
        raise NavError(f"{path}: expected a .bsp or a .nav")
    loose = path.with_suffix(".nav")
    if loose.is_file():
        return NavSource(map_name, loose.read_bytes(), path.stat().st_size, str(loose))
    entry = f"maps/{map_name}.nav"
    for vpk_path in sorted(path.parent.parent.glob("*_dir.vpk")):
        vpk = Vpk.open(vpk_path)
        if entry in vpk:
            return NavSource(map_name, vpk.read(entry), path.stat().st_size, f"{vpk_path.name}:{entry}")
    bsp = path.read_bytes()
    found = _pakfile_nav(bsp, map_name)
    if found is None:
        raise NoNavMesh(f"{path.name} has no mesh: none loose, in a VPK, or in its pakfile")
    name, data = found
    return NavSource(map_name, data, len(bsp), f"{path.name} pakfile:{name}")


# Command line


def _convert_one(path: Path, out_dir) -> str:
    source = load_source(path)
    mesh = TF_LOADER.parse(source.data)
    converted = convert(mesh, source.bsp_size)
    data = write_nav(converted)
    attributes = tf_attributes(mesh)
    line = (
        f"{source.map}: {len(mesh.areas)} areas, {len(mesh.ladders)} ladders, {len(mesh.places.names)} places, "
        f"{len(attributes)} areas with TF attributes; "
        f"sub-version {mesh.sub_version} -> {converted.sub_version}; "
        f"bsp size {mesh.bsp_size} -> {converted.bsp_size}; {len(source.data)} -> {len(data)} bytes; "
        f"from {source.origin}"
    )
    if out_dir is None:
        return line + "; not written (pass --out DIR)"
    target = out_dir / f"{source.map}.nav"
    target.write_bytes(data)
    sidecar = out_dir / f"{source.map}.tfnav.txt"
    sidecar.write_text(write_sidecar(attributes, len(data)))
    return line + f"; wrote {target} and {sidecar.name}"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", type=Path, metavar="MAP.bsp|MAP.nav")
    ap.add_argument("--out", type=Path, help="write <map>.nav and <map>.tfnav.txt here, e.g. garrysmod/maps")
    args = ap.parse_args(argv)
    if args.out is not None and not args.out.is_dir():
        ap.error(f"--out {args.out} is not a directory")
    status = 0
    for path in args.paths:
        try:
            print(_convert_one(path, args.out))
        except NavError as e:
            print(f"{path.stem}: FAILED {type(e).__name__}: {e}")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
