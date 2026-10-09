#!/usr/bin/env python3
"""Build the dedicated server's own Garry's Mod root out of symlinks.

  server_root.py            build or refresh it, and print where it is

The Steam bottle's GarrysMod is the operator's install (a link into the
"Team Fortress 2" bottle), shared with the game the operator plays. The server needs
addons the game must not load twice (DrGBase, which the server cannot take
from the Workshop: it runs -noworkshop). So the server runs from
GarrysModServer beside it: every entry a symlink to the shared install, but
garrysmod/ is a folder whose addons/, data/ and cache/ are its own (the
server writes there, the game never reads them). addons/ links each of the
shared addons, and server_mounts, whose autorun (server_root/mounts.lua)
mounts each Workshop archive in SERVER_WORKSHOP, linked as cache/<name>.gma
(GMod ignores a loose .gma in addons/). Nothing is copied but TF2's
sound scripts that GMod's own files of the same name hide on a server
(mount.cfg puts TF2 under "GAME", where they shadow it, and there is no
"tf" path): TF_SCRIPTS are extracted from TF2's pak into the server's own
data/ on every build, where wetsand/sh_soundscripts.lua reads them.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

from vpk import Vpk

STEAMAPPS = Path.home() / "Library/Application Support/CrossOver/Bottles/Steam/drive_c/Steam/steamapps"
SHARED = STEAMAPPS / "common" / "GarrysMod"
ROOT = STEAMAPPS / "common" / "GarrysModServer"
ROOT_WINDOWS = r"C:\Steam\steamapps\common\GarrysModServer"
WORKSHOP = STEAMAPPS.parents[3] / "Team Fortress 2/drive_c/Steam/steamapps/workshop/content/4000"
TF = STEAMAPPS.parents[3] / "Team Fortress 2/drive_c/Steam/steamapps/common/Team Fortress 2/tf"
TF_PAK = "tf2_misc_dir.vpk"
# TF2's sound scripts a server's "GAME" path finds as GMod's: the manifest
# and the four it lists that GMod's content shadows (measured on pl_upward)
TF_SCRIPTS = (
    "scripts/game_sounds_manifest.txt",
    "scripts/game_sounds.txt",
    "scripts/game_sounds_physics.txt",
    "scripts/game_sounds_weapons.txt",
    "scripts/game_sounds_player.txt",
)
TF_SCRIPTS_DIR = "sandcastle/tf_scripts"  # under the server's data/
# Workshop addons the server mounts: name -> item id
SERVER_WORKSHOP = {"drgbase": "1560118657", "ulib": "557962238", "ulx": "557962280"}
MOUNTS_LUA = Path(__file__).resolve().parent / "server_root" / "mounts.lua"
# garrysmod/ entries the server owns: never links into the operator's game
OWN = ("addons", "data", "cache", "console.log")


def link(path: Path, target: Path) -> None:
    if path.is_symlink() and path.readlink() == target:
        return
    if path.is_symlink():
        path.unlink()
    path.symlink_to(target)


@dataclass(frozen=True)
class Layout:
    shared: Path  # the operator's GarrysMod
    root: Path  # the server's, built here
    workshop: Path  # workshop/content/4000
    mounts_lua: Path
    tf: Path  # TF2's tf/, which holds TF_PAK


LAYOUT = Layout(SHARED, ROOT, WORKSHOP, MOUNTS_LUA, TF)


def workshop_archive(workshop: Path, item: str) -> Path:
    archives = sorted((workshop / item).glob("*.gma"))
    if len(archives) != 1:
        raise FileNotFoundError(f"Workshop item {item}: expected one .gma under {workshop / item}, found {len(archives)}")
    return archives[0]


def build(layout: Layout = LAYOUT) -> Path:
    layout.root.mkdir(exist_ok=True)
    for entry in layout.shared.iterdir():
        if entry.name != "garrysmod":
            link(layout.root / entry.name, entry)
    game = layout.root / "garrysmod"
    game.mkdir(exist_ok=True)
    for entry in (layout.shared / "garrysmod").iterdir():
        if entry.name not in OWN:
            link(game / entry.name, entry)
    for own in ("addons", "data", "cache"):
        (game / own).mkdir(exist_ok=True)
    addons = game / "addons"
    for entry in (layout.shared / "garrysmod" / "addons").iterdir():
        link(addons / entry.name, entry)
    autorun = addons / "server_mounts" / "lua" / "autorun" / "server"
    autorun.mkdir(parents=True, exist_ok=True)
    link(autorun / "server_mounts.lua", layout.mounts_lua)
    for name, item in SERVER_WORKSHOP.items():
        link(game / "cache" / f"{name}.gma", workshop_archive(layout.workshop, item))
    pak = Vpk.open(layout.tf / TF_PAK)
    for path in TF_SCRIPTS:
        target = game / "data" / TF_SCRIPTS_DIR / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(pak.read(path))
    return layout.root


def main() -> int:
    print(build())
    return 0


if __name__ == "__main__":
    sys.exit(main())
