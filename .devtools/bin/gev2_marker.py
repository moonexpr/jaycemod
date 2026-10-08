#!/usr/bin/env python3
"""Set and restore the uncommitted marker lines that game events v2's client
tests (T1, T2, and phase E's stale-file check) put in an addon file the
dedicated server reads through main.

  gev2_marker.py set <file> <line>   put the line, tagged, at the top of a clean, tracked .lua file under addon/
  gev2_marker.py restore             put back every marked file's exact bytes
  gev2_marker.py status              list the marked files

The marker goes on the file's first line, not its last: a feature part ends
with `return View`, and Lua allows nothing after a chunk's final return.
Every marker line ends with the Lua comment TAG (-- GEV2_MARKER_DO_NOT_COMMIT),
so check_no_markers.py can refuse a commit that carries one; that is why
only .lua files are marked. The file must still compile with the marker
(luajit -b), or nothing is written. `set` refuses a file with uncommitted changes, because the operator
may be working on main, and a file already marked: restore first. `restore`
leaves alone a file that changed since it was marked, and says so.

The saved bytes are kept in .devtools/artifacts/gev2_marker.json until
restored. Every run restores in a `finally` (Markers.marking), or, from a
shell, with `trap 'python3 .devtools/bin/gev2_marker.py restore' EXIT`.
Markers are never committed: `git status --short` must be unchanged after.
Its git commands run with GIT_OPTIONAL_LOCKS=0, so they never take the
index.lock of a main the operator is committing on.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterator, List

__all__ = ["ADDON", "Markers", "Refused", "STATE_FILE", "TAG"]

REPO = Path(__file__).resolve().parents[2]
STATE_FILE = REPO / ".devtools" / "artifacts" / "gev2_marker.json"
ADDON = "addon"
TAG = "-- GEV2_MARKER_DO_NOT_COMMIT"  # ends every marker line; check_no_markers.py looks for it
LUA_SUFFIX = ".lua"
GIT_ENV = {**os.environ, "GIT_OPTIONAL_LOCKS": "0"}  # status never refreshes (and locks) the index


class Refused(Exception):
    """Nothing was written."""


def _git(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, env=GIT_ENV)


def _lua_error(text: bytes) -> str:
    """luajit's complaint about the chunk, or "" if it compiles."""
    result = subprocess.run(["luajit", "-b", "-", "/dev/null"], input=text, capture_output=True)
    return "" if result.returncode == 0 else result.stderr.decode("utf-8", "replace").strip()


def _encode(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def _decode(text: str) -> bytes:
    return base64.b64decode(text.encode("ascii"))


@dataclass(frozen=True)
class Markers:
    state_file: Path

    def marked(self) -> List[str]:
        return list(self._state())

    def set(self, file: Path, line: str) -> None:
        """Mark file with line, or raise Refused having written nothing."""
        path = Path(os.path.abspath(file))
        if "\n" in line or "\r" in line:
            raise Refused("a marker is one line")
        if str(path) in self._state():
            raise Refused(f"{path} is already marked; restore first")
        if not path.is_file():
            raise Refused(f"{path} is not a file")
        if path.suffix != LUA_SUFFIX:
            raise Refused(f"{path} is not a Lua file; a marker's tag is a Lua comment")
        top = _git(path.parent, "rev-parse", "--show-toplevel")
        if top.returncode != 0:
            raise Refused(f"{path} is not in a git work tree, so not under any addon/")
        root = Path(top.stdout.strip()).resolve()
        try:
            relative = path.resolve().relative_to(root)
        except ValueError:
            raise Refused(f"{path} is not inside its work tree {root}") from None
        if relative.parts[0] != ADDON:
            raise Refused(f"{relative} is not under {ADDON}/")
        if _git(root, "ls-files", "--error-unmatch", "--", str(relative)).returncode != 0:
            raise Refused(f"{relative} is not tracked")
        if _git(root, "status", "--porcelain", "--", str(relative)).stdout.strip():
            raise Refused(f"{relative} has uncommitted changes; it may be the operator's work")
        original = path.read_bytes()
        marked = f"{line} {TAG}".encode("utf-8") + b"\n" + original
        error = _lua_error(marked)
        if error:
            raise Refused(f"{relative} would not compile with the marker: {error}")
        state = self._state()
        state[str(path)] = {"original": _encode(original), "marked": _encode(marked)}
        self._save(state)
        path.write_bytes(marked)

    def restore(self) -> List[str]:
        """Put back every marked file's bytes; the problems, if any. A file
        that changed since it was marked is left alone and kept listed."""
        problems = []
        state = self._state()
        for name, saved in list(state.items()):
            path = Path(name)
            original, marked = _decode(saved["original"]), _decode(saved["marked"])
            current = path.read_bytes() if path.exists() else None
            if current == marked:
                path.write_bytes(original)
            elif current != original:
                problems.append(f"{name} changed since it was marked; left alone (its saved bytes are in "
                                f"{self.state_file})")
                continue
            del state[name]
        self._save(state)
        return problems

    @contextmanager
    def marking(self, file: Path, line: str) -> Iterator[None]:
        """Mark file for the block, and restore it whatever happens."""
        self.set(file, line)
        try:
            yield
        finally:
            self.restore()

    def _state(self) -> Dict[str, Dict[str, str]]:
        return json.loads(self.state_file.read_text()) if self.state_file.exists() else {}

    def _save(self, state: Dict[str, Dict[str, str]]) -> None:
        if state:
            self.state_file.parent.mkdir(parents=True, exist_ok=True)
            self.state_file.write_text(json.dumps(state, indent=1) + "\n")
        else:
            self.state_file.unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    s = sub.add_parser("set")
    s.add_argument("file", type=Path)
    s.add_argument("line")
    sub.add_parser("restore")
    sub.add_parser("status")
    args = ap.parse_args()
    markers = Markers(STATE_FILE)
    if args.action == "set":
        try:
            markers.set(args.file, args.line)
        except Refused as e:
            print(f"gev2_marker: refused: {e}", file=sys.stderr)
            return 1
        print(f"marked {args.file}")
        return 0
    if args.action == "restore":
        problems = markers.restore()
        for problem in problems:
            print(f"gev2_marker: {problem}", file=sys.stderr)
        return 1 if problems else 0
    for name in markers.marked():
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
