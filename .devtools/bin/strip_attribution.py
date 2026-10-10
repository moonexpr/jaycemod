#!/usr/bin/env python3
"""Rewrite a branch's history without Claude attribution in its messages.

    strip_attribution.py OLDEST [TIP]

Every commit from OLDEST to TIP (default HEAD's branch) is rebuilt with
git commit-tree: the same tree, parents mapped to their rewrites, the same
author and committer and dates, and the message without its Co-Authored-By,
Claude-Session and "Generated with Claude Code" lines. A commit whose message
and parents are unchanged is kept as it is, signature and all. The working
tree and index are never touched, so uncommitted work survives; the branch
moves only if it still points at TIP. Prints the new tip; pushing it is the
caller's step (git push --force-with-lease).
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ATTRIBUTION = re.compile(
    r"^(Co-Authored-By: .*(Claude|anthropic\.com).*"
    r"|Claude-Session: .*"
    r"|🤖 Generated with \[Claude Code\].*"
    r"|https://claude\.ai/code/session_\S+)$",
    re.IGNORECASE,
)


def stripped(message: str) -> str:
    """The message without its attribution lines or the blank lines they leave at the end."""
    kept = [line for line in message.splitlines() if not ATTRIBUTION.match(line)]
    return "\n".join(kept).rstrip() + "\n"


@dataclass(frozen=True)
class Commit:
    sha: str
    tree: str
    parents: tuple[str, ...]
    author: tuple[str, str, str]  # name, email, date
    committer: tuple[str, str, str]
    message: str


@dataclass(frozen=True)
class Git:
    repo: Path
    sign: bool

    def run(self, *args: str, env: dict | None = None, stdin: str | None = None) -> str:
        return subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True,
                              text=True, input=stdin, env=env).stdout

    def commits(self, oldest: str, tip: str) -> list[str]:
        return self.run("rev-list", "--reverse", "--topo-order", f"{oldest}^..{tip}").split()

    def read(self, sha: str) -> Commit:
        fields = self.run("show", "-s", "--format=%T%n%P%n%an%n%ae%n%aI%n%cn%n%ce%n%cI", sha).split("\n")
        raw = self.run("cat-file", "commit", sha)
        return Commit(sha, fields[0], tuple(fields[1].split()), tuple(fields[2:5]), tuple(fields[5:8]),
                      raw.split("\n\n", 1)[1])

    def write(self, c: Commit, parents: tuple[str, ...], message: str) -> str:
        env = dict(os.environ,
                   GIT_AUTHOR_NAME=c.author[0], GIT_AUTHOR_EMAIL=c.author[1], GIT_AUTHOR_DATE=c.author[2],
                   GIT_COMMITTER_NAME=c.committer[0], GIT_COMMITTER_EMAIL=c.committer[1],
                   GIT_COMMITTER_DATE=c.committer[2])
        sign = ["-c", "gpg.program=gpg-loopback", "commit-tree", "-S"] if self.sign else ["commit-tree", "--no-gpg-sign"]
        args = [a for p in parents for a in ("-p", p)]
        return self.run(*sign, c.tree, *args, env=env, stdin=message).strip()


def rewrite(git: Git, oldest: str, tip: str) -> str:
    """The rewritten tip: each commit from oldest on, rebuilt only where its message or parents change."""
    mapped: dict[str, str] = {}
    for sha in git.commits(oldest, tip):
        c = git.read(sha)
        parents = tuple(mapped.get(p, p) for p in c.parents)
        message = stripped(c.message)
        if parents == c.parents and message == c.message:
            mapped[sha] = sha
            continue
        mapped[sha] = git.write(c, parents, message)
    return mapped[git.run("rev-parse", tip).strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("oldest")
    parser.add_argument("tip", nargs="?", default="HEAD")
    args = parser.parse_args()
    git = Git(Path.cwd(), sign=True)
    branch = git.run("symbolic-ref", "HEAD").strip()
    tip = git.run("rev-parse", args.tip).strip()
    new = rewrite(git, args.oldest, tip)
    if git.run("rev-parse", f"{new}^{{tree}}") != git.run("rev-parse", f"{tip}^{{tree}}"):
        sys.exit("the rewrite's tree differs from the tip's; branch left alone")
    git.run("update-ref", "-m", "strip_attribution", branch, new, tip)
    print(new)


if __name__ == "__main__":
    main()
