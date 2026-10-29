#!/usr/bin/env python3
"""List or extract a Garry's Mod addon archive (.gma), e.g. a Workshop addon.

  gma.py ADDON.gma                      file paths and sizes
  gma.py ADDON.gma --extract DIR        write every file under DIR
  gma.py ADDON.gma --extract DIR --glob 'lua/*'   only the matching paths
"""
import argparse
import fnmatch
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Tuple

MAGIC = b"GMAD"
REQUIRED_CONTENT_SINCE = 2  # gmad's format: versions above 1 list required content


class GmaError(Exception):
    pass


@dataclass(frozen=True)
class GmaFile:
    path: str
    data: bytes


@dataclass(frozen=True)
class Gma:
    name: str
    files: Tuple[GmaFile, ...]


class _Reader:
    def __init__(self, blob: bytes):
        self.blob, self.at = blob, 0

    def take(self, size: int) -> bytes:
        if self.at + size > len(self.blob):
            raise GmaError(f"truncated at byte {self.at}, wanted {size} more")
        chunk = self.blob[self.at:self.at + size]
        self.at += size
        return chunk

    def unpack(self, fmt: str):
        return struct.unpack(fmt, self.take(struct.calcsize(fmt)))

    def cstring(self) -> str:
        end = self.blob.find(b"\x00", self.at)
        if end < 0:
            raise GmaError(f"unterminated string at byte {self.at}")
        text = self.blob[self.at:end].decode("utf-8", "replace")
        self.at = end + 1
        return text


def read_gma(blob: bytes) -> Gma:
    r = _Reader(blob)
    if r.take(len(MAGIC)) != MAGIC:
        raise GmaError("not a GMA archive")
    (version,) = r.unpack("<B")
    r.unpack("<QQ")  # steamid, timestamp
    if version >= REQUIRED_CONTENT_SINCE:
        while r.cstring():
            pass
    name = r.cstring()
    r.cstring()  # description
    r.cstring()  # author
    r.unpack("<i")  # addon version
    entries = []
    while r.unpack("<I")[0] != 0:
        path = r.cstring()
        size, _crc = r.unpack("<qI")
        entries.append((path, size))
    return Gma(name, tuple(GmaFile(path, r.take(size)) for path, size in entries))


WRITE_VERSION = 3


def write_gma(gma: Gma) -> bytes:
    """The archive gmad writes (version 3, no required content, no CRCs), which
    GMod mounts and read_gma reads back."""
    out = bytearray(MAGIC + bytes([WRITE_VERSION]) + struct.pack("<QQ", 0, 0))
    out += b"\x00"  # no required content
    out += gma.name.encode() + b"\x00" + b"\x00" + b"\x00" + struct.pack("<i", 1)
    for number, f in enumerate(gma.files, start=1):
        out += struct.pack("<I", number) + f.path.encode() + b"\x00" + struct.pack("<qI", len(f.data), 0)
    out += struct.pack("<I", 0)
    for f in gma.files:
        out += f.data
    return bytes(out + struct.pack("<I", 0))


def main(argv) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("gma", type=Path)
    parser.add_argument("--extract", type=Path, metavar="DIR")
    parser.add_argument("--glob", default="*")
    args = parser.parse_args(argv)
    files = [f for f in read_gma(args.gma.read_bytes()).files if fnmatch.fnmatch(f.path, args.glob)]
    for f in files:
        if args.extract:
            out = args.extract / f.path
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(f.data)
        else:
            print(f"{len(f.data):>10}  {f.path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
