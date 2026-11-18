#!/usr/bin/env python3
"""A linux64 ELF's C++ vtables by their symbols, without running it: the Itanium
ABI's counterpart of pe_rtti.py. A Source server's .so keeps its symbol table, so
each slot is named by the function it holds rather than read from its code.

Each `_ZTV` symbol is a vtable group: one table per polymorphic base, each
`offset-to-top, typeinfo, slots...`; the table's object offset is -offset-to-top.
Slot pointers are relocations in the file (R_X86_64_RELATIVE or R_X86_64_64), so
they are resolved through .rela.dyn before they are named.

    elf_vtables.py BINARY REGEX            each matching class's tables (offset, slot count)
    elf_vtables.py BINARY REGEX --slots    and each slot's function, demangled
"""
import argparse
import re
import struct
import subprocess
import sys
from dataclasses import dataclass

SHT_SYMTAB, SHT_RELA, SHT_DYNSYM = 2, 4, 11
R_X86_64_64, R_X86_64_RELATIVE = 1, 8
STT_FUNC = 2


@dataclass(frozen=True)
class Section:
    name: str
    kind: int
    addr: int
    offset: int
    size: int
    link: int
    entsize: int


@dataclass(frozen=True)
class Symbol:
    name: str
    value: int
    size: int
    kind: int


@dataclass(frozen=True)
class Table:
    """One table of a vtable group: where its object sits, and each slot as (address,
    symbol name when the loader binds it by name, else None)."""
    offset: int
    slots: tuple


class Elf:
    def __init__(self, data):
        if data[:4] != b"\x7fELF" or data[4] != 2:
            raise ValueError("not a 64-bit ELF")
        self.data = data
        shoff = struct.unpack_from("<Q", data, 0x28)[0]
        count, names = struct.unpack_from("<HH", data, 0x3C)
        raw = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * 64) for i in range(count)]
        strtab = raw[names][4]
        self.sections = [
            Section(self._cstr(strtab + r[0]), r[1], r[3], r[4], r[5], r[6], r[9]) for r in raw
        ]
        self.symbols = self._symbols()
        self.by_name = {s.name: s for s in self.symbols}
        self.functions = {}
        for s in self.symbols:
            if s.kind == STT_FUNC and s.value:
                # several names may share one body (a destructor's variants): keep the first
                self.functions.setdefault(s.value, s.name)
        self.relocations = self._relocations()

    def _cstr(self, at):
        return self.data[at:self.data.index(b"\0", at)].decode("latin-1")

    def _symbols(self):
        found = []
        for sec in self.sections:
            if sec.kind not in (SHT_SYMTAB, SHT_DYNSYM):
                continue
            names = self.sections[sec.link].offset
            for at in range(sec.offset, sec.offset + sec.size, 24):
                name, info, _, _, value, size = struct.unpack_from("<IBBHQQ", self.data, at)
                if name:
                    found.append(Symbol(self._cstr(names + name), value, size, info & 0xF))
        return found

    def _relocations(self):
        dynsym = next(s for s in self.sections if s.kind == SHT_DYNSYM)
        dyn = [struct.unpack_from("<IBBHQQ", self.data, at)[4]
               for at in range(dynsym.offset, dynsym.offset + dynsym.size, 24)]
        names = self.sections[dynsym.link].offset
        dyn_names = [self._cstr(names + struct.unpack_from("<I", self.data, at)[0])
                     for at in range(dynsym.offset, dynsym.offset + dynsym.size, 24)]
        found = {}
        for sec in self.sections:
            if sec.kind != SHT_RELA:
                continue
            for at in range(sec.offset, sec.offset + sec.size, 24):
                where, info, addend = struct.unpack_from("<QQq", self.data, at)
                kind, sym = info & 0xFFFFFFFF, info >> 32
                if kind == R_X86_64_RELATIVE:
                    found[where] = (addend, None)
                elif kind == R_X86_64_64:
                    found[where] = (dyn[sym] + addend, dyn_names[sym] if sym else None)
        return found

    def file_offset(self, addr):
        for sec in self.sections:
            if sec.addr and sec.addr <= addr < sec.addr + sec.size and sec.kind != 8:  # not NOBITS
                return sec.offset + addr - sec.addr
        raise ValueError(f"{addr:#x} is in no section with file contents")

    def word(self, addr):
        """The pointer at addr as the loader leaves it: (value, symbol name if relocated by one)."""
        if addr in self.relocations:
            return self.relocations[addr]
        return struct.unpack_from("<q", self.data, self.file_offset(addr))[0], None

    def code(self, addr, size):
        at = self.file_offset(addr)
        return self.data[at:at + size]

    def name_at(self, addr):
        return self.functions.get(addr)

    def slot_name(self, slot):
        """A slot's mangled function name: the symbol it is bound by, or the body it holds."""
        addr, name = slot
        if name:
            return name
        if addr == 0:
            return "(null)"  # GCC leaves an uninstantiated template destructor's slot empty
        return self.functions.get(addr) or f"{addr:#x}"

    def vtable(self, mangled):
        """The tables of `_ZTV<mangled>`, in the order the group lays them out."""
        sym = self.by_name.get("_ZTV" + mangled)
        if sym is None:
            raise KeyError(f"_ZTV{mangled} is not in the binary")
        typeinfo = self.by_name.get("_ZTI" + mangled)
        if typeinfo is None:
            raise KeyError(f"_ZTI{mangled} is not in the binary")
        words = [self.word(sym.value + i * 8) for i in range(sym.size // 8)]
        # every table of a group points at the complete class's typeinfo, after its offset-to-top
        starts = [i - 1 for i in range(1, len(words))
                  if words[i][0] == typeinfo.value and words[i - 1][1] is None
                  and -0x100000 < words[i - 1][0] <= 0
                  and (sym.value + (i - 1) * 8) not in self.relocations]
        if not starts or starts[0] != 0:
            raise ValueError(f"_ZTV{mangled} does not open with offset-to-top and typeinfo")
        tables = []
        for n, start in enumerate(starts):
            end = starts[n + 1] if n + 1 < len(starts) else len(words)
            tables.append(Table(-words[start][0], tuple(words[start + 2:end])))
        return tables


def rtti_vtable(elf, mangled):
    """The tables of a class in a binary stripped of its C++ symbols, found by its RTTI as
    pe_rtti.py finds MSVC's: the name string (`7IVision`), the typeinfo whose second word
    points at it, then each table whose typeinfo word points at that typeinfo. Ordered by
    address; a table's slots run while each word is relocated (a function, or an imported
    one such as __cxa_pure_virtual), an unrelocated zero allowed only before a function."""
    wanted = mangled.encode() + b"\0"
    names = []
    for sec in elf.sections:
        if sec.kind != 1 or not sec.addr:  # PROGBITS loaded
            continue
        blob = elf.data[sec.offset:sec.offset + sec.size]
        at = blob.find(wanted)
        while at >= 0:
            names.append(sec.addr + at)  # the linker may merge it into a longer name's tail
            at = blob.find(wanted, at + 1)
    by_target = {}
    for where, (value, _) in elf.relocations.items():
        by_target.setdefault(value, []).append(where)
    if id(elf) not in TYPEINFO_CACHE:
        TYPEINFO_CACHE[id(elf)] = _typeinfo_addresses(elf)
    typeinfos = [w - 8 for n in names for w in by_target.get(n, []) if w - 8 in TYPEINFO_CACHE[id(elf)]]
    if len(typeinfos) != 1:
        raise KeyError(f"{mangled}: {len(typeinfos)} typeinfo objects name it")
    typeinfo = typeinfos[0]
    tables = []
    for where in sorted(by_target.get(typeinfo, [])):
        top_at = where - 8
        if top_at in elf.relocations:
            continue  # a typeinfo's base list pointing at it, not a vtable
        top = struct.unpack_from("<q", elf.data, elf.file_offset(top_at))[0]
        if not -0x100000 < top <= 0:
            continue
        slots, at = [], where + 8
        while True:
            bound = elf.relocations.get(at)
            if bound and "class_type_info" in (bound[1] or ""):
                break  # a typeinfo object follows the table
            if bound and (bound[1] or in_code(elf, bound[0])):
                slots.append(elf.relocations[at])
            elif struct.unpack_from("<q", elf.data, elf.file_offset(at))[0] == 0 \
                    and in_code(elf, elf.relocations.get(at + 8, (-1, None))[0]):
                slots.append((0, None))
            else:
                break
            at += 8
        tables.append(Table(-top, tuple(slots)))
    return typeinfo, tables


def in_code(elf, addr):
    return any(sec.addr <= addr < sec.addr + sec.size for sec in elf.sections
               if sec.name == ".text")


def slots_end(elf, at, by_target):
    """Whether `at` is the next table's offset-to-top: the word after it is a typeinfo."""
    if id(elf) not in TYPEINFO_CACHE:
        TYPEINFO_CACHE[id(elf)] = _typeinfo_addresses(elf)
    return elf.relocations[at + 8][0] in TYPEINFO_CACHE[id(elf)]


TYPEINFO_CACHE = {}


def _typeinfo_addresses(elf):
    """Every typeinfo object's address: a word the loader binds to a __cxxabiv1
    *class_type_info vtable (by name when imported, or by its address when the binary
    defines one, which is then itself bound by name somewhere)."""
    abi = {value for value, name in elf.relocations.values() if name and "class_type_info" in name}
    return {where for where, (value, name) in elf.relocations.items()
            if (name and "class_type_info" in name) or value in abi}


def demangle(names):
    """Itanium names demangled in one c++filt call, in order."""
    if not names:
        return []
    out = subprocess.run(["c++filt"], input="\n".join(names), capture_output=True, text=True,
                         check=True).stdout
    return out.rstrip("\n").split("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("binary")
    parser.add_argument("pattern", help="a regex over the mangled class name after _ZTV")
    parser.add_argument("--slots", action="store_true")
    args = parser.parse_args()
    elf = Elf(open(args.binary, "rb").read())
    classes = sorted(s.name[4:] for s in elf.symbols
                     if s.name.startswith("_ZTV") and re.fullmatch(args.pattern, s.name[4:]))
    if not classes:
        sys.exit(f"no vtable matches {args.pattern}")
    for mangled, pretty in zip(classes, demangle(["_ZTS" + c for c in classes])):
        print(f"{pretty.removeprefix('typeinfo name for ')}  (_ZTV{mangled})")
        for table in elf.vtable(mangled):
            print(f"  table at +{table.offset:#x}: {len(table.slots)} slots")
            if args.slots:
                names = [elf.slot_name(slot) for slot in table.slots]
                for i, name in enumerate(demangle(names)):
                    print(f"    {i:3d}  {name}")


if __name__ == "__main__":
    main()
