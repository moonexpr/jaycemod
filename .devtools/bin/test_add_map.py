"""add_map.py: a Workshop map onto the running server, without a restart."""
import json
import lzma
from dataclasses import dataclass, field
from pathlib import Path

import pytest

import add_map
from add_map import (Blocked, DownloadFailed, Installed, MountFailed, NameTaken, NotAMap, NotAnItem, Request,
                     ServerGone, SteamCmd, Worker, WorkshopItem, go_live, hold_worker_lock, install, maps_in,
                     until_server_gone)
from gma import Gma, GmaFile, write_gma
from instances import FileLeases
from server_lua import Reply
from server_root import SERVER_MAPS, Instance, Layout, map_archive_name, read_added_maps

ITEM = WorkshopItem("3632274158")
INSTANCE = Instance(2)


def gma_of(*paths: str) -> bytes:
    return write_gma(Gma("a map", tuple(GmaFile(path, b"data") for path in paths)))


class FakeSteam:
    """Downloads by writing what it was given to steamcmd's folder."""

    def __init__(self, folder: Path, blob: bytes, file: str = "addon.gma"):
        self.folder, self.blob, self.file = folder, blob, file

    def download(self, item: WorkshopItem) -> None:
        (self.folder / item.id).mkdir(parents=True, exist_ok=True)
        (self.folder / item.id / self.file).write_bytes(self.blob)


@dataclass
class FakeBackend:
    up: bool = True
    humans: tuple = ()
    mounted: bool = True
    ran: list = field(default_factory=list)
    changed: list = field(default_factory=list)

    def alive(self, instance: Instance) -> bool:
        return self.up

    def lua(self, instance: Instance, code: str, timeout: float) -> Reply:
        self.ran.append(code)
        if "MountGMA" in code:
            return Reply([], ["true" if self.mounted else "false"], None, None)
        return Reply([], [json.dumps(list(self.humans))], None, None)

    def change_map(self, instance: Instance, map_name: str) -> None:
        self.changed.append(map_name)


@pytest.fixture
def layout(tmp_path):
    root = tmp_path / "root"
    (root / "garrysmod" / "cache").mkdir(parents=True)
    maps = tmp_path / "steamcmd"
    maps.mkdir()
    return Layout(tmp_path, root, tmp_path, tmp_path, tmp_path, 27100, maps)


@pytest.fixture
def leases(tmp_path):
    return FileLeases(tmp_path / "leases")


# The item, as the operator pastes it

@pytest.mark.parametrize("text", [
    "3632274158",
    "https://steamcommunity.com/sharedfiles/filedetails/?id=3632274158",
    "https://steamcommunity.com/sharedfiles/filedetails/?id=3632274158&searchtext=tunnels",
    "https://steamcommunity.com/workshop/filedetails/?l=german&id=3632274158",
])
def test_an_item_is_its_id_or_its_workshop_link(text):
    assert WorkshopItem.parse(text) == ITEM


@pytest.mark.parametrize("text", ["", "gm_flatgrass", "12a", "https://example.com/?id=", "1; rm -rf /"])
def test_anything_else_is_refused(text):
    with pytest.raises(NotAnItem):
        WorkshopItem.parse(text)


# The maps an archive holds

def test_the_maps_are_the_bsps_directly_under_maps(tmp_path):
    archive = tmp_path / "addon.gma"
    archive.write_bytes(gma_of("maps/gm_a.bsp", "maps/gm_a.nav", "maps/graphs/gm_a.ain", "maps/old/gm_b.bsp", "materials/x.vtf"))
    assert maps_in(archive) == ("gm_a",)


def test_a_map_is_named_as_mounts_lua_compares_it(tmp_path):
    archive = tmp_path / "addon.gma"
    archive.write_bytes(gma_of("maps/GM_Loud.bsp"))
    assert maps_in(archive) == ("gm_loud",)


def test_a_legacy_download_is_read_through_its_compression(tmp_path):
    archive = tmp_path / "123_legacy.bin"
    archive.write_bytes(lzma.compress(gma_of("maps/gm_old.bsp"), format=lzma.FORMAT_ALONE))
    assert maps_in(archive) == ("gm_old",)


# Downloading: steamcmd exits 0 whether or not it got the item

def test_steamcmd_is_asked_for_gmods_item():
    commands = []

    def run(command: list) -> str:
        commands.append(command)
        return f'Success. Downloaded item {ITEM.id} to "somewhere" (10 bytes)'

    SteamCmd(run).download(ITEM)
    assert commands == [["steamcmd", "+login", "anonymous", "+workshop_download_item", "4000", ITEM.id, "+quit"]]


def test_steamcmd_saying_anything_but_success_is_a_failed_download():
    with pytest.raises(DownloadFailed, match="No subscription"):
        SteamCmd(lambda command: "ERROR! Download item 1 failed (No subscription).").download(ITEM)


# Installing: the map is listed, so a later build keeps it, and linked into cache/

def test_installing_lists_the_map_and_links_its_archive(layout, tmp_path):
    added = tmp_path / "added.json"
    names = install(ITEM, FakeSteam(layout.maps, gma_of("maps/gm_new.bsp")), layout, added)
    assert names == Installed(ITEM, ("gm_new",))
    assert read_added_maps(added) == {"gm_new": ITEM.id}
    assert (layout.root / "garrysmod" / "cache" / map_archive_name(ITEM.id)).resolve() == layout.maps / ITEM.id / "addon.gma"


def test_installing_keeps_the_maps_already_listed(layout, tmp_path):
    added = tmp_path / "added.json"
    install(WorkshopItem("1"), FakeSteam(layout.maps, gma_of("maps/gm_one.bsp")), layout, added)
    install(WorkshopItem("2"), FakeSteam(layout.maps, gma_of("maps/gm_two.bsp")), layout, added)
    assert read_added_maps(added) == {"gm_one": "1", "gm_two": "2"}


def test_installing_a_legacy_download_decompresses_it_into_cache(layout, tmp_path):
    blob = gma_of("maps/gm_old.bsp")
    steam = FakeSteam(layout.maps, lzma.compress(blob, format=lzma.FORMAT_ALONE), "123_legacy.bin")
    install(ITEM, steam, layout, tmp_path / "added.json")
    assert (layout.root / "garrysmod" / "cache" / map_archive_name(ITEM.id)).read_bytes() == blob


def test_an_addon_with_no_map_is_refused_and_left_unlisted(layout, tmp_path):
    added = tmp_path / "added.json"
    with pytest.raises(NotAMap):
        install(ITEM, FakeSteam(layout.maps, gma_of("lua/autorun/x.lua")), layout, added)
    assert read_added_maps(added) == {}
    assert not (layout.root / "garrysmod" / "cache" / map_archive_name(ITEM.id)).exists()


def test_a_name_another_item_holds_is_refused(layout, tmp_path):
    added = tmp_path / "added.json"
    name = next(iter(SERVER_MAPS))
    with pytest.raises(NameTaken, match=name):
        install(ITEM, FakeSteam(layout.maps, gma_of(f"maps/{name}.bsp")), layout, added)
    assert read_added_maps(added) == {}


def test_a_pool_map_added_again_is_not_listed_twice(layout, tmp_path):
    added = tmp_path / "added.json"
    name, item = next(iter(SERVER_MAPS.items()))
    install(WorkshopItem(item), FakeSteam(layout.maps, gma_of(f"maps/{name}.bsp")), layout, added)
    assert read_added_maps(added) == {}


def test_adding_a_map_again_is_no_conflict_with_itself(layout, tmp_path):
    added = tmp_path / "added.json"
    steam = FakeSteam(layout.maps, gma_of("maps/gm_new.bsp"))
    install(ITEM, steam, layout, added)
    install(ITEM, steam, layout, added)
    assert read_added_maps(added) == {"gm_new": ITEM.id}


# Going live: mount it, then move the server, unless someone is using it

INSTALLED = Installed(ITEM, ("gm_new",))


def test_a_server_down_is_left_down(leases):
    backend = FakeBackend(up=False)
    outcome = go_live(INSTALLED, backend, leases, INSTANCE, None, False)
    assert backend.ran == [] and backend.changed == []
    assert "not running" in outcome


def test_an_empty_server_mounts_the_archive_then_changes_map(leases):
    backend = FakeBackend()
    go_live(INSTALLED, backend, leases, INSTANCE, None, False)
    assert f'game.MountGMA("cache/{map_archive_name(ITEM.id)}")' in backend.ran[0]
    assert backend.changed == ["gm_new"]


def test_a_mounted_map_joins_ulxs_list_on_the_server_and_its_clients(leases):
    backend = FakeBackend()
    go_live(Installed(ITEM, ("gm_a", "gm_b")), backend, leases, INSTANCE, None, False)
    assert '{"gm_a", "gm_b"}' in backend.ran[0]
    assert "ulx.maps" in backend.ran[0]
    assert 'ULib.clientRPC(nil, "ulx.populateClMaps", ulx.maps)' in backend.ran[0]


def test_a_mount_refused_stops_before_the_map_changes(leases):
    backend = FakeBackend(mounted=False)
    with pytest.raises(MountFailed):
        go_live(INSTALLED, backend, leases, INSTANCE, None, False)
    assert backend.changed == []


def test_players_keep_their_map_but_the_new_one_is_mounted(leases):
    backend = FakeBackend(humans=("someone",))
    outcome = go_live(INSTALLED, backend, leases, INSTANCE, None, False)
    assert backend.changed == []
    assert any("MountGMA" in code for code in backend.ran)
    assert "someone" in outcome and "changelevel gm_new" in outcome


def test_a_leased_server_keeps_its_map(leases):
    leases.take(INSTANCE, "ns_bench_run")
    backend = FakeBackend()
    outcome = go_live(INSTALLED, backend, leases, INSTANCE, None, False)
    assert backend.changed == []
    assert "ns_bench_run" in outcome


def test_asking_for_the_change_overrides_players(leases):
    backend = FakeBackend(humans=("someone",))
    go_live(INSTALLED, backend, leases, INSTANCE, None, True)
    assert backend.changed == ["gm_new"]


def test_asking_for_the_change_does_not_override_a_lease(leases):
    leases.take(INSTANCE, "ns_bench_run")
    backend = FakeBackend()
    with pytest.raises(Blocked, match="ns_bench_run"):
        go_live(INSTALLED, backend, leases, INSTANCE, None, True)
    assert backend.changed == []


def test_an_item_of_several_maps_waits_to_be_told_which(leases):
    backend = FakeBackend()
    outcome = go_live(Installed(ITEM, ("gm_a", "gm_b")), backend, leases, INSTANCE, None, False)
    assert backend.changed == []
    assert "gm_a" in outcome and "gm_b" in outcome


def test_an_item_of_several_maps_changes_to_the_one_named(leases):
    backend = FakeBackend()
    go_live(Installed(ITEM, ("gm_a", "gm_b")), backend, leases, INSTANCE, "gm_b", False)
    assert backend.changed == ["gm_b"]


def test_a_map_the_item_does_not_hold_is_refused_before_mounting(leases):
    backend = FakeBackend()
    with pytest.raises(NotAMap, match="gm_c"):
        go_live(INSTALLED, backend, leases, INSTANCE, "gm_c", False)
    assert backend.ran == []


# The worker: requests from `ulx addmap`, as lines of the watch log, answered in game

def said_by(backend: FakeBackend) -> list:
    return [code for code in backend.ran if "tsay" in code]


def serving(backend: FakeBackend, steam: FakeSteam, layout: Layout, leases: FileLeases, added: Path):
    return Worker(steam, backend, leases, INSTANCE, lambda: layout, added)


def request_line(**fields) -> str:
    return "12.5 add_map_request event " + json.dumps({"item": ITEM.id, "change": False} | fields)


def test_a_request_is_its_item_and_what_to_do_with_it():
    assert Request.parse('{"item": "3632274158", "map": "gm_b", "change": true}') == Request(ITEM, "gm_b", True)


def test_a_request_with_no_map_named_leaves_it_open():
    assert Request.parse('{"item": "3632274158", "map": "", "change": false}') == Request(ITEM, None, False)
    assert Request.parse('{"item": "3632274158", "change": false}') == Request(ITEM, None, False)


def test_a_request_for_rubbish_is_refused():
    with pytest.raises(NotAnItem):
        Request.parse('{"item": "gm_flatgrass", "change": false}')


def test_a_request_is_acknowledged_then_installed_and_answered(layout, leases, tmp_path):
    backend = FakeBackend()
    worker = serving(backend, FakeSteam(layout.maps, gma_of("maps/gm_new.bsp")), layout, leases, tmp_path / "added.json")
    worker.on_line(request_line())
    assert add_map.ACK_TIMER in backend.ran[0]
    assert backend.changed == ["gm_new"]
    assert read_added_maps(tmp_path / "added.json") == {"gm_new": ITEM.id}
    assert "gm_new" in said_by(backend)[-1]


def test_a_request_passes_on_the_change_it_asked_for(layout, leases, tmp_path):
    backend = FakeBackend(humans=("someone",))
    worker = serving(backend, FakeSteam(layout.maps, gma_of("maps/gm_new.bsp")), layout, leases, tmp_path / "added.json")
    worker.on_line(request_line(change=True))
    assert backend.changed == ["gm_new"]


def test_a_refusal_is_told_in_game_and_the_worker_goes_on(layout, leases, tmp_path):
    backend = FakeBackend()
    worker = serving(backend, FakeSteam(layout.maps, gma_of("lua/autorun/x.lua")), layout, leases, tmp_path / "added.json")
    worker.on_line(request_line())
    assert "holds no maps" in said_by(backend)[-1]


def test_an_answer_quoting_a_quote_stays_a_lua_string(layout, leases, tmp_path):
    backend = FakeBackend()
    worker = serving(backend, FakeSteam(layout.maps, gma_of("maps/gm_new.bsp")), layout, leases, tmp_path / "added.json")
    worker.say('a "quoted" name')
    assert r'a \"quoted\" name' in said_by(backend)[-1]


def test_our_own_failure_is_told_logged_and_survived(layout, leases, tmp_path, capsys):
    class Broken(FakeBackend):
        def change_map(self, instance, map_name):
            raise RuntimeError("the map never came up")

    backend = Broken()
    worker = serving(backend, FakeSteam(layout.maps, gma_of("maps/gm_new.bsp")), layout, leases, tmp_path / "added.json")
    worker.on_line(request_line())
    assert "the map never came up" in said_by(backend)[-1]
    assert "the map never came up" in capsys.readouterr().err


def test_other_lines_of_the_log_are_not_requests(layout, leases, tmp_path):
    backend = FakeBackend()
    worker = serving(backend, FakeSteam(layout.maps, gma_of("maps/gm_new.bsp")), layout, leases, tmp_path / "added.json")
    worker.on_line("12.5 stage3 met all good")
    worker.on_line("12.5 add_map_request met {}")
    worker.on_line("not a line of the log")
    assert backend.ran == []


def test_the_worker_stops_once_the_server_is_gone():
    alive = [True, False]
    naps = []
    wait = until_server_gone(lambda: alive.pop(0), naps.append, polls_per_check=2)
    wait()
    wait()
    wait()
    with pytest.raises(ServerGone):
        wait()
    assert len(naps) == 4


def test_one_worker_an_instance(tmp_path):
    first = hold_worker_lock(tmp_path / "add_map.lock")
    assert first is not None
    assert hold_worker_lock(tmp_path / "add_map.lock") is None
    first.close()
    assert hold_worker_lock(tmp_path / "add_map.lock") is not None
