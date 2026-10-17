"""server_root.py's symlinked server root, built in a temporary folder: every
shared entry is a link, the server's own folders are real, and nothing is
copied."""
import lzma
import os
import struct
from pathlib import Path

import pytest

from server_root import LUADEV_PORT_FILE, REPO_ADDONS, ROOT, ROOT_WINDOWS, SERVER_BINARIES, SERVER_LUA, SERVER_EXE, SERVER_WORKSHOP, TF_SCRIPTS,\
    TF_SCRIPTS_DIR, Instance, Layout, NotAnExe, build, console_exe
from test_vpk import DIR_ARCHIVE, entry, write_pak

# a Workshop item from before .gma downloads: one LZMA-compressed .gma, as .bin
LEGACY = "949733637"
LEGACY_GMA = b"GMAD legacy"

# a PE image's header, as far as the subsystem: e_lfanew at 0x3c, "PE\0\0", the
# 20-byte file header, and the optional header whose subsystem sits at +68
PE_OFFSET = 0x80
SUBSYSTEM_AT = PE_OFFSET + 4 + 20 + 68
GUI, CUI = 2, 3


def pe_image(subsystem: int, size: int = 0x200) -> bytes:
    image = bytearray(size)
    image[0:2] = b"MZ"
    struct.pack_into("<I", image, 0x3c, PE_OFFSET)
    image[PE_OFFSET:PE_OFFSET + 4] = b"PE\0\0"
    struct.pack_into("<H", image, SUBSYSTEM_AT, subsystem)
    image[-4:] = b"tail"
    return bytes(image)


@pytest.fixture
def layout(tmp_path: Path) -> Layout:
    shared = tmp_path / "GarrysMod"
    (shared / "garrysmod" / "addons" / "luadev").mkdir(parents=True)
    (shared / "garrysmod" / "gamemodes").mkdir()
    (shared / "garrysmod" / "data").mkdir()
    (shared / "garrysmod" / "lua" / "bin").mkdir(parents=True)
    (shared / "garrysmod" / "lua" / "includes").mkdir()
    for source in SERVER_BINARIES.values():
        (shared / "garrysmod" / "lua" / "bin" / source).write_bytes(b"MZ")
    (shared / "srcds.exe").write_text("the 32-bit server")
    (shared / "garrysmod" / "console.log").write_text("the game's log")
    (shared / SERVER_EXE).write_bytes(pe_image(GUI))
    workshop = tmp_path / "4000"
    for item in SERVER_WORKSHOP.values():
        (workshop / item).mkdir(parents=True)
        if item == LEGACY:
            (workshop / item / "123_legacy.bin").write_bytes(lzma.compress(LEGACY_GMA, format=lzma.FORMAT_ALONE))
        else:
            (workshop / item / "addon.gma").write_bytes(b"GMAD")
    lua = tmp_path / "server_root"
    lua.mkdir()
    for source in SERVER_LUA.values():
        (lua / source).write_text(f"-- {source}")
    tf = tmp_path / "tf"
    tf.mkdir()
    inline, files = b"", []
    for path in TF_SCRIPTS:
        body = f"// TF2's {path}".encode()
        folder, name = path.rsplit("/", 1)
        files.append(("txt", folder, name.removesuffix(".txt"), entry(0, b"", DIR_ARCHIVE, len(inline), len(body))))
        inline += body
    write_pak(tf, "tf2_misc", files, inline_data=inline)
    return Layout(shared, tmp_path / "GarrysModServer", workshop, lua, tf, 27100)


def test_every_shared_entry_is_a_link_and_the_servers_own_folders_are_real(layout):
    root = build(layout)
    assert (root / "srcds.exe").resolve() == layout.shared / "srcds.exe"
    assert (root / "garrysmod" / "gamemodes").resolve() == layout.shared / "garrysmod" / "gamemodes"
    for own in ("addons", "data", "cache"):
        path = root / "garrysmod" / own
        assert path.is_dir() and not path.is_symlink(), own
    assert not (root / "garrysmod" / "console.log").exists(), "the server writes its own log"


def test_the_shared_addons_are_linked_and_the_workshop_archives_land_in_cache(layout):
    root = build(layout)
    addons, cache = root / "garrysmod" / "addons", root / "garrysmod" / "cache"
    assert (addons / "luadev").resolve() == layout.shared / "garrysmod" / "addons" / "luadev"
    for path, source in SERVER_LUA.items():
        assert (addons / "server_mounts/lua" / path).resolve() == layout.lua / source, path
    for name, item in SERVER_WORKSHOP.items():
        if item != LEGACY:
            assert (cache / f"{name}.gma").resolve() == layout.workshop / item / "addon.gma"


def test_the_repos_own_addons_are_linked_into_the_servers_addons(layout):
    addons = build(layout) / "garrysmod" / "addons"
    assert REPO_ADDONS, "the repo has addons of its own"
    for name, source in REPO_ADDONS.items():
        assert (addons / name).resolve() == source, name


def test_the_servers_lua_bin_is_its_own_and_links_the_server_binaries(layout):
    root = build(layout)
    lua, shared_lua = root / "garrysmod" / "lua", layout.shared / "garrysmod" / "lua"
    assert lua.is_dir() and not lua.is_symlink()
    assert (lua / "includes").resolve() == shared_lua / "includes"
    assert (lua / "bin").is_dir() and not (lua / "bin").is_symlink()
    for name, source in SERVER_BINARIES.items():
        assert (lua / "bin" / name).resolve() == shared_lua / "bin" / source, name
        assert (lua / "bin" / source).resolve() == shared_lua / "bin" / source, "the shared binaries stay"
    assert sorted(p.name for p in (shared_lua / "bin").iterdir()) == sorted(SERVER_BINARIES.values()), \
        "nothing is added to the operator's install"


def test_a_server_root_whose_lua_was_a_link_gets_its_own(layout):
    layout.root.mkdir()
    (layout.root / "garrysmod").mkdir()
    (layout.root / "garrysmod" / "lua").symlink_to(layout.shared / "garrysmod" / "lua")
    lua = build(layout) / "garrysmod" / "lua"
    assert lua.is_dir() and not lua.is_symlink()


def legacy_name() -> str:
    return next(name for name, item in SERVER_WORKSHOP.items() if item == LEGACY)


def test_a_legacy_workshop_item_is_decompressed_into_cache(layout):
    gma = build(layout) / "garrysmod" / "cache" / f"{legacy_name()}.gma"
    assert not gma.is_symlink()
    assert gma.read_bytes() == LEGACY_GMA


def test_a_legacy_item_is_decompressed_again_only_when_its_download_is_newer(layout):
    gma = build(layout) / "garrysmod" / "cache" / f"{legacy_name()}.gma"
    gma.write_bytes(b"GMAD kept")
    build(layout)
    assert gma.read_bytes() == b"GMAD kept", "up to date: not rewritten"
    download = layout.workshop / LEGACY / "123_legacy.bin"
    later = gma.stat().st_mtime + 10
    os.utime(download, (later, later))
    build(layout)
    assert gma.read_bytes() == LEGACY_GMA


def test_nothing_is_copied_but_tf2s_hidden_sound_scripts_legacy_archives_and_the_luadev_port(layout):
    root = build(layout)
    files = sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and not p.is_symlink())
    assert files == sorted(
        [f"garrysmod/data/{TF_SCRIPTS_DIR}/{path}" for path in TF_SCRIPTS]
        + [f"garrysmod/cache/{legacy_name()}.gma", SERVER_EXE, f"garrysmod/data/{LUADEV_PORT_FILE}"]
    )


def test_the_server_exe_is_a_console_program_copy_and_the_shared_one_is_untouched(layout):
    exe = build(layout) / SERVER_EXE
    assert not exe.is_symlink()
    copy, shared = exe.read_bytes(), (layout.shared / SERVER_EXE).read_bytes()
    assert struct.unpack_from("<H", copy, SUBSYSTEM_AT)[0] == CUI
    assert struct.unpack_from("<H", shared, SUBSYSTEM_AT)[0] == GUI
    assert copy[:SUBSYSTEM_AT] == shared[:SUBSYSTEM_AT] and copy[SUBSYSTEM_AT + 2:] == shared[SUBSYSTEM_AT + 2:], \
        "only the subsystem differs"


def test_a_root_whose_exe_was_a_link_gets_the_copy_and_the_shared_exe_is_not_written(layout):
    layout.root.mkdir()
    (layout.root / SERVER_EXE).symlink_to(layout.shared / SERVER_EXE)
    exe = build(layout) / SERVER_EXE
    assert not exe.is_symlink()
    assert struct.unpack_from("<H", (layout.shared / SERVER_EXE).read_bytes(), SUBSYSTEM_AT)[0] == GUI


def test_the_exe_copy_follows_an_update_of_the_shared_exe(layout):
    exe = build(layout) / SERVER_EXE
    (layout.shared / SERVER_EXE).write_bytes(pe_image(GUI, size=0x400))
    later = exe.stat().st_mtime + 10
    os.utime(layout.shared / SERVER_EXE, (later, later))
    build(layout)
    assert len(exe.read_bytes()) == 0x400
    assert struct.unpack_from("<H", exe.read_bytes(), SUBSYSTEM_AT)[0] == CUI


@pytest.mark.parametrize("image", [b"", b"ZM" + bytes(0x200), pe_image(GUI)[:SUBSYSTEM_AT],
                                   pe_image(GUI).replace(b"PE\0\0", b"NE\0\0")])
def test_a_file_that_is_not_a_pe_image_is_refused(tmp_path, image):
    source = tmp_path / "bad.exe"
    source.write_bytes(image)
    with pytest.raises(NotAnExe):
        console_exe(tmp_path / "out.exe", source)


def test_tf2s_hidden_sound_scripts_are_extracted_into_the_servers_data(layout):
    root = build(layout)
    for path in TF_SCRIPTS:
        assert (root / "garrysmod" / "data" / TF_SCRIPTS_DIR / path).read_text() == f"// TF2's {path}"


def test_the_extracted_scripts_follow_tf2_on_every_build(layout):
    root = build(layout)
    stale = root / "garrysmod" / "data" / TF_SCRIPTS_DIR / TF_SCRIPTS[0]
    stale.write_text("stale")
    build(layout)
    assert stale.read_text() == f"// TF2's {TF_SCRIPTS[0]}"


def test_building_again_changes_nothing(layout):
    root = build(layout)
    before = sorted((str(p), str(p.readlink()) if p.is_symlink() else "") for p in root.rglob("*"))
    build(layout)
    assert sorted((str(p), str(p.readlink()) if p.is_symlink() else "") for p in root.rglob("*")) == before


def test_a_workshop_item_not_downloaded_is_refused(layout, tmp_path):
    missing = Layout(layout.shared, layout.root, tmp_path / "empty", layout.lua, layout.tf, layout.luadev_port)
    with pytest.raises(FileNotFoundError):
        build(missing)



# A second server beside the first (another agent's tests on one): each
# instance has its own root, so its own console.log, data/ and cache/.
def test_the_main_instance_keeps_the_servers_root_and_luadev_port():
    main = Instance(1)
    assert (main.root, main.root_windows, main.luadev_port) == (ROOT, ROOT_WINDOWS, 27098)


def test_another_instance_has_its_own_root_and_a_luadev_port_clear_of_the_games():
    second = Instance(2)
    assert second.root == ROOT.with_name("GarrysModServer-2")
    assert second.root_windows == ROOT_WINDOWS + "-2"
    assert second.luadev_port == 27100  # 27099 is socketdev's, in the operator's game
    assert Instance(3).luadev_port == 27102


def test_an_instance_below_one_is_refused():
    with pytest.raises(ValueError):
        Instance(0)


def test_the_build_tells_the_servers_lua_its_luadev_port(layout):
    build(layout)
    assert (layout.root / "garrysmod" / "data" / LUADEV_PORT_FILE).read_text() == "27100"
