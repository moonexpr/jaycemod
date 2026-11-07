#!/usr/bin/env python3
"""Build dev_3house, the room-operations bench map, through hammer-mcp.

Three sealed houses in a row on grass, under a sky box (x -2048..2048,
y -1024..1024, the ground's top at z 0):

  RED's house   x -1760..-1120  RED's spawn room, its door east
  the bench     x  -384..384    one room, a doorway in each wall
  BLU's house   x  1120..1760   BLU's spawn room, its door west

The bench stands in a walled court, its wall COURT out from the bench's on every side and a
house's height, so neither spawn sees the bench nor the other (their doors and the bench's lie on
one line); its east and west walls each have two gateways, GATE wide, near their ends, none on
that line.

Every doorway is DOOR wide and DOOR_HEIGHT high, room for TF2's shutter
doors; every wall has windows of breakable glass (func_breakable, which the
war's rooms read as windows). Each house stands on a floor slab FLOOR_TOP
above the grass, under a roof, so the war's rooms (wartactics.rooms) find
each roofed, sealed (its doorways well under a fifth of its walls) and a
room.

A spawn room holds the classic amenities: twelve info_player_teamspawns, a
func_respawnroom filling it, a resupply locker (prop_dynamic) and its
func_regenerate, and at its door a shutter (func_door rising into the wall)
opened by a trigger_multiple for its own team (filter_activator_tfteam), a
func_respawnroomvisualizer across the doorway outside it.

Named points for a bench's checks: red_muster (RED's spawn room's middle),
bench_room (the bench's middle) and bench_danger (outside the bench on
BLU's side); bench_alarm, the bench's ent_room_alarm.

Writes .devtools/artifacts/maps/dev_3house.vmf (anew: an old one is moved
aside), renders it top-down, from the side and through the bench's doors,
and its floor plan (dev_3house_*.png beside it), compiles it with
run_compile and, with --install, copies the .bsp into the dedicated server's
maps folder. Its nav mesh is the server's to generate (nav_generate).

Needs hammer-mcp at ~/Repositories/hammer-mcp, built and configured (its
MapCompile bottle). Run from the repo root:

    python3 .devtools/bin/dev_3house_map.py [--install] [--no-compile]
"""
import argparse
import base64
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HAMMER = Path.home() / "Repositories" / "hammer-mcp"
OUT = REPO / ".devtools" / "artifacts" / "maps"
NAME = "dev_3house"
VMF = OUT / f"{NAME}.vmf"
SERVER_MAPS = Path.home() / "Library/Application Support/CrossOver/Bottles/GModServer/drive_c/Steam/steamapps/common/GarrysModServer/garrysmod/maps"

GRASS = "GM_CONSTRUCT/GRASS_13"
FLOOR = "DEV/DEV_MEASUREGENERIC01B"
WALL = "DEV/DEV_MEASUREWALL01A"
GLASS = "GLASS/REFLECTIVEGLASS001"
SKY = "TOOLS/TOOLSSKYBOX"
NODRAW = "TOOLS/TOOLSNODRAW"
TRIGGER = "TOOLS/TOOLSTRIGGER"
LOCKER = "models/props_gameplay/resupply_locker.mdl"

# The world's extent, the sky's height, and the ground's depth.
HALF_X, HALF_Y, SKY_TOP, GROUND = 2048, 1024, 1024, 64
# A house: its floor slab's top, its walls' thickness and height above the slab, its roof's
# thickness and overhang.
FLOOR_TOP, WALL_T, HOUSE_HEIGHT, ROOF_T, EAVE = 8, 32, 192, 16, 16
# A doorway, room for a TF2 shutter; a window, its sill above the floor; a pane's thickness.
DOOR, DOOR_HEIGHT = 128, 144
WINDOW, WINDOW_SILL, WINDOW_HEIGHT, PANE = 96, 48, 64, 4
# The bench's room (its inside), the spawn rooms' (theirs), and where a spawn house stands.
ROOM_SIZE, SPAWN_SIZE, SPAWN_X = 768, 640, 1440
# A spawn room's starts: columns in from its back wall, rows across it.
SPAWN_COLUMNS, SPAWN_ROWS = (96, 192, 288), (-216, -72, 72, 216)
# The resupply locker's reach behind its origin, and the volume before it it serves
# (ent_gameplay_locker's): along its facing, across, up.
LOCKER_BACK, REGEN_ALONG, REGEN_ACROSS, REGEN_UP = 16.25, (-16, 72), 48, 113
# Where a door's trigger reaches from the doorway, each side.
DOOR_TRIGGER_REACH = 96
# The bench's court: how far out from the bench's walls its wall stands, its gateways' width, and
# how far from the court's axis each gateway's middle is.
COURT, GATE, GATE_OFF = 288, 128, 512
TEAMS = {"red": 2, "blu": 3}


def box(mins, maxs):
    return {"shape": "box", "mins": list(mins), "maxs": list(maxs)}


def solids(shapes, material=None, materials=None, entity_id=None):
    args = {"path": str(VMF), "solids": shapes, "confirm": True, "backup": False}
    if material:
        args["material"] = material
    if materials:
        args["materials"] = materials
    if entity_id is not None:
        args["entityId"] = entity_id
    return ("write_vmf_solid", args)


def entity(**keyvalues):
    return {"op": "add", "keyvalues": {k: str(v) for k, v in keyvalues.items()}}


class House:
    """A sealed house centred at (cx, 0), its inside size square: its world solids, and the
    brush entities and point entities in it. Openings are (side, along, kind): side one of
    "north", "south", "east", "west", along the offset of its centre along that wall from the
    house's middle, kind "door" or "window"."""

    def __init__(self, cx, size, openings):
        self.cx, self.h = cx, size / 2
        self.openings = openings
        self.points = []  # point entities' keyvalues
        self.brushes = []  # (keyvalues, shapes, material)

    def inside(self):
        return (self.cx - self.h, -self.h, FLOOR_TOP), (self.cx + self.h, self.h, FLOOR_TOP + HOUSE_HEIGHT)

    def doorway(self, side):
        """Where a wall's doorway is: the wall's axis, its inner and outer faces' coordinate,
        and the doorway's centre along it."""
        for s, along, kind in self.openings:
            if s == side and kind == "door":
                return self.face(side) + (self.centre(side) + along,)
        raise ValueError(f"no door on the {side}")

    def face(self, side):
        h, cx = self.h, self.cx
        inner = {"north": h, "south": -h, "east": cx + h, "west": cx - h}[side]
        out = 1 if side in ("north", "east") else -1
        return ("x" if side in ("north", "south") else "y"), inner, inner + out * WALL_T

    def centre(self, side):
        return self.cx if side in ("north", "south") else 0

    def walls(self):
        """The four walls, cut at their openings; north and south cover the corners."""
        shapes = []
        top = FLOOR_TOP + HOUSE_HEIGHT
        for side in ("north", "south", "east", "west"):
            axis, inner, outer = self.face(side)
            a, b = sorted((inner, outer))
            if axis == "x":
                lo, hi = self.cx - self.h - WALL_T, self.cx + self.h + WALL_T
            else:
                lo, hi = -self.h, self.h
            cuts = sorted((self.centre(side) + along, kind) for s, along, kind in self.openings if s == side)
            start = lo
            for at, kind in cuts:
                width, bottom, height = (DOOR, 0, FLOOR_TOP + DOOR_HEIGHT) if kind == "door" else \
                    (WINDOW, FLOOR_TOP + WINDOW_SILL, FLOOR_TOP + WINDOW_SILL + WINDOW_HEIGHT)
                pieces = [(start, at - width / 2, 0, top), (at - width / 2, at + width / 2, height, top)]
                if bottom > 0:
                    pieces.append((at - width / 2, at + width / 2, 0, bottom))
                for p0, p1, z0, z1 in pieces:
                    shapes.append(box((p0, a, z0), (p1, b, z1)) if axis == "x" else box((a, p0, z0), (b, p1, z1)))
                if kind == "window":
                    mid = (a + b) / 2
                    pane = (box((at - width / 2, mid - PANE / 2, bottom), (at + width / 2, mid + PANE / 2, height))
                            if axis == "x" else
                            box((mid - PANE / 2, at - width / 2, bottom), (mid + PANE / 2, at + width / 2, height)))
                    self.brushes.append(({"classname": "func_breakable", "material": "0", "health": "1",
                                          "propdata": "0"}, [pane], GLASS))
                start = at + width / 2
            last = (start, hi, 0, top)
            shapes.append(box((last[0], a, 0), (last[1], b, top)) if axis == "x" else box((a, last[0], 0), (b, last[1], top)))
        return shapes

    def calls(self):
        (x0, y0, _), (x1, y1, _) = self.inside()
        top = FLOOR_TOP + HOUSE_HEIGHT
        o = WALL_T + EAVE
        return [
            solids([box((x0, y0, 0), (x1, y1, FLOOR_TOP))], materials={"top": FLOOR, "sides": WALL, "bottom": NODRAW}),
            solids(self.walls(), WALL),
            solids([box((x0 - o, y0 - o, top), (x1 + o, y1 + o, top + ROOF_T))],
                   materials={"top": FLOOR, "sides": WALL, "bottom": WALL}),
        ]


def spawn_house(team, side):
    """A team's spawn house on side (-1 west, 1 east), its door facing the bench."""
    toward = "east" if side < 0 else "west"
    windows = [("north", -160, "window"), ("north", 160, "window"), ("south", -160, "window"),
               ("south", 160, "window"), (("west" if side < 0 else "east"), 0, "window")]
    house = House(side * SPAWN_X, SPAWN_SIZE, [(toward, 0, "door")] + windows)
    number, h, cx = TEAMS[team], house.h, house.cx
    inward = -side  # from its back wall toward its door
    back = cx - inward * h
    yaw = 0 if inward > 0 else 180
    stand = FLOOR_TOP + 8
    for column in SPAWN_COLUMNS:
        for row in SPAWN_ROWS:
            house.points.append({"classname": "info_player_teamspawn", "origin": f"{back + inward * column} {row} {stand}",
                                 "angles": f"0 {yaw} 0", "TeamNum": number, "targetname": f"{team}_spawn"})
    house.points.append({"classname": "info_target", "targetname": f"{team}_muster", "origin": f"{cx} 0 {FLOOR_TOP}"})
    # the spawn room, filling the house
    house.brushes.append(({"classname": "func_respawnroom", "targetname": f"{team}_spawnroom", "TeamNum": number,
                           "StartDisabled": 0}, [box(*house.inside())], TRIGGER))
    # the resupply locker against the north wall, facing south, and the volume it serves
    lx, ly = cx, h - LOCKER_BACK
    house.points.append({"classname": "prop_dynamic", "targetname": f"{team}_locker", "model": LOCKER,
                         "origin": f"{lx} {ly} {FLOOR_TOP}", "angles": "0 270 0", "solid": 6,
                         "DefaultAnim": "idle"})
    house.brushes.append(({"classname": "func_regenerate", "TeamNum": number, "associatedmodel": f"{team}_locker"},
                          [box((lx - REGEN_ACROSS, ly - REGEN_ALONG[1], FLOOR_TOP),
                               (lx + REGEN_ACROSS, ly - REGEN_ALONG[0], FLOOR_TOP + REGEN_UP))], TRIGGER))
    # the door: a shutter in the wall rising into it, opened by its team's trigger, the
    # visualizer across the doorway's outer face
    _, inner, outer, along = house.doorway(toward)
    a, b = sorted((inner, outer))
    mid = (a + b) / 2
    shutter_top = FLOOR_TOP + DOOR_HEIGHT
    house.brushes.append(({"classname": "func_door", "targetname": f"{team}_door", "movedir": "-90 0 0",
                           "speed": 300, "wait": -1, "lip": 8, "spawnflags": 0, "forceclosed": 1},
                          [box((mid - 4, along - DOOR / 2, 0), (mid + 4, along + DOOR / 2, shutter_top))], FLOOR))
    house.points.append({"classname": "filter_activator_tfteam", "targetname": f"{team}_filter", "TeamNum": number,
                         "Negated": 0})
    reach = DOOR_TRIGGER_REACH
    house.brushes.append(({"classname": "trigger_multiple", "targetname": f"{team}_door_trigger",
                           # clients, NPCs and everything else: a NextBot is no NPC to a trigger
                           "filtername": f"{team}_filter", "spawnflags": 67, "wait": 1,
                           "_outputs": [("OnStartTouchAll", f"{team}_door,Open,,0,-1"),
                                        ("OnEndTouchAll", f"{team}_door,Close,,0,-1")]},
                          [box((a - reach, along - DOOR / 2 - 16, FLOOR_TOP), (b + reach, along + DOOR / 2 + 16,
                                                                               shutter_top))], TRIGGER))
    lip = outer - (2 if outer > inner else -2)
    v0, v1 = sorted((lip, outer))
    house.brushes.append(({"classname": "func_respawnroomvisualizer", "respawnroomname": f"{team}_spawnroom",
                           "solid_to_enemies": 1, "TeamNum": number},
                          [box((v0, along - DOOR / 2, 0), (v1, along + DOOR / 2, shutter_top))], NODRAW))
    house.points.append({"classname": "light", "origin": f"{cx} 0 {FLOOR_TOP + HOUSE_HEIGHT - 24}",
                         "_light": "255 240 220 300"})
    return house


def bench_house():
    """The bench: one room, a doorway centred in each wall, windows either side of each."""
    openings = []
    for side in ("north", "south", "east", "west"):
        openings += [(side, 0, "door"), (side, -224, "window"), (side, 224, "window")]
    house = House(0, ROOM_SIZE, openings)
    house.points.append({"classname": "info_target", "targetname": "bench_room", "origin": f"0 0 {FLOOR_TOP}"})
    # its alarm, which the squad holding it raises when it stacks up, a guard missing
    house.points.append({"classname": "ent_room_alarm", "targetname": "bench_alarm",
                         "origin": f"0 0 {FLOOR_TOP + HOUSE_HEIGHT - 32}"})
    house.points.append({"classname": "info_target", "targetname": "bench_danger",
                         "origin": f"{ROOM_SIZE // 2 + WALL_T + 256} 0 0"})
    for x, y in ((-192, -192), (192, -192), (-192, 192), (192, 192)):
        house.points.append({"classname": "light", "origin": f"{x} {y} {FLOOR_TOP + HOUSE_HEIGHT - 24}",
                             "_light": "255 240 220 250"})
    return house


def houses():
    return [spawn_house("red", -1), bench_house(), spawn_house("blu", 1)]


def court():
    """The court's wall round the bench, its east and west walls cut at their gateways."""
    inner = ROOM_SIZE // 2 + WALL_T + COURT
    outer, top = inner + WALL_T, HOUSE_HEIGHT
    shapes = [box((-outer, inner, 0), (outer, outer, top)), box((-outer, -outer, 0), (outer, -inner, top))]
    cuts = sorted([-GATE_OFF - GATE // 2, -GATE_OFF + GATE // 2, GATE_OFF - GATE // 2, GATE_OFF + GATE // 2])
    spans = [(-inner, cuts[0]), (cuts[1], cuts[2]), (cuts[3], inner)]
    for x0, x1 in ((-outer, -inner), (inner, outer)):
        shapes += [box((x0, y0, 0), (x1, y1, top)) for y0, y1 in spans]
    return shapes


def calls(built):
    shell = [
        box((-HALF_X - 16, -HALF_Y - 16, SKY_TOP), (HALF_X + 16, HALF_Y + 16, SKY_TOP + 16)),  # sky
        box((-HALF_X - 16, HALF_Y, -GROUND), (HALF_X + 16, HALF_Y + 16, SKY_TOP)),  # north
        box((-HALF_X - 16, -HALF_Y - 16, -GROUND), (HALF_X + 16, -HALF_Y, SKY_TOP)),  # south
        box((-HALF_X - 16, -HALF_Y, -GROUND), (-HALF_X, HALF_Y, SKY_TOP)),  # west
        box((HALF_X, -HALF_Y, -GROUND), (HALF_X + 16, HALF_Y, SKY_TOP)),  # east
    ]
    yield ("write_vmf", {"path": str(VMF), "skyname": "sky_day01_01", "confirm": True})
    yield solids(shell, SKY)
    yield solids([box((-HALF_X, -HALF_Y, -GROUND - 16), (HALF_X, HALF_Y, 0))],
                 materials={"top": GRASS, "sides": NODRAW, "bottom": NODRAW})
    for house in built:
        yield from house.calls()
    yield solids(court(), WALL)
    ops = [entity(classname="info_player_start", origin=f"{-SPAWN_X} 0 {FLOOR_TOP + 8}", angles="0 0 0"),
           entity(classname="light_environment", origin="0 0 900", angles="-50 30 0", pitch=-50,
                  _light="255 244 222 450", _ambient="160 180 210 120")]
    for house in built:
        ops += [entity(**kv) for kv in house.points]
    yield ("edit_vmf", {"path": str(VMF), "ops": ops, "confirm": True})


def brush_entities(built):
    """Every house's brush entities, added: (their ids, their shapes and material), in order."""
    listed = [b for house in built for b in house.brushes]
    ops, outputs = [], []
    for kv, _, _ in listed:
        kv = dict(kv)
        outputs.append(kv.pop("_outputs", []))
        ops.append(entity(**kv))
    answer = run([("edit_vmf", {"path": str(VMF), "ops": ops, "confirm": True})])
    ids = [int(n) for n in re.findall(r'"ids":\s*\[\s*(\d+)', answer)]
    if len(ids) != len(listed):
        raise SystemExit(f"added {len(listed)} brush entities, got ids for {len(ids)}")
    wiring = [{"op": "addOutput", "match": {"id": ids[i]}, "output": name, "value": value}
              for i, pairs in enumerate(outputs) for name, value in pairs]
    tool_calls = [solids(shapes, material, entity_id=ids[i]) for i, (_, shapes, material) in enumerate(listed)]
    if wiring:
        tool_calls.append(("edit_vmf", {"path": str(VMF), "ops": wiring, "confirm": True}))
    return tool_calls


def run(tool_calls):
    argv = ["node", str(HAMMER / ".devtools/bin/mcp-call.mjs")]
    for name, args in tool_calls:
        argv += [name, json.dumps(args)]
    done = subprocess.run(argv, cwd=HAMMER, capture_output=True, text=True)
    if done.returncode != 0 or "(error)" in done.stdout:
        print(done.stdout[-6000:])
        print(done.stderr[-3000:], file=sys.stderr)
        sys.exit(done.returncode or 1)
    return done.stdout


def save_image(output, path):
    """The PNG a render tool answered, written to path; the rest of its answer printed."""
    for line in output.splitlines():
        if line.startswith("{") and '"image"' in line:
            path.write_bytes(base64.b64decode(json.loads(line)["data"]))
            print(f"rendered {path}")
        elif not line.startswith("{"):
            print(line[:400])


VIEWS = {
    # straight down from under the sky over the whole row of houses
    "top": {"origin": [0, 0, SKY_TOP - 32], "angles": [90, 90, 0], "fov": 125, "width": 1024, "height": 512},
    # from the south, just inside the sky box, level with the houses, looking north at the row
    "side": {"origin": [0, -HALF_Y + 32, 72], "angles": [0, 90, 0], "fov": 125, "width": 1024, "height": 384},
    # from the grass between RED's house and the bench, looking east through the bench's west
    # and east doors at BLU's door
    "through": {"origin": [-SPAWN_X + 560, 0, 64], "angles": [0, 0, 0], "fov": 70, "width": 768, "height": 384},
    # inside RED's spawn room, from its back corner toward its door: starts, locker, shutter
    "spawn": {"origin": [-SPAWN_X - SPAWN_SIZE / 2 + 24, -SPAWN_SIZE / 2 + 24, FLOOR_TOP + 120],
              "lookAt": [-SPAWN_X + SPAWN_SIZE / 2, 0, FLOOR_TOP + 48], "fov": 100, "width": 768, "height": 432},
}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--install", action="store_true", help="copy the .bsp into the dedicated server's maps")
    parser.add_argument("--no-compile", action="store_true", help="write and render only")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if VMF.exists():
        VMF.rename(VMF.with_suffix(".vmf.old"))
    built = houses()
    run(list(calls(built)))
    run(brush_entities(built))
    for view, camera in VIEWS.items():
        save_image(run([("render_vmf_view", {"path": str(VMF), **camera})]), OUT / f"{NAME}_{view}.png")
    save_image(run([("render_vmf_plan", {"path": str(VMF), "grid": 256, "width": 1400, "height": 800})]),
               OUT / f"{NAME}_plan.png")
    report = run([("read_vmf_leak", {"path": str(VMF)}), ("read_vmf_lint", {"path": str(VMF)})])
    print("\n".join(line for line in report.splitlines() if "unknown-classname" not in line)[-3000:])
    if args.no_compile:
        return
    print(run([("run_compile", {"vmf": str(VMF), "toolchain": "stock", "confirm": True})])[-2500:])
    bsp = VMF.with_suffix(".bsp")
    if args.install:
        shutil.copy2(bsp, SERVER_MAPS / bsp.name)
        print(f"installed {SERVER_MAPS / bsp.name}")


if __name__ == "__main__":
    main()
