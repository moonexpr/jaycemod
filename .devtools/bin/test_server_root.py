"""server_root.py's symlinked server root, built in a temporary folder: every
shared entry is a link, the server's own folders are real, and nothing is
copied."""
import lzma
import os
from pathlib import Path

import pytest

from server_root import SERVER_LUA, SERVER_WORKSHOP, TF_SCRIPTS, TF_SCRIPTS_DIR, Layout, build
from test_vpk import DIR_ARCHIVE, entry, write_pak

# a Workshop item from before .gma downloads: one LZMA-compressed .gma, as .bin
LEGACY = "949733637"
LEGACY_GMA = b"GMAD legacy"


@pytest.fixture
def layout(tmp_path: Path) -> Layout:
    shared = tmp_path / "GarrysMod"
    (shared / "garrysmod" / "addons" / "luadev").mkdir(parents=True)
    (shared / "garrysmod" / "gamemodes").mkdir()
    (shared / "garrysmod" / "data").mkdir()
    (shared / "garrysmod" / "console.log").write_text("the game's log")
    (shared / "srcds_win64.exe").write_text("exe")
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
    return Layout(shared, tmp_path / "GarrysModServer", workshop, lua, tf)


def test_every_shared_entry_is_a_link_and_the_servers_own_folders_are_real(layout):
    root = build(layout)
    assert (root / "srcds_win64.exe").resolve() == layout.shared / "srcds_win64.exe"
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


def test_nothing_is_copied_but_tf2s_hidden_sound_scripts_and_legacy_archives(layout):
    root = build(layout)
    files = sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and not p.is_symlink())
    assert files == sorted(
        [f"garrysmod/data/{TF_SCRIPTS_DIR}/{path}" for path in TF_SCRIPTS] + [f"garrysmod/cache/{legacy_name()}.gma"]
    )


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
    missing = Layout(layout.shared, layout.root, tmp_path / "empty", layout.lua, layout.tf)
    with pytest.raises(FileNotFoundError):
        build(missing)

