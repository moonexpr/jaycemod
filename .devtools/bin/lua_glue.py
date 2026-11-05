#!/usr/bin/env python3
"""What a GMod Lua method calls in a win64 server.dll, which exports no symbols.

Each method is an entry in a static table, its name beside its C function. This finds
those functions and disassembles them: the virtual slots and field offsets in them are
the binary's own answer to where a native module reaches the same thing.

  uv run --with capstone --with pefile .devtools/bin/lua_glue.py SERVER_DLL NAME... [--bytes N]
"""
import argparse

import capstone
import pefile

# A method's entry in its class's table in .data: name, an empty string, function, 0.
FUNCTION_AFTER_NAME = 16


def section_of(pe, rva):
    for section in pe.sections:
        if section.VirtualAddress <= rva < section.VirtualAddress + section.Misc_VirtualSize:
            return section
    return None


def strings_named(pe, name):
    """The rvas of the zero-terminated string `name`, whole."""
    wanted = b"\0" + name.encode() + b"\0"
    for section in pe.sections:
        if section.Characteristics & 0x20000000:
            continue
        data = section.get_data()
        at = data.find(wanted)
        while at >= 0:
            yield section.VirtualAddress + at + 1
            at = data.find(wanted, at + 1)


def functions_named(pe, name):
    """The function of each table entry naming `name`."""
    base = pe.OPTIONAL_HEADER.ImageBase
    found = set()
    for string in strings_named(pe, name):
        pointer = (base + string).to_bytes(8, "little")
        for section in pe.sections:
            data = section.get_data()
            at = data.find(pointer)
            while at >= 0:
                entry = data[at + FUNCTION_AFTER_NAME : at + FUNCTION_AFTER_NAME + 8]
                found.add(int.from_bytes(entry, "little") - base)
                at = data.find(pointer, at + 1)
    return sorted(found)


def disassemble(pe, rva, size):
    section = section_of(pe, rva)
    start = rva - section.VirtualAddress
    code = section.get_data()[start : start + size]
    decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    for instruction in decoder.disasm(code, rva):
        yield instruction
        if instruction.mnemonic == "ret" or instruction.mnemonic == "int3":
            return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dll")
    parser.add_argument("names", nargs="+")
    parser.add_argument("--bytes", type=int, default=400)
    args = parser.parse_args()
    pe = pefile.PE(args.dll, fast_load=True)
    for name in args.names:
        functions = functions_named(pe, name)
        print(f"== {name}: {['%#x' % f for f in functions]}")
        for function in functions:
            print(f"-- {function:#x}")
            for instruction in disassemble(pe, function, args.bytes):
                print(f"{instruction.address:#x}  {instruction.mnemonic} {instruction.op_str}")


if __name__ == "__main__":
    main()
