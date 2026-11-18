#!/usr/bin/env python3
"""A class's virtual functions in a win64 binary, disassembled slot by slot.

pe_rtti.py says where a class's vtables are and how many slots each has; this shows
what each slot does, so a slot's meaning is read from its code, not assumed from a
header (MSVC groups overloaded virtuals, so a header's order can lie). A slot shared
with `--base`'s vtable is marked, which shows what the class overrides.

  uv run --with capstone .devtools/bin/vtable_dis.py SERVER_DLL CLASS_PATTERN \
      [--table N] [--slots 46-72] [--base IVision] [--bytes 160]
"""
import argparse
import os
import re
import sys

import capstone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pe_rtti  # noqa: E402


def class_tables(image, pattern):
    """(name, offset, vtable rva) of each vtable of each class matching `pattern`."""
    descriptors = pe_rtti.type_descriptors(image)
    objects = pe_rtti.locators(image)
    pointers = pe_rtti.vtables(image)
    found = []
    for name in sorted(descriptors):
        if not re.fullmatch(pattern, name):
            continue
        for own, offset, _ in objects.get(descriptors[name], []):
            for table in pointers.get(own, []):
                found.append((name, offset, table))
    return found


def disassemble(image, rva, size):
    at = image.offset(rva)
    decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    for instruction in decoder.disasm(image.data[at : at + size], rva):
        yield instruction
        if instruction.mnemonic in ("ret", "int3") or instruction.mnemonic == "jmp":
            return


def slot_range(text, count):
    if not text:
        return range(count)
    low, _, high = text.partition("-")
    return range(int(low), int(high or low) + 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dll")
    parser.add_argument("cls", help="the class's mangled name, as a regex matched whole")
    parser.add_argument("--table", type=int, default=0, help="which of its vtables")
    parser.add_argument("--slots", help="a slot or a range, e.g. 46-72")
    parser.add_argument("--base", help="a base class whose vtable slots to compare against")
    parser.add_argument("--bytes", type=int, default=160)
    args = parser.parse_args()
    with open(args.dll, "rb") as f:
        image = pe_rtti.Image(f.read())
    tables = class_tables(image, args.cls)
    if len(tables) <= args.table:
        raise SystemExit(f"{args.cls}: {len(tables)} vtables")
    name, offset, table = tables[args.table]
    filled = pe_rtti.slots(image, table)
    base = []
    if args.base:
        base_tables = class_tables(image, args.base)
        base = pe_rtti.slots(image, base_tables[args.table][2]) if base_tables else []
    print(f"{name} vtable {table:#x} at +{offset:#x}: {len(filled)} slots")
    for slot in slot_range(args.slots, len(filled)):
        rva = filled[slot]
        same = slot < len(base) and base[slot] == rva
        print(f"-- {slot}: {rva:#x}{'  (= base)' if same else ''}")
        for instruction in disassemble(image, rva, args.bytes):
            print(f"   {instruction.address:#x} {instruction.mnemonic} {instruction.op_str}")


if __name__ == "__main__":
    sys.exit(main())
