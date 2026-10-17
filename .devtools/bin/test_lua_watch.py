"""lua_watch.py: the path GMod knows a file by, what changed between two
scans, and which running games hear about it. The games are fakes; no test
opens a socket."""
from pathlib import Path

import pytest

from lua_watch import Changes, Target, TargetDown, Watcher, gmod_path, scan_changes

ADDON = Path("/repo/addons/sandcastle")


def test_a_gamemode_file_is_known_by_its_path_under_the_addon():
    assert gmod_path(ADDON, ADDON / "gamemodes/sandcastle/gamemode/ws/sv_spectate.lua") == \
        "gamemodes/sandcastle/gamemode/ws/sv_spectate.lua"


def test_a_file_under_the_addons_lua_folder_is_known_by_its_path_under_lua():
    assert gmod_path(ADDON, ADDON / "lua/autorun/server/x.lua") == "autorun/server/x.lua"


def test_an_edited_file_is_modified_a_new_one_is_added_and_an_untouched_one_is_neither():
    before = {Path("a.lua"): 1, Path("b.lua"): 1}
    after = {Path("a.lua"): 2, Path("b.lua"): 1, Path("c.lua"): 1}
    assert scan_changes(before, after) == Changes(modified=[Path("a.lua")], added=[Path("c.lua")])


def test_a_deleted_file_is_no_change():
    assert scan_changes({Path("a.lua"): 1}, {}) == Changes(modified=[], added=[])


class FakeTarget(Target):
    def __init__(self, name: str, up: bool):
        self.name, self.up, self.sent = name, up, []

    def refresh(self, path: str) -> None:
        if not self.up:
            raise TargetDown(f"{self.name} is not running")
        self.sent.append(path)


def test_an_edit_reaches_every_running_game_and_skips_one_that_is_not():
    server, client = FakeTarget("server", up=True), FakeTarget("client", up=False)
    lines = []
    Watcher(ADDON, [server, client], lines.append).apply(
        Changes(modified=[ADDON / "gamemodes/sandcastle/gamemode/init.lua"], added=[]))
    assert server.sent == ["gamemodes/sandcastle/gamemode/init.lua"]
    assert client.sent == []
    assert lines == ["refreshed gamemodes/sandcastle/gamemode/init.lua on server"]


def test_an_edit_with_no_game_running_says_so():
    lines = []
    Watcher(ADDON, [FakeTarget("server", up=False)], lines.append).apply(
        Changes(modified=[ADDON / "gamemodes/sandcastle/gamemode/init.lua"], added=[]))
    assert lines == ["gamemodes/sandcastle/gamemode/init.lua changed; no game is running"]


def test_a_new_file_is_not_sent_since_lua_refresh_file_only_reruns_loaded_files():
    server, lines = FakeTarget("server", up=True), []
    Watcher(ADDON, [server], lines.append).apply(
        Changes(modified=[], added=[ADDON / "gamemodes/sandcastle/gamemode/new.lua"]))
    assert server.sent == []
    assert lines == ["gamemodes/sandcastle/gamemode/new.lua is new; it loads on the next map change"]


@pytest.mark.parametrize("path", ['a"b.lua', "a;b.lua", "a\nb.lua"])
def test_a_path_that_could_break_out_of_the_console_command_is_refused(path):
    with pytest.raises(ValueError):
        gmod_path(ADDON, ADDON / "gamemodes" / path)
