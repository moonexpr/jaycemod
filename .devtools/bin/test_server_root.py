"""server_root.py's symlinked server root, built in a temporary folder: every
shared entry is a link, the server's own folders are real, and nothing is
copied."""
from pathlib import Path

import pytest

from server_root import SERVER_WORKSHOP, Layout, build


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
        (workshop / item / "addon.gma").write_bytes(b"GMAD")
    mounts = tmp_path / "mounts.lua"
    mounts.write_text("-- mounts")
    return Layout(shared, tmp_path / "GarrysModServer", workshop, mounts)


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
    assert (addons / "server_mounts/lua/autorun/server/server_mounts.lua").resolve() == layout.mounts_lua
    for name, item in SERVER_WORKSHOP.items():
        assert (cache / f"{name}.gma").resolve() == layout.workshop / item / "addon.gma"


def test_nothing_is_copied(layout):
    root = build(layout)
    files = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink()]
    assert files == []


def test_building_again_changes_nothing(layout):
    root = build(layout)
    before = sorted((str(p), str(p.readlink()) if p.is_symlink() else "") for p in root.rglob("*"))
    build(layout)
    assert sorted((str(p), str(p.readlink()) if p.is_symlink() else "") for p in root.rglob("*")) == before


def test_a_workshop_item_not_downloaded_is_refused(layout, tmp_path):
    missing = Layout(layout.shared, layout.root, tmp_path / "empty", layout.mounts_lua)
    with pytest.raises(FileNotFoundError):
        build(missing)

