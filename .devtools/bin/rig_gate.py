#!/usr/bin/env python3
"""Gate a TF2 weapon's retarget onto a hands model: fail, with a nonzero exit, what goes past the evidence.

  rig_gate.py SWEP.lua [--hands MODEL] [--vpk PATH]...

The sequences gated are the ones the weapon can play: each activity its TFAnimations names
(addons/tf_weapons/lua/weapons/*.lua), every sequence of the class arms' animations that has it.
Over every frame of them, the hands posed as mdl_rig.solve poses them (which the addon's rig.lua is
held to by tests/tf_weapons_rig_test.lua):

  streams   no frame's animation data is empty (mdl_rig.EmptyStream)
  lengths   every hands bone sits at its own rest distance from its parent, within LENGTH_EPSILON
            (the ancestors held to the arms aside: rig.lua's ABOVE bones)
  mesh      the hands' mesh deforms no more than GMod's own animations deform it: per region (the
            edges whose ends are weighted most to the same two bones), the largest change of an edge's
            length over the c_arms fists' and the 16 HL2 c_ weapons' animations, bone-merged onto the
            hands as the engine merges them, is the envelope; an edge past it fails once the excess,
            projected through the game's camera at 1920x1080, reaches PIXEL_FLOOR

Prints each check and the worst cases; exits 0 only when all pass. The native envelope is computed
once a hands model and cached under .devtools/artifacts/rig_gate/.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import numpy as np

from mdl_rig import DEFAULT_VPKS, PROC_QUATINTERP, EmptyStream, Library, Model, RigError, quatinterp, solve
from rig_view import Camera, load_mesh, skin

REPO = Path(__file__).resolve().parents[2]
CACHE = REPO / ".devtools" / "artifacts" / "rig_gate"
HANDS = "models/weapons/c_arms_citizen.mdl"
NATIVE_ANIMATIONS = "models/weapons/c_arms_animations.mdl"
NATIVE_WEAPONS = ("357", "bugbait", "crossbow", "crowbar", "grenade", "irifle", "medkit", "physcannon", "pistol",
                  "rpg", "shotgun", "slam", "smg1", "stunstick", "superphyscannon", "toolgun")
# seq_admire translates the forearm (its forearm is 14.9 long, not 11.5): a stretch no rotation makes
NATIVE_EXCLUDED = {"seq_admire"}
SCREEN = (1920, 1080)
PIXEL_FLOOR = 1.0       # a mesh edge's excess over the native envelope, on screen
LENGTH_EPSILON = 1e-3   # units
MIN_EDGE = 0.05         # units: shorter bind-pose edges are left out of the regions
# Bumped whenever mdl_rig's decoding or rig_view's skinning changes: a cached envelope from before is dropped
ENVELOPE_VERSION = 2


def swep_animations(path: Path) -> Tuple[str, Dict[str, str]]:
    """The class arms model and the TFAnimations a SWEP file names, read from its text."""
    text = path.read_text()
    model = re.search(r'SWEP\.ViewModel\s*=\s*"([^"]+)"', text)
    block = re.search(r"SWEP\.TFAnimations\s*=\s*\{(.*?)\}", text, re.S)
    if not model or not block:
        raise RigError(f"{path}: no SWEP.ViewModel or SWEP.TFAnimations")
    return model.group(1), dict(re.findall(r'(\w+)\s*=\s*"([^"]+)"', block.group(1)))


class Regions:
    """The hands mesh's edges grouped by the two bones their ends are weighted most to."""

    def __init__(self, hands: Model, mesh):
        self.hands, self.mesh = hands, mesh
        tri = mesh.triangles
        edges = np.unique(np.sort(np.vstack([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]]), axis=1), axis=0)
        length = np.linalg.norm(mesh.positions[edges[:, 0]] - mesh.positions[edges[:, 1]], axis=1)
        keep = length > MIN_EDGE
        self.edges, self.bind = edges[keep], length[keep]
        top = mesh.bones[np.arange(len(mesh.bones)), np.argmax(mesh.weights, axis=1)]
        pairs = np.sort(np.stack([top[self.edges[:, 0]], top[self.edges[:, 1]]], axis=1), axis=1)
        self.keys = sorted({(int(a), int(b)) for a, b in pairs})
        self.members = {k: np.nonzero((pairs[:, 0] == k[0]) & (pairs[:, 1] == k[1]))[0] for k in self.keys}

    def name(self, key) -> str:
        return "/".join(self.hands.bones[b].name.replace("ValveBiped.Bip01_", "") for b in key)

    def change(self, pose) -> Tuple[np.ndarray, np.ndarray]:
        """Each edge's change of length (absolute), and the skinned vertices."""
        v, _ = skin(self.hands, self.mesh, pose)
        return np.abs(np.linalg.norm(v[self.edges[:, 0]] - v[self.edges[:, 1]], axis=1) - self.bind), v


def merged(hands: Model, gun: Model, label: str, frame: int):
    """A HL2 c_ weapon's frame bone-merged onto the hands by name, the helpers solved; None if the
    weapon lacks a hands bone."""
    w = gun.world(gun.pose(label, frame))
    out = {j: w[gun.index[b.name]] for j, b in enumerate(hands.bones) if b.name in gun.index}
    if any(j not in out and b.proctype != PROC_QUATINTERP for j, b in enumerate(hands.bones)):
        return None
    for j, b in enumerate(hands.bones):
        if j not in out:
            out[j] = quatinterp(hands, j, out)
    return out


def native_envelope(lib: Library, hands: Model, regions: Regions) -> Tuple[Dict, int, int]:
    """Per region, the largest edge change over GMod's own animations of these hands: cached."""
    CACHE.mkdir(parents=True, exist_ok=True)
    cache = CACHE / (hands.name.replace("/", "_") + ".json")
    if cache.exists():
        data = json.loads(cache.read_text())
        if data.get("version") == ENVELOPE_VERSION and data.get("regions") == [list(k) for k in regions.keys]:
            return {tuple(k): v for k, v in zip(data["regions"], data["envelope"])}, data["frames"], data["refused"]
    env = {k: 0.0 for k in regions.keys}
    frames = refused = 0
    sources = [(lib.model(NATIVE_ANIMATIONS), True)] + [(lib.model(f"models/weapons/c_{w}.mdl"), False) for w in NATIVE_WEAPONS]
    for model, own in sources:
        for s in model.sequences:
            if s.anim < 0 or s.label in NATIVE_EXCLUDED:
                continue
            for f in range(s.frames):
                try:
                    pose = merged(hands, model, s.label, f)
                except EmptyStream:
                    refused += 1
                    continue
                if pose is None:
                    break
                change, _ = regions.change(pose)
                for k in regions.keys:
                    env[k] = max(env[k], float(change[regions.members[k]].max()))
                frames += 1
    cache.write_text(json.dumps({"version": ENVELOPE_VERSION, "regions": [list(k) for k in regions.keys], "envelope": [env[k] for k in regions.keys],
                                 "frames": frames, "refused": refused}))
    return env, frames, refused


def gate(lib: Library, swep: Path, hands_name: str) -> bool:
    arms_name, animations = swep_animations(swep)
    arms, hands = lib.model(arms_name), lib.model(hands_name)
    anims = lib.model(arms.includes[0]) if arms.includes else arms
    wanted = set(animations.values())
    sequences = [s for s in anims.sequences if s.activity in wanted and s.anim >= 0]
    missing = wanted - {s.activity for s in sequences}
    print(f"{swep.name}: {arms_name} on {hands_name}")
    print(f"  sequences gated: {', '.join(s.label for s in sequences)}")
    ok = True
    if missing:
        print(f"FAIL activities with no sequence: {sorted(missing)}")
        ok = False

    mesh = load_mesh(lib, hands)
    regions = Regions(hands, mesh)
    env, native_frames, refused = native_envelope(lib, hands, regions)
    print(f"  native envelope: {native_frames} frames of GMod's own animations, {refused} empty frames refused, "
          f"{len(regions.keys)} mesh regions")

    camera = Camera(SCREEN)
    empty, worst_length, over = [], (0.0, ""), {}
    above = _above(hands, arms)
    for s in sequences:
        for f in range(s.frames):
            at = f"{s.label}@{f}"
            try:
                local = anims.pose(s.label, f)
            except EmptyStream:
                empty.append(at)
                continue
            pose = solve(arms, arms.world(local), hands)
            for j, b in enumerate(hands.bones):
                if b.parent < 0 or j in above or b.proctype == PROC_QUATINTERP:
                    continue
                d = np.linalg.norm(np.subtract(pose[j][0], pose[b.parent][0])) - np.linalg.norm(b.pos)
                if abs(d) > worst_length[0]:
                    worst_length = (abs(d), f"{at} {b.name}")
            change, v = regions.change(pose)
            for k in regions.keys:
                ids = regions.members[k]
                n = ids[int(np.argmax(change[ids]))]
                excess = change[n] - env[k]
                if excess <= 0:
                    continue
                i, j = regions.edges[n]
                xy, depth = camera.project(v[[i, j]])
                px = excess * np.linalg.norm(xy[0] - xy[1]) / max(np.linalg.norm(v[i] - v[j]), 1e-9)
                visible = bool(depth.min() > camera.NEAR and ((xy >= 0) & (xy <= SCREEN)).all())
                if px > over.get(k, (0.0,))[0]:
                    over[k] = (px, excess, at, visible)

    if empty:
        print(f"FAIL {len(empty)} frames with empty animation streams: {empty[:5]}")
        ok = False
    else:
        print("ok   no empty animation streams")
    if worst_length[0] > LENGTH_EPSILON:
        print(f"FAIL a bone off its rest length by {worst_length[0]:.5f} at {worst_length[1]}")
        ok = False
    else:
        print(f"ok   bone lengths, worst {worst_length[0]:.2e} units")
    failing = {k: o for k, o in over.items() if o[0] >= PIXEL_FLOOR}
    for k, (px, excess, at, visible) in sorted(over.items(), key=lambda kv: -kv[1][0]):
        verdict = "FAIL" if k in failing else "    "
        print(f"{verdict} mesh {regions.name(k):24s} {excess:.3f} units past native = {px:.2f} px "
              f"({'on' if visible else 'off'} screen) at {at}")
    if failing:
        ok = False
    else:
        print(f"ok   mesh: {len(over)} of {len(regions.keys)} regions past native, none by {PIXEL_FLOOR:g} px")
    print("PASS" if ok else "FAILED")
    return ok


def _above(hands: Model, arms: Model) -> set:
    """The hands bones rig.lua holds to the arms from below (ancestors of the paired bones)."""
    out, paired = set(), {j for j, b in enumerate(hands.bones) if "UpperArm" in b.name}
    for j in paired:
        p = hands.bones[j].parent
        while p >= 0:
            out.add(p)
            p = hands.bones[p].parent
    return out


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("swep", type=Path)
    ap.add_argument("--hands", default=HANDS)
    ap.add_argument("--vpk", action="append", type=Path)
    a = ap.parse_args(argv)
    return 0 if gate(Library(a.vpk or DEFAULT_VPKS), a.swep, a.hands) else 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RigError as e:
        print(f"rig_gate: {e}", file=sys.stderr)
        sys.exit(2)
