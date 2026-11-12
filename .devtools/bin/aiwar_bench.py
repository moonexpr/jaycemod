"""The AI war's fixed benchmark: one saved fight, replayed under each condition in turn, so before
and after are the same fight and a difference has an interval (docs/wartactics-engine-plan.md §4.4).

  aiwar_bench.py --save NAME [--team-size 16] [--warmup 60]
      start a war at the team size on the server's map, let it fill and warm up, save it as a
      scenario (.devtools/scenarios/<map>/NAME). The bots' quota keeps a slot free, so 16v16 needs
      a server of 33 slots or more: srcds.py start --gamemode wetsands --maxplayers 34

  aiwar_bench.py --scenario NAME [--conditions "async=ns_bots_routes_engine 0;engine=ns_bots_routes_engine 1"]
                 [--replications 5] [--settle 5] [--window 30]
      for each replication and condition (alternating: a b b a a b ...), set the condition's
      convars, load the scenario, let it settle, and measure the window with the war's probe
      (aiwar_tick_probe.lua, hooks alone)

A replication's figures (seconds): the war's time a second (`war.rate`), and, a tick, the war's
and its route searches' together (`both`: p99, worst, ticks over the tick interval). Each
condition is reported as the mean over its replications with a 95 % Student's t interval; two
conditions differ when their intervals are apart. The pass line (--p99, --worst; 10 and 15 ms, the
operator's 16v16 target) is judged on every replication's `both`.

The report is JSON in .devtools/artifacts/aiwar_bench-<UTC time>.json.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BIN = REPO / ".devtools/bin"
ARTIFACTS = REPO / ".devtools/artifacts"
PROBE = BIN / "aiwar_tick_probe.lua"
READY_TIMEOUT = 300
# Student's t at 95 %, two-sided, by degrees of freedom; 1.96 beyond.
T95 = (12.71, 4.30, 3.18, 2.78, 2.57, 2.45, 2.36, 2.31, 2.26, 2.23, 2.20, 2.18, 2.16, 2.14, 2.13,
       2.12, 2.11, 2.10, 2.09, 2.09, 2.08, 2.07, 2.07, 2.06, 2.06, 2.06, 2.05, 2.05, 2.05, 2.04)
# The map's own rotation and the bots' wait for a human, off for a bench.
HOLD = ("mp_timelimit 0", "mp_winlimit 0", "mp_maxrounds 0", "tf_bot_join_after_player 0")


class BenchError(Exception):
    pass


@dataclass(frozen=True)
class Condition:
    name: str
    convars: tuple[tuple[str, str], ...]

    @classmethod
    def parse(cls, text: str) -> "Condition":
        name, _, rest = text.partition("=")
        name = name.strip()
        if not re.fullmatch(r"\w+", name):
            raise ValueError(f"a condition's name is one word, not {name!r}")
        convars = []
        for part in filter(None, (p.strip() for p in rest.split(","))):
            words = part.split()
            if len(words) != 2:
                raise ValueError(f"a convar is set as `name value`, not {part!r}")
            convars.append((words[0], words[1]))
        return cls(name, tuple(convars))


@dataclass(frozen=True)
class Interval:
    mean: float
    half: float

    def apart(self, other: "Interval") -> bool:
        return abs(self.mean - other.mean) > self.half + other.half


def interval_of(values: list[float]) -> Interval:
    n = len(values)
    mean = sum(values) / n
    if n < 2:
        return Interval(mean, math.inf)
    s = math.sqrt(sum((v - mean) ** 2 for v in values) / (n - 1))
    t = T95[n - 2] if n - 2 < len(T95) else 1.96
    return Interval(mean, t * s / math.sqrt(n))


def schedule(conditions: list[Condition], replications: int) -> list[Condition]:
    """Each replication's conditions, every other one reversed, so a drift in the server falls
    on every condition alike."""
    order = []
    for r in range(replications):
        order.extend(conditions if r % 2 == 0 else reversed(conditions))
    return order


@dataclass(frozen=True)
class PassLine:
    p99: float
    worst: float

    def failures(self, replications: list[dict]) -> list[str]:
        out = []
        for i, rep in enumerate(replications, 1):
            tail = rep["both"]["tail"]
            if tail["p99"] >= self.p99:
                out.append(f"replication {i}: p99 {tail['p99'] * 1e3:.2f} ms, not under {self.p99 * 1e3:.0f}")
            if tail["max"] > self.worst:
                out.append(f"replication {i}: a tick of {tail['max'] * 1e3:.2f} ms, over {self.worst * 1e3:.0f}")
        return out


@dataclass(frozen=True)
class Server:
    instance: int

    def _run(self, tool: str, *args: str, timeout: float) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(BIN / tool), "--instance", str(self.instance), *args],
                              capture_output=True, text=True, timeout=timeout)

    def lua(self, code: str, timeout: float = 60) -> str:
        out = self._run("server_lua.py", code, timeout=timeout)
        values = [line[3:] for line in out.stdout.splitlines() if line.startswith("=> ")]
        if out.returncode != 0 or not values:
            raise BenchError(f"lua failed: {out.stdout[-400:]} {out.stderr[-400:]}")
        return values[0]

    def lua_file(self, path: Path) -> None:
        out = self._run("server_lua.py", "-f", str(path), timeout=60)
        if out.returncode != 0:
            raise BenchError(f"lua file {path.name} failed: {out.stdout[-400:]} {out.stderr[-400:]}")

    def rcon(self, command: str) -> str:
        return self._run("srcds.py", "rcon", command, timeout=30).stdout

    def json(self, code: str, timeout: float = 60):
        return json.loads(self.lua(f"return util.TableToJSON(({code}) or {{}})", timeout))


def wait_for(what: str, check, timeout: float = READY_TIMEOUT) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if check():
                return
        except (BenchError, subprocess.TimeoutExpired, ValueError):
            pass
        time.sleep(3)
    raise BenchError(f"timed out waiting for {what}")


LIVE_SOLDIERS = ('(function() local C = WS.Feature("aiwar") local n = 0 '
                 'if C.war then for e in pairs(C.war.members) do if IsValid(e) and e:Health() > 0 then n = n + 1 end end end '
                 'return { n = n } end)()')


def save(server: Server, args) -> None:
    for command in HOLD:
        server.rcon(command)
    server.rcon("tf_bot_quota 0")  # a quota of 0 fills the teams' sizes
    server.rcon(f"mp_aiwar_team_size {args.team_size}")
    if server.lua('return tostring(WS.Feature("aiwar"):Active())') != "true":
        server.rcon("mp_aiwar_start")
    target = 2 * args.team_size
    wait_for(f"{target} soldiers alive", lambda: server.json(LIVE_SOLDIERS)["n"] >= target)
    print(f"{target} soldiers up; warming {args.warmup} s", flush=True)
    time.sleep(args.warmup)
    # mid-fight, some are dead and waiting on their wave: the scenario holds them dead, as they were
    alive = server.json(LIVE_SOLDIERS)["n"]
    description = f"aiwar_bench: {args.team_size}v{args.team_size}, warmed {args.warmup} s, {alive} alive"
    result = server.json(f'dev.scenario.save("{args.save}", "{description}")')
    print(json.dumps(result, indent=1))


def replicate(server: Server, condition: Condition, args) -> dict:
    for name, value in condition.convars:
        server.rcon(f"{name} {value}")
    loaded = server.json(f'dev.scenario.load("{args.scenario}")', timeout=120)
    time.sleep(args.settle)
    started = server.lua(f"return WarProbe.Start({args.window}, true)")
    if not started.startswith("measuring"):
        raise BenchError(f"the probe did not start: {started}")
    # the window is the server's time, which a server behind its ticks takes longer than ours to pass
    time.sleep(args.window)
    deadline = time.monotonic() + args.window * 3
    while True:
        data = json.loads(server.lua("return WarProbe.Data()"))
        if "error" not in data:
            break
        if not data["error"].startswith("measuring") or time.monotonic() > deadline:
            raise BenchError(f"the probe: {data['error']}")
        time.sleep(2)
    data["condition"] = condition.name
    data["notes"] = loaded.get("notes") if isinstance(loaded, dict) else None
    return data


def report(conditions: list[Condition], results: list[dict], line: PassLine) -> dict:
    out = {}
    for c in conditions:
        reps = [r for r in results if r["condition"] == c.name]
        figures = {
            "war ms/s": interval_of([r["war"]["rate"] * 1e3 for r in reps]),
            "searches ms/s": interval_of([r["search"]["rate"] * 1e3 for r in reps]),
            "tick p99 ms": interval_of([r["both"]["tail"]["p99"] * 1e3 for r in reps]),
            "tick worst ms": interval_of([r["both"]["tail"]["max"] * 1e3 for r in reps]),
            "ticks over": interval_of([float(r["both"]["over"]) for r in reps]),
        }
        out[c.name] = {
            "replications": len(reps),
            "soldiers": [r["soldiers"] for r in reps],
            "figures": {k: {"mean": v.mean, "half": v.half} for k, v in figures.items()},
            "failures": line.failures(reps),
        }
        print(f"{c.name}: {len(reps)} replications, soldiers {sorted(set(out[c.name]['soldiers']))}")
        for k, v in figures.items():
            print(f"  {k:15s} {v.mean:8.2f} +- {v.half:.2f}")
        failures = out[c.name]["failures"]
        print("  pass line: " + ("passed" if not failures else f"failed ({len(failures)})"))
        for f in failures:
            print("    " + f)
    names = [c.name for c in conditions]
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            for k in ("war ms/s", "tick p99 ms"):
                fa, fb = out[a]["figures"][k], out[b]["figures"][k]
                apart = Interval(fa["mean"], fa["half"]).apart(Interval(fb["mean"], fb["half"]))
                print(f"{a} vs {b}, {k}: {'differ' if apart else 'no difference shown'}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--save", metavar="NAME")
    mode.add_argument("--scenario", metavar="NAME")
    ap.add_argument("--team-size", type=int, default=16)
    ap.add_argument("--warmup", type=int, default=60)
    ap.add_argument("--conditions", default="base")
    ap.add_argument("--replications", type=int, default=5)
    ap.add_argument("--settle", type=int, default=5)
    ap.add_argument("--window", type=int, default=30)
    ap.add_argument("--p99", type=float, default=10.0, help="ms")
    ap.add_argument("--worst", type=float, default=15.0, help="ms")
    ap.add_argument("--instance", type=int, default=1)
    args = ap.parse_args()
    server = Server(args.instance)
    try:
        if args.save:
            save(server, args)
            return 0
        conditions = [Condition.parse(t) for t in args.conditions.split(";")]
        for command in HOLD:
            server.rcon(command)
        server.lua_file(PROBE)
        results = []
        for i, condition in enumerate(schedule(conditions, args.replications), 1):
            print(f"[{i}] {condition.name}", flush=True)
            results.append(replicate(server, condition, args))
            b = results[-1]["both"]
            print(f"    {results[-1]['soldiers']} soldiers, war {results[-1]['war']['rate'] * 1e3:.1f} ms/s, "
                  f"tick p99 {b['tail']['p99'] * 1e3:.2f} max {b['tail']['max'] * 1e3:.2f} ms, over {b['over']}",
                  flush=True)
        summary = report(conditions, results, PassLine(args.p99 / 1e3, args.worst / 1e3))
    except BenchError as e:
        print(f"bench failed: {e}", file=sys.stderr)
        return 1
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = ARTIFACTS / f"aiwar_bench-{stamp}.json"
    path.write_text(json.dumps({"args": vars(args), "results": results, "summary": summary}, indent=1))
    print(f"report: {path.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
