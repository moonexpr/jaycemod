#!/usr/bin/env python3
r"""HolyLib (github.com/RaphaelIT7/gmod-holylib) for GMod's Linux server, fetched for server_root.py.

  holylib.py fetch      download the pinned release's linux64 files into .devtools/artifacts/holylib/
  holylib.py status     whether they are there and match

HolyLib is a server plugin: its .vdf in garrysmod/addons/ names its binary in
garrysmod/lua/bin/, which srcds loads at start. The dev workbench's dev.vprof
reads the engine's VProf through its vprof module. srcds.py start --runtime
docker --holylib links both files into the server's root (server_root.py's
LINUX_HOLYLIB) and starts it with every module off but vprof
(-holylib_startdisabled -holylib_enable_vprof 1), so nothing else HolyLib
detours touches the shared dev server. Started without --holylib, the links
are taken away again.

The release is pinned by tag and by each file's SHA-256: a new release is a
change here, its hashes checked by hand. The README's Linux 64 steps name
gmsv_holylib_linux.so, which is the 32-bit build; the 64-bit .vdf loads
gmsv_holylib_linux64.so, which is what is fetched. Windows (the CrossOver
runtime) is left out: HolyLib's vprof shows no hooks there.
"""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path
from typing import Callable, Dict

REPO = Path(__file__).resolve().parents[2]
DIR = REPO / ".devtools" / "artifacts" / "holylib"
RELEASE = "Release0.8"  # "HolyLib Serverplugin V0.8"
URL = "https://github.com/RaphaelIT7/gmod-holylib/releases/download/{release}/{name}"
# name -> SHA-256 of the release's file
FILES: Dict[str, str] = {
    "holylib_linux_64.vdf": "e343d644e0dd9296b5208768bb7a05b367da5a0fb604c8af9a127ffeeb0d0907",
    "gmsv_holylib_linux64.so": "e995edafd246de85aba5c9cb470e0303f66acae3b854ca042134abac833523b7",
}
# what the server is started with when it runs HolyLib: every module off but vprof
SERVER_ARGS = ["-holylib_startdisabled", "-holylib_enable_vprof", "1"]

Download = Callable[[str], bytes]


class Mismatch(ValueError):
    pass


def download(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(folder: Path = DIR, get: Download = download) -> Dict[str, Path]:
    """Each file of the release in `folder`, downloaded when missing or not the pinned one,
    refused unless it hashes to its pin; a refused file is never written."""
    folder.mkdir(parents=True, exist_ok=True)
    placed = {}
    for name, digest in FILES.items():
        path = folder / name
        if not (path.exists() and sha256(path.read_bytes()) == digest):
            data = get(URL.format(release=RELEASE, name=name))
            if sha256(data) != digest:
                raise Mismatch(f"{name} from {RELEASE} hashes to {sha256(data)}, not the pinned {digest}")
            partial = path.with_name(name + ".partial")
            partial.write_bytes(data)
            partial.replace(path)
        placed[name] = path
    return placed


def status(folder: Path = DIR) -> Dict[str, str]:
    """name -> "ok", "missing" or "mismatch"."""
    states = {}
    for name, digest in FILES.items():
        path = folder / name
        if not path.exists():
            states[name] = "missing"
        else:
            states[name] = "ok" if sha256(path.read_bytes()) == digest else "mismatch"
    return states


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    try:
        if action == "fetch":
            for name, path in fetch().items():
                print(f"{name}: {path}")
            return 0
        if action == "status":
            states = status()
            for name, state in states.items():
                print(f"{RELEASE} {name}: {state}")
            return 0 if all(state == "ok" for state in states.values()) else 1
    except (OSError, Mismatch) as e:
        print(f"holylib: {e}", file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
