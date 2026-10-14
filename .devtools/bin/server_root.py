#!/usr/bin/env python3
"""Build the dedicated server's own Garry's Mod root out of symlinks.

  server_root.py [--instance N]   build or refresh it, and print where it is

The GModServer bottle's GarrysMod is the operator's install (a link into the
"Steam" bottle), shared with the game the operator plays. The server needs
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
data/ on every build, where ws/sh_soundscripts.lua reads them, and
SERVER_EXE: a copy marked a console program, rewritten when the shared one is
newer. As the GUI program it ships as, -console makes it open a console of its
own, which Wine draws as a window that prints ANSI colors raw; as a console
program started from srcds.py's pty it writes to that pty, colors and all.
"""
from __future__ import annotations

import lzma
import struct
import sys
import argparse
from dataclasses import dataclass
from pathlib import Path

from vpk import Vpk

STEAMAPPS = Path.home() / "Library/Application Support/CrossOver/Bottles/GModServer/drive_c/Steam/steamapps"
SHARED = STEAMAPPS / "common" / "GarrysMod"
ROOT = STEAMAPPS / "common" / "GarrysModServer"
ROOT_WINDOWS = r"C:\Steam\steamapps\common\GarrysModServer"
WORKSHOP = STEAMAPPS.parents[3] / "Steam/drive_c/Steam/steamapps/workshop/content/4000"
TF = STEAMAPPS.parents[3] / "Steam/drive_c/Steam/steamapps/common/Team Fortress 2/tf"
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
    "autorun/server/hotswap.lua": "hotswap.lua",  # ws_hotswap_module, ws_hotswap_feature
    "autorun/gamemode_entities.lua": "gamemode_entities.lua",  # shared: the gamemode's entities win
    "ulx/modules/sh/luadev.lua": "ulx_luadev.lua",  # ULX includes every module it finds, on both sides
    "autorun/server/luadev_socket.lua": "luadev_socket.lua",  # server_lua.py's listener on 127.0.0.1:27098
    "autorun/server/sandcastle_watch.lua": "sandcastle_watch.lua",  # Watch: events server_watch.py follows
    "autorun/server/sandcastle_debug.lua": "sandcastle_debug.lua",  # breakpoints and Lua errors, for gmod_mcp.py
}
WATCH_LOG = "sandcastle_watch.txt"  # under the server's data/
# binary modules only the server loads: name in its lua/bin -> file in the shared lua/bin.
# GMod's server requires gmsv_<name>_win64.dll; luadev's socket build is plain
# LuaSocket against lua_shared, the same on either side (luadev_socket.lua)
SERVER_BINARIES = {"gmsv_luasocket_win64.dll": "gmcl_luasocket_win64.dll"}
SERVER_EXE = "srcds_win64.exe"
# PE: e_lfanew at 0x3c names the "PE\\0\\0" signature; the optional header follows
# the 20-byte file header, with the subsystem at +68 in PE32 and PE32+ alike
PE_POINTER = 0x3c
PE_SIGNATURE = b"PE\0\0"
SUBSYSTEM_OFFSET = 4 + 20 + 68
CONSOLE_SUBSYSTEM = 3  # IMAGE_SUBSYSTEM_WINDOWS_CUI
# garrysmod/ entries the server owns: never links into the operator's game
OWN = ("addons", "data", "cache", "lua", "console.log")
# luadev's socket (luadev_socket.lua, server_lua.py): the main server's port,
# the others' from LUADEV_PORT_STEP above it, so 27099, socketdev's in the
# operator's game, stays clear; the build writes it to the root's data/
LUADEV_PORT = 27098
LUADEV_PORT_STEP = 2
LUADEV_PORT_FILE = "sandcastle_luadev_port.txt"
LOCALHOST = "127.0.0.1"
MAIN_INSTANCE = 1


@dataclass(frozen=True)
class Instance:
    """One of the dedicated servers that may run side by side: the first is
    the main one, at ROOT; instance n runs from its own GarrysModServer-n,
    with its own console.log, data/ and cache/."""
    number: int

    def __post_init__(self):
        if self.number < MAIN_INSTANCE:
            raise ValueError(f"instance {self.number}: instances count from {MAIN_INSTANCE}")

    @property
    def suffix(self) -> str:
        return "" if self.number == MAIN_INSTANCE else f"-{self.number}"

    @property
    def root(self) -> Path:
        return ROOT.with_name(ROOT.name + self.suffix)

    @property
    def root_windows(self) -> str:
        return ROOT_WINDOWS + self.suffix

    @property
    def luadev_port(self) -> int:
        return LUADEV_PORT + LUADEV_PORT_STEP * (self.number - MAIN_INSTANCE)


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
    luadev_port: int  # luadev_socket.lua's, written to LUADEV_PORT_FILE

    @classmethod
    def of(cls, instance: Instance) -> "Layout":
        return cls(SHARED, instance.root, WORKSHOP, SERVER_LUA_DIR, TF, instance.luadev_port)


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


class NotAnExe(ValueError):
    pass


def console_exe(path: Path, source: Path) -> None:
    """A copy of the PE image `source` at `path`, its subsystem the console's;
    written again only when `source` is newer."""
    if path.is_symlink():
        path.unlink()
    if path.exists() and path.stat().st_mtime >= source.stat().st_mtime:
        return
    image = bytearray(source.read_bytes())
    if image[:2] != b"MZ" or len(image) < PE_POINTER + 4:
        raise NotAnExe(f"{source} is not a PE image")
    (pe,) = struct.unpack_from("<I", image, PE_POINTER)
    if image[pe:pe + 4] != PE_SIGNATURE or len(image) < pe + SUBSYSTEM_OFFSET + 2:
        raise NotAnExe(f"{source} is not a PE image")
    struct.pack_into("<H", image, pe + SUBSYSTEM_OFFSET, CONSOLE_SUBSYSTEM)
    path.write_bytes(image)


def build(layout: Layout) -> Path:
    layout.root.mkdir(exist_ok=True)
    for entry in layout.shared.iterdir():
        if entry.name not in ("garrysmod", SERVER_EXE):
            link(layout.root / entry.name, entry)
    console_exe(layout.root / SERVER_EXE, layout.shared / SERVER_EXE)
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
    (game / "data" / LUADEV_PORT_FILE).write_text(str(layout.luadev_port))
    return layout.root


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--instance", type=int, default=MAIN_INSTANCE)
    print(build(Layout.of(Instance(ap.parse_args().instance))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
