#!/usr/bin/env python3
"""Build a navigation bench map: a region of a real map, cordoned off.

A bench is a part of a shipped map (TF2's own geometry, its static props
and displacements) cut out by a cordon box, with spawns put inside it, so
the same errands can be run on it again and again without the rest of
the map or its game (ns_bench_run.py runs them). Each bench is named in
BENCHES: the map it comes from, the cordon box, and where each team
spawns.

The steps, each through a tool that already does it:

  1. decompile the map with BSPSource (java; BSPSRC_JAR, default
     ~/.local/share/bspsrc-1.4.8/bspsrc.jar) to <bench>.vmf;
  2. drop every point entity outside the box (vbsp's cordon cuts brushes,
     never point entities or static props) and every spawn, then add the
     bench's spawns (info_player_teamspawn, info_player_start);
  3. set the cordon (hammer-mcp's set_cordon) and compile
     (hammer-mcp's run_compile, the MapCompile bottle; TF2's content
     mounted there through its cfg/mount.cfg);
  4. with --install, copy the .bsp into the dedicated server's maps.

Output goes to .devtools/artifacts/maps/benches/. Run from the repo root:

    python3 .devtools/bin/ns_bench_map.py ns_bench_watchtower [--install]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

REPO = Path(__file__).resolve().parents[2]
HAMMER = Path.home() / "Repositories" / "hammer-mcp"
OUT = REPO / ".devtools" / "artifacts" / "maps" / "benches"
BSPSRC_JAR = Path(os.environ.get("BSPSRC_JAR", Path.home() / ".local/share/bspsrc-1.4.8/bspsrc.jar"))
BSPSRC_MAIN = "info.ata4.bspsrc.app.src.cli.BspSourceCli"
TF_MAPS = Path.home() / "Library/Application Support/CrossOver/Bottles/Steam/drive_c/Program Files (x86)/Steam/steamapps/common/Team Fortress 2/tf/maps"
SERVER_MAPS = Path.home() / "Library/Application Support/CrossOver/Bottles/GModServer/drive_c/Steam/steamapps/common/GarrysModServer/garrysmod/maps"

RED, BLU = 2, 3
Vec = Tuple[float, float, float]


@dataclass(frozen=True)
class Spawn:
    team: int
    origin: Vec
    yaw: float


@dataclass(frozen=True)
class Bench:
    source: Path
    mins: Vec
    maxs: Vec
    spawns: Tuple[Spawn, ...]

    def contains(self, p: Vec) -> bool:
        return all(lo <= v <= hi for v, lo, hi in zip(p, self.mins, self.maxs))


def column(team: int, x: float, z: float, yaw: float) -> Tuple[Spawn, ...]:
    return tuple(Spawn(team, (x, y, z), yaw) for y in (-96, -32, 32, 96))


# arena_watchtower's middle: both sides' high ground (the pipes and the
# health packs on them, the log ramps up, the drops), the stairways and the
# point's platform; the spawn buildings (y beyond +-2000) are left out.
# RED spawns on the west ground, BLU on the east.
BENCHES = {
    "ns_bench_watchtower": Bench(
        source=TF_MAPS / "arena_watchtower.bsp",
        mins=(-1600, -1100, -192),
        maxs=(1600, 1100, 1344),
        spawns=column(RED, -1213, 16, 0) + column(BLU, 1212, 24, 180),
    ),
}

# Entities the bench keeps wherever they are: they have no place in the
# world, or a brush that the cordon already cuts.
KEPT_ANYWHERE = {"worldspawn"}
SPAWNS = {"info_player_teamspawn", "info_player_start"}
ENTITY = re.compile(r"^entity\n\{\n.*?^\}\n", re.S | re.M)
KEYVALUE = re.compile(r'^\t"([^"]+)" "([^"]*)"$', re.M)


def entity_text(classname: str, origin: Vec, keyvalues: dict, eid: int) -> str:
    lines = [f'\t"id" "{eid}"', f'\t"classname" "{classname}"', '\t"origin" "%g %g %g"' % origin]
    lines += [f'\t"{k}" "{v}"' for k, v in keyvalues.items()]
    return "entity\n{\n" + "\n".join(lines) + "\n}\n"


def cut(vmf: str, bench: Bench) -> Tuple[str, int, int]:
    """The VMF without the point entities outside the box nor the map's
    spawns, with the bench's spawns; and how many were dropped and added."""
    dropped = 0

    def keep(match: re.Match) -> str:
        nonlocal dropped
        block = match.group(0)
        top = dict(KEYVALUE.findall(block))  # one tab deep: the entity's own, not its solids'
        classname = top.get("classname", "")
        if classname in KEPT_ANYWHERE or "\n\tsolid\n" in block:
            return block
        origin = top.get("origin")
        inside = origin is not None and bench.contains(tuple(float(v) for v in origin.split()))
        if classname in SPAWNS or (origin is not None and not inside):
            dropped += 1
            return ""
        return block

    kept = ENTITY.sub(keep, vmf)
    top_id = max(int(i) for i in re.findall(r'^\t*"id" "(\d+)"', kept, re.M))
    added: List[str] = []
    for i, spawn in enumerate(bench.spawns):
        added.append(entity_text("info_player_teamspawn", spawn.origin,
                                 {"angles": f"0 {spawn.yaw:g} 0", "TeamNum": spawn.team, "StartDisabled": 0},
                                 top_id + 1 + i))
    first = bench.spawns[0]
    added.append(entity_text("info_player_start", first.origin, {"angles": f"0 {first.yaw:g} 0"},
                             top_id + 1 + len(bench.spawns)))
    at = kept.index("\ncameras\n") + 1 if "\ncameras\n" in kept else len(kept)
    return kept[:at] + "".join(added) + kept[at:], dropped, len(added)


def decompile(source: Path, vmf: Path) -> None:
    done = subprocess.run(["java", "-cp", str(BSPSRC_JAR), BSPSRC_MAIN, "-o", str(vmf), str(source)],
                          capture_output=True, text=True)
    if done.returncode != 0 or not vmf.exists():
        sys.exit(f"BSPSource failed on {source}:\n{done.stdout[-2000:]}{done.stderr[-2000:]}")


def hammer(calls: List[Tuple[str, dict]]) -> dict:
    """Runs hammer-mcp tools in order; each one's JSON result by name."""
    argv = ["node", str(HAMMER / ".devtools/bin/mcp-call.mjs")]
    for name, args in calls:
        argv += [name, json.dumps(args)]
    done = subprocess.run(argv, cwd=HAMMER, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(f"hammer-mcp failed:\n{done.stdout[-3000:]}{done.stderr[-3000:]}")
    results = {}
    for section in done.stdout.split("\n=== ")[1:]:
        name, _, body = section.partition("\n")
        results[name.split()[0]] = json.loads(body[body.index("{"):])
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("bench", choices=sorted(BENCHES))
    parser.add_argument("--install", action="store_true", help="copy the .bsp into the dedicated server's maps")
    args = parser.parse_args()
    bench = BENCHES[args.bench]
    OUT.mkdir(parents=True, exist_ok=True)
    vmf = OUT / f"{args.bench}.vmf"
    decompile(bench.source, vmf)
    text, dropped, added = cut(vmf.read_text(encoding="utf-8", errors="surrogateescape"), bench)
    vmf.write_text(text, encoding="utf-8", errors="surrogateescape")
    print(f"{vmf.name}: {dropped} point entities outside the box or spawns dropped, {added} spawns added")
    results = hammer([
        ("set_cordon", {"path": str(vmf), "mins": list(bench.mins), "maxs": list(bench.maxs), "confirm": True,
                        "backup": False}),
        ("run_compile", {"vmf": str(vmf), "toolchain": "stock", "fast": True, "confirm": True}),
    ])
    compiled = results["run_compile"]
    for stage in compiled["stages"]:
        print(f"{stage['stage']}: exit {stage['exitCode']}, {len(stage['findings'])} findings")
        for line in stage.get("stdoutTail", "").splitlines():
            if "Error loading studio model" in line or "LEAKED" in line:
                print("  " + line)
    if not compiled["bspExists"] or any(s["exitCode"] != 0 for s in compiled["stages"]):
        sys.exit("the compile failed")
    bsp = vmf.with_suffix(".bsp")
    print(f"{bsp} ({compiled['bspBytes']} bytes)")
    if args.install:
        shutil.copy2(bsp, SERVER_MAPS / bsp.name)
        print(f"installed {SERVER_MAPS / bsp.name}")


if __name__ == "__main__":
    main()
