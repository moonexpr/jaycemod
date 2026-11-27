#!/usr/bin/env python3
"""NextSoldier's engine layout, read and checked offline: the vtable slots and field offsets
its binding uses (addons/nextsoldier/native/src/layout.rs), for linux64 and win64.

GMod's linux64 server.so is stripped of its C++ symbols but keeps its RTTI, so each class's
tables are found by their typeinfo (elf_vtables.rtti_vtable). Its slots are named from TF2's
linux64 server_srv.so, which keeps its symbols and is built on the same NextBot SDK: each
GMod table is lined up with TF2's after TF2's own VScript slots (GetScriptDesc...) are
dropped, and is named only where the two then hold the same number of slots.

win64's server.dll has no symbols either. Its slots are predicted from the named linux64
tables by MSVC's rules and held against layout.rs, which was read from the DLL's code:

  - one destructor slot (Itanium has two: complete and deleting);
  - no primary-table entry for a function that overrides a secondary base's virtual
    (Itanium adds one; MSVC reaches it only through the secondary table);
  - a class's overloads of one name grouped where the first is declared, last first.

Fields are not predicted across ABIs. linux64's are read from the code of the virtual
getters that load them; win64's are layout.rs's, checked against the DLL by the crate's
tests (`cargo test` reads the CrossOver bottle's server.dll).

    nextbot_layout.py read SERVER_SO TF2_SERVER_SO SERVER_DLL [--write DIR]
    nextbot_layout.py check DIR SERVER_SO TF2_SERVER_SO SERVER_DLL

`read` prints what disagrees and exits 1 if anything does; `check` holds a new build to the
records saved in DIR (linux64.json, win64.json). Run under `uv run --with capstone`.
"""
import argparse
import hashlib
import json
import os
import re
import struct
import sys

import capstone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import source_tools  # noqa: F401  (claude-config2's source readers on sys.path)
import elf_vtables  # noqa: E402
import pe_rtti  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LAYOUT_RS = os.path.join(REPO, "addons", "nextsoldier", "native", "src", "layout.rs")

# Each class: GMod's Itanium name, MSVC's RTTI name, TF2's class whose table names its
# slots (its actor CTFBot read as CLuaNextBot), and its primary base (None at a root).
CLASSES = {
    "INextBotEventResponder": ("22INextBotEventResponder", ".?AVINextBotEventResponder@@",
                               "22INextBotEventResponder", None),
    "IContextualQuery": ("16IContextualQuery", ".?AVIContextualQuery@@", "16IContextualQuery", None),
    "INextBotComponent": ("17INextBotComponent", ".?AVINextBotComponent@@", "17INextBotComponent",
                          "INextBotEventResponder"),
    "INextBot": ("8INextBot", ".?AVINextBot@@", "8INextBot", "INextBotEventResponder"),
    "IIntention": ("10IIntention", ".?AVIIntention@@", "10IIntention", "INextBotComponent"),
    "CLuaNextBotIntention": ("N11CLuaNextBot20CLuaNextBotIntentionE",
                             ".?AVCLuaNextBotIntention@CLuaNextBot@@", "10IIntention", "IIntention"),
    "IVision": ("7IVision", ".?AVIVision@@", "7IVision", "INextBotComponent"),
    "CLuaNextBotVision": ("17CLuaNextBotVision", ".?AVCLuaNextBotVision@@", "7IVision", "IVision"),
    "IBody": ("5IBody", ".?AVIBody@@", "5IBody", "INextBotComponent"),
    "CLuaNextBotBody": ("15CLuaNextBotBody", ".?AVCLuaNextBotBody@@", "5IBody", "IBody"),
    "CKnownEntity": ("12CKnownEntity", ".?AVCKnownEntity@@", "12CKnownEntity", None),
    "Action": ("6ActionI11CLuaNextBotE", ".?AV?$Action@VCLuaNextBot@@@@", "6ActionI6CTFBotE",
               "INextBotEventResponder"),
    "CLuaBehaviour": ("13CLuaBehaviour", ".?AVCLuaBehaviour@@", "6ActionI6CTFBotE", "Action"),
    "Behavior": ("8BehaviorI11CLuaNextBotE", ".?AV?$Behavior@VCLuaNextBot@@@@", "8BehaviorI6CTFBotE",
                 "INextBotEventResponder"),
    "CLuaNextBot": ("11CLuaNextBot", ".?AVCLuaNextBot@@", None, None),
    "NextBotPlayer": ("13NextBotPlayerI12CGMOD_PlayerE", ".?AV?$NextBotPlayer@VCGMOD_Player@@@@", None, None),
    "CBaseEntity": ("11CBaseEntity", ".?AVCBaseEntity@@", None, None),
    "CGlobalEntityList": ("17CGlobalEntityList", ".?AVCGlobalEntityList@@", None, None),
}

# Slots only a class of GMod's own adds past its base's, named here: TF2 has no such class.
OWN_SLOTS = {"CLuaNextBotVision": ["CLuaNextBotVision::SetMaxVisionRange(float)"]}

# TF2's concrete class naming the slots a template of its own leaves pure.
FILL = {"6ActionI6CTFBotE": "16CTFBotMainAction"}

# TF2's VScript additions, which GMod's NextBot does not have.
TF2_ONLY = re.compile(r"::(GetScriptDesc|GetScriptInstance|ScriptGet\w*)\(")

# layout.rs's slot constants: (class, method, a fragment of the overload's arguments or None).
SLOTS = {
    "DESTRUCTOR": ("Action", "~", None),
    "GET_NAME": ("Action", "GetName", None),
    "ON_START": ("Action", "OnStart", None),
    "UPDATE": ("Action", "Update", None),
    "ON_END": ("Action", "OnEnd", None),
    "ON_SUSPEND": ("Action", "OnSuspend", None),
    "ON_RESUME": ("Action", "OnResume", None),
    "INITIAL_CONTAINED": ("Action", "InitialContainedAction", None),
    "ON_STUCK": ("Action", "OnStuck", "CLuaNextBot*"),
    "ON_INJURED": ("Action", "OnInjured", "CLuaNextBot*"),
    "ON_COMMAND_STRING": ("Action", "OnCommandString", "CLuaNextBot*"),
    "SHOULD_HURRY": ("IContextualQuery", "ShouldHurry", None),
    "SHOULD_RETREAT": ("IContextualQuery", "ShouldRetreat", None),
    "RESPONDER_COMMAND_STRING": ("INextBot", "OnCommandString", None),
    "GET_BODY": ("INextBot", "GetBodyInterface", None),
    "GET_INTENTION": ("INextBot", "GetIntentionInterface", None),
    "GET_VISION": ("INextBot", "GetVisionInterface", None),
    "VISION_FOR_EACH_KNOWN": ("IVision", "ForEachKnownEntity", None),
    "VISION_PRIMARY_THREAT": ("IVision", "GetPrimaryKnownThreat", None),
    "VISION_TIME_SINCE_VISIBLE": ("IVision", "GetTimeSinceVisible", None),
    "VISION_CLOSEST_KNOWN_FILTER": ("IVision", "GetClosestKnown", "INextBotEntityFilter"),
    "VISION_CLOSEST_KNOWN": ("IVision", "GetClosestKnown", "int"),
    "VISION_KNOWN_COUNT": ("IVision", "GetKnownCount", None),
    "VISION_GET_KNOWN": ("IVision", "GetKnown", None),
    "VISION_ADD_KNOWN": ("IVision", "AddKnownEntity", None),
    "VISION_FORGET": ("IVision", "ForgetEntity", None),
    "VISION_FORGET_ALL": ("IVision", "ForgetAllKnownEntities", None),
    "VISION_MAX_RANGE": ("IVision", "GetMaxVisionRange", None),
    "VISION_MIN_RECOGNIZE": ("IVision", "GetMinRecognizeTime", None),
    "VISION_ABLE_TO_SEE_POINT": ("IVision", "IsAbleToSee", "Vector"),
    "VISION_ABLE_TO_SEE": ("IVision", "IsAbleToSee", "CBaseEntity*"),
    "VISION_IN_FOV": ("IVision", "IsInFieldOfView", "CBaseEntity*"),
    "VISION_IN_FOV_POINT": ("IVision", "IsInFieldOfView", "Vector"),
    "VISION_DEFAULT_FOV": ("IVision", "GetDefaultFieldOfView", None),
    "VISION_FOV": ("IVision", "GetFieldOfView", None),
    "VISION_SET_FOV": ("IVision", "SetFieldOfView", None),
    "VISION_CLEAR_TO_POINT": ("IVision", "IsLineOfSightClear", "Vector"),
    "VISION_CLEAR_TO": ("IVision", "IsLineOfSightClearToEntity", None),
    "VISION_LOOKING_AT": ("IVision", "IsLookingAt", "CBaseCombatCharacter"),
    "VISION_LOOKING_AT_POINT": ("IVision", "IsLookingAt", "Vector"),
    "VISION_SET_MAX_RANGE": ("CLuaNextBotVision", "SetMaxVisionRange", None),
    "KNOWN_ENTITY": ("CKnownEntity", "GetEntity", None),
    "KNOWN_POSITION": ("CKnownEntity", "GetLastKnownPosition", None),
    "KNOWN_POSITION_SEEN": ("CKnownEntity", "HasLastKnownPositionBeenSeen", None),
    "KNOWN_SINCE_KNOWN": ("CKnownEntity", "GetTimeSinceLastKnown", None),
    "KNOWN_SINCE_BECAME_KNOWN": ("CKnownEntity", "GetTimeSinceBecameKnown", None),
    "KNOWN_VISIBLE_NOW": ("CKnownEntity", "IsVisibleInFOVNow", None),
    "KNOWN_VISIBLE_RECENTLY": ("CKnownEntity", "IsVisibleRecently", None),
    "KNOWN_SINCE_BECAME_VISIBLE": ("CKnownEntity", "GetTimeSinceBecameVisible", None),
    "KNOWN_SINCE_SEEN": ("CKnownEntity", "GetTimeSinceLastSeen", None),
    "KNOWN_EVER_VISIBLE": ("CKnownEntity", "WasEverVisible", None),
    "BODY_EYE_POSITION": ("IBody", "GetEyePosition", None),
    "BODY_VIEW_VECTOR": ("IBody", "GetViewVector", None),
    "BODY_AIM_HEAD": ("IBody", "AimHeadTowards", "CBaseEntity*"),  # MSVC puts it before the point's
    "BODY_HEAD_ON_TARGET": ("IBody", "IsHeadAimingOnTarget", None),
    "BODY_HEAD_STEADY": ("IBody", "IsHeadSteady", None),
    "BODY_START_ACTIVITY": ("IBody", "StartActivity", None),
    "BODY_ACTIVITY": ("IBody", "GetActivity", None),
    "BODY_IS_ACTIVITY": ("IBody", "IsActivity", None),
    "BODY_HULL_WIDTH": ("IBody", "GetHullWidth", None),
    "BODY_HULL_HEIGHT": ("IBody", "GetHullHeight", None),
    "BODY_STAND_HEIGHT": ("IBody", "GetStandHullHeight", None),
    "BODY_CROUCH_HEIGHT": ("IBody", "GetCrouchHullHeight", None),
    "BODY_HULL_MINS": ("IBody", "GetHullMins", None),
    "BODY_HULL_MAXS": ("IBody", "GetHullMaxs", None),
    "BODY_SOLID_MASK": ("IBody", "GetSolidMask", None),
    "BODY_COLLISION_GROUP": ("IBody", "GetCollisionGroup", None),
    "FIRST_CONTAINED": ("CLuaNextBotIntention", "FirstContainedResponder", None),
    "NEXT_CONTAINED": ("CLuaNextBotIntention", "NextContainedResponder", None),
    "INTENTION_UPDATE": ("IIntention", "Update", None),
    "INTENTION_UPKEEP": ("IIntention", "Upkeep", None),
    "COMPONENT_GET_BOT": ("IIntention", "GetBot", None),
}

# CBaseEntity's slots differ between GMod and TF2, so they are not named here: on win64
# reach.rs reads them from the Lua methods' glue as the binding binds.
UNNAMED = ["IS_ALIVE", "IS_PLAYER", "EYE_POSITION", "EYE_ANGLES"]

# layout.rs's table sizes: (class, table index).
COUNTS = {
    "ACTION_SLOTS": ("Action", 0),
    "QUERY_SLOTS": ("Action", 1),
    "VISION_SLOTS": ("IVision", 0),
    "LUA_VISION_SLOTS": ("CLuaNextBotVision", 0),
    "BODY_SLOTS": ("IBody", 0),
    "KNOWN_SLOTS": ("CKnownEntity", 0),
    "INTENTION_SLOTS": ("IIntention", 0),
}

# Fields read from the code of a virtual getter: (class, method, its argument fragment).
FIELDS = {
    "INTENTION_BEHAVIOR": ("CLuaNextBotIntention", "FirstContainedResponder", None),
    "COMPONENT_BOT": ("IIntention", "GetBot", None),
    "BEHAVIOR_ACTION": ("Behavior", "FirstContainedResponder", None),
    "ACTION_CHILD": ("Action", "FirstContainedResponder", None),
    "KNOWN_HANDLE": ("CKnownEntity", "GetEntity", None),
    "KNOWN_POSITION_FIELD": ("CKnownEntity", "GetLastKnownPosition", None),
    "LUA_VISION_RANGE": ("CLuaNextBotVision", "GetMaxVisionRange", None),
}

# Where one class's subobject sits in another: the table of `outer` whose length is `inner`'s.
SUBOBJECTS = {
    "INEXTBOT_OFFSET": ("CLuaNextBot", "INextBot"),
    "PLAYER_INEXTBOT_OFFSET": ("NextBotPlayer", "INextBot"),
    "INTENTION_QUERY": ("IIntention", "IContextualQuery"),
}


def layout_constants(path=LAYOUT_RS):
    text = open(path).read()
    pattern = r"pub const (\w+): (?:usize|i32|u32) = (0x[0-9A-Fa-f_]+|-?\d+);"
    return {name: int(value.replace("_", ""), 0) for name, value in re.findall(pattern, text)}


def identity(path):
    data = open(path, "rb").read()
    return {"file": os.path.basename(path), "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(), "steam_build": steam_build(path)}, data


def steam_build(path):
    """The Steam build of the install a binary is in, from its appmanifest, if it has one."""
    at = os.path.dirname(os.path.abspath(path))
    for _ in range(10):
        for manifest in ("appmanifest_4020.acf", "appmanifest_232250.acf", "appmanifest_4000.acf"):
            for root in (at, os.path.join(at, "steamapps")):
                found = os.path.join(root, manifest)
                if os.path.exists(found):
                    m = re.search(r'"buildid"\s+"(\d+)"', open(found).read())
                    return int(m.group(1)) if m else None
        at = os.path.dirname(at)
    return None


def method(pretty):
    """`A<B>::C::Get(int) const` → `Get`; `~A` for a destructor."""
    return pretty.split("(")[0].rsplit("::", 1)[-1]


def arguments(pretty):
    return pretty[pretty.find("(") + 1:pretty.rfind(")")]


class Names:
    """TF2's tables, named by their symbols and read with CLuaNextBot for its actor."""

    def __init__(self, data):
        self.elf = elf_vtables.Elf(data)
        self.cache = {}

    def tables(self, itanium):
        if itanium not in self.cache:
            tables = self.elf.vtable(itanium)
            fill = self.elf.vtable(FILL[itanium]) if itanium in FILL else []
            named = []
            for i, table in enumerate(tables):
                slots = list(table.slots)
                if i < len(fill):
                    slots = [fill[i].slots[j] if self.elf.slot_name(s) in ("__cxa_pure_virtual", "(null)")
                             and j < len(fill[i].slots) and j >= 2 else s for j, s in enumerate(slots)]
                pretty = elf_vtables.demangle([self.elf.slot_name(s) for s in slots])
                named.append([p.replace("CTFBot", "CLuaNextBot") for p in pretty])
            self.cache[itanium] = named
        return self.cache[itanium]


class Gmod:
    """GMod's linux64 server.so: its classes by RTTI, named by lining them up with TF2's."""

    def __init__(self, data, names):
        self.elf = elf_vtables.Elf(data)
        self.tables, self.named, self.problems = {}, {}, []
        for key, (itanium, _, _, _) in CLASSES.items():
            try:
                self.tables[key] = elf_vtables.rtti_vtable(self.elf, itanium)[1]
            except KeyError as why:
                self.problems.append(f"{key}: {why}")
        for key, (_, _, template, _) in CLASSES.items():
            if key in self.tables and template:
                self._name(key, names.tables(template))

    def _name(self, key, template):
        """Each table named by TF2's, without TF2's VScript slots, where the counts agree."""
        own = OWN_SLOTS.get(key, [])
        named = []
        for i, table in enumerate(self.tables[key]):
            if i >= len(template):
                named.append(None)
                continue
            kept = [p for p in template[i] if not TF2_ONLY.search(p)]
            if i == 0:
                kept = kept + own
            if len(kept) != len(table.slots):
                self.problems.append(f"{key} table {i}: GMod has {len(table.slots)} slots, "
                                     f"TF2's names {len(kept)} once its VScript slots are dropped")
                named.append(None)
                continue
            named.append(kept)
        self.named[key] = named

    def slot(self, key, name, argument, table=0):
        """The index of a class's slot named so, among its overloads by argument."""
        names = (self.named.get(key) or [None])[table]
        if names is None:
            raise LookupError(f"{key} table {table} is not named")
        hits = []
        for j, pretty in enumerate(names):
            if pretty.startswith(("non-virtual thunk", "virtual thunk")):
                continue
            if name == "~":
                if "::~" in pretty or pretty in ("(null)", "__cxa_pure_virtual"):
                    hits.append(j)
                continue
            if method(pretty) != name:
                continue
            if argument is not None and argument not in arguments(pretty).split(",")[0]:
                continue
            hits.append(j)
        if name == "~" and hits:
            return hits[0], names[hits[0]]
        if len(hits) != 1:
            raise LookupError(f"{key}::{name}({argument or ''}) matches slots {hits}")
        return hits[0], names[hits[0]]

    def msvc(self, key):
        """Each primary slot's MSVC index (None where MSVC has none), by the rules above."""
        names = self.named[key][0]
        base = CLASSES[key][3]
        mapping, start, next_index = [], 0, 0
        if base:
            mapping = self.msvc(base)
            start = len(self.named[base][0])
            next_index = 1 + max((m for m in mapping if m is not None), default=-1)
        thunked = set()
        for table in self.named[key][1:]:
            for pretty in table or []:
                for prefix in ("non-virtual thunk to ", "virtual thunk to "):
                    if pretty.startswith(prefix):
                        thunked.add(pretty[len(prefix):])
        kept, destructor = [], False
        for j in range(start, len(names)):
            if names[j] in thunked:
                continue
            if "::~" in names[j] or (names[j] == "(null)" and j - start < 2):
                if destructor:
                    continue
                destructor = True
            kept.append(j)
        result = mapping + [None] * (len(names) - start)
        placed = set()
        for j in kept:
            if j in placed:
                continue
            same = method(names[j])
            group = [j] if same in ("__cxa_pure_virtual", "(null)") else \
                [k for k in kept if method(names[k]) == same]
            for k in reversed(group):
                result[k] = next_index
                next_index += 1
                placed.add(k)
        return result

    def code_of(self, key, index, table=0):
        addr = self.tables[key][table].slots[index][0]
        return addr, self.elf.code(addr, 96)

    def field(self, key, name, argument):
        """The displacement the getter's first memory operand off this (rdi) uses."""
        index, pretty = self.slot(key, name, argument)
        addr, code = self.code_of(key, index)
        decoder = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
        decoder.detail = True
        for insn in decoder.disasm(code, addr):
            for op in insn.operands:
                if op.type == capstone.x86.X86_OP_MEM and op.mem.base == capstone.x86.X86_REG_RDI:
                    return {"offset": op.mem.disp, "from": pretty, "instruction": f"{insn.mnemonic} {insn.op_str}"}
            if insn.mnemonic in ("ret", "jmp", "call"):
                break
        return {"offset": None, "from": pretty, "instruction": "no load through rdi"}

    def subobject(self, outer, inner):
        """The offset of the table of `outer` whose slot count is `inner`'s primary table's."""
        want = len(self.tables[inner][0].slots)
        hits = [t.offset for t in self.tables[outer][1:] if len(t.slots) == want]
        return hits[0] if len(hits) == 1 else None


def read(server_so, tf2_so, server_dll, constants):
    gmod_id, gmod_data = identity(server_so)
    tf2_id, tf2_data = identity(tf2_so)
    win_id, win_data = identity(server_dll)
    gmod = Gmod(gmod_data, Names(tf2_data))
    linux = {
        "platform": "linux64", "binary": gmod_id, "names_from": tf2_id,
        "classes": {k: {"rtti": CLASSES[k][0], "tables": [{"offset": t.offset, "slots": len(t.slots)} for t in v]}
                    for k, v in gmod.tables.items()},
        "slots": {}, "counts": {}, "fields": {}, "subobjects": {},
        "not_derived": {c: "CBaseEntity's slots differ from TF2's, and the binary has no names" for c in UNNAMED},
    }
    predicted, problems = {}, list(gmod.problems)
    maps = {}
    for const, (key, name, argument) in SLOTS.items():
        table = 0
        try:
            index, pretty = gmod.slot(key, name, argument, table)
        except LookupError as why:
            problems.append(f"{const}: {why}")
            continue
        linux["slots"][const] = {"class": key, "slot": index, "function": pretty}
        try:
            maps.setdefault(key, gmod.msvc(key))
            predicted[const] = maps[key][index]
        except (KeyError, TypeError) as why:
            problems.append(f"{const}: no MSVC prediction ({why})")
    for const, (key, table) in COUNTS.items():
        if key not in gmod.tables or table >= len(gmod.tables[key]):
            continue
        n = len(gmod.tables[key][table].slots)
        linux["counts"][const] = n
        if table == 0 and key in gmod.named and gmod.named[key][0]:
            predicted[const] = 1 + max(m for m in maps.setdefault(key, gmod.msvc(key)) if m is not None)
        elif table > 0:
            predicted[const] = n - 1  # the secondary table's own two destructors, one on MSVC
    for const, spec in FIELDS.items():
        try:
            linux["fields"][const] = gmod.field(*spec)
        except LookupError as why:
            problems.append(f"{const}: {why}")
    for const, (outer, inner) in SUBOBJECTS.items():
        linux["subobjects"][const] = gmod.subobject(outer, inner)
    linux["problems"] = problems

    image = pe_rtti.Image(win_data)
    descriptors, objects, pointers = pe_rtti.type_descriptors(image), pe_rtti.locators(image), pe_rtti.vtables(image)
    win = {"platform": "win64", "binary": win_id, "classes": {}}
    for key, (_, msvc, _, _) in CLASSES.items():
        if msvc not in descriptors:
            continue
        tables = [{"offset": offset, "slots": len(pe_rtti.slots(image, table))}
                  for own, offset, _ in objects.get(descriptors[msvc], []) for table in pointers.get(own, [])]
        win["classes"][key] = {"rtti": msvc, "tables": sorted(tables, key=lambda t: (t["offset"], t["slots"]))}
    agree, disagree = [], []
    for const, value in sorted(predicted.items()):
        if const in constants:
            (agree if value == constants[const] else disagree).append((const, value, constants[const]))
    win["layout_rs"] = constants
    win["predicted_from_linux64"] = {
        "agree": [c for c, _, _ in agree],
        "disagree": [{"constant": c, "predicted": p, "layout_rs": v} for c, p, v in disagree],
    }
    return linux, win, disagree


def write(directory, record):
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, f"{record['platform']}.json")
    with open(path, "w") as out:
        json.dump(record, out, indent=2)
        out.write("\n")
    return path


STABLE = {"linux64": ("binary", "classes", "slots", "counts", "fields", "subobjects"),
          "win64": ("binary", "classes", "layout_rs")}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    r = sub.add_parser("read")
    r.add_argument("server_so")
    r.add_argument("tf2_server_so")
    r.add_argument("server_dll")
    r.add_argument("--write")
    c = sub.add_parser("check")
    c.add_argument("directory")
    c.add_argument("server_so")
    c.add_argument("tf2_server_so")
    c.add_argument("server_dll")
    args = parser.parse_args()
    constants = layout_constants()
    linux, win, disagree = read(args.server_so, args.tf2_server_so, args.server_dll, constants)
    for problem in linux["problems"]:
        print("problem:", problem)
    print(f"win64 slots predicted from linux64: {len(win['predicted_from_linux64']['agree'])} agree "
          f"with layout.rs, {len(disagree)} do not")
    for const, p, v in disagree:
        print(f"  {const}: predicted {p}, layout.rs {v}")
    failed = bool(disagree or linux["problems"])
    if args.command == "read":
        if args.write:
            print("wrote", write(args.write, linux))
            print("wrote", write(args.write, win))
        sys.exit(1 if failed else 0)
    for record in (linux, win):
        saved = json.load(open(os.path.join(args.directory, f"{record['platform']}.json")))
        for part in STABLE[record["platform"]]:
            if record[part] != saved.get(part):
                failed = True
                print(f"{record['platform']} {part} differs from the saved record")
    print("layout differs" if failed else "layout unchanged")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
