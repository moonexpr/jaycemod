#!/usr/bin/env python3
"""Build ns_fixture, the NextSoldier pathing fixture map, through hammer-mcp.

A hall (x 0..3072, y -512..512, floor z 0) between RED's spawn (west) and
BLU's (east), with a KOTH point in the middle, and in between the geometry
that stopped soldiers on TF2 maps:

  A  a wall with a doorway off the straight line (x 448..480)
  B  a pit (x 1024..1280, 128 deep) beside a walkway, a player clip along
     the walkway's edge (the rail a bullet passes, cp_doublecross), stairs
     out of the pit's east end
  C  a thin stage plate over a crawlspace (cp_altitude's BLU stage), stairs
     up, a ramp down
  D  stairs under a clip ramp up to a ledge (cp_altitude's clip stairs)
  E  the point's base on the floor (a prop to stand on)

Writes .devtools/artifacts/maps/ns_fixture.vmf (anew: an old one is moved
aside), compiles it with run_compile and, with --install, copies the .bsp
into the dedicated server's maps folder.

Needs hammer-mcp at ~/Repositories/hammer-mcp, built and configured (its
MapCompile bottle). Run from the repo root:

    python3 .devtools/bin/ns_fixture_map.py [--install]
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HAMMER = Path.home() / "Repositories" / "hammer-mcp"
OUT = REPO / ".devtools" / "artifacts" / "maps"
VMF = OUT / "ns_fixture.vmf"
SERVER_MAPS = Path.home() / "Library/Application Support/CrossOver/Bottles/GModServer/drive_c/Steam/steamapps/common/GarrysModServer/garrysmod/maps"

FLOOR = "DEV/DEV_MEASUREGENERIC01B"
WALL = "DEV/DEV_MEASUREWALL01A"
CLIP = "TOOLS/TOOLSPLAYERCLIP"
TRIGGER = "TOOLS/TOOLSTRIGGER"


def box(mins, maxs):
    return {"shape": "box", "mins": list(mins), "maxs": list(maxs)}


def solids(shapes, material=None, materials=None):
    args = {"path": str(VMF), "solids": shapes, "confirm": True, "backup": False}
    if material:
        args["material"] = material
    if materials:
        args["materials"] = materials
    return ("write_vmf_solid", args)


def entity(**keyvalues):
    return {"op": "add", "keyvalues": {k: str(v) for k, v in keyvalues.items()}}


def calls():
    shell = [
        box((-16, -528, -144), (3088, 528, -128)),  # bottom
        box((-16, -528, 320), (3088, 528, 336)),  # ceiling
        box((-16, 512, -128), (3088, 528, 320)),  # north
        box((-16, -528, -128), (3088, -512, 320)),  # south
        box((-16, -512, -128), (0, 512, 320)),  # west
        box((3072, -512, -128), (3088, 512, 320)),  # east
    ]
    ground = [
        box((0, -512, -128), (1024, 512, 0)),
        box((1280, -512, -128), (3072, 512, 0)),
        box((1024, 256, -128), (1280, 512, 0)),  # B: the walkway beside the pit
    ]
    yield ("write_vmf", {"path": str(VMF), "skyname": "sky_day01_01", "confirm": True})
    yield solids(shell, WALL)
    yield solids(ground, materials={"top": FLOOR, "sides": WALL, "bottom": "TOOLS/TOOLSNODRAW"})
    # A: a wall with a doorway 64 wide at y 128..192
    yield solids([box((448, -512, 0), (480, 128, 320)), box((448, 192, 0), (480, 512, 320))], WALL)
    # B: the pit's floor and the stairs out of its east end, the rail clip along the walkway
    yield solids([box((1024, -512, -144), (1280, 256, -128))], FLOOR)
    yield solids([{"shape": "stairs", "mins": [1152, -512, -128], "maxs": [1280, -384, 0], "steps": 8, "direction": "+x"}],
                 materials={"top": FLOOR, "sides": WALL})
    yield solids([box((1024, 256, 0), (1280, 264, 48))], CLIP)
    # C: the stage, a plate 8 thick with 48 open beneath, stairs up from the west, a ramp down to the east
    yield solids([box((1536, -256, 48), (1792, 256, 56))], materials={"top": FLOOR, "sides": WALL, "bottom": WALL})
    yield solids([{"shape": "stairs", "mins": [1472, -64, 0], "maxs": [1536, 64, 56], "steps": 3, "direction": "+x"}],
                 materials={"top": FLOOR, "sides": WALL})
    yield solids([{"shape": "wedge", "mins": [1792, -64, 0], "maxs": [1920, 64, 56], "slopeAxis": "x", "high": "min"}],
                 materials={"top": FLOOR, "sides": WALL, "bottom": "TOOLS/TOOLSNODRAW"})
    # D: stairs up to a ledge along the north wall, a clip ramp over the stairs
    yield solids([{"shape": "stairs", "mins": [2304, 320, 0], "maxs": [2432, 512, 64], "steps": 4, "direction": "+x"}],
                 materials={"top": FLOOR, "sides": WALL})
    yield solids([box((2432, 320, 0), (2688, 512, 64))], materials={"top": FLOOR, "sides": WALL})
    yield solids([{"shape": "wedge", "mins": [2304, 320, 0], "maxs": [2432, 512, 64], "slopeAxis": "x", "high": "max"}], CLIP)
    # entities: spawns, the point, light
    ops = []
    for i, y in enumerate((-96, -32, 32, 96)):
        ops.append(entity(classname="info_player_teamspawn", origin=f"96 {y} 8", angles="0 0 0", TeamNum=2,
                          targetname="red_spawn"))
        ops.append(entity(classname="info_player_teamspawn", origin=f"2976 {y} 8", angles="0 180 0", TeamNum=3,
                          targetname="blu_spawn"))
    ops.append(entity(classname="info_player_start", origin="96 0 8", angles="0 0 0"))
    ops.append(entity(classname="team_control_point_master", targetname="cp_master", origin="2048 0 160",
                      cpm_restrict_team_cap_win="1"))
    ops.append(entity(classname="team_control_point", targetname="cp_center", origin="2048 0 0",
                      point_index=0, point_default_owner=0, point_printname="Center", point_start_locked=0))
    ops.append(entity(classname="prop_dynamic", targetname="cp_center_prop", origin="2048 0 0",
                      model="models/props_gameplay/cap_point_base.mdl", solid=6))
    ops.append(entity(classname="tf_logic_koth", origin="2048 0 200", timer_length=180, unlock_point=5))
    for x in (256, 768, 1152, 1664, 2048, 2560, 2944):
        ops.append(entity(classname="light", origin=f"{x} 0 288", _light="255 255 255 600"))
    ops.append(entity(classname="trigger_capture_area", targetname="cp_center_area", area_cap_point="cp_center",
                      team_cancap_2=1, team_cancap_3=1, team_numcap_2=1, team_numcap_3=1, area_time_to_cap=5))
    yield ("edit_vmf", {"path": str(VMF), "ops": ops, "confirm": True})


def run(tool_calls):
    argv = ["node", str(HAMMER / ".devtools/bin/mcp-call.mjs")]
    for name, args in tool_calls:
        argv += [name, json.dumps(args)]
    done = subprocess.run(argv, cwd=HAMMER, capture_output=True, text=True)
    print(done.stdout[-6000:])
    if done.returncode != 0:
        print(done.stderr[-3000:], file=sys.stderr)
        sys.exit(done.returncode)
    return done.stdout


def capture_brush_id(listing):
    """The Hammer id of the trigger_capture_area, from read_vmf's text."""
    data = json.loads(listing[listing.index("{"):])
    for ent in data.get("entities", []):
        if ent.get("classname") == "trigger_capture_area":
            return ent["id"]
    raise SystemExit("no trigger_capture_area in the map")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--install", action="store_true", help="copy the .bsp into the dedicated server's maps")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if VMF.exists():
        VMF.rename(VMF.with_suffix(".vmf.old"))
    run(list(calls()))
    listing = run([("read_vmf", {"path": str(VMF), "classname": "trigger_capture_area"})])
    trigger = capture_brush_id(listing.split("=== read_vmf", 1)[1])
    run([("write_vmf_solid", {"path": str(VMF), "solids": [box((1984, -64, 0), (2112, 64, 128))],
                              "material": TRIGGER, "entityId": trigger, "confirm": True, "backup": False})])
    run([("read_vmf_leak", {"path": str(VMF)}), ("read_vmf_lint", {"path": str(VMF)}),
         ("run_compile", {"vmf": str(VMF), "toolchain": "stock", "fast": True, "confirm": True})])
    bsp = VMF.with_suffix(".bsp")
    if args.install:
        shutil.copy2(bsp, SERVER_MAPS / bsp.name)
        print(f"installed {SERVER_MAPS / bsp.name}")


if __name__ == "__main__":
    main()
