#!/usr/bin/env python3
"""Read GMod's client Lua cache (garrysmod/cache/lua/<name>.lua), read-only.

  gmod_lua_cache.py verify [--limit N]     check each entry's layout and naming
  gmod_lua_cache.py match <addon-dir>      which of the addon's .lua files are cached

Layout as third parties reverse-engineered it (djsime1/gluapack src/pack.rs,
src/gluapack.lua): a 32-byte header, then util.Compress's LZMA ("alone")
stream of the file's text plus one NUL. The entry's name is the first 20
bytes, in hex, of SHA-256(text + NUL). `verify` tests that claim on every
entry; `match` hashes the addon's files the same way and looks them up.
Writes nothing.
"""
from __future__ import annotations

import argparse
import hashlib
import lzma
import sys
from dataclasses import dataclass
from pathlib import Path

GMOD_DIR = (Path.home() / "Library/Application Support/CrossOver/Bottles/Steam"
            / "drive_c/Steam/steamapps/common/GarrysMod/garrysmod")
CACHE_DIR = GMOD_DIR / "cache" / "lua"
HEADER_BYTES = 32
NAME_BYTES = 20


class NotAnEntry(Exception):
    pass


@dataclass(frozen=True)
class Entry:
    name: str
    header: bytes
    text: bytes  # the file's text, its trailing NUL removed

    @classmethod
    def parse(cls, name: str, raw: bytes) -> "Entry":
        try:
            body = lzma.decompress(raw[HEADER_BYTES:], format=lzma.FORMAT_ALONE)
        except lzma.LZMAError as e:
            raise NotAnEntry(f"{name}: payload is not LZMA-alone: {e}") from e
        if not body.endswith(b"\0"):
            raise NotAnEntry(f"{name}: text does not end in NUL")
        return cls(name, raw[:HEADER_BYTES], body[:-1])


def content_digest(text: bytes) -> bytes:
    return hashlib.sha256(text + b"\0").digest()


def cache_name(text: bytes) -> str:
    return content_digest(text)[:NAME_BYTES].hex()


def verify(limit: int) -> int:
    files = sorted(CACHE_DIR.glob("*.lua"))[:limit]
    named = header_is_digest = bad = 0
    for path in files:
        try:
            entry = Entry.parse(path.stem, path.read_bytes())
        except NotAnEntry as e:
            bad += 1
            print(e)
            continue
        named += cache_name(entry.text) == entry.name
        header_is_digest += entry.header == content_digest(entry.text)
    print(f"entries {len(files)}; name == sha256(text+NUL)[:20]: {named}; "
          f"header == sha256(text+NUL): {header_is_digest}; unreadable: {bad}")
    return 0


def match(addon: Path) -> int:
    cached = {p.stem for p in CACHE_DIR.glob("*.lua")}
    sources = sorted(addon.rglob("*.lua"))
    hits = [p for p in sources if cache_name(p.read_bytes()) in cached]
    print(f"addon .lua files {len(sources)}; present in the cache as their current text: {len(hits)}")
    for p in hits[:10]:
        print("  hit", p.relative_to(addon), cache_name(p.read_bytes()))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    v = sub.add_parser("verify")
    v.add_argument("--limit", type=int, default=10**9)
    m = sub.add_parser("match")
    m.add_argument("addon", type=Path)
    args = ap.parse_args()
    return verify(args.limit) if args.action == "verify" else match(args.addon)


if __name__ == "__main__":
    sys.exit(main())
