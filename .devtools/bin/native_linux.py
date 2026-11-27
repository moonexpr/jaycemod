#!/usr/bin/env python3
"""Build the repo's binary modules for GMod's Linux server (srcds.py --runtime docker).

  native_linux.py        build every crate the server links a linux64 build of (gmod.toml's [native.linux64])

Each crate is built in a container (DOCKERFILE_DIR, made the first time it is
missing) on Ubuntu 22.04, the server image's: a module linked against a newer
glibc than the server's may not load there. The repo is mounted at its own
path (NextSoldier's crate reads foundation's by a relative path), the build
runs as the operator, and cargo keeps its downloads in .devtools/artifacts.
The output lands in each crate's target/x86_64-unknown-linux-gnu/release/,
where the server's root links it from (.devtools/gmod.toml's [native.linux64]).
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Callable, List

import gmod_plugin  # noqa: F401  (the gmod plugin's tools on sys.path)
from project import Project

REPO = Path(__file__).resolve().parents[2]
LINUX_TARGET = "x86_64-unknown-linux-gnu"
# the modules the server links, built for Linux: name in its lua/bin -> the build's output
LINUX_NATIVE_BINARIES = Project.load(REPO).native.get("linux64", {})
DOCKERFILE_DIR = REPO / ".devtools" / "docker" / "native-linux"
IMAGE = "sandcastle-native-linux:1"  # its tag goes up with every change to the Dockerfile
CARGO_HOME = REPO / ".devtools" / "artifacts" / "docker" / "cargo"


def crates() -> List[Path]:
    """The crates whose linux64 builds the server links, in the config's order:
    each output is <crate>/target/<target>/release/lib<name>.so."""
    return [path.parents[3] for path in LINUX_NATIVE_BINARIES.values() if LINUX_TARGET in path.parts]


def build_command(crate: Path, uid: int, gid: int) -> List[str]:
    return ["docker", "run", "--rm", "--user", f"{uid}:{gid}", "-e", f"CARGO_HOME={CARGO_HOME}",
            "-v", f"{REPO}:{REPO}", "-w", str(crate), IMAGE,
            "cargo", "build", "--release", "--target", LINUX_TARGET]


Run = Callable[..., subprocess.CompletedProcess]


def ensure_image(run: Run = subprocess.run) -> None:
    """Builds IMAGE from DOCKERFILE_DIR when docker does not have it."""
    inspected = run(["docker", "image", "inspect", IMAGE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if inspected.returncode != 0:
        run(["docker", "build", "-t", IMAGE, str(DOCKERFILE_DIR)], check=True)


def main() -> int:
    ensure_image()
    CARGO_HOME.mkdir(parents=True, exist_ok=True)
    for crate in crates():
        print(f"native_linux: {crate.relative_to(REPO)}", flush=True)
        subprocess.run(build_command(crate, os.getuid(), os.getgid()), check=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as e:
        print(f"native_linux: {' '.join(e.cmd[:2])} ... failed ({e.returncode})", file=sys.stderr)
        sys.exit(1)
