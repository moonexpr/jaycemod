#!/usr/bin/env python3
"""Put a Workshop map on the running dedicated server, with no restart.

  add_map.py 3632274158                     by its item id
  add_map.py 'https://steamcommunity.com/sharedfiles/filedetails/?id=3632274158'
  add_map.py ITEM --map gm_b                an item of several maps: which to play
  add_map.py ITEM --change                  change map though players are on it
  add_map.py --instance 2 ITEM              a second server's (srcds.py --instance 2)
  add_map.py --serve                        answer `ulx addmap` until the server stops

steamcmd downloads the item, its maps are listed in ADDED_MAPS (so a later
server_root.py build keeps them, on every instance) and its archive is linked
into the instance's cache/. A running server then mounts it, which is what lets
changelevel find the map, and changes to it; from there mounts.lua mounts it
each map, and sends it to clients as its Workshop item when it is the current
map. Others share the dev server, so players on it keep their map unless asked
(--change), and a server a bench has leased (instances.py) is left alone.

`ulx addmap` (server_root/ulx_add_map.lua) asks the same from in game. Lua cannot
download an item, so it writes a request to the watch log, and a worker here
follows the log and answers in chat; srcds.py starts one with each server, and
it ends with the server.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import re
import subprocess
import sys
import time
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional, Protocol, TextIO
from urllib.parse import parse_qs, urlparse

import srcds
from gma import read_gma
from instances import Backend, FileLeases, SrcdsBackend
from server_root import ADDED_MAPS, MAIN_INSTANCE, SERVER_MAPS, Instance, Layout, archive_bytes, downloaded_archive, \
    map_archive_name, place_archive, read_added_maps, write_added_maps
from server_watch import POLL_SECONDS, WatchLine, follow, log_path

GMOD_APP = "4000"
WORKSHOP_HOST = "steamcommunity.com"
MAP_FILE = re.compile(r"maps/([^/]+)\.bsp")
LUA_TIMEOUT = 30  # seconds for the server to answer
REQUEST = "add_map_request"  # ulx_add_map.lua's, a line of the watch log
ACK_TIMER = "ws_add_map_ack"  # ulx_add_map.lua's, which tells the game if it is not removed
POLLS_PER_CHECK = 25  # how many of the log's polls pass between asking if the server is up


class Refused(Exception):
    """The caller's mistake, or a state only the caller can change."""


class NotAnItem(Refused):
    pass


class NotAMap(Refused):
    pass


class NameTaken(Refused):
    pass


class Blocked(Refused):
    pass


class Failed(Exception):
    """What was asked was fine, and did not happen."""


class DownloadFailed(Failed):
    pass


class MountFailed(Failed):
    pass


@dataclass(frozen=True)
class WorkshopItem:
    id: str

    @classmethod
    def parse(cls, text: str) -> "WorkshopItem":
        """An item id, or a Workshop link to one."""
        if text.isascii() and text.isdigit():
            return cls(text)
        link = urlparse(text)
        ids = parse_qs(link.query).get("id", [])
        if link.hostname == WORKSHOP_HOST and len(ids) == 1 and ids[0].isascii() and ids[0].isdigit():
            return cls(ids[0])
        raise NotAnItem(f"not a Workshop item id or link: {text!r}")


@dataclass(frozen=True)
class Installed:
    item: WorkshopItem
    maps: tuple[str, ...]


class Steam(Protocol):
    def download(self, item: WorkshopItem) -> None: ...


@dataclass(frozen=True)
class SteamCmd:
    run: Callable[[list[str]], str]  # a command -> what it printed

    def download(self, item: WorkshopItem) -> None:
        printed = self.run(["steamcmd", "+login", "anonymous", "+workshop_download_item", GMOD_APP, item.id, "+quit"])
        # steamcmd exits 0 whether or not it got the item
        if f"Downloaded item {item.id}" not in printed:
            raise DownloadFailed(f"steamcmd did not download {item.id}: {printed.strip().splitlines()[-1:]}")


def run_command(command: list[str]) -> str:
    return subprocess.run(command, capture_output=True, text=True, check=False).stdout


def maps_in(archive: Path) -> tuple[str, ...]:
    """The maps an item's download holds, named as mounts.lua compares them."""
    found = (MAP_FILE.fullmatch(file.path.lower()) for file in read_gma(archive_bytes(archive)).files)
    return tuple(sorted(match[1] for match in found if match))


def install(item: WorkshopItem, steam: Steam, layout: Layout, added: Path) -> Installed:
    """The item downloaded, its maps listed, its archive in the instance's cache/."""
    steam.download(item)
    archive = downloaded_archive(layout, item.id, item.id)
    names = maps_in(archive)
    if not names:
        raise NotAMap(f"item {item.id} holds no maps/*.bsp")
    listed = read_added_maps(added)
    known = SERVER_MAPS | listed
    for name in names:
        if known.get(name, item.id) != item.id:
            raise NameTaken(f"{name} is already item {known[name]}'s")
    write_added_maps(added, listed | {name: item.id for name in names if name not in SERVER_MAPS})
    place_archive(layout.root / "garrysmod" / "cache" / map_archive_name(item.id), archive)
    return Installed(item, names)


def humans_on(backend: Backend, instance: Instance) -> list[str]:
    code = ("local names = {} for _, ply in ipairs(player.GetHumans()) do names[#names + 1] = ply:Nick() end "
            "return util.TableToJSON(names)")
    return json.loads(backend.lua(instance, code, LUA_TIMEOUT).returns[0])


def mount(installed: Installed, backend: Backend, instance: Instance) -> None:
    archive = map_archive_name(installed.item.id)
    names = ", ".join(f'"{name}"' for name in installed.maps)
    # ULX lists the maps once, as it loads: `ulx map` refuses any other
    code = (f'local ok = game.MountGMA("cache/{archive}") '
            f'if ok then for _, name in ipairs({{{names}}}) do '
            f'if not table.HasValue(ulx.maps, name) then table.insert(ulx.maps, name) end end '
            f'table.sort(ulx.maps) ULib.clientRPC(nil, "ulx.populateClMaps", ulx.maps) end '
            f'return ok')
    reply = backend.lua(instance, code, LUA_TIMEOUT)
    if reply.error or reply.returns != ["true"]:
        raise MountFailed(f"the server did not mount cache/{archive}: {reply.error or reply.returns}")


def go_live(installed: Installed, backend: Backend, leases: FileLeases, instance: Instance,
            wanted: Optional[str], change: bool) -> str:
    """Mount the item on a running server and change to its map, unless someone
    is using the server; what happened, for the operator."""
    if wanted is not None and wanted not in installed.maps:
        raise NotAMap(f"item {installed.item.id} holds {', '.join(installed.maps)}, not {wanted}")
    names = ", ".join(installed.maps)
    if not backend.alive(instance):
        return f"installed {names}; the server is not running, so it mounts them when it next starts"
    holder = leases.holder(instance)
    if holder is not None and leases.alive_pid(holder.pid):
        message = f"{holder.owner} has leased this server"
        if change:
            raise Blocked(f"{message}; try again when it gives the server back")
        return f"installed {names}; {message}, so it mounts them on its next map load"
    mount(installed, backend, instance)
    if wanted is None and len(installed.maps) > 1:
        return f"mounted {names}; name one with --map to change to it"
    target = wanted or installed.maps[0]
    if not change:
        humans = humans_on(backend, instance)
        if humans:
            return f"mounted {names}; {', '.join(humans)} still playing here. To move them: changelevel {target}"
    backend.change_map(instance, target)
    return f"the server is on {target}"


@dataclass(frozen=True)
class Request:
    """What `ulx addmap` asked; its map is empty when none was named."""
    item: WorkshopItem
    map: Optional[str]
    change: bool

    @classmethod
    def parse(cls, text: str) -> "Request":
        fields = json.loads(text)
        return cls(WorkshopItem.parse(fields["item"]), fields.get("map") or None, fields["change"])


class ServerGone(Exception):
    pass


def until_server_gone(alive: Callable[[], bool], sleep: Callable[[float], None],
                      polls_per_check: int = POLLS_PER_CHECK) -> Callable[[], None]:
    """A wait for the log's follower, which ends it once the server is down."""
    polls = 0

    def wait() -> None:
        nonlocal polls
        sleep(POLL_SECONDS)
        polls += 1
        if polls % polls_per_check == 0 and not alive():
            raise ServerGone()

    return wait


def hold_worker_lock(path: Path) -> Optional[TextIO]:
    """The instance's one worker's lock, held while the file stays open; None if another has it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lock = path.open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock.close()
        return None
    return lock


@dataclass(frozen=True)
class Worker:
    """Answers the requests `ulx addmap` writes to the watch log."""
    steam: Steam
    backend: Backend
    leases: FileLeases
    instance: Instance
    layout: Callable[[], Layout]
    added: Path

    def say(self, text: str) -> None:
        message = json.dumps(f"add_map: {text}", ensure_ascii=False)
        self.backend.lua(self.instance, f"ULib.tsay(nil, {message})", LUA_TIMEOUT)

    def answer(self, text: str) -> None:
        self.backend.lua(self.instance, f'timer.Remove("{ACK_TIMER}")', LUA_TIMEOUT)
        try:
            request = Request.parse(text)
            self.say(f"downloading {request.item.id}...")
            installed = install(request.item, self.steam, self.layout(), self.added)
            self.say(go_live(installed, self.backend, self.leases, self.instance, request.map, request.change))
        except (Refused, Failed) as e:
            self.say(str(e))
        except Exception as e:  # ours: told in game, then logged by on_line
            self.say(f"failed: {e}")
            raise

    def on_line(self, text: str) -> None:
        line = WatchLine.parse(text)
        if line is None or line.name != REQUEST or line.kind != "event":
            return
        try:
            self.answer(line.text)
        except Exception:  # one request's failure leaves the worker serving the next
            traceback.print_exc()


def serve(instance: Instance) -> int:
    lock = hold_worker_lock(srcds.ARTIFACTS / f"add_map{instance.suffix}.lock")
    if lock is None:
        print(f"add_map: a worker already serves instance {instance.number}")
        return 0
    backend = SrcdsBackend()
    worker = Worker(SteamCmd(run_command), backend, FileLeases(srcds.ARTIFACTS), instance,
                    lambda: Layout.of(instance), ADDED_MAPS)
    try:
        follow(log_path(instance), None, worker.on_line, until_server_gone(lambda: backend.alive(instance), time.sleep))
    except ServerGone:
        print(f"add_map: instance {instance.number} stopped")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--instance", type=int, default=MAIN_INSTANCE)
    ap.add_argument("--map", help="which of the item's maps to change to, when it has several")
    ap.add_argument("--change", action="store_true", help="change map though players are on the server")
    ap.add_argument("--serve", action="store_true", help="answer `ulx addmap` until the server stops")
    ap.add_argument("item", nargs="?", help="a Workshop item id or link")
    args = ap.parse_args()
    instance = Instance(args.instance)
    if args.serve:
        return serve(instance)
    if args.item is None:
        ap.error("give a Workshop item id or link, or --serve")
    try:
        installed = install(WorkshopItem.parse(args.item), SteamCmd(run_command), Layout.of(instance), ADDED_MAPS)
        print(go_live(installed, SrcdsBackend(), FileLeases(srcds.ARTIFACTS), instance, args.map, args.change))
    except Refused as e:
        print(f"add_map: {e}", file=sys.stderr)
        return 2
    except Failed as e:
        print(f"add_map: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
