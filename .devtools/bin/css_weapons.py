#!/usr/bin/env python3
"""Write CS:S's weapon scripts as the Lua data part of gameplay.css_weapons.

  css_weapons.py CSTRIKE_DIR OUT.lua

CSTRIKE_DIR is Counter-Strike: Source's cstrike folder: its pak
(cstrike_pak_dir.vpk) holds scripts/weapon_*.ctx, ICE-encrypted KeyValues
(ice.py), and resource/cstrike_english.txt (UTF-16) names them. C4 is left
out: it is the bomb of bomb defusal, not a weapon. Each weapon keeps its
numbers under Lua names (FIELDS), its accuracy model's and its second
mode's (ACCURACY: silencer on, scoped, burst), and its sounds.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from ice import CSS_KEY, decrypt_file
from vpk import Vpk

SKIPPED = {"weapon_c4"}

# script key -> (Lua name, type)
FIELDS = {
    "WeaponType": ("type", str),
    "Team": ("team", str),
    "WeaponPrice": ("price", int),
    "FullAuto": ("fullAuto", bool),
    "Damage": ("damage", float),
    "Bullets": ("bullets", int),
    "CycleTime": ("cycle", float),
    "Penetration": ("penetration", int),
    "Range": ("range", float),
    "RangeModifier": ("rangeModifier", float),
    "MaxPlayerSpeed": ("maxSpeed", float),
    "WeaponArmorRatio": ("armorRatio", float),
    "clip_size": ("clip", int),
    "primary_ammo": ("ammo", str),
    "bucket": ("slot", int),
    "bucket_position": ("slotPos", int),
    "viewmodel": ("viewModel", str),
    "playermodel": ("worldModel", str),
    "SilencerModel": ("silencerModel", str),
    "PlayerAnimationExtension": ("animation", str),
}

ACCURACY = {
    "Spread": "spread",
    "InaccuracyCrouch": "crouch",
    "InaccuracyStand": "stand",
    "InaccuracyJump": "jump",
    "InaccuracyLand": "land",
    "InaccuracyLadder": "ladder",
    "InaccuracyFire": "fire",
    "InaccuracyMove": "move",
    "RecoveryTimeCrouch": "recoveryCrouch",
    "RecoveryTimeStand": "recoveryStand",
}
ALT = "Alt"

TOKEN = re.compile(r'"([^"]*)"|([{}])|([^\s"{}]+)')


class ScriptError(Exception):
    pass


def keyvalues(text: str) -> dict:
    """Valve KeyValues: keys with quoted or bare values, or nested blocks."""
    text = re.sub(r"//[^\n]*", "", text)
    tokens = [m.group(1) if m.group(1) is not None else m.group(2) or m.group(3) for m in TOKEN.finditer(text)]
    root: dict = {}
    stack = [root]
    key = None
    for tok in tokens:
        if tok == "{":
            if key is None:
                raise ScriptError("a block without a key")
            block: dict = {}
            stack[-1][key] = block
            stack.append(block)
            key = None
        elif tok == "}":
            stack.pop()
        elif key is None:
            key = tok
        else:
            stack[-1].setdefault(key, tok)
            key = None
    return root


def weapon(cls: str, script: dict, names: dict) -> dict:
    data = script.get("WeaponData")
    if data is None:
        raise ScriptError(f"{cls}: no WeaponData")
    out: dict = {"name": names.get(data.get("printname", "").lstrip("#"), cls)}
    for key, (name, kind) in FIELDS.items():
        if key in data:
            raw = data[key]
            out[name] = (raw.strip() != "0") if kind is bool else kind(float(raw)) if kind is int else kind(raw)
    accuracy = {name: float(data[key]) for key, name in ACCURACY.items() if key in data}
    if accuracy:
        out["accuracy"] = accuracy
    alt = {name: float(data[key + ALT]) for key, name in ACCURACY.items() if key + ALT in data}
    if alt:
        out["alt"] = alt
    sounds = data.get("SoundData")
    if isinstance(sounds, dict) and sounds:
        out["sounds"] = dict(sounds)
    return out


def localization(raw: bytes) -> dict:
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8")
    return dict(re.findall(r'"(Cstrike_WPNHUD_\w+)"\s+"([^"]*)"', text))


def _value(v, depth: int) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return lua(v, depth)


def _key(k: str) -> str:
    return k if re.fullmatch(r"[A-Za-z_]\w*", k) else f'["{k}"]'


def lua(table: dict, depth: int = 0) -> str:
    pad = "\t" * (depth + 1)
    lines = [f"{pad}{_key(k)} = {_value(table[k], depth + 1)}," for k in sorted(table)]
    return "{\n" + "\n".join(lines) + "\n" + "\t" * depth + "}"


HEADER = """-- CS:S's weapon scripts (cstrike_pak_dir.vpk, scripts/weapon_*.ctx), as
-- data: written by .devtools/bin/css_weapons.py from the game's own files,
-- never by hand. gameplay.css_weapons makes its weapons from them.
module(...)

SCRIPTS = """


def main() -> int:
    cstrike, out = Path(sys.argv[1]), Path(sys.argv[2])
    pak = Vpk.open(cstrike / "cstrike_pak_dir.vpk")
    names = localization((cstrike / "resource" / "cstrike_english.txt").read_bytes())
    weapons = {}
    for path in sorted(pak.names()):
        m = re.fullmatch(r"scripts/(weapon_\w+)\.ctx", path)
        if not m or m.group(1) in SKIPPED:
            continue
        text = decrypt_file(pak.read(path), CSS_KEY).decode("utf-8", "replace")
        weapons[m.group(1)] = weapon(m.group(1), keyvalues(text), names)
    out.write_text(HEADER + lua(weapons) + "\n")
    print(f"{len(weapons)} weapons -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
