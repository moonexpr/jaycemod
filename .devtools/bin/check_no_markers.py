#!/usr/bin/env python3
"""Fail when a game events v2 marker line is staged or committed.

  check_no_markers.py [--repo PATH] staged        the index adds no marker line under addon/
  check_no_markers.py [--repo PATH] range A..B    no commit in A..B adds a marker line under addon/

A marker line is one gev2_marker.py wrote: it ends with gev2_marker.TAG
(-- GEV2_MARKER_DO_NOT_COMMIT), and only files under addon/ are ever marked,
so only added lines there count; the tools and docs that name the tag never
do. Each finding prints as `<commit or "staged"> <file>: <line>`.

Exit 0 when there is none, 1 when there is any, 2 when git cannot answer (a
bad range or not a repository): an error is never a pass. git runs with
GIT_OPTIONAL_LOCKS=0, so the check never takes the repository's index.lock.

As a pre-commit hook it would be `check_no_markers.py staged`; this repo
installs no git hooks, and this script installs none.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gev2_marker import ADDON, GIT_ENV, REPO, TAG  # noqa: E402

__all__ = ["Finding", "GitFailed", "findings", "main"]

EXIT_FOUND = 1
EXIT_GIT_FAILED = 2
STAGED = "staged"
COMMIT_MARK = "commit "


class GitFailed(Exception):
    """git could not answer, so nothing is known to be clean."""


@dataclass(frozen=True)
class Finding:
    where: str  # a commit's short hash, or "staged"
    file: str
    line: str

    def text(self) -> str:
        return f"{self.where} {self.file}: {self.line}"


def _git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, errors="replace",
                            env=GIT_ENV)
    if result.returncode != 0:
        raise GitFailed(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def findings(patch: str, where: Optional[str]) -> List[Finding]:
    """The tagged lines a -U0 patch adds. where names every finding, or None
    to take it from `commit <hash>` lines (git log --format='commit %H')."""
    found = []
    file = ""
    current = where or ""
    for line in patch.splitlines():
        if line.startswith(COMMIT_MARK) and where is None:
            current = line[len(COMMIT_MARK):].strip()[:12]
        elif line.startswith("+++ "):
            file = line[len("+++ b/"):] if line.startswith("+++ b/") else line[len("+++ "):]
        elif line.startswith("+") and TAG in line:
            found.append(Finding(current, file, line[1:]))
    return found


def staged(repo: Path) -> List[Finding]:
    return findings(_git(repo, "diff", "--cached", "-U0", "--no-color", "--no-ext-diff", "--", ADDON), STAGED)


def in_range(repo: Path, spec: str) -> List[Finding]:
    return findings(_git(repo, "log", "-p", "-U0", "--no-color", "--no-ext-diff", "--format=commit %H", spec,
                         "--", ADDON), None)


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", type=Path, default=REPO)
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser(STAGED)
    r = sub.add_parser("range")
    r.add_argument("spec", help="A..B")
    args = ap.parse_args(argv)
    try:
        found = staged(args.repo) if args.action == STAGED else in_range(args.repo, args.spec)
    except GitFailed as e:
        print(f"check_no_markers: {e}", file=sys.stderr)
        return EXIT_GIT_FAILED
    for finding in found:
        print(finding.text())
    if found:
        print(f"check_no_markers: {len(found)} marker line(s) ({TAG}); restore with gev2_marker.py restore",
              file=sys.stderr)
        return EXIT_FOUND
    return 0


if __name__ == "__main__":
    sys.exit(main())
