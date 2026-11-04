#!/usr/bin/env python3
"""A win64 PE's C++ classes from its MSVC RTTI, without running it: each class
matching a pattern, with its base classes and vtables (RVA, offset in the
object, slot count), which is how a binary module finds a class in a server.dll
that exports no symbols (docs/native-foundation-plan.md, "Detouring the
engine's functions").

    pe_rtti.py BINARY REGEX             the matching classes
    pe_rtti.py BINARY REGEX --slots     and each vtable's slots (function RVAs)
    pe_rtti.py BINARY --strings REGEX   the matching plain strings, with the RVAs
"""
import argparse
import re
import struct
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Section:
    name: str
    rva: int
    size: int
    raw: int
    executable: bool


class Image:
    def __init__(self, data):
        self.data = data
        pe = struct.unpack_from("<I", data, 0x3C)[0]
        if data[pe : pe + 4] != b"PE\0\0":
            raise SystemExit("not a PE file")
        count = struct.unpack_from("<H", data, pe + 6)[0]
        optional = struct.unpack_from("<H", data, pe + 20)[0]
        if struct.unpack_from("<H", data, pe + 24)[0] != 0x20B:
            raise SystemExit("not a 64-bit image")
        self.base = struct.unpack_from("<Q", data, pe + 24 + 24)[0]
        self.sections = []
        for i in range(count):
            at = pe + 24 + optional + i * 40
            name = data[at : at + 8].rstrip(b"\0").decode("latin1")
            vsize, rva, rawsize, raw = struct.unpack_from("<IIII", data, at + 8)
            flags = struct.unpack_from("<I", data, at + 36)[0]
            self.sections.append(Section(name, rva, min(vsize, rawsize), raw, bool(flags & 0x20000000)))

    def section_of(self, rva):
        for s in self.sections:
            if s.rva <= rva < s.rva + s.size:
                return s
        return None

    def offset(self, rva):
        s = self.section_of(rva)
        return None if s is None else s.raw + rva - s.rva

    def u32(self, rva):
        at = self.offset(rva)
        return None if at is None or at + 4 > len(self.data) else struct.unpack_from("<I", self.data, at)[0]

    def u64(self, rva):
        at = self.offset(rva)
        return None if at is None or at + 8 > len(self.data) else struct.unpack_from("<Q", self.data, at)[0]

    def text(self, rva):
        at = self.offset(rva)
        if at is None:
            return None
        return self.data[at : self.data.index(b"\0", at)].decode("latin1")

    def rva_at(self, offset):
        for s in self.sections:
            if s.raw <= offset < s.raw + s.size:
                return s.rva + offset - s.raw
        return None

    def executable(self, rva):
        s = self.section_of(rva)
        return s is not None and s.executable


def type_descriptors(image):
    """Name -> RVA of each type descriptor (a vtable pointer, a spare, then the name)."""
    found = {}
    for match in re.finditer(rb"\.\?A[VU][^\0]{1,400}?@@\0", image.data):
        rva = image.rva_at(match.start())
        if rva is not None:
            found[match.group()[:-1].decode("latin1")] = rva - 16
    return found


def locators(image):
    """Descriptor RVA -> its complete object locators: (locator RVA, offset, hierarchy RVA)."""
    found = {}
    for s in image.sections:
        if s.executable:
            continue
        for at in range(s.raw, s.raw + s.size - 24, 4):
            signature, offset, _, descriptor, hierarchy, own = struct.unpack_from("<IIIIII", image.data, at)
            if signature == 1 and own == s.rva + at - s.raw:
                found.setdefault(descriptor, []).append((own, offset, hierarchy))
    return found


def vtables(image):
    """Locator RVA -> the RVA of the vtable after the pointer to it."""
    wanted = {}
    for s in image.sections:
        if s.executable:
            continue
        for at in range(s.raw, s.raw + s.size - 8, 8):
            value = struct.unpack_from("<Q", image.data, at)[0]
            if value > image.base and value - image.base < 1 << 31:
                wanted.setdefault(value - image.base, []).append(s.rva + at - s.raw + 8)
    return wanted


def bases(image, hierarchy):
    count = image.u32(hierarchy + 8)
    array = image.u32(hierarchy + 12)
    names = []
    for i in range(count or 0):
        descriptor = image.u32(image.u32(array + 4 * i))
        names.append(image.text(descriptor + 16))
    return names


def slots(image, table):
    found = []
    while True:
        value = image.u64(table + 8 * len(found))
        if value is None or value <= image.base or not image.executable(value - image.base):
            return found
        found.append(value - image.base)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary")
    parser.add_argument("pattern", nargs="?")
    parser.add_argument("--slots", action="store_true")
    parser.add_argument("--strings")
    args = parser.parse_args()
    with open(args.binary, "rb") as f:
        image = Image(f.read())
    if args.strings:
        for match in re.finditer(rb"[\x20-\x7e]{4,}", image.data):
            if re.search(args.strings, match.group().decode("latin1")):
                print(f"{image.rva_at(match.start()) or 0:#010x} {match.group().decode('latin1')}")
        return
    descriptors = type_descriptors(image)
    objects = locators(image)
    pointers = vtables(image)
    for name in sorted(descriptors):
        if not re.search(args.pattern, name):
            continue
        located = objects.get(descriptors[name], [])
        print(name)
        if not located:
            print("  no vtable (only named as a base or thrown)")
        for own, offset, hierarchy in located:
            print(f"  bases: {' '.join(bases(image, hierarchy))}")
            for table in pointers.get(own, []):
                filled = slots(image, table)
                print(f"  vtable {table:#010x} at +{offset:#x}: {len(filled)} slots")
                if args.slots:
                    print("    " + " ".join(f"{i}:{rva:#x}" for i, rva in enumerate(filled)))


if __name__ == "__main__":
    sys.exit(main())
