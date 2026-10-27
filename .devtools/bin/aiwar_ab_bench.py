"""An A/B bench of the AI war on the dev server: the native foundation
(native/foundation and native/wetsands installed) against the Lua twins
alone, in alternating legs on the same map and settings.

  aiwar_ab_bench.py [--map pl_upward] [--team-size 15] [--legs native,lua,native,lua]
                    [--warmup 90] [--window 60] [--instance 1]

Each leg moves the two DLL links in or out of the server root's lua/bin
(gmsv_<crate>_win64.dll <-> .off, so util.IsBinaryModuleInstalled sees
them or not), changes level, checks which implementation loaded, starts a
war at the team size, warms up, then measures for the window:

  ticks     the gap between Tick hooks (p50, p95, p99, max, how many came
            later than 1.5 tick intervals)
  profile   LuaJIT's sampler through wsprofile (VM states, the functions
            running, inclusive); the hook dispatcher's own share is time
            outside Lua (docs/ns-performance-baseline.md, "Sampling profiler")
  stats     the console's `stats` every 10 s: process CPU and FPS

The links are put back as they were found when it ends, failed or not. The
report is JSON in .devtools/artifacts/aiwar_ab_bench-<UTC time>.json, and a
summary is printed.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BIN = REPO / ".devtools/bin"
ARTIFACTS = REPO / ".devtools/artifacts"
CRATES = ("foundation", "wetsands")
LEGS = ("native", "lua")
STATS_EVERY = 10
LATE = 1.5  # tick intervals
READY_TIMEOUT = 300


class BenchError(Exception):
    pass


@dataclass(frozen=True)
class Server:
    instance: int

    def _args(self) -> list[str]:
        return ["--instance", str(self.instance)]

    def lua(self, code: str, timeout: float = 60) -> list[str]:
        out = subprocess.run([sys.executable, str(BIN / "server_lua.py"), *self._args(), code],
                             capture_output=True, text=True, timeout=timeout)
        values = [line[3:] for line in out.stdout.splitlines() if line.startswith("=> ")]
        if out.returncode != 0 or any("Error" in line for line in out.stderr.splitlines()):
            raise BenchError(f"lua failed: {out.stdout[-400:]} {out.stderr[-400:]}")
        return values

    def rcon(self, command: str, timeout: float = 30) -> str:
        out = subprocess.run([sys.executable, str(BIN / "srcds.py"), *self._args(), "rcon", command],
                             capture_output=True, text=True, timeout=timeout)
        return out.stdout

    def root(self) -> Path:
        out = subprocess.run([sys.executable, str(BIN / "server_root.py"), *self._args()],
                             capture_output=True, text=True, check=True)
        return Path(out.stdout.strip().splitlines()[-1])


class Links:
    """The crates' DLL links in the server root, on or off."""

    def __init__(self, root: Path):
        self.bin = root / "garrysmod/lua/bin"

    def _paths(self, crate: str) -> tuple[Path, Path]:
        on = self.bin / f"gmsv_{crate}_win64.dll"
        return on, on.with_name(on.name + ".off")

    def state(self) -> dict[str, bool]:
        return {crate: self._paths(crate)[0].is_symlink() for crate in CRATES}

    def set(self, wanted: dict[str, bool]) -> None:
        for crate, on_wanted in wanted.items():
            on, off = self._paths(crate)
            if on_wanted and not on.is_symlink():
                off.rename(on)
            elif not on_wanted and on.is_symlink():
                on.rename(off)


START = r"""
WSBench = { deltas = {}, last = nil }
hook.Add("Tick", "ws_ab_bench", function()
	local t = SysTime()
	if WSBench.last then WSBench.deltas[#WSBench.deltas + 1] = t - WSBench.last end
	WSBench.last = t
end)
if not wsprofile then require("wsprofile") end
local ok, why = wsprofile.Start("fi1", "F;", -12)
WSBench.memory = collectgarbage("count")
return tostring(ok) .. " " .. tostring(why)
"""

FINISH = r"""
hook.Remove("Tick", "ws_ab_bench")
local report = analysis.analytics.SampleReport(wsprofile.Stop(), 25)
local d = WSBench.deltas
table.sort(d)
local function at(p) return d[math.max(1, math.ceil(#d * p))] or 0 end
local interval, late = engine.TickInterval(), 0
for _, x in ipairs(d) do if x > interval * __LATE__ then late = late + 1 end end
local soldiers = 0
for _, e in ipairs(ents.GetAll()) do if e.IsNextBot and e:IsNextBot() then soldiers = soldiers + 1 end end
return util.TableToJSON({
	ticks = { count = #d, interval = interval, p50 = at(0.5), p95 = at(0.95), p99 = at(0.99), max = d[#d] or 0, late = late },
	profile = report,
	soldiers = soldiers,
	memory_kb = { start = WSBench.memory, finish = collectgarbage("count") },
})
""".replace("__LATE__", str(LATE))

IMPLEMENTATION = 'return debug.getinfo(core.namespace.Twin, "S").what .. " " .. debug.getinfo(tree.heap.New, "S").what'

SOLDIERS = 'local n = 0 for _, e in ipairs(ents.GetAll()) do if e.IsNextBot and e:IsNextBot() then n = n + 1 end end return n'

STATS = re.compile(r"^\s*([\d.]+)\s+[\d.]+\s+[\d.]+\s+\d+\s+\d+\s+([\d.]+)\s+\d+", re.M)


def wait_for(what: str, check, timeout: float = READY_TIMEOUT) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if check():
                return
        except (BenchError, subprocess.TimeoutExpired):
            pass
        time.sleep(3)
    raise BenchError(f"timed out waiting for {what}")


def run_leg(server: Server, links: Links, leg: str, args) -> dict:
    links.set({crate: leg == "native" for crate in CRATES})
    server.rcon(f"changelevel {args.map}")
    time.sleep(10)
    wait_for("the map", lambda: server.lua("return game.GetMap()")[0] == args.map)
    expected = "C C" if leg == "native" else "Lua Lua"
    loaded = server.lua(IMPLEMENTATION)[0]
    if loaded != expected:
        raise BenchError(f"{leg} leg loaded {loaded!r}, expected {expected!r}")
    server.rcon(f"mp_aiwar_team_size {args.team_size}")
    server.rcon("mp_aiwar_end")
    time.sleep(2)
    server.rcon("mp_aiwar_start")
    target = 2 * args.team_size - 2
    wait_for(f"{target} soldiers", lambda: int(server.lua(SOLDIERS)[0]) >= target)
    print(f"[{leg}] {loaded}: war up, warming {args.warmup} s", flush=True)
    time.sleep(args.warmup)
    started = server.lua(START)[0]
    if not started.startswith("true"):
        raise BenchError(f"profiler did not start: {started}")
    stats = []
    end = time.monotonic() + args.window
    while time.monotonic() < end:
        time.sleep(STATS_EVERY)
        match = STATS.search(server.rcon("stats"))
        if match:
            stats.append({"cpu": float(match.group(1)), "fps": float(match.group(2))})
    result = json.loads(server.lua(FINISH, timeout=120)[0])
    result.update(leg=leg, loaded=loaded, stats=stats)
    return result


def outside_lua(profile: dict) -> float:
    for row in profile["self"]:
        if "hook.lua" in row["name"]:
            return row["share"]
    return 0.0


def summary(result: dict) -> str:
    t, stats = result["ticks"], result["stats"]
    cpu = sum(s["cpu"] for s in stats) / len(stats) if stats else float("nan")
    fps = sum(s["fps"] for s in stats) / len(stats) if stats else float("nan")
    states = ", ".join(f"{r['name']} {r['share'] * 100:.1f}" for r in result["profile"]["states"])
    return (f"{result['leg']:6s} soldiers {result['soldiers']:2d}  CPU {cpu:5.1f} %  FPS {fps:5.1f}  "
            f"tick p50/p95/p99/max {t['p50'] * 1e3:.1f}/{t['p95'] * 1e3:.1f}/{t['p99'] * 1e3:.1f}/{t['max'] * 1e3:.1f} ms  "
            f"late {t['late']}/{t['count']}  Lua {100 * (1 - outside_lua(result['profile'])):.1f} % of the thread  "
            f"[{states}]")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--map", default="pl_upward")
    ap.add_argument("--team-size", type=int, default=15)
    ap.add_argument("--legs", default="native,lua,native,lua")
    ap.add_argument("--warmup", type=int, default=90)
    ap.add_argument("--window", type=int, default=60)
    ap.add_argument("--instance", type=int, default=1)
    args = ap.parse_args()
    legs = args.legs.split(",")
    for leg in legs:
        if leg not in LEGS:
            ap.error(f"a leg is one of {LEGS}, not {leg!r}")
    server = Server(args.instance)
    links = Links(server.root())
    found = links.state()
    results = []
    try:
        for leg in legs:
            results.append(run_leg(server, links, leg, args))
            print(summary(results[-1]), flush=True)
    finally:
        links.set(found)
        stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        out = ARTIFACTS / f"aiwar_ab_bench-{stamp}.json"
        out.write_text(json.dumps({"args": vars(args), "results": results}, indent=1))
        print(f"report: {out}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
