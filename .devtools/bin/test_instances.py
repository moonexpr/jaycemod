#!/usr/bin/env python3
"""Tests for instances.py: leasing dedicated servers to benches."""
from __future__ import annotations

import asyncio
import os
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List, Optional

import instances as I
from server_lua import Reply
from server_root import Instance

ONE, TWO = Instance(1), Instance(2)


class FakeBackend(I.Backend):
    """Instances in memory: which run, on which map, and what was done."""

    def __init__(self, running: Optional[Dict[int, str]] = None):
        self.maps: Dict[int, str] = dict(running or {})
        self.log: List[str] = []
        self.lua_reply = Reply([], ["1"], None, 0)

    def alive(self, instance):
        return instance.number in self.maps

    def start(self, instance, map_name):
        self.log.append(f"start {instance.number} {map_name}")
        self.maps[instance.number] = map_name

    def stop(self, instance):
        self.log.append(f"stop {instance.number}")
        del self.maps[instance.number]

    def current_map(self, instance):
        return self.maps.get(instance.number)

    def change_map(self, instance, map_name):
        self.log.append(f"changelevel {instance.number} {map_name}")
        self.maps[instance.number] = map_name

    def rcon(self, instance, text, timeout):
        return f"{instance.number}: {text}"

    def lua(self, instance, code, timeout):
        return self.lua_reply


def manager(backend, folder, usable=(ONE,), alive_pid=lambda pid: True, poll=0.01):
    return I.InstanceManager(backend, I.FileLeases(Path(folder), alive_pid), usable, poll=poll)


def run(coro):
    return asyncio.run(coro)


class LeaseTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()

    def test_a_running_instance_is_leased_without_a_start(self):
        backend = FakeBackend({1: "ns_bench_watchtower"})

        async def bench():
            async with manager(backend, self.folder).lease("ns_bench_watchtower", "t") as server:
                return server.instance, await server.current_map()

        self.assertEqual(run(bench()), (ONE, "ns_bench_watchtower"))
        self.assertEqual(backend.log, [])

    def test_a_running_instance_on_another_map_changes_map(self):
        backend = FakeBackend({1: "pl_upward"})

        async def bench():
            async with manager(backend, self.folder).lease("ns_bench_watchtower", "t"):
                pass

        run(bench())
        self.assertEqual(backend.log, ["changelevel 1 ns_bench_watchtower"])
        self.assertTrue(backend.alive(ONE), "an instance it did not start keeps running")

    def test_a_stopped_instance_is_started_and_stopped_after(self):
        backend = FakeBackend()

        async def bench():
            async with manager(backend, self.folder).lease("ns_bench_watchtower", "t") as server:
                return await server.rcon("status")

        self.assertEqual(run(bench()), "1: status")
        self.assertEqual(backend.log, ["start 1 ns_bench_watchtower", "stop 1"])

    def test_keep_running_leaves_a_started_instance_up(self):
        backend = FakeBackend()

        async def bench():
            async with manager(backend, self.folder).lease("m", "t", keep_running=True):
                pass

        run(bench())
        self.assertEqual(backend.log, ["start 1 m"])

    def test_a_second_bench_waits_for_the_only_instance(self):
        backend = FakeBackend({1: "m"})
        order = []

        async def bench(name, hold):
            async with pool.lease("m", name):
                order.append(f"{name} in")
                await asyncio.sleep(hold)
                order.append(f"{name} out")

        async def both():
            await asyncio.gather(bench("a", 0.05), bench("b", 0))

        pool = manager(backend, self.folder)
        run(both())
        self.assertEqual(order, ["a in", "a out", "b in", "b out"])

    def test_concurrent_benches_share_out_the_instances_running_first(self):
        backend = FakeBackend({2: "m"})
        got = []

        async def bench(name):
            async with pool.lease("m", name) as server:
                got.append(server.instance)
                await asyncio.sleep(0.02)

        async def both():
            await asyncio.gather(bench("a"), bench("b"))

        pool = manager(backend, self.folder, usable=(ONE, TWO))
        run(both())
        self.assertEqual(got, [TWO, ONE], "the running one first, then one started")
        self.assertEqual(backend.log, ["start 1 m", "stop 1"])

    def test_a_lease_held_by_a_live_process_is_waited_for(self):
        backend = FakeBackend({1: "m"})
        leases = I.FileLeases(Path(self.folder), lambda pid: True)
        self.assertTrue(leases.take(ONE, "other bench", pid=999999))

        async def bench():
            async with manager(backend, self.folder).lease("m", "t", timeout=0.1):
                pass

        with self.assertRaises(I.NoInstance):
            run(bench())

    def test_a_lease_whose_process_died_is_taken_over(self):
        backend = FakeBackend({1: "m"})
        I.FileLeases(Path(self.folder), lambda pid: True).take(ONE, "crashed bench", pid=999999)

        async def bench():
            async with manager(backend, self.folder, alive_pid=lambda pid: pid == os.getpid()).lease("m", "t"):
                return I.FileLeases(Path(self.folder), lambda pid: True).holder(ONE)

        self.assertEqual(run(bench()).owner, "t")

    def test_the_lease_is_given_back_after_a_failure(self):
        backend = FakeBackend({1: "m"})
        pool = manager(backend, self.folder)

        async def failing():
            async with pool.lease("m", "t"):
                raise RuntimeError("bench failed")

        with self.assertRaises(RuntimeError):
            run(failing())
        self.assertIsNone(I.FileLeases(Path(self.folder), lambda pid: True).holder(ONE))

    def test_a_lua_error_is_raised(self):
        backend = FakeBackend({1: "m"})
        backend.lua_reply = Reply(["printed"], [], "boom", 0)

        async def bench():
            async with manager(backend, self.folder).lease("m", "t") as server:
                await server.lua("error('boom')")

        with self.assertRaises(I.LuaFailed) as caught:
            run(bench())
        self.assertIn("boom", str(caught.exception))

    def test_lua_returns_the_reply(self):
        backend = FakeBackend({1: "m"})

        async def bench():
            async with manager(backend, self.folder).lease("m", "t") as server:
                return await server.lua("return 1")

        self.assertEqual(run(bench()).returns, ["1"])


if __name__ == "__main__":
    unittest.main()
