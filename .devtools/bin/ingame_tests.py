#!/usr/bin/env python3
"""Run Sandcastle's in-game checks on a dedicated server, map by map, and
write a report.

  ingame_tests.py                       every map in PLAN
  ingame_tests.py --maps koth_viaduct   only these (comma-separated)

It starts the server (srcds.py) on the first map, then for each map: loads
the Lua runner (ingame/runner.lua) with lua_run, runs the map's checks
(ingame/checks/<name>.lua) one at a time, reads each one's JSON record from
garrysmod/data/ws_tests/results/, and scans the map's part of the
console (srcds.log, srcds.py's record of it) for Lua errors. It stops the server, removes what it
put in the GMod install, and writes .devtools/artifacts/ingame-report-<date>.md
with ingame-<date>/ (the records and each map's console log) beside it.

The server runs the gamemode garrysmod/gamemodes/sandcastle points to (the
operator's main checkout); the report says which, and whether its files
equal this checkout's addons/sandcastle/gamemodes/sandcastle.
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import bsp_entities
import srcds

__all__ = [
    "CHECKS_DIR",
    "HALLOWEEN_MAPS",
    "PLAN",
    "full_plan",
    "halloween_run",
    "CheckLine",
    "LuaError",
    "MapResult",
    "MapRun",
    "Step",
    "StepResult",
    "console_notes",
    "deploy",
    "lua_errors",
    "render_report",
    "result_from_json",
    "tree_digest",
]

HERE = Path(__file__).resolve().parent
INGAME_DIR = HERE / "ingame"
CHECKS_DIR = INGAME_DIR / "checks"
REPO = HERE.parents[1]
TF_MAPS = srcds.GMOD_DIR.parent.parent / "Team Fortress 2" / "tf" / "maps"
DATA_NAME = "ws_tests"
SCRIPT_EXT = ".txt"  # what the runner reads; GMod's data folder is for data files
BOOT = f'lua_run RunString(file.Read("{DATA_NAME}/harness/runner{SCRIPT_EXT}", "DATA"), "{DATA_NAME}/runner")'
RUNNER_READY = "ws_tests: runner ready on "
POLL_SECONDS = 1
BOOT_TIMEOUT = 60
MAP_LOAD_TIMEOUT = 300
LOG_SETTLE = 2  # seconds for the console log to catch up after a map's last check

# The plan --------------------------------------------------------------------------------


@dataclass(frozen=True)
class Step:
    """A check to run, the seconds to wait for its record, its arguments,
    and a console command the harness sends over RCON just before it (for
    what Lua may not run, such as exec)."""
    check: str
    timeout: float
    args: Dict[str, object] = field(default_factory=dict)
    before: Optional[str] = None


@dataclass(frozen=True)
class MapRun:
    map: str
    steps: Tuple[Step, ...]


HALLOWEEN_FEATURES = ["npc", "combat", "holiday", "spells", "hazards", "tag"]


def load(rounds: bool, has: Sequence[str] = (), lacks: Sequence[str] = (), lacks_modules: Sequence[str] = ()) -> Step:
    # aiwar loads only once mp_aiwar_start runs (docs/aiwar-koth-cp.md §6, 14).
    return Step("load", 30, {
        "rounds": rounds,
        "has": list(has),
        "lacks": list(lacks) + ["aiwar"],
        "lacks_modules": list(lacks_modules),
    })


GAMEPLAY_START = Step("gameplay_start", 80, {"red": 2, "blue": 3})

# The payload, KOTH and CP maps of docs/pass4-koth-cp.md §9 and
# docs/aiwar-koth-cp.md §6, after the Halloween maps.
PLAN: Tuple[MapRun, ...] = (
    MapRun("pl_badwater", (
        load(True, has=["rounds", "capture", "payload"], lacks=["koth"] + HALLOWEEN_FEATURES,
             lacks_modules=["features.koth.model"]),
        Step("defaults_change", 20),
        Step("defaults_apply", 20, before="ws_defaults_apply"),
        Step("aiwar", 90),
        Step("aiwar_sitting", 300),
        GAMEPLAY_START,
        Step("payload", 420),
    )),
    MapRun("koth_viaduct", (
        load(True, has=["rounds", "capture", "koth"], lacks=["payload"], lacks_modules=["foundation.payload"]),
        GAMEPLAY_START,
        Step("koth", 200),
    )),
    MapRun("cp_granary", (
        load(True, has=["rounds", "capture"], lacks=["koth", "payload"]),
        Step("sandbox_capture", 45),
        Step("capture_cleanup", 20),
        GAMEPLAY_START,
        Step("cp_capture", 420, {"timeout": 400}),
    )),
    MapRun("cp_dustbowl", (
        load(True, has=["rounds", "capture"], lacks=["koth", "payload"]),
        GAMEPLAY_START,
        Step("cp_capture", 420, {"timeout": 400}),
    )),
    # Arena (tf_logic_arena): the round with bots, then the AI war's tie,
    # capture and elimination. arena_well's point stands still (nucleus's
    # rides bridges its nav mesh does not follow); TF2 ships no mesh for it:
    # make one with mp_nav_generate first.
    MapRun("arena_well", (
        load(True, has=["rounds", "capture", "arena"], lacks=["koth", "payload"]),
        Step("arena", 150),
        Step("aiwar_arena", 720),
    )),
)

# The Halloween payload maps of the live playtest, run first; each one's
# checks follow from what its BSP places (halloween_run).
HALLOWEEN_MAPS = (
    "pl_fifthcurve_event",
    "pl_rumble_event",
    "pl_millstone_event",
    "pl_bloodwater",
    "pl_terror_event",
    "pl_hasslecastle",
    "pl_sludgepit_event",
    "plr_hacksaw_event",
    "plr_hightower_event",
    "pl_precipice_event_final",
    "pl_coal_event",
)
BOSS_CLASSES = ("headless_hatman", "eyeball_boss", "merasmus")
HALLOWEEN_CLASSES = BOSS_CLASSES + (
    "tf_logic_holiday",
    "tf_zombie_spawner",
    "tf_zombie",
    "tf_spell_pickup",
    "halloween_zapper",
    "halloween_fortune_teller",
    "tf_pumpkin_bomb",
    "func_nav_prefer",
    "tf_halloween_gift_spawn_location",
    "tf_halloween_minigame",
    "tf_logic_minigames",
)
STUB_CLASSES = ("tf_halloween_minigame", "tf_logic_minigames")  # accept their inputs and ignore them
ENGINE_CLASSES = ("func_nav_prefer",)  # the engine's own entity, which Merasmus reads


def _template_targets(e: Dict[str, str]) -> List[str]:
    return [v for k, v in e.items() if k.lower().startswith("template") and v]


HALLOWEEN = 2  # TF2's kHoliday_Halloween (foundation.holiday.HALLOWEEN)


def _map_holiday(entities: Sequence[Dict[str, str]]) -> int:
    """The holiday the map's tf_logic_holiday turns on (pl_coal_event's is
    Christmas, 3)."""
    logic = next((e for e in entities if e.get("classname") == "tf_logic_holiday"), {})
    return int(logic.get("holiday_type") or HALLOWEEN)


def halloween_run(map_name: str, entities: Sequence[Dict[str, str]]) -> MapRun:
    """A Halloween map's checks, from its BSP's entities (dicts of keyvalues)."""
    templated = {t for e in entities if e.get("classname") == "point_template" for t in _template_targets(e)}
    by_name = {e["targetname"]: e.get("classname") for e in entities if e.get("targetname")}
    classes: Dict[str, int] = {}
    for e in entities:
        c = e.get("classname", "")
        if c in HALLOWEEN_CLASSES and e.get("targetname") not in templated:
            classes[c] = classes.get(c, 0) + 1
    bosses = [{"template": e.get("targetname", ""), "class": by_name[target]}
              for e in entities if e.get("classname") == "point_template"
              for target in _template_targets(e) if by_name.get(target) in BOSS_CLASSES]
    steps = [
        load(True, has=["rounds", "capture", "payload", "holiday"], lacks=["koth"]),
        Step("halloween_entities", 30, {
            "holiday": _map_holiday(entities),
            "classes": classes,
            "stubs": [c for c in STUB_CLASSES if c in classes],
            "engine": [c for c in ENGINE_CLASSES if c in classes],
        }),
        GAMEPLAY_START,
        Step("payload", 200, {"checkpoint": False}),
    ]
    if "tf_zombie_spawner" in classes:
        steps.append(Step("skeletons", 90))
    if "tf_spell_pickup" in classes:
        steps.append(Step("spells", 30))
    if "tf_halloween_gift_spawn_location" in classes:
        steps.append(Step("gifts", 30))
    if bosses:
        steps.append(Step("bosses", 150 * len(bosses), {"bosses": bosses}))
    return MapRun(map_name, tuple(steps))


def bsp_entities_of(map_name: str) -> List[Dict[str, str]]:
    bsp = TF_MAPS / f"{map_name}.bsp"
    parsed = bsp_entities.parse_entity_lump(bsp_entities.read_entity_lump(bsp.read_bytes()))
    return [dict(e.pairs) for e in parsed]


def full_plan() -> List[MapRun]:
    return [halloween_run(m, bsp_entities_of(m)) for m in HALLOWEEN_MAPS] + list(PLAN)

HUMAN_ONLY = [
    "Sound: announcer lines (KOTH unlock count, 'Mission ends in 60 seconds', time awarded, Overtime!), "
    "capture hologram start/loop/stop, Success/Failure stings, win songs, boss music and spell sounds "
    "(game events reach clients only; the dedicated server has none).",
    "Visuals: the HUD (setup timer, KOTH clocks and highlight, capture panels and lock text, icons, "
    "payload HUD and race bars), the win panel text, goal strings, the 'Sandbox mode' note, particles, "
    "gibs, client ragdolls, the boss bar, the overlay and nbdebug views.",
    "Client prediction and input: the pre-round freeze, spellbook casting with H, the team menu.",
    "The AI war's behaviour (staging, rushing, posts, lanes, carnage): the checks start the war, run "
    "the ns_* commands and ride the cart, but whether the soldiers fight well takes someone watching.",
]

# Records ---------------------------------------------------------------------------------


@dataclass(frozen=True)
class CheckLine:
    name: str
    ok: bool
    detail: str


@dataclass(frozen=True)
class StepResult:
    check: str
    status: str  # pass, fail, skip, error, timeout
    checks: Tuple[CheckLine, ...]
    info: Dict[str, object]
    error: Optional[str]
    seconds: float


@dataclass(frozen=True)
class LuaError:
    message: str
    stack: Tuple[str, ...]
    count: int


@dataclass(frozen=True)
class MapResult:
    map: str
    steps: Tuple[StepResult, ...]
    errors: Tuple[LuaError, ...]
    notes: Tuple[str, ...]


def result_from_json(check: str, data: Dict[str, object]) -> StepResult:
    # util.TableToJSON writes an empty table as {}.
    lines = data.get("checks") or []
    return StepResult(
        check=check,
        status=str(data["status"]),
        checks=tuple(CheckLine(str(c["name"]), bool(c["ok"]), str(c.get("detail", ""))) for c in lines),
        info=dict(data.get("info") or {}),
        error=data.get("error"),
        seconds=float(data.get("seconds", 0)),
    )


# The console log ---------------------------------------------------------------------------

ERROR_LINE = re.compile(r"^\[ERROR\] (.*)$")
STACK_LINE = re.compile(r"^\s+(\d+\. .*)$")
NOTE_LINE = re.compile(
    r"Unknown command|couldn't exec|MapIO infinite loop|^ERROR|Can't create physics|Failed to load|"
    r"Lua Error|Couldn't include|not found|SV_StartSound|Timer Failed"
)


def _lines(text: str) -> List[str]:
    return text.replace("\r", "").split("\n")


def lua_errors(text: str) -> List[LuaError]:
    """GMod's Lua errors in a console log: the [ERROR] line and the stack
    lines indented under it, counted when the same error repeats."""
    found: Dict[Tuple[str, Tuple[str, ...]], int] = {}
    lines = _lines(text)
    for i, line in enumerate(lines):
        m = ERROR_LINE.match(line)
        if not m:
            continue
        stack = []
        for following in lines[i + 1:]:
            s = STACK_LINE.match(following)
            if not s:
                break
            stack.append(s.group(1))
        key = (m.group(1), tuple(stack))
        found[key] = found.get(key, 0) + 1
    return [LuaError(message, stack, count) for (message, stack), count in found.items()]


def console_notes(text: str) -> List[str]:
    """Engine complaints worth a look that are not Lua errors, once each."""
    notes: List[str] = []
    for line in _lines(text):
        line = line.strip()
        if line and NOTE_LINE.search(line) and not line.startswith("[ERROR]") and line not in notes:
            notes.append(line)
    return notes


# The GMod install -------------------------------------------------------------------------


def deploy(data_root: Path) -> None:
    """Copies the runner and checks under data_root/harness as .txt, and
    clears results and arguments of an earlier run."""
    for sub in ("harness", "results"):
        shutil.rmtree(data_root / sub, ignore_errors=True)
    checks = data_root / "harness" / "checks"
    checks.mkdir(parents=True)
    (data_root / "harness" / "args").mkdir()
    (data_root / "results").mkdir()
    shutil.copyfile(INGAME_DIR / "runner.lua", data_root / "harness" / f"runner{SCRIPT_EXT}")
    for script in CHECKS_DIR.glob("*.lua"):
        shutil.copyfile(script, checks / f"{script.stem}{SCRIPT_EXT}")


def tree_digest(root: Path) -> str:
    h = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file() and p.name != ".DS_Store"):
        h.update(str(path.relative_to(root)).encode())
        h.update(b"\0")
        h.update(path.read_bytes())
    return h.hexdigest()


@dataclass(frozen=True)
class AddonIdentity:
    target: Path
    same_as_checkout: bool
    commit: str

    @classmethod
    def of(cls, install: srcds.Install) -> "AddonIdentity":
        link = install.gmod_dir / "gamemodes" / "sandcastle"
        target = Path(os.path.realpath(link))
        commit = subprocess.run(["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"],
                                capture_output=True, text=True).stdout.strip()
        return cls(target, tree_digest(target) == tree_digest(REPO / "addons" / "sandcastle" / "gamemodes" / "sandcastle"), commit)

    def describe(self) -> str:
        same = "identical to" if self.same_as_checkout else "DIFFERENT from"
        return f"`{self.target}` (files {same} this checkout's addons/sandcastle/gamemodes/sandcastle at {self.commit})"


TERMINAL_CODES = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07")


class ConsoleLog:
    """The server's console as srcds.py's supervisor records it (srcds.log;
    the server writes no console.log of its own), read from an offset so
    earlier lines are left out, its terminal codes removed. A start begins
    the file again."""

    def __init__(self, path: Path):
        self.path = path

    def size(self) -> int:
        return self.path.stat().st_size if self.path.exists() else 0

    def read_from(self, offset: int) -> str:
        with open(self.path, "rb") as f:
            f.seek(offset)
            return TERMINAL_CODES.sub("", f.read().decode("utf-8", errors="replace"))


# Running ---------------------------------------------------------------------------------


class Harness:
    def __init__(self, server: srcds.Server, data_root: Path, out_dir: Path):
        self.server = server
        self.data_root = data_root
        self.out_dir = out_dir
        self.console = ConsoleLog(server.files.log)

    def boot(self) -> None:
        deadline = time.monotonic() + BOOT_TIMEOUT
        reply = ""
        while time.monotonic() < deadline:
            reply = self.server.rcon(BOOT)
            if RUNNER_READY in reply:
                return
            time.sleep(POLL_SECONDS)
        raise srcds.ServerDown(f"the runner did not load: {reply.strip()}")

    def run_step(self, map_name: str, index: int, step: Step) -> StepResult:
        run_id = f"{map_name}_{index}_{step.check}"
        before = {step.before: self.server.rcon(step.before).strip()} if step.before else {}
        args = dict(step.args, before_reply=before[step.before]) if step.before else step.args
        (self.data_root / "harness" / "args" / f"{run_id}{SCRIPT_EXT}").write_text(json.dumps(args))
        result_path = self.data_root / "results" / f"{run_id}.json"
        reply = self.server.rcon(f'lua_run WS_TESTS.Run("{step.check}", "{run_id}")')
        if "[ERROR]" in reply:
            return StepResult(step.check, "error", (), {}, reply.strip(), 0)
        deadline = time.monotonic() + step.timeout
        while time.monotonic() < deadline:
            if result_path.exists():
                try:
                    result = result_from_json(step.check, json.loads(result_path.read_text()))
                except json.JSONDecodeError:
                    pass  # still being written
                else:
                    return dataclasses.replace(result, info={**result.info, "rcon": before}) if before else result
            time.sleep(POLL_SECONDS)
        return StepResult(step.check, "timeout", (), {}, f"no record within {step.timeout:.0f} s", step.timeout)

    def run_map(self, run: MapRun, first: bool) -> MapResult:
        offset = self.console.size()
        if first:
            self.server.start()
            offset = 0  # the start began the log again
        else:
            self.server.rcon("lua_run if WS_TESTS then WS_TESTS.KickBots() end")
            self.server.rcon("sv_gameplay_enabled 0")
            self.server.rcon(f"changelevel {run.map}")
        self.server.wait_for_map(run.map, MAP_LOAD_TIMEOUT)
        self.boot()
        steps = []
        for i, step in enumerate(run.steps):
            result = self.run_step(run.map, i, step)
            print(f"  {run.map} {step.check}: {result.status}", flush=True)
            steps.append(result)
        time.sleep(LOG_SETTLE)
        segment = self.console.read_from(offset)
        (self.out_dir / f"{run.map}.console.log").write_text(segment)
        return MapResult(run.map, tuple(steps), tuple(lua_errors(segment)), tuple(console_notes(segment)))

    def run(self, plan: Sequence[MapRun]) -> List[MapResult]:
        results = []
        for i, run in enumerate(plan):
            print(f"{run.map}", flush=True)
            results.append(self.run_map(run, first=(i == 0)))
        return results


# The report --------------------------------------------------------------------------------


def _detail(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def render_report(results: Sequence[MapResult], header: str, human_only: Sequence[str]) -> str:
    out = [header, "", "## Summary", "", "| map | check | status | Lua errors |", "|---|---|---|---|"]
    for r in results:
        for s in r.steps:
            out.append(f"| {r.map} | {s.check} | {s.status.upper()} | {len(r.errors)} |")
    for r in results:
        out += ["", f"## {r.map}", ""]
        for s in r.steps:
            out.append(f"### {s.check}: {s.status.upper()} ({s.seconds:.0f} s)")
            out.append("")
            if s.error:
                out += ["```", s.error.strip(), "```", ""]
            for c in s.checks:
                mark = "pass" if c.ok else "FAIL"
                out.append(f"- {mark}: {c.name}" + (f" ({_detail(c.detail)})" if c.detail else ""))
            if s.info:
                out += ["", "<details><summary>info</summary>", "", "```json",
                        json.dumps(s.info, indent=2, sort_keys=True), "```", "</details>"]
            out.append("")
        out.append(f"### Lua errors on {r.map}: {len(r.errors)}")
        out.append("")
        for e in r.errors:
            out += ["```", f"[ERROR] {e.message}" + (f"   (x{e.count})" if e.count > 1 else "")]
            out += [f"  {line}" for line in e.stack]
            out += ["```", ""]
        if r.notes:
            out += ["Engine notes (not Lua errors):", ""]
            out += [f"- `{n}`" for n in r.notes]
            out.append("")
    out += ["## Needs a human", ""]
    out += [f"- {line}" for line in human_only]
    return "\n".join(out) + "\n"


# Main ------------------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--maps", help="comma-separated maps from the plan (default: all)")
    ap.add_argument("--port", type=int, default=srcds.DEFAULT_PORT)
    args = ap.parse_args()
    plan = full_plan()
    if args.maps:
        wanted = args.maps.split(",")
        unknown = set(wanted) - {r.map for r in plan}
        if unknown:
            ap.error(f"not in the plan: {', '.join(sorted(unknown))}")
        plan = [r for r in plan if r.map in wanted]

    # A run of some maps keeps the full run's report: its own name carries the time.
    stamp = datetime.date.today().isoformat() + (datetime.datetime.now().strftime("-%H%M") if args.maps else "")
    out_dir = srcds.ARTIFACTS / f"ingame-{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    server = srcds.make_server(plan[0].map, args.port)
    data_root = server.install.data_dir / DATA_NAME
    identity = AddonIdentity.of(server.install)
    deploy(data_root)
    harness = Harness(server, data_root, out_dir)
    started = datetime.datetime.now()
    try:
        results = harness.run(plan)
    finally:
        server.stop()
        if (data_root / "results").exists():
            shutil.copytree(data_root / "results", out_dir / "results", dirs_exist_ok=True)
        shutil.rmtree(data_root, ignore_errors=True)
    header = "\n".join([
        f"# In-game test report, {stamp}",
        "",
        f"Run {started:%Y-%m-%d %H:%M} by `.devtools/bin/ingame_tests.py` on GMod's dedicated server "
        f"(srcds_win64.exe in the CrossOver bottle {srcds.BOTTLE!r}, port {args.port}).",
        f"Addon tested: {identity.describe()}.",
        f"Records and each map's console log: `{out_dir.relative_to(REPO)}/`.",
    ])
    report = srcds.ARTIFACTS / f"ingame-report-{stamp}.md"
    report.write_text(render_report(results, header, HUMAN_ONLY))
    (out_dir / "results.json").write_text(json.dumps([_as_json(r) for r in results], indent=2))
    print(f"report: {report}")
    failed = any(s.status in ("fail", "error", "timeout") for r in results for s in r.steps) or any(r.errors for r in results)
    return 1 if failed else 0


def _as_json(r: MapResult) -> Dict[str, object]:
    return {
        "map": r.map,
        "steps": [{"check": s.check, "status": s.status, "checks": [c.__dict__ for c in s.checks],
                   "info": s.info, "error": s.error, "seconds": s.seconds} for s in r.steps],
        "lua_errors": [{"message": e.message, "stack": list(e.stack), "count": e.count} for e in r.errors],
        "notes": list(r.notes),
    }


if __name__ == "__main__":
    sys.exit(main())
