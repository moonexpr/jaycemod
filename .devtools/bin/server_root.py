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
shared addons, and server_mounts, whose lua/ links the server's own Lua in
server_root/ (SERVER_LUA): an autorun (mounts.lua) that mounts each Workshop
archive in SERVER_WORKSHOP, linked as cache/<name>.gma (GMod ignores a loose
.gma in addons/), the gamemode's entities winning over a mounted addon's of
the same name, luadev's access on a LAN server, ULX's luadev commands, and
luadev's socket for server_lua.py. lua/ is its own too, every entry a link
but bin/, which adds SERVER_BINARIES (the server's LuaSocket) beside links to
the shared binaries.
A legacy Workshop item, downloaded as an LZMA-compressed .bin, is
decompressed to its cache/<name>.gma, again only when the download is newer.
Nothing else is copied but TF2's sound scripts that GMod's own files of the same name hide on a server
(mount.cfg puts TF2 under "GAME", where they shadow it, and there is no
"tf" path): TF_SCRIPTS are extracted from TF2's pak into the server's own
data/ on every build, where wetsand/sh_soundscripts.lua reads them.
"""
from __future__ import annotations

import lzma
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
SERVER_WORKSHOP = {
    "drgbase": "1560118657",
    "ulib": "557962238",
    "ulx": "557962280",
    "tf2_weapon_pack": "949733637",
    "bmesa_weapons": "3490724227",
    "bmesa_npc_weapons": "3497164530",
    "custom_loadout": "2675972006",
    "sound_browser": "2718685926",
}
SERVER_LUA_DIR = Path(__file__).resolve().parent / "server_root"
# the server's own Lua: path under server_mounts/lua/ -> file in SERVER_LUA_DIR
SERVER_LUA = {
    "autorun/server/server_mounts.lua": "mounts.lua",
    "autorun/server/luadev_lan.lua": "luadev_lan.lua",
    "autorun/server/hotswap.lua": "hotswap.lua",  # wetsand_hotswap_module, wetsand_hotswap_feature
    "autorun/gamemode_entities.lua": "gamemode_entities.lua",  # shared: the gamemode's entities win
    "ulx/modules/sh/luadev.lua": "ulx_luadev.lua",  # ULX includes every module it finds, on both sides
    "autorun/server/luadev_socket.lua": "luadev_socket.lua",  # server_lua.py's listener on 127.0.0.1:27098
}
# binary modules only the server loads: name in its lua/bin -> file in the shared lua/bin.
# GMod's server requires gmsv_<name>_win64.dll; luadev's socket build is plain
# LuaSocket against lua_shared, the same on either side (luadev_socket.lua)
SERVER_BINARIES = {"gmsv_luasocket_win64.dll": "gmcl_luasocket_win64.dll"}
# garrysmod/ entries the server owns: never links into the operator's game
OWN = ("addons", "data", "cache", "lua", "console.log")


def own_dir(path: Path) -> None:
    """A real folder at `path`, replacing a link an older build left there."""
    if path.is_symlink():
        path.unlink()
    path.mkdir(exist_ok=True)


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
    lua: Path  # SERVER_LUA's folder
    tf: Path  # TF2's tf/, which holds TF_PAK


LAYOUT = Layout(SHARED, ROOT, WORKSHOP, SERVER_LUA_DIR, TF)


def workshop_archive(workshop: Path, item: str) -> Path:
    """The item's download: one .gma, or one legacy .bin (an LZMA-compressed .gma)."""
    archives = sorted((workshop / item).glob("*.gma")) + sorted((workshop / item).glob("*.bin"))
    if len(archives) != 1:
        raise FileNotFoundError(f"Workshop item {item}: expected one .gma or .bin under {workshop / item}, found {len(archives)}")
    return archives[0]


def place_archive(path: Path, archive: Path) -> None:
    """A .gma is linked; a legacy .bin is decompressed, again only when the download is newer."""
    if archive.suffix == ".gma":
        link(path, archive)
        return
    if path.is_symlink():
        path.unlink()
    if path.exists() and path.stat().st_mtime >= archive.stat().st_mtime:
        return
    path.write_bytes(lzma.decompress(archive.read_bytes(), format=lzma.FORMAT_ALONE))


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
    for own in ("addons", "data", "cache", "lua", "lua/bin"):
        own_dir(game / own)
    shared_lua = layout.shared / "garrysmod" / "lua"
    for entry in shared_lua.iterdir():
        if entry.name != "bin":
            link(game / "lua" / entry.name, entry)
    for entry in (shared_lua / "bin").iterdir():
        link(game / "lua" / "bin" / entry.name, entry)
    for name, source in SERVER_BINARIES.items():
        link(game / "lua" / "bin" / name, shared_lua / "bin" / source)
    addons = game / "addons"
    for entry in (layout.shared / "garrysmod" / "addons").iterdir():
        link(addons / entry.name, entry)
    for path, source in SERVER_LUA.items():
        target = addons / "server_mounts" / "lua" / path
        target.parent.mkdir(parents=True, exist_ok=True)
        link(target, layout.lua / source)
    for name, item in SERVER_WORKSHOP.items():
        place_archive(game / "cache" / f"{name}.gma", workshop_archive(layout.workshop, item))
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
