#!/usr/bin/env python3
"""Check that models, sounds, particles and materials exist in TF2's shipped content.

  tf2_content.py model NAME...       models/<...>.mdl in the VPKs
  tf2_content.py sound NAME...       a soundscript entry, or a sound/<...>.wav file
  tf2_content.py particle NAME...    a particle system defined in a particles/*.pcf
  tf2_content.py material NAME...    materials/<NAME>.vmt (vgui/spellbook_* icons)
  tf2_content.py lua FILE...         every reference found in Lua source (see references_in_lua)
  --tf DIR                           TF2's tf/ directory (default: the CrossOver install)

Prints what is missing and exits 1 if anything is, 0 if everything exists.
Content comes from every tf/*_dir.vpk tree, the soundscripts listed in
scripts/game_sounds_manifest.txt, and the element table of each binary .pcf.
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
from dataclasses import dataclass
from enum import Enum
from functools import cached_property
from pathlib import Path
from typing import Iterable, Iterator, List, Mapping, Tuple

TF_DIR = Path.home() / (
    "Library/Application Support/CrossOver/Bottles/Steam/"
    "drive_c/Steam/steamapps/common/Team Fortress 2/tf"
)
VPK_SIGNATURE = 0x55AA1234
VPK_HEADER_SIZE = {1: 12, 2: 28}
VPK_INLINE_ARCHIVE = 0x7FFF
VPK_ENTRY = struct.Struct("<IHHIIH")  # crc, preload bytes, archive index, offset, length, terminator
SOUND_MANIFEST = "scripts/game_sounds_manifest.txt"
MANIFEST_KEYS = {"precache_file", "preload_file"}
PCF_HEADER = b"<!-- dmx encoding binary 2 format pcf "
PARTICLE_SYSTEM = "DmeParticleSystemDefinition"
DMX_GUID_SIZE = 16
AUDIO_SUFFIXES = (".wav", ".mp3", ".ogg")
SOUND_CHARS = "*#@><^)}$!?&~`+%"  # Source's sound-channel prefixes (soundchars.h)


class ContentError(Exception):
    """The content on disk is not in a format this tool reads."""


class Kind(Enum):
    MODEL = "model"
    SOUND = "sound"
    PARTICLE = "particle"
    MATERIAL = "material"


def _normal(name: str) -> str:
    return name.replace("\\", "/").lstrip("/").lower()


# VPK


@dataclass(frozen=True)
class VpkEntry:
    preload: bytes
    archive: int
    offset: int
    length: int


def _cstring(data: bytes, pos: int) -> Tuple[str, int]:
    end = data.index(b"\0", pos)
    return data[pos:end].decode("latin-1"), end + 1


def parse_vpk_tree(data: bytes) -> Tuple[int, Mapping[str, VpkEntry]]:
    """Return the header size and the directory's entries, keyed by normalized path."""
    signature, version = struct.unpack_from("<II", data, 0)
    if signature != VPK_SIGNATURE or version not in VPK_HEADER_SIZE:
        raise ContentError(f"not a VPK directory (signature {signature:#x}, version {version})")
    tree_size = struct.unpack_from("<I", data, 8)[0]
    header = VPK_HEADER_SIZE[version]
    entries = {}
    pos = header
    while True:
        ext, pos = _cstring(data, pos)
        if not ext:
            break
        while True:
            path, pos = _cstring(data, pos)
            if not path:
                break
            while True:
                stem, pos = _cstring(data, pos)
                if not stem:
                    break
                _crc, preload, archive, offset, length, _end = VPK_ENTRY.unpack_from(data, pos)
                pos += VPK_ENTRY.size
                file = stem if ext == " " else f"{stem}.{ext}"
                full = file if path == " " else f"{path}/{file}"
                entries[_normal(full)] = VpkEntry(data[pos : pos + preload], archive, offset, length)
                pos += preload
    return header + tree_size, entries


@dataclass(frozen=True)
class Vpk:
    """A VPK directory file and the numbered archives beside it."""

    path: Path
    data_start: int
    entries: Mapping[str, VpkEntry]

    @classmethod
    def open(cls, path: Path) -> "Vpk":
        data_start, entries = parse_vpk_tree(path.read_bytes())
        return cls(path, data_start, entries)

    @property
    def names(self) -> Iterable[str]:
        return self.entries.keys()

    def __contains__(self, name: str) -> bool:
        return _normal(name) in self.entries

    def read(self, name: str) -> bytes:
        entry = self.entries[_normal(name)]
        if entry.length == 0:
            return entry.preload
        if entry.archive == VPK_INLINE_ARCHIVE:
            archive, offset = self.path, self.data_start + entry.offset
        else:
            prefix = self.path.name[: -len("_dir.vpk")]
            archive, offset = self.path.with_name(f"{prefix}_{entry.archive:03d}.vpk"), entry.offset
        with archive.open("rb") as f:
            f.seek(offset)
            return entry.preload + f.read(entry.length)


# KeyValues (soundscripts and their manifest)

_KV_TOKEN = re.compile(r'//[^\n]*|"([^"]*)"|([{}])|([^\s{}"]+)')


def _kv_tokens(text: str) -> Iterator[str]:
    for m in _KV_TOKEN.finditer(text):
        quoted, brace, bare = m.groups()
        if brace:
            yield brace
        elif quoted is not None:
            yield quoted
        elif bare and not bare.startswith("["):  # [$WIN32]-style conditionals
            yield bare


def soundscript_names(text: str) -> set:
    names, depth, previous = set(), 0, None
    for token in _kv_tokens(text):
        if token == "{":
            if depth == 0 and previous is not None:
                names.add(previous.lower())
            depth += 1
        elif token == "}":
            depth -= 1
        previous = token if token not in ("{", "}") else None
    return names


def manifest_files(text: str) -> List[str]:
    tokens = list(_kv_tokens(text))
    return [value for key, value in zip(tokens, tokens[1:]) if key.lower() in MANIFEST_KEYS]


# Particles


def particle_names(pcf: bytes) -> set:
    """Names of the particle systems in a binary-2 DMX .pcf, read from its element table."""
    if not pcf.startswith(PCF_HEADER):
        raise ContentError(f"not a binary-2 particle file: {pcf[:48]!r}")
    pos = pcf.index(b"\0") + 1
    (count,) = struct.unpack_from("<h", pcf, pos)
    pos += 2
    strings = []
    for _ in range(count):
        s, pos = _cstring(pcf, pos)
        strings.append(s)
    (elements,) = struct.unpack_from("<i", pcf, pos)
    pos += 4
    names = set()
    for _ in range(elements):
        (type_index,) = struct.unpack_from("<h", pcf, pos)
        name, pos = _cstring(pcf, pos + 2)
        pos += DMX_GUID_SIZE
        if strings[type_index] == PARTICLE_SYSTEM:
            names.add(name)
    return names


# Lua references


@dataclass(frozen=True)
class Reference:
    kind: Kind
    name: str
    file: str
    line: int

    @property
    def where(self) -> str:
        return f"{self.file}:{self.line}"


_LUA_TOKEN = re.compile(
    r"""(?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
      | (?P<long>\[(?P<leq>=*)\[.*?\](?P=leq)\])
      | "(?P<dq>(?:\\.|[^"\\\n])*)"
      | '(?P<sq>(?:\\.|[^'\\\n])*)'
      | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
      | (?P<punct>\S)""",
    re.X | re.S,
)
_SKIPPABLE = set("(={,[]")
_CONTEXT_KINDS = (("particle", Kind.PARTICLE), ("sound", Kind.SOUND), ("material", Kind.MATERIAL))


def _shape_kind(literal: str):
    lower = _normal(literal)
    if lower.endswith(".mdl"):
        return Kind.MODEL
    if lower.endswith(AUDIO_SUFFIXES):
        return Kind.SOUND
    if lower.startswith(("vgui/", "materials/")) or lower.endswith(".vmt"):
        return Kind.MATERIAL
    return None


def _context_kind(context: str):
    lower = context.lower()
    return next((kind for word, kind in _CONTEXT_KINDS if word in lower), None)


def references_in_lua(source: str, file: str) -> List[Reference]:
    """Content names in Lua string literals.

    A literal counts by its shape (.mdl, an audio file, vgui/ or materials/), or
    else by the nearest name before it, skipping ( = { , [ ] and other literals:
    a name containing "particle", "sound" or "material" (ParticleEffect,
    EmitSound, SOUNDS = {...}, Material). Comments and long strings are skipped.
    """
    tokens = []  # (kind, text, line): kind is "str", "name" or "punct"
    for m in _LUA_TOKEN.finditer(source):
        line = source.count("\n", 0, m.start()) + 1
        if m.group("dq") is not None or m.group("sq") is not None:
            tokens.append(("str", m.group("dq") if m.group("dq") is not None else m.group("sq"), line))
        elif m.group("name"):
            tokens.append(("name", m.group("name"), line))
        elif m.group("punct"):
            tokens.append(("punct", m.group("punct"), line))
    refs = []
    for i, (kind, text, line) in enumerate(tokens):
        if kind != "str":
            continue
        found = _shape_kind(text) or _context_kind(_context_before(tokens, i))
        if found:
            refs.append(Reference(found, text, file, line))
    return refs


def _context_before(tokens, i: int) -> str:
    j = i - 1
    while j >= 0 and (tokens[j][0] == "str" or tokens[j][1] in _SKIPPABLE):
        j -= 1
    chain = []
    while j >= 0 and tokens[j][0] == "name":
        chain.append(tokens[j][1])
        if j >= 1 and tokens[j - 1][1] in ".:":
            j -= 2
        else:
            break
    return ".".join(reversed(chain))


# Catalog


@dataclass(frozen=True)
class Catalog:
    files: frozenset
    soundscripts: frozenset
    particles: frozenset

    def has(self, kind: Kind, name: str) -> bool:
        lower = _normal(name)
        if kind is Kind.MODEL:
            return (lower if lower.startswith("models/") else f"models/{lower}") in self.files
        if kind is Kind.SOUND:
            if lower.endswith(AUDIO_SUFFIXES):
                path = lower.lstrip(SOUND_CHARS)
                return (path if path.startswith("sound/") else f"sound/{path}") in self.files
            return lower in self.soundscripts
        if kind is Kind.PARTICLE:
            return name in self.particles
        if kind is Kind.MATERIAL:
            stem = lower[len("materials/") :] if lower.startswith("materials/") else lower
            stem = stem[: -len(".vmt")] if stem.endswith(".vmt") else stem
            return f"materials/{stem}.vmt" in self.files
        raise ValueError(kind)


@dataclass(frozen=True)
class Tf2Install:
    """TF2's tf/ directory: its VPKs, read lazily."""

    tf_dir: Path

    @cached_property
    def vpks(self) -> List[Vpk]:
        found = [Vpk.open(p) for p in sorted(self.tf_dir.glob("*_dir.vpk"))]
        if not found:
            raise ContentError(f"no *_dir.vpk in {self.tf_dir}")
        return found

    def read(self, name: str) -> bytes:
        vpk = next((v for v in self.vpks if name in v), None)
        if vpk is None:
            raise ContentError(f"{name} is in no VPK under {self.tf_dir}")
        return vpk.read(name)

    def catalog(self) -> Catalog:
        files = frozenset(n for v in self.vpks for n in v.names)
        return Catalog(files, frozenset(self._soundscripts(files)), frozenset(self._particles(files)))

    def _soundscripts(self, files) -> set:
        if SOUND_MANIFEST not in files:
            return set()
        names = set()
        for script in manifest_files(self.read(SOUND_MANIFEST).decode("latin-1")):
            names |= soundscript_names(self.read(script).decode("latin-1"))
        return names

    def _particles(self, files) -> set:
        names = set()
        for pcf in sorted(f for f in files if f.startswith("particles/") and f.endswith(".pcf")):
            names |= particle_names(self.read(pcf))
        return names


# Command line


def _check(catalog: Catalog, wanted: Iterable[Tuple[Kind, str, str]]) -> Tuple[int, List[str]]:
    total, missing = 0, []
    for kind, name, where in wanted:
        total += 1
        if not catalog.has(kind, name):
            missing.append(f"missing {kind.value} {name}{' ' + where if where else ''}")
    return total, missing


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tf", type=Path, default=TF_DIR)
    ap.add_argument("mode", choices=[k.value for k in Kind] + ["lua"])
    ap.add_argument("names", nargs="+")
    args = ap.parse_args(argv)
    try:
        catalog = Tf2Install(args.tf).catalog()
    except ContentError as e:
        print(f"tf2_content: {e}", file=sys.stderr)
        return 2
    if args.mode == "lua":
        refs = [r for f in args.names for r in references_in_lua(Path(f).read_text(), f)]
        total, missing = _check(catalog, ((r.kind, r.name, r.where) for r in refs))
    else:
        total, missing = _check(catalog, ((Kind(args.mode), n, "") for n in args.names))
    for line in missing:
        print(line)
    print(f"{total} checked, {len(missing)} missing")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
