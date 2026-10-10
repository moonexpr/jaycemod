#!/usr/bin/env python3
"""Check Sandcastle's own names in Lua: no TF2 in them, and every hook and networked var has both ends.

  check_names.py                 check addon/ and tests/
  check_names.py DIR_OR_FILE...  check these instead

Fails (exit 1) on:
  - an old name: an identifier in code, or a whole name-shaped string, containing tf2
    (comments and prose strings are skipped, since they may cite or describe TF2);
  - one of our hooks (WS*, Sandcastle*, TF2*) that is added but never run;
  - a networked var (Global2, NW2, NW) that is read but never set.
Notes, without failing: our hooks run with no listener (a published event) and
vars set but never read. Keys built from a variable (key .. "team") are skipped.
"""
import re
import sys
from dataclasses import dataclass
from pathlib import Path

OUR_HOOK_PREFIXES = ("WS", "Sandcastle", "TF2")
OLD = re.compile(r"[Tt][Ff]2")
IDENTIFIER = re.compile(r"[A-Za-z_]\w*(?:[.:][A-Za-z_]\w*)*")
NAME_SHAPED = re.compile(r"[\w.:]+")
PLACEHOLDER = "@S{}@"
HOOK = re.compile(r"\bhook\.(Add|Run|Call)\(\s*(?:@S(\d+)@|([A-Za-z_]\w*))")
LOCAL_CONSTANT = re.compile(r"\blocal\s+([A-Za-z_]\w*)\s*=\s*@S(\d+)@")
VAR = re.compile(r"\b(Set|Get)(?:Global2|NW2|NW)\w+\(\s*@S(\d+)@(\s*\.\.)?")
LONG_OPEN = re.compile(r"\[(=*)\[")


@dataclass(frozen=True)
class LuaSource:
    """A Lua file split into code (comments blanked, strings as @S<n>@) and its strings."""

    path: str
    code: str
    strings: list[tuple[int, str]]

    @classmethod
    def parse(cls, path: str, text: str) -> "LuaSource":
        code: list[str] = []
        strings: list[tuple[int, str]] = []
        line, i, n = 1, 0, len(text)

        def add_string(body: str) -> None:
            code.append(PLACEHOLDER.format(len(strings)) + "\n" * body.count("\n"))
            strings.append((line, body))

        while i < n:
            if text.startswith("--", i):
                long = LONG_OPEN.match(text, i + 2)
                if long:
                    close = "]" + long.group(1) + "]"
                    end = text.find(close, long.end())
                    end = n if end < 0 else end + len(close)
                else:
                    end = text.find("\n", i)
                    end = n if end < 0 else end
                blanked = "\n" * text.count("\n", i, end)
                code.append(blanked)
                line += len(blanked)
                i = end
            elif text[i] in "\"'":
                quote, j = text[i], i + 1
                while j < n and text[j] != quote and text[j] != "\n":
                    j += 2 if text[j] == "\\" else 1
                add_string(text[i + 1 : j])
                i = j + 1
            elif (long := LONG_OPEN.match(text, i)):
                close = "]" + long.group(1) + "]"
                end = text.find(close, long.end())
                end = n if end < 0 else end
                body = text[long.end() : end]
                add_string(body)
                line += body.count("\n")
                i = end + len(close)
            else:
                if text[i] == "\n":
                    line += 1
                code.append(text[i])
                i += 1
        return cls(path, "".join(code), strings)

    def line_of(self, pos: int) -> int:
        return self.code.count("\n", 0, pos) + 1


@dataclass(frozen=True)
class Findings:
    old_names: list[tuple[str, int, str]]
    hooks_never_run: list[str]
    hooks_without_listener: list[str]
    vars_never_set: list[str]
    vars_never_read: list[str]

    @property
    def failed(self) -> bool:
        return bool(self.old_names or self.hooks_never_run or self.vars_never_set)


def check(sources: list[LuaSource]) -> Findings:
    old: list[tuple[str, int, str]] = []
    added, run, set_, got = set(), set(), set(), set()
    for src in sources:
        for m in IDENTIFIER.finditer(src.code):
            if OLD.search(m.group()):
                old.append((src.path, src.line_of(m.start()), m.group()))
        for line, body in src.strings:
            if OLD.search(body) and NAME_SHAPED.fullmatch(body):
                old.append((src.path, line, body))
        constants = {c.group(1): src.strings[int(c.group(2))][1] for c in LOCAL_CONSTANT.finditer(src.code)}
        for m in HOOK.finditer(src.code):
            name = src.strings[int(m.group(2))][1] if m.group(2) else constants.get(m.group(3), "")
            if name.startswith(OUR_HOOK_PREFIXES):
                (added if m.group(1) == "Add" else run).add(name)
        for m in VAR.finditer(src.code):
            name = src.strings[int(m.group(2))][1] + (".." if m.group(3) else "")
            (set_ if m.group(1) == "Set" else got).add(name)
    old.sort()
    return Findings(
        old_names=old,
        hooks_never_run=sorted(added - run),
        hooks_without_listener=sorted(run - added),
        vars_never_set=sorted(got - set_),
        vars_never_read=sorted(set_ - got),
    )


def lua_files(roots: list[Path]) -> list[Path]:
    return sorted(f for root in roots for f in ([root] if root.is_file() else root.rglob("*.lua")))


def main(argv: list[str]) -> int:
    repo = Path(__file__).resolve().parents[2]
    roots = [Path(a) for a in argv] or [repo / "addon", repo / "tests"]
    sources = [LuaSource.parse(str(f), f.read_text(errors="replace")) for f in lua_files(roots)]
    f = check(sources)
    for path, line, name in f.old_names:
        print(f"OLD NAME {path}:{line}: {name}")
    for name in f.hooks_never_run:
        print(f"HOOK ADDED, NEVER RUN: {name}")
    for name in f.vars_never_set:
        print(f"VAR READ, NEVER SET: {name}")
    for name in f.hooks_without_listener:
        print(f"note: hook run with no listener: {name}")
    for name in f.vars_never_read:
        print(f"note: var set, never read: {name}")
    print(f"checked {len(sources)} files: {'FAIL' if f.failed else 'ok'}")
    return 1 if f.failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
