#!/usr/bin/env python3
"""The dedicated servers as objects a bench leases.

A bench (any test-managing program) asks an InstanceManager for a server on
a map and gets a GameServer for as long as it holds the lease:

    pool = InstanceManager.default()
    async with pool.lease("ns_bench_watchtower", owner="ns_bench_run") as server:
        reply = await server.lua("return game.GetMap()")

The manager owns the instances' lifecycle, so a bench never starts, stops or
changes the map of a server itself:

- It leases an instance no one holds, preferring one that is running (and
  of those, one already on the map); with none free, it starts one of the
  instances it may use that is not running; with none of those either, the
  bench waits until one is given back, up to its timeout (NoInstance).
- A running instance on another map changes map; a stopped one starts on
  the map.
- Given back, an instance the lease started is stopped (unless the bench
  asks to keep it running); one that was already running is left as it was.

Benches run as asyncio tasks, any number at once: the manager's condition
shares the instances out among the tasks of one process, and a lease file
per instance (FileLeases, srcds[-n].lease beside the launch record) among
processes. A lease whose process has died is taken over. Everything that
blocks (RCON, luadev, wine's processes) runs in a worker thread
(asyncio.to_thread), so one bench's map change never holds up another's
errands.

The instances a manager may use are named when it is made; the default is
the main server alone (a second one only when the caller lists it).

From a shell, for looking around on a bench's map without managing a server:

    python3 .devtools/bin/instances.py MAP 'return game.GetMap()'   # - reads the chunk from stdin
"""
from __future__ import annotations

import asyncio
import contextlib
import json
import os
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import AsyncIterator, Callable, Optional, Sequence, Set

import server_lua
import srcds
from server_lua import Realm, Reply
from server_root import MAIN_INSTANCE, Instance

DEFAULT_LEASE_TIMEOUT = 600  # seconds a bench waits for an instance
POLL = 2.0  # how often a waiting bench looks again at the other processes' leases
LUA_READY_TIMEOUT = 60  # after a map is up, until its luadev socket answers


class NoInstance(Exception):
    """No instance came free in the time the bench would wait."""


class LuaFailed(Exception):
    """The Lua a bench ran raised an error on the server."""


class Backend(ABC):
    """The process-level operations on one instance (the port tests fake)."""

    @abstractmethod
    def alive(self, instance: Instance) -> bool: ...

    @abstractmethod
    def start(self, instance: Instance, map_name: str) -> None:
        """Returns once the map is up and its Lua answers."""

    @abstractmethod
    def stop(self, instance: Instance) -> None: ...

    @abstractmethod
    def current_map(self, instance: Instance) -> Optional[str]: ...

    @abstractmethod
    def change_map(self, instance: Instance, map_name: str) -> None:
        """Returns once the map is up and its Lua answers."""

    @abstractmethod
    def rcon(self, instance: Instance, text: str, timeout: float) -> str: ...

    @abstractmethod
    def lua(self, instance: Instance, code: str, timeout: float) -> Reply: ...


class SrcdsBackend(Backend):
    """srcds.py's servers in the GModServer bottle, and server_lua's bridge."""

    def _running(self, instance: Instance) -> srcds.Server:
        files = srcds.InstanceFiles.of(instance)
        return srcds.make_server("gm_construct", srcds.started_port(files.port, instance), instance=instance)

    def _wait_for_lua(self, instance: Instance) -> None:
        deadline = time.monotonic() + LUA_READY_TIMEOUT
        while True:
            try:
                self.lua(instance, "return true", timeout=5)
                return
            except (server_lua.BridgeDown, server_lua.NoReply, OSError):
                if time.monotonic() > deadline:
                    raise
                time.sleep(1)

    def alive(self, instance: Instance) -> bool:
        return self._running(instance).alive()

    def start(self, instance: Instance, map_name: str) -> None:
        port = srcds.InstanceFiles.of(instance).port
        server = srcds.make_server(map_name, port, ip=srcds.bind_address(srcds.DEFAULT_BIND_HOST), instance=instance)
        server.start()
        server.wait_for_map(map_name, srcds.MAP_LOAD_TIMEOUT)
        self._wait_for_lua(instance)

    def stop(self, instance: Instance) -> None:
        self._running(instance).stop()

    def current_map(self, instance: Instance) -> Optional[str]:
        return self._running(instance).current_map()

    def change_map(self, instance: Instance, map_name: str) -> None:
        if not srcds.MAP_NAME.match(map_name):
            raise ValueError(f"not a map name: {map_name!r}")
        server = self._running(instance)
        server.rcon(f"changelevel {map_name}")
        server.wait_for_map(map_name, srcds.MAP_LOAD_TIMEOUT)
        self._wait_for_lua(instance)

    def rcon(self, instance: Instance, text: str, timeout: float) -> str:
        return self._running(instance).rcon(text, timeout)

    def lua(self, instance: Instance, code: str, timeout: float) -> Reply:
        return server_lua.run(Realm.SERVER, code, server_lua.address(instance.number), timeout)


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


@dataclass(frozen=True)
class Holder:
    owner: str
    pid: int
    since: float


class FileLeases:
    """One lease file per instance, made exclusively, so two processes never
    hold an instance at once; a lease whose process died is taken over."""

    def __init__(self, folder: Path, alive_pid: Callable[[int], bool] = pid_alive):
        self.folder = folder
        self.alive_pid = alive_pid

    def path(self, instance: Instance) -> Path:
        return self.folder / f"srcds{instance.suffix}.lease"

    def holder(self, instance: Instance) -> Optional[Holder]:
        path = self.path(instance)
        if not path.exists():
            return None
        return Holder(**json.loads(path.read_text()))

    def take(self, instance: Instance, owner: str, pid: Optional[int] = None) -> bool:
        held = self.holder(instance)
        if held is not None and not self.alive_pid(held.pid):
            self.path(instance).unlink(missing_ok=True)
        self.folder.mkdir(parents=True, exist_ok=True)
        try:
            fd = os.open(self.path(instance), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            return False
        with os.fdopen(fd, "w") as f:
            json.dump({"owner": owner, "pid": pid or os.getpid(), "since": time.time()}, f)
        return True

    def give_back(self, instance: Instance) -> None:
        self.path(instance).unlink(missing_ok=True)


@dataclass(frozen=True)
class GameServer:
    """A leased instance: what a bench does on it, each call awaited."""
    instance: Instance
    backend: Backend

    @property
    def log(self) -> Path:
        return srcds.InstanceFiles.of(self.instance).log

    async def lua(self, code: str, timeout: float = 10) -> Reply:
        reply = await asyncio.to_thread(self.backend.lua, self.instance, code, timeout)
        if reply.error:
            raise LuaFailed(reply.error + "".join("\n" + line for line in reply.output))
        return reply

    async def rcon(self, text: str, timeout: float = 10) -> str:
        return await asyncio.to_thread(self.backend.rcon, self.instance, text, timeout)

    async def current_map(self) -> Optional[str]:
        return await asyncio.to_thread(self.backend.current_map, self.instance)

    async def change_map(self, map_name: str) -> None:
        await asyncio.to_thread(self.backend.change_map, self.instance, map_name)


@dataclass(frozen=True)
class Lease:
    server: GameServer
    owner: str
    started: bool  # the lease started the instance, so giving it back stops it


class InstanceManager:
    def __init__(self, backend: Backend, leases: FileLeases, usable: Sequence[Instance], poll: float = POLL):
        self.backend = backend
        self.leases = leases
        self.usable = tuple(usable)
        self.poll = poll
        self._held: Set[Instance] = set()
        self._changed: Optional[asyncio.Condition] = None

    @classmethod
    def default(cls, usable: Sequence[Instance] = (Instance(MAIN_INSTANCE),)) -> "InstanceManager":
        return cls(SrcdsBackend(), FileLeases(srcds.ARTIFACTS), usable)

    def _condition(self) -> asyncio.Condition:
        if self._changed is None:
            self._changed = asyncio.Condition()
        return self._changed

    async def _claim(self, owner: str, map_name: str) -> Optional[Instance]:
        """A free instance, now leased to owner: running ones first, on the map first."""
        async def rank(instance: Instance):
            alive = await asyncio.to_thread(self.backend.alive, instance)
            on_map = alive and await asyncio.to_thread(self.backend.current_map, instance) == map_name
            return (not alive, not on_map)

        free = [i for i in self.usable if i not in self._held]
        ranks = [await rank(i) for i in free]
        for _, instance in sorted(zip(ranks, free), key=lambda pair: pair[0]):
            if self.leases.take(instance, owner):
                self._held.add(instance)
                return instance
        return None

    async def acquire(self, map_name: str, owner: str, timeout: float = DEFAULT_LEASE_TIMEOUT) -> Lease:
        changed = self._condition()
        deadline = time.monotonic() + timeout
        async with changed:
            while True:
                instance = await self._claim(owner, map_name)
                if instance is not None:
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise NoInstance(f"{owner}: no instance of {[i.number for i in self.usable]} came free "
                                     f"in {timeout:g} s")
                with contextlib.suppress(asyncio.TimeoutError):
                    await asyncio.wait_for(changed.wait(), min(self.poll, remaining))
        try:
            started = not await asyncio.to_thread(self.backend.alive, instance)
            if started:
                await asyncio.to_thread(self.backend.start, instance, map_name)
            elif await asyncio.to_thread(self.backend.current_map, instance) != map_name:
                await asyncio.to_thread(self.backend.change_map, instance, map_name)
        except BaseException:
            await self._give_back(instance)
            raise
        return Lease(GameServer(instance, self.backend), owner, started)

    async def release(self, lease: Lease, keep_running: bool = False) -> None:
        try:
            if lease.started and not keep_running:
                await asyncio.to_thread(self.backend.stop, lease.server.instance)
        finally:
            await self._give_back(lease.server.instance)

    async def _give_back(self, instance: Instance) -> None:
        self.leases.give_back(instance)
        self._held.discard(instance)
        changed = self._condition()
        async with changed:
            changed.notify_all()

    @contextlib.asynccontextmanager
    async def lease(self, map_name: str, owner: str, timeout: float = DEFAULT_LEASE_TIMEOUT,
                    keep_running: bool = False) -> AsyncIterator[GameServer]:
        held = await self.acquire(map_name, owner, timeout)
        try:
            yield held.server
        finally:
            await self.release(held, keep_running)


# The command line: Lua on a leased server ------------------------------------------


async def run_lua(pool: InstanceManager, map_name: str, code: str, timeout: float) -> Reply:
    async with pool.lease(map_name, "instances.py lua", keep_running=True) as server:
        return await server.lua(code, timeout)


def main() -> int:
    import argparse
    import sys
    parser = argparse.ArgumentParser(description="Run Lua on a server leased on a map (it stays running after)")
    parser.add_argument("map")
    parser.add_argument("code", help="a Lua chunk; - reads it from stdin")
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--instance", type=int, nargs="+", default=[MAIN_INSTANCE])
    args = parser.parse_args()
    code = sys.stdin.read() if args.code == "-" else args.code
    pool = InstanceManager.default([Instance(n) for n in args.instance])
    try:
        reply = asyncio.run(run_lua(pool, args.map, code, args.timeout))
    except LuaFailed as e:
        print(e, file=sys.stderr)
        return 1
    for line in reply.output:
        print(line)
    for value in reply.returns:
        print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
