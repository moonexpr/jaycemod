#!/usr/bin/env python3
"""Read files out of a Valve pak (VPK, versions 1 and 2), e.g. TF2's tf2_misc_dir.vpk.

  vpk.py PAK_dir.vpk                    every file's path
  vpk.py PAK_dir.vpk PATH               one file's bytes to stdout

The directory file holds a tree (extension, then folder, then name, each
list ended by an empty string) of entries: crc, preload length, archive
index, offset, length, a 0xffff terminator, then the preload bytes. A file
is its preload bytes followed by `length` bytes at `offset` in archive
<base>_<index:03d>.vpk, or, for index DIR_ARCHIVE, in the directory file
just past the tree. A folder of " " is the pak's root.
"""
from __future__ import annotations

import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable

SIGNATURE = 0x55AA1234
HEADER_SIZES = {1: 12, 2: 28}
DIR_ARCHIVE = 0x7FFF
ENTRY = struct.Struct("<IHHIIH")  # crc, preload, archive, offset, length, terminator
TERMINATOR = 0xFFFF
ROOT = " "


class VpkError(Exception):
    pass


@dataclass(frozen=True)
class Entry:
    preload: bytes
    archive: int
    offset: int
    length: int


@dataclass(frozen=True)
class Vpk:
    dir_path: Path
    data_start: int  # where DIR_ARCHIVE data begins in the directory file
    entries: Dict[str, Entry]  # lower-case path -> entry

    @classmethod
    def open(cls, dir_path: Path) -> "Vpk":
        data = dir_path.read_bytes()
        signature, version, tree_size = struct.unpack_from("<III", data, 0)
        if signature != SIGNATURE or version not in HEADER_SIZES:
            raise VpkError(f"{dir_path} is not a VPK (signature {signature:#x}, version {version})")
        start = HEADER_SIZES[version]
        return cls(dir_path, start + tree_size, dict(_entries(data, start)))

    def names(self) -> Iterable[str]:
        return self.entries.keys()

    def read(self, path: str) -> bytes:
        entry = self.entries[path.lower()]
        if entry.archive == DIR_ARCHIVE:
            source, offset = self.dir_path, self.data_start + entry.offset
        else:
            source, offset = self._archive(entry.archive), entry.offset
        with open(source, "rb") as f:
            f.seek(offset)
            return entry.preload + f.read(entry.length)

    def _archive(self, index: int) -> Path:
        base = self.dir_path.name.removesuffix("_dir.vpk")
        return self.dir_path.with_name(f"{base}_{index:03d}.vpk")


def _string(data: bytes, at: int):
    end = data.index(b"\0", at)
    return data[at:end].decode("utf-8", "replace"), end + 1


def _entries(data: bytes, at: int):
    while True:
        ext, at = _string(data, at)
        if not ext:
            return
        while True:
            folder, at = _string(data, at)
            if not folder:
                break
            while True:
                name, at = _string(data, at)
                if not name:
                    break
                _, preload, archive, offset, length, terminator = ENTRY.unpack_from(data, at)
                if terminator != TERMINATOR:
                    raise VpkError(f"bad entry terminator {terminator:#x} for {folder}/{name}.{ext}")
                at += ENTRY.size
                path = f"{name}.{ext}" if folder == ROOT else f"{folder}/{name}.{ext}"
                yield path.lower(), Entry(data[at:at + preload], archive, offset, length)
                at += preload


def main() -> int:
    pak = Vpk.open(Path(sys.argv[1]))
    if len(sys.argv) > 2:
        sys.stdout.buffer.write(pak.read(sys.argv[2]))
    else:
        for name in sorted(pak.names()):
            print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
