#!/usr/bin/env python3
"""The Source SDK's NextBot classes laid out by a compiler, for both of GMod's ABIs, to
check NextSoldier's engine layout (addons/nextsoldier/native/src/layout.rs and
native/layout/linux64.json) against the compiler's own rules rather than a reading of
the binaries.

clang compiles a probe of the SDK's headers twice, never linking: once as MSVC
(x86_64-pc-windows-msvc, win64's ABI) and once as Itanium (x86_64-apple-darwin with the SDK's macOS
configuration: LP64 Itanium, which lays these classes out as x86_64 Linux does). Each class's record and
vtable layouts come from clang's -fdump-record-layouts and -fdump-vtable-layouts. The
probe calls one virtual of each class, which makes clang compute its vtable.

The SDK checkout is the 2025 TF2 update, which adds VScript to NextBot (a GetScriptDesc
slot and an HSCRIPT field in INextBotComponent) that GMod's build has not got. --gmod
(the default) compiles through an overlay of the NextBot headers with those taken out.

No sysroot is needed. Itanium uses macOS's headers. MSVC uses only
clang's builtin headers, an empty stub for every other system header, and a shim declaring
the few C runtime names the SDK's headers use: layout never depends on them.

    sdk_layout.py [--sdk ~/Repositories/source-sdk-2013] [--vscript] [--json OUT]

Prints the comparison and exits 1 when the compiler and the saved layout disagree.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nextbot_layout  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORK = os.path.join(REPO, ".workbench", "artifacts", "sdk_layout")
LINUX64 = os.path.join(REPO, "addons", "nextsoldier", "native", "layout", "linux64.json")

# The actor the templates are laid out for; GMod's CLuaNextBot is not in the SDK, but an
# Action's and a Behavior's layout does not depend on its actor.
ACTOR = "NextBotCombatCharacter"
PROBE_CLASSES = {
    "INextBotEventResponder": "INextBotEventResponder",
    "IContextualQuery": "IContextualQuery",
    "INextBotComponent": "INextBotComponent",
    "INextBot": "INextBot",
    "IIntention": "IIntention",
    "IVision": "IVision",
    "IBody": "IBody",
    "ILocomotion": "ILocomotion",
    "CKnownEntity": "CKnownEntity",
    "Action": f"Action<{ACTOR}>",
    "Behavior": f"Behavior<{ACTOR}>",
    "NextBotCombatCharacter": ACTOR,
}

PROBE = """\
#include "cbase.h"
#include "NextBot.h"
#include "NextBotBehavior.h"
#include "NextBotKnownEntity.h"
#include "NextBotVisionInterface.h"
#include "NextBotBodyInterface.h"
#include "NextBotIntentionInterface.h"
#include "NextBotLocomotionInterface.h"
""" + "".join(
    f"void probe_{i}({cls} *p) {{ delete p; }}\n" for i, cls in enumerate(PROBE_CLASSES.values())
)

# What the SDK's headers ask of MSVC's C runtime: declarations only, for a parse.
CRT_SHIM = r"""
#pragma once
#include <stddef.h>
#include <stdarg.h>
typedef long long time_t;
typedef struct { char _[256]; } jmp_buf[1];
namespace std { typedef decltype(nullptr) nullptr_t; }
using std::nullptr_t;
#define _Check_return_
#define __CRTDECL
#ifdef offsetof
#undef offsetof
#endif
#define offsetof(type, member) __builtin_offsetof(type, member)
inline void *operator new(size_t, void *p) noexcept { return p; }
inline void *operator new[](size_t, void *p) noexcept { return p; }
inline void operator delete(void *, void *) noexcept {}
namespace std { template <class> class function; struct bad_alloc {}; }
extern "C" {
void *memset(void *, int, size_t); void *memcpy(void *, const void *, size_t);
void *memmove(void *, const void *, size_t); int memcmp(const void *, const void *, size_t);
size_t strlen(const char *); char *strcpy(char *, const char *); char *strncpy(char *, const char *, size_t);
char *strcat(char *, const char *); int strcmp(const char *, const char *); char *strstr(const char *, const char *);
char *strchr(const char *, int); char *strrchr(const char *, int); size_t strcspn(const char *, const char *);
int _stricmp(const char *, const char *); char *_itoa(int, char *, int); char *_i64toa(long long, char *, int);
char *_ui64toa(unsigned long long, char *, int);
int snprintf(char *, size_t, const char *, ...); int sscanf(const char *, const char *, ...);
int sprintf(char *, const char *, ...); int printf(const char *, ...); int vsnprintf(char *, size_t, const char *, va_list);
int atoi(const char *); double atof(const char *); long strtol(const char *, char **, int); double strtod(const char *, char **);
unsigned long strtoul(const char *, char **, int); long long strtoll(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int); int tolower(int); int toupper(int);
int strncmp(const char *, const char *, size_t); int strcasecmp(const char *, const char *);
int strncasecmp(const char *, const char *, size_t); char *strdup(const char *); void abort(void); void exit(int); int _vsnprintf(char *, size_t, const char *, va_list);
int _vscprintf(const char *, va_list); int _vsntprintf(char *, size_t, const char *, va_list);
size_t wcslen(const wchar_t *); int wcscmp(const wchar_t *, const wchar_t *); wchar_t *wcscpy(wchar_t *, const wchar_t *);
wchar_t *wcsncpy(wchar_t *, const wchar_t *, size_t); wchar_t *wcschr(const wchar_t *, wchar_t);
wchar_t *_wcslwr(wchar_t *); wchar_t *_wcsupr(wchar_t *);
void *malloc(size_t); void *realloc(void *, size_t); void free(void *); size_t _msize(void *);
size_t malloc_usable_size(void *); void *_aligned_malloc(size_t, size_t); void _aligned_free(void *); int rand(void);
double fabs(double); double sqrt(double); double floor(double); float fabsf(float); float sqrtf(float);
float sinf(float); float cosf(float); float powf(float, float); float logf(float); float expf(float);
int isalnum(int); int isalpha(int); int iscntrl(int); int isgraph(int); int islower(int); int isprint(int);
int ispunct(int); int isspace(int); int isupper(int); int isxdigit(int);
}
namespace std { using ::sqrtf; using ::strchr; }
"""

DEFINES = {
    "msvc": ["-DWIN32", "-D_WIN32", "-D_WIN64", "-DPLATFORM_64BITS", "-DCOMPILER_MSVC", "-DCOMPILER_MSVC64",
             "-fms-extensions", "-fms-compatibility"],
    # the SDK's own macOS build: LP64 Itanium, as linux64, on the headers this machine has
    "itanium": ["-DPOSIX", "-DOSX", "-D_OSX", "-DPLATFORM_64BITS", "-DGNUC", "-DCOMPILER_GCC"],
}
TRIPLE = {"msvc": "x86_64-pc-windows-msvc", "itanium": "x86_64-apple-darwin"}

# The VScript the 2025 update put into NextBot's headers, which GMod's build lacks.
VSCRIPT = [
    re.compile(r"^\s*DECLARE_ENT_SCRIPTDESC\(\s*\);.*$", re.M),
    re.compile(r"^\s*HSCRIPT\s+m_hScriptInstance;.*$", re.M),
]


def overlay(sdk, directory):
    """The NextBot tree copied whole, with VScript taken out of the headers that have it: whole,
    because its headers include each other with quotes, found beside the includer first."""
    source = os.path.join(sdk, "src", "game", "server", "NextBot")
    shutil.copytree(source, directory, dirs_exist_ok=True)
    changed = []
    for path in glob.glob(os.path.join(directory, "**", "*.h"), recursive=True):
        text = open(path, encoding="latin-1").read()
        stripped = text
        for pattern in VSCRIPT:
            stripped = pattern.sub("", stripped)
        if stripped != text:
            with open(path, "w", encoding="latin-1") as out:
                out.write(stripped)
            changed.append(os.path.relpath(path, directory))
    return changed


def includes(sdk, first):
    src = os.path.join(sdk, "src")
    nextbot = [] if first else ["game/server/NextBot", "game/server/NextBot/Path"]
    dirs = first + [os.path.join(d, "Path") for d in first] + ["game/server"] + nextbot + ["game/shared",
                    "public", "public/tier0", "public/tier1", "common"]
    return [f"-I{d if os.path.isabs(d) else os.path.join(src, d)}" for d in dirs]


def compile_abi(abi, sdk, first, work):
    """clang's record and vtable dumps of the probe, as text, for one ABI."""
    probe = os.path.join(work, "probe.cpp")
    with open(probe, "w") as out:
        out.write(PROBE)
    flags = ["-std=gnu++17", "-w", "-ferror-limit=0", "-S", "-emit-llvm", "-o", os.devnull,
             "-Xclang", "-fdump-record-layouts", "-Xclang", "-fdump-vtable-layouts",
             "-DGAME_DLL", "-DNEXT_BOT"] + DEFINES[abi]
    stub = os.path.join(work, f"stub_{abi}")
    os.makedirs(stub, exist_ok=True)
    flags += ["-isystem", stub, "-D__restrict="]  # RESTRICT on a member function: no layout in it
    if abi == "msvc":
        # no Windows sysroot: clang's builtin headers, an empty stub for every other system
        # header, and the shim for the C runtime names the SDK's headers use
        with open(os.path.join(stub, "crt_shim.h"), "w") as out:
            out.write(CRT_SHIM)
        resource = subprocess.run(["clang++", "-print-resource-dir"], capture_output=True, text=True,
                                  check=True).stdout.strip()
        flags += ["-nostdinc", "-nostdinc++", "-isystem", os.path.join(resource, "include"), "-include", "crt_shim.h"]
    cmd = ["clang++", "-target", TRIPLE[abi]] + flags + includes(sdk, first) + [probe]
    for _ in range(60):  # stub each system header the target's sysroot lacks
        run = subprocess.run(cmd, capture_output=True, text=True)
        missing = re.search(r"fatal error: '([^']+)' file not found", run.stderr)
        if not missing:
            break
        stub = os.path.join(work, f"stub_{abi}", missing.group(1))
        os.makedirs(os.path.dirname(stub), exist_ok=True)
        open(stub, "a").close()
    errors = [line for line in run.stderr.splitlines() if " error: " in line]
    if os.environ.get("SDK_LAYOUT_ERRORS"):
        print("\n".join(errors))
    return run.stdout + run.stderr, errors


def plain(name):
    return re.sub(r"\b(class|struct) ", "", name).strip()


def parse_records(text, wanted):
    """name → { size, fields: { name: offset } } for the classes asked."""
    found = {}
    for block in text.split("*** Dumping AST Record Layout")[1:]:
        lines = block.strip("\n").splitlines()
        head = re.match(r"\s*0 \| (?:class|struct) (.+)$", lines[0])
        if not head or plain(head.group(1)) not in wanted or plain(head.group(1)) in found:
            continue
        fields, depth0 = {}, None
        for line in lines[1:]:
            m = re.match(r"\s*(\d+)(?::\d+-\d+)? \|( +)(.*)$", line)
            if m:
                indent = len(m.group(2))
                if depth0 is None:
                    depth0 = indent
                if indent == depth0:  # the class's own members and bases, not theirs
                    fields[m.group(3).strip()] = int(m.group(1))
            size = re.search(r"\[sizeof=(\d+)", line)
            if size:
                found[plain(head.group(1))] = {"size": int(size.group(1)), "fields": fields}
                break
    return found


def parse_vtables(text, abi):
    """class → its primary table's slots, as clang names them (Itanium: after offset and RTTI)."""
    tables = {}
    if abi == "itanium":
        for m in re.finditer(r"Vtable for '([^']+)' \((\d+) entries\)\.\n((?:\s+\d+ \|.*\n|\s+--.*\n)+)", text):
            name = plain(m.group(1))
            if name in tables:
                continue
            rows, slots, primary = m.group(3).splitlines(), [], True
            for row in rows:
                r = re.match(r"\s+(\d+) \| (.*)$", row)
                if not r:
                    continue
                entry = r.group(2)
                if entry.startswith("offset_to_top") or entry.endswith(" RTTI"):
                    if slots:
                        primary = False  # a secondary table begins
                    continue
                if primary:
                    slots.append(entry)
            tables[name] = slots
    else:
        for m in re.finditer(r"VFTable for '([^']+)'((?: in '[^']+')*) \((\d+) entries\)\.\n((?:\s+\d+ \|.*\n|\s+\[.*\n)+)",
                             text):
            path = re.findall(r"'([^']+)'", m.group(2))
            owner = plain(path[-1] if path else m.group(1))
            rows = [re.match(r"\s+\d+ \| (.*)$", row).group(1) for row in m.group(4).splitlines()
                    if re.match(r"\s+\d+ \|", row)]
            rows = [r for r in rows if not r.endswith(" RTTI")]
            # the first table named for a class is its primary (its own, or its first base's)
            tables.setdefault(owner, rows)
    return tables


def table(tables, sdk_class):
    return tables.get(sdk_class) or tables.get(sdk_class.split("<")[0], [])


# layout.rs's field constants, as the SDK names them: (class, member as clang prints it, ending).
FIELD_CONSTANTS = {
    "COMPONENT_INTERVAL": ("INextBotComponent", "m_curInterval"),
    "COMPONENT_BOT": ("INextBotComponent", "m_bot"),
    "INTENTION_QUERY": ("IIntention", "IContextualQuery (base)"),
    "BEHAVIOR_ACTION": ("Behavior", "m_action"),
    "BEHAVIOR_ME": ("Behavior", "m_me"),
    "KNOWN_HANDLE": ("CKnownEntity", "m_who"),
}
# layout.rs's Action struct (its offset_of! assertions), by the SDK's member names.
ACTION_MEMBERS = {"query_vtable": "IContextualQuery (base)", "behavior": "m_behavior", "parent": "m_parent",
                  "child": "m_child", "buried": "m_buriedUnderMe", "covering": "m_coveringMe",
                  "actor": "m_actor", "event": "m_eventResult", "started": "m_isStarted",
                  "suspended": "m_isSuspended"}


def member(record, name):
    """A member's offset by its name's ending (clang prefixes its type)."""
    for field, offset in record["fields"].items():
        if field == name or field.endswith(" " + name) or field.endswith(name):
            return offset
    return None


def check_fields(result, constants):
    """layout.rs's fields and sizes against the compiler's, on both ABIs: (lines, failed)."""
    lines, failed = [], False
    text = open(nextbot_layout.LAYOUT_RS).read()
    expected = {}
    for const, (cls, name) in FIELD_CONSTANTS.items():
        expected[f"{const} ({cls}::{name})"] = (PROBE_CLASSES[cls], name, constants[const])
    for rust, value in re.findall(r"offset_of!\(Action, (\w+)\),\s*(0x[0-9a-fA-F]+)", text):
        expected[f"Action.{rust} ({ACTION_MEMBERS[rust]})"] = (PROBE_CLASSES["Action"], ACTION_MEMBERS[rust], int(value, 16))
    sizes = {"Action": int(re.search(r"size_of::<Action>\(\),\s*(0x[0-9a-fA-F]+)", text).group(1), 16),
             "Behavior": constants["BEHAVIOR_WORDS"] * 8}
    for label, (cls, name, want) in expected.items():
        got = [member(result[abi]["records"].get(cls, {"fields": {}}), name) for abi in ("msvc", "itanium")]
        bad = any(g != want for g in got)
        failed |= bad
        lines.append(f"  {'DIFFERS' if bad else 'agrees '} {label}: {want:#x}; msvc {fmt(got[0])}, itanium {fmt(got[1])}")
    for cls, want in sizes.items():
        got = [result[abi]["records"].get(PROBE_CLASSES[cls], {}).get("size") for abi in ("msvc", "itanium")]
        bad = any(g != want for g in got)
        failed |= bad
        lines.append(f"  {'DIFFERS' if bad else 'agrees '} sizeof {cls}: {want:#x}; msvc {fmt(got[0])}, itanium {fmt(got[1])}")
    return lines, failed


def fmt(value):
    return "none" if value is None else f"{value:#x}"


def slot_of(slots, cls, name, argument):
    hits = []
    for i, entry in enumerate(slots):
        head = entry.split("(")[0]
        method = head.rsplit("::", 1)[-1]
        if name == "~":
            if "~" in method:
                return i
            continue
        if method != name:
            continue
        args = entry[entry.find("(") + 1:entry.find(")")].replace(" *", "*").replace(" &", "&")
        # clang names a template's own parameter, Actor, where GMod's class is CLuaNextBot
        if argument and argument.replace("CLuaNextBot", "Actor") not in args.split(",")[0]:
            continue
        hits.append(i)
    return hits[0] if len(hits) == 1 else None


def sdk_revision(sdk):
    run = subprocess.run(["git", "-C", sdk, "rev-parse", "HEAD"], capture_output=True, text=True)
    return run.stdout.strip() or None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sdk", default=os.path.expanduser("~/Repositories/source-sdk-2013"))
    parser.add_argument("--vscript", action="store_true", help="compile the SDK as it is, VScript and all")
    parser.add_argument("--json", help="write what the compiler laid out here")
    parser.add_argument("--write", help="save the compiler's layout of the classes NextSoldier uses as DIR/sdk2013.json")
    args = parser.parse_args()
    os.makedirs(WORK, exist_ok=True)
    work = tempfile.mkdtemp(dir=WORK)
    first = []
    if not args.vscript:
        over = os.path.join(work, "overlay")
        os.makedirs(over)
        print("without VScript:", ", ".join(overlay(args.sdk, over)) or "nothing to take out")
        first = [over]
    wanted = set(PROBE_CLASSES.values())
    result, failed = {}, False
    for abi in ("msvc", "itanium"):
        text, errors = compile_abi(abi, args.sdk, first, work)
        if errors:
            print(f"{abi}: {len(errors)} errors, e.g. {errors[0]}")
        result[abi] = {"records": parse_records(text, wanted), "vtables": parse_vtables(text, abi)}
        missing = wanted - set(result[abi]["records"])
        if missing:
            print(f"{abi}: no record layout for {sorted(missing)}")
    constants = nextbot_layout.layout_constants()
    linux = json.load(open(LINUX64))
    keys = {v: k for k, v in PROBE_CLASSES.items()}
    print("\nslots: the compiler against layout.rs (win64) and linux64.json")
    for const, (cls, name, argument) in nextbot_layout.SLOTS.items():
        sdk_class = PROBE_CLASSES.get(cls)
        if sdk_class is None:
            continue
        ms = slot_of(table(result["msvc"]["vtables"], sdk_class), cls, name, argument)
        it = slot_of(table(result["itanium"]["vtables"], sdk_class), cls, name, argument)
        saved_ms, saved_it = constants.get(const), linux["slots"].get(const, {}).get("slot")
        bad = (ms is not None and saved_ms is not None and ms != saved_ms) or \
              (it is not None and saved_it is not None and it != saved_it)
        if bad or ms is None or it is None:
            failed |= bad
            print(f"  {'DIFFERS' if bad else 'unread '} {const}: msvc {ms} (layout.rs {saved_ms}), "
                  f"itanium {it} (linux64 {saved_it})")
    compared = sum(1 for c in nextbot_layout.SLOTS if PROBE_CLASSES.get(nextbot_layout.SLOTS[c][0]))
    print(f"  {compared} slot constants compared; only those that differ or were not read are listed")
    print("\nfields: layout.rs against the compiler")
    lines, bad = check_fields(result, constants)
    print("\n".join(lines))
    failed |= bad
    print("\nrecords: size and fields, msvc / itanium")
    for cls in PROBE_CLASSES.values():
        ms, it = result["msvc"]["records"].get(cls), result["itanium"]["records"].get(cls)
        if not ms or not it:
            continue
        print(f"  {cls}: size {ms['size']:#x} / {it['size']:#x}")
        for field in ms["fields"]:
            if field in it["fields"]:
                a, b = ms["fields"][field], it["fields"][field]
                print(f"    {field}: {a:#x} / {b:#x}{'' if a == b else '   (differs)'}")
    if args.json:
        with open(args.json, "w") as out:
            json.dump(result, out, indent=2)
    if args.write:
        saved = {"sdk": sdk_revision(args.sdk), "without_vscript": not args.vscript, "actor": ACTOR,
                 "abis": {abi: {"triple": TRIPLE[abi], "records": result[abi]["records"],
                                "vtables": {k: table(result[abi]["vtables"], v) for k, v in PROBE_CLASSES.items()
                                            if table(result[abi]["vtables"], v)}}
                          for abi in result}}
        os.makedirs(args.write, exist_ok=True)
        with open(os.path.join(args.write, "sdk2013.json"), "w") as out:
            json.dump(saved, out, indent=2)
            out.write("\n")
        print("wrote", os.path.join(args.write, "sdk2013.json"))
    shutil.rmtree(work, ignore_errors=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
