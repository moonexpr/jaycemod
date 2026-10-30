#!/usr/bin/env python3
"""Decrypt what Source encrypts with IceKey(0): Thin-ICE, an 8-round, 64-bit
block cipher (Matthew Kwan's ICE, level 0). CS:S keeps its weapon scripts
this way (scripts/weapon_*.ctx, key "d7NSuLq2"); Source decrypts each whole
8-byte block of a file and leaves a shorter tail as it is.

  ice.py KEY < FILE.ctx > FILE.txt

With vpk.py:  vpk.py cstrike_pak_dir.vpk scripts/weapon_ak47.ctx | ice.py d7NSuLq2
"""
from __future__ import annotations

import sys

BLOCK = 8
ROUNDS = 8
CSS_KEY = b"d7NSuLq2"

_SMOD = ((333, 313, 505, 369), (379, 375, 319, 391), (361, 445, 451, 397), (397, 425, 395, 505))
_SXOR = ((0x83, 0x85, 0x9B, 0xCD), (0xCC, 0xA7, 0xAD, 0x41), (0x4B, 0x2E, 0xD4, 0x33), (0xEA, 0xCB, 0x2E, 0x04))
_PBOX = (
    0x00000001, 0x00000080, 0x00000400, 0x00002000, 0x00080000, 0x00200000, 0x01000000, 0x40000000,
    0x00000008, 0x00000020, 0x00000100, 0x00004000, 0x00010000, 0x00800000, 0x04000000, 0x20000000,
    0x00000004, 0x00000010, 0x00000200, 0x00008000, 0x00020000, 0x00400000, 0x08000000, 0x10000000,
    0x00000002, 0x00000040, 0x00000800, 0x00001000, 0x00040000, 0x00100000, 0x02000000, 0x80000000,
)
_KEYROT = (0, 1, 2, 3, 2, 1, 3, 0)


class IceError(Exception):
    pass


def _gf_mult(a: int, b: int, m: int) -> int:
    result = 0
    while b:
        if b & 1:
            result ^= a
        a <<= 1
        b >>= 1
        if a >= 256:
            a ^= m
    return result


def _gf_exp7(b: int, m: int) -> int:
    if b == 0:
        return 0
    x = _gf_mult(b, b, m)
    x = _gf_mult(b, x, m)
    x = _gf_mult(x, x, m)
    return _gf_mult(b, x, m)


def _perm32(x: int) -> int:
    result, i = 0, 0
    while x:
        if x & 1:
            result |= _PBOX[i]
        i += 1
        x >>= 1
    return result


def _sboxes():
    boxes = [[0] * 1024 for _ in range(4)]
    for i in range(1024):
        col = (i >> 1) & 0xFF
        row = (i & 1) | ((i & 0x200) >> 8)
        for box, shift in enumerate((24, 16, 8, 0)):
            boxes[box][i] = _perm32(_gf_exp7(col ^ _SXOR[box][row], _SMOD[box][row]) << shift)
    return boxes


_SBOX = _sboxes()


def _f(p: int, sk) -> int:
    tl = ((p >> 16) & 0x3FF) | (((p >> 14) | (p << 18)) & 0xFFC00)
    tr = (p & 0x3FF) | ((p << 2) & 0xFFC00)
    al = sk[2] & (tl ^ tr)
    ar = al ^ tr
    al ^= tl
    al ^= sk[0]
    ar ^= sk[1]
    return _SBOX[0][al >> 10] | _SBOX[1][al & 0x3FF] | _SBOX[2][ar >> 10] | _SBOX[3][ar & 0x3FF]


class IceKey:
    """A level-0 key: eight bytes, eight rounds."""

    def __init__(self, key: bytes):
        if len(key) != BLOCK:
            raise IceError(f"a Thin-ICE key is {BLOCK} bytes, not {len(key)}")
        kb = [0] * 4
        for i in range(4):
            kb[3 - i] = (key[i * 2] << 8) | key[i * 2 + 1]
        self._schedule = []
        for i in range(ROUNDS):
            rot = _KEYROT[i]
            sk = [0, 0, 0]
            for j in range(15):
                for k in range(4):
                    w = (rot + k) & 3
                    bit = kb[w] & 1
                    sk[j % 3] = (sk[j % 3] << 1) | bit
                    kb[w] = (kb[w] >> 1) | ((bit ^ 1) << 15)
            self._schedule.append(sk)

    def encrypt_block(self, block: bytes) -> bytes:
        left, right = int.from_bytes(block[:4], "big"), int.from_bytes(block[4:], "big")
        for i in range(0, ROUNDS, 2):
            left ^= _f(right, self._schedule[i])
            right ^= _f(left, self._schedule[i + 1])
        return right.to_bytes(4, "big") + left.to_bytes(4, "big")

    def decrypt_block(self, block: bytes) -> bytes:
        left, right = int.from_bytes(block[:4], "big"), int.from_bytes(block[4:], "big")
        for i in range(ROUNDS - 1, 0, -2):
            left ^= _f(right, self._schedule[i])
            right ^= _f(left, self._schedule[i - 1])
        return right.to_bytes(4, "big") + left.to_bytes(4, "big")


def decrypt_file(data: bytes, key: bytes) -> bytes:
    ice = IceKey(key)
    whole = len(data) - len(data) % BLOCK
    return b"".join(ice.decrypt_block(data[i:i + BLOCK]) for i in range(0, whole, BLOCK)) + data[whole:]


def main() -> int:
    key = sys.argv[1].encode() if len(sys.argv) > 1 else CSS_KEY
    sys.stdout.buffer.write(decrypt_file(sys.stdin.buffer.read(), key))
    return 0


if __name__ == "__main__":
    sys.exit(main())
