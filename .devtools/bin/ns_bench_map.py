#!/usr/bin/env python3
"""Build a navigation bench map: a region of a real map, cordoned off.

A bench is a part of a shipped map (TF2's own geometry, its static props
and displacements) cut out by a cordon box, with spawns put inside it, so
the same errands can be run on it again and again without the rest of
the map or its game (ns_bench_run.py runs them). Each bench is named in
BENCHES: the map it comes from, the cordon box, and where each team
spawns. A bench's name is dev_<origin>_<purpose>: dev_ marks a map not for
production, the second word is the map (or place) it comes from, the rest
what it tests (dev_watchtower_ns_locomotion).

The steps, each through a tool that already does it:

  1. decompile the map with BSPSource (java; BSPSRC_JAR, default
     ~/.local/share/bspsrc-1.4.8/bspsrc.jar) to <bench>.vmf;
  2. cut the box out (cut): drop the world brushes, brush entities, point
     entities and static props outside it, and every spawn, then add the
     bench's spawns (info_player_teamspawn, info_player_start). GMod's
     vbsp ignores a VMF's cordons (hammer-mcp's set_cordon compiled the
     whole map), so the cut is made here;
  3. seal the box with skybox slabs (hammer-mcp's write_vmf_solid) and
     compile (hammer-mcp's run_compile, the MapCompile bottle; TF2's
     content mounted there through its cfg/mount.cfg);
  4. with --install, copy the .bsp into the dedicated server's maps.

Output goes to .devtools/artifacts/maps/benches/. Run from the repo root:

    python3 .devtools/bin/ns_bench_map.py dev_watchtower_ns_locomotion [--install]
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

    def overlaps(self, lo: Vec, hi: Vec) -> bool:
        return all(a < bhi and b < ahi for a, ahi, b, bhi in zip(lo, hi, self.mins, self.maxs))


def column(team: int, x: float, z: float, yaw: float) -> Tuple[Spawn, ...]:
    return tuple(Spawn(team, (x, y, z), yaw) for y in (-96, -32, 32, 96))


# arena_watchtower's middle: both sides' high ground (the pipes and the
# health packs on them, the log ramps up, the drops), the stairways and the
# point's platform; the spawn buildings (y beyond +-2000) are left out.
# RED spawns on the west ground, BLU on the east.
BENCHES = {
    "dev_watchtower_ns_locomotion": Bench(
        source=TF_MAPS / "arena_watchtower.bsp",
        mins=(-1600, -1100, -192),
        maxs=(1600, 1100, 1344),
        spawns=column(RED, -1213, 16, 0) + column(BLU, 1212, 24, 180),
    ),
}

SPAWNS = {"info_player_teamspawn", "info_player_start"}
SEAL = "TOOLS/TOOLSSKYBOX"
SEAL_THICKNESS = 16
WORLD = re.compile(r"^world\n\{\n.*?^\}\n", re.S | re.M)
ENTITY = re.compile(r"^entity\n\{\n.*?^\}\n", re.S | re.M)
SOLID = re.compile(r"^\tsolid\n\t\{\n.*?^\t\}\n", re.S | re.M)
KEYVALUE = re.compile(r'^\t"([^"]+)" "([^"]*)"$', re.M)
PLANE_POINT = re.compile(r"\(([-\d.e+]+) ([-\d.e+]+) ([-\d.e+]+)\)")


def brush_bounds(solid: str) -> Tuple[Vec, Vec]:
    """A brush's bounds by its sides' plane points (BSPSource puts them on the faces)."""
    points = [tuple(float(v) for v in p) for line in solid.splitlines() if '"plane"' in line
              for p in PLANE_POINT.findall(line)]
    return tuple(min(c) for c in zip(*points)), tuple(max(c) for c in zip(*points))


def shell(mins: Vec, maxs: Vec, thickness: float) -> List[dict]:
    """Six slabs around the box, sealing it."""
    (x0, y0, z0), (x1, y1, z1), t = mins, maxs, thickness
    boxes = [((x0 - t, y0 - t, z0 - t), (x1 + t, y1 + t, z0)),  # floor
             ((x0 - t, y0 - t, z1), (x1 + t, y1 + t, z1 + t)),  # ceiling
             ((x0 - t, y0 - t, z0), (x0, y1 + t, z1)),  # west
             ((x1, y0 - t, z0), (x1 + t, y1 + t, z1)),  # east
             ((x0, y0 - t, z0), (x1, y0, z1)),  # south
             ((x0, y1, z0), (x1, y1 + t, z1))]  # north
    return [{"shape": "box", "mins": list(lo), "maxs": list(hi)} for lo, hi in boxes]


def entity_text(classname: str, origin: Vec, keyvalues: dict, eid: int) -> str:
    lines = [f'\t"id" "{eid}"', f'\t"classname" "{classname}"', '\t"origin" "%g %g %g"' % origin]
    lines += [f'\t"{k}" "{v}"' for k, v in keyvalues.items()]
    return "entity\n{\n" + "\n".join(lines) + "\n}\n"


def cut(vmf: str, bench: Bench) -> Tuple[str, int, int]:
    """The VMF with only what lies in the box (world brushes, brush entities
    with a brush in it, point entities and static props standing in it),
    the map's spawns replaced by the bench's; and how many things were
    dropped and added. (vbsp ignores a VMF's cordons, so the cut is made here.)"""
    dropped = 0

    def keep_solid(match: re.Match) -> str:
        nonlocal dropped
        if bench.overlaps(*brush_bounds(match.group(0))):
            return match.group(0)
        dropped += 1
        return ""

    def keep_entity(match: re.Match) -> str:
        nonlocal dropped
        block = match.group(0)
        solids = SOLID.findall(block)
        if solids:
            inside = any(bench.overlaps(*brush_bounds(s)) for s in solids)
        else:
            top = dict(KEYVALUE.findall(block))  # one tab deep: the entity's own, not its solids'
            origin = top.get("origin")
            inside = top.get("classname") not in SPAWNS and (
                origin is None or bench.contains(tuple(float(v) for v in origin.split())))
        if inside:
            return block
        dropped += 1
        return ""

    kept = WORLD.sub(lambda world: SOLID.sub(keep_solid, world.group(0)), vmf)
    kept = ENTITY.sub(keep_entity, kept)
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
    print(f"{vmf.name}: {dropped} brushes and entities outside the box (or spawns) dropped, {added} spawns added")
    results = hammer([
        ("write_vmf_solid", {"path": str(vmf), "solids": shell(bench.mins, bench.maxs, SEAL_THICKNESS),
                             "material": SEAL, "confirm": True, "backup": False}),
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
