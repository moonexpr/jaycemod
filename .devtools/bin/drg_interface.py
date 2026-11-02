"""DrGBase's interface as our code uses it: the names only, never its code.

NextSoldier keeps the interface our code uses of DrGBase's NextBot (names
and hook contracts) and implements it from scratch (issue #8; DrGBase has no
licence, so nothing of its source is copied). This reads DrGBase's Workshop
addon for the names its NextBot defines (methods, default fields) and our
addons for the ones we call, define and set, and lists their intersection.

  drg_interface.py inventory [--gma PATH]   the names, by kind, with where we use them
  drg_interface.py check [--gma PATH]       fail (exit 1) naming each one
                                            nextsoldier/base.lua does not declare

A name GMod gives every entity (Initialize, Think, Draw...) is left out.
A name only shared with DrGBase (GMod's, Lua's or our own, used on
something that is not DrGBase's NextBot) is a collision, listed with why;
check passes a name base.lua declares or REPLACED names, or a collision.
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GMA = (Path.home() / "Library/Application Support/CrossOver/Bottles/Steam/drive_c/Steam/steamapps"
       / "workshop/content/4000/1560118657/gmpublisher.gma")
NEXTBOT_DIRS = ("lua/entities/drgbase_nextbot/", "lua/entities/drgbase_nextbot_human/", "lua/drgbase/")
OUR_ROOTS = ("addons/sandcastle", "addons/sandcastle_dev")
SKIP = ("/vendor/",)
BASE = REPO / "addons/sandcastle/gamemodes/sandcastle/gamemode/nextsoldier/base.lua"
GENERIC = frozenset({"Initialize", "Think", "Draw", "OnRemove", "Use", "SetupDataTables",
                     "DrawTranslucent", "UpdateTransmitState", "KeyValue", "AcceptInput"})

# Names our code uses that are DrGBase's only by coincidence: name -> why.
COLLISIONS = {
    **dict.fromkeys(("Approach", "SetDesiredSpeed", "SetAcceleration", "SetDeceleration", "SetJumpHeight",
                     "SetMaxYawRate", "SetStepHeight", "SetDeathDropHeight"),
                    "GMod's locomotion (CLuaLocomotion), on our own NextBots (base_nextsoldier_npc, the bosses)"),
    **dict.fromkeys(("BehaveUpdate", "BodyUpdate", "OnContact", "OnInjured", "OnKilled", "OnLeaveGround"),
                    "GMod's NextBot hooks, on our own NextBots (base_nextsoldier_npc, the bosses)"),
    "PlaySequence": "our own NextBots' (base_nextsoldier_npc, eyeball_boss)",
    **dict.fromkeys(("Alive", "SetTeam", "Kill", "GetShootPos", "GetAimVector", "GetWeapon", "HasWeapon"),
                    "GMod's Player and NPC methods, on players, bots and HL2's NPCs"),
    **dict.fromkeys(("Base", "Type", "PrintName", "Category", "ModelScale"), "GMod's scripted entity keys"),
    "Length": "GMod's Vector:Length", "Height": "our own (a size's height)",
    **dict.fromkeys(("Attack", "Patrol", "IsStuck", "Wait"), "features.aiwar.orders' own actions and port"),
    "IsEnemy": "our projectiles' own (ws_projectile, tf_projectile_jar)",
    **dict.fromkeys(("EyeAngles", "EyePos", "GetMaxHealth", "GetModelScale", "GetVelocity", "Health", "Remove",
                     "SetHealth", "SetMaxHealth", "SetPos"),
                    "GMod's entity methods, which DrGBase redefines on its NextBots; NextSoldier's base keeps GMod's"),
    "SetVelocity": "GMod's locomotion (self.loco)", "ClearStuck": "GMod's locomotion (self.loco)", "OnGround": "GMod's Player:OnGround, on bot players",
    "ScreenShake": "our own NextBots' (base_nextsoldier_npc, the bosses)",
    **dict.fromkeys(("DrG_JoinFaction", "DrG_LeaveFaction"),
                    "DrGBase's player factions, which only its own NextBots read (ws/sh_factions.lua)"),
}

COMMENT = re.compile(r"--\[(=*)\[.*?\]\1\]|--[^\n]*", re.S)
# its NextBot's (ENT) and what it adds to GMod's metatables, not its own helper classes
DRG_METHOD = re.compile(r"\bfunction\s+(?:ENT|entMETA|plyMETA|npcMETA|physMETA|vecMETA):(\w+)\s*\(")
DRG_FIELD = re.compile(r"^\s*ENT\.(\w+)\s*=", re.M)
OUR_DEFINED = re.compile(r"\bfunction\s+ENT:(\w+)\s*\(|^\s*ENT\.(\w+)\s*=\s*function\b", re.M)
OUR_SET = re.compile(r"^\s*ENT\.(\w+)\s*=(?!\s*function\b)", re.M)
CALL = re.compile(r":(\w+)\s*\(")
READ = re.compile(r"\.(\w+)\b")


def read_gma(data: bytes) -> dict[str, str]:
    """A GMod addon archive's files: path -> text."""
    if data[:4] != b"GMAD":
        raise ValueError("not a GMod addon archive")
    at = 4 + 1 + 8 + 8

    def cstring() -> str:
        nonlocal at
        end = data.index(b"\0", at)
        text = data[at:end].decode("utf-8", "replace")
        at = end + 1
        return text

    while data[at] != 0:  # required content
        cstring()
    at += 1
    cstring(), cstring(), cstring()  # name, description, author
    at += 4  # addon version
    entries = []
    while struct.unpack_from("<I", data, at)[0] != 0:
        at += 4
        path = cstring()
        size = struct.unpack_from("<q", data, at)[0]
        at += 8 + 4  # size, crc
        entries.append((path, size))
    at += 4
    files = {}
    for path, size in entries:
        files[path] = data[at:at + size].decode("utf-8", "replace")
        at += size
    return files


def code(text: str) -> str:
    return COMMENT.sub("", text)


@dataclass(frozen=True)
class Names:
    methods: frozenset[str]
    fields: frozenset[str]

    @classmethod
    def of_drgbase(cls, text: str) -> "Names":
        body = code(text)
        return cls(frozenset(DRG_METHOD.findall(body)), frozenset(DRG_FIELD.findall(body)))

    def __or__(self, other: "Names") -> "Names":
        return Names(self.methods | other.methods, self.fields | other.fields)


@dataclass(frozen=True)
class Usage:
    defined: frozenset[str]
    set: frozenset[str]
    called: frozenset[str]
    read: frozenset[str]

    @classmethod
    def of(cls, text: str) -> "Usage":
        body = code(text)
        defined = {a or b for a, b in OUR_DEFINED.findall(body)}
        return cls(frozenset(defined), frozenset(OUR_SET.findall(body)),
                   frozenset(CALL.findall(body)), frozenset(READ.findall(body)))


@dataclass(frozen=True)
class Entry:
    name: str
    kind: str  # hook (we define it), method (we call it), field (we set or read it)
    files: tuple[str, ...]


def drgbase_names(gma: Path) -> Names:
    names = Names(frozenset(), frozenset())
    for path, text in read_gma(gma.read_bytes()).items():
        if path.endswith(".lua") and path.startswith(NEXTBOT_DIRS):
            names = names | Names.of_drgbase(text)
    return names


def our_files() -> list[Path]:
    files = []
    for root in OUR_ROOTS:
        files += [p for p in (REPO / root).rglob("*.lua") if not any(s in str(p) for s in SKIP)]
    return sorted(files)


def inventory(names: Names) -> list[Entry]:
    seen: dict[tuple[str, str], list[str]] = {}
    for path in our_files():
        usage = Usage.of(path.read_text(errors="replace"))
        where = str(path.relative_to(REPO))
        for name in usage.defined & names.methods:
            seen.setdefault((name, "hook"), []).append(where)
        for name in usage.called & names.methods:
            seen.setdefault((name, "method"), []).append(where)
        for name in (usage.set | usage.read) & names.fields:
            seen.setdefault((name, "field"), []).append(where)
    return sorted((Entry(name, kind, tuple(files)) for (name, kind), files in seen.items()
                   if name not in GENERIC), key=lambda e: (e.kind, e.name))


def declared(text: str) -> frozenset[str]:
    """The names a base declares: each quoted name, and each key given a
    string (REPLACED's)."""
    body = code(text)
    return frozenset(re.findall(r'"(\w+)"', body)) | frozenset(re.findall(r"^\s*(\w+)\s*=\s*\"", body, re.M))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=("inventory", "check"))
    ap.add_argument("--gma", type=Path, default=GMA)
    args = ap.parse_args()
    entries = inventory(drgbase_names(args.gma))
    if args.action == "inventory":
        for kind in ("hook", "method", "field"):
            chosen = [e for e in entries if e.kind == kind]
            print(f"== {kind}s ({len(chosen)})")
            for e in chosen:
                why = f"  (collision: {COLLISIONS[e.name]})" if e.name in COLLISIONS else ""
                print(f"  {e.name:28s} {len(e.files):3d} files  {', '.join(Path(f).name for f in e.files[:4])}{why}")
        return 0
    known = declared(BASE.read_text()) | COLLISIONS.keys()
    missing = sorted({e.name for e in entries} - known)
    for name in missing:
        print(f"not declared in {BASE.relative_to(REPO)}: {name}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
