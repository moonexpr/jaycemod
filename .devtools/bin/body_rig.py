#!/usr/bin/env python3
"""The per-character transformer: a TF2 class's player animation on a GMod (ValveBiped) player model.

  body_rig.py corrections TF2_PLAYER GMOD_PLAYER     the correction a bone, rest pose to rest pose
  body_rig.py check TF2_PLAYER ANIMS GMOD_PLAYER BASE [LAYER] [--weapon C_MODEL]
                                                      over BASE's frames (LAYER, a delta, added at its
                                                      own cycle): hinge, length, foot and grip errors

As the viewmodel's (mdl_rig.py, the addon's rig.lua) but for the whole body: each GMod bone turns
as its TF2 bone does, times a correction built from each skeleton's own rest pose, so their
different rest postures and axes do not leak into the motion. Each bone's frame is its length (the
offset to its child; a leaf, its parent's way) and a second axis: the elbow's and fingers' bend (as
the arms'), and for the trunk, neck, head, clavicles and legs the body's left (the left hip from the
right in the rest pose), which both skeletons' standing rest poses share. The pelvis is placed where
TF2's is, scaled by the ratio of the two skeletons' leg lengths, so the feet reach the ground; every
other bone by its own rest offset: rotations only, the GMod model's proportions kept.

The weapon rides the right hand as TF2's rides bip_hand_R: in every base PRIMARY pose of the Scout
weapon_bone is fixed in the hand (docs/tf2-hands-spike.md), so its place is the hand's frame (the
TF2 hand's, through the correction) times that grip.
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

from mdl_rig import (DEFAULT_VPKS, PROC_QUATINTERP, Library, Model, RigError, axis_angle, canonical, cross,
                     frame_quat, qconj, qmul, qrot, quatinterp, swing_twist, unit)

Vec = Tuple[float, float, float]
Quat = Tuple[float, float, float, float]
Pose = Dict[int, Tuple[Vec, Quat]]

VB = "ValveBiped.Bip01_"
# TF2 bone, ValveBiped bone, the child each frame's length points to (None: a leaf, its parent's way)
TRUNK = [
    ("bip_pelvis", VB + "Pelvis", "bip_spine_0", VB + "Spine"),
    ("bip_spine_0", VB + "Spine", "bip_spine_1", VB + "Spine1"),
    ("bip_spine_1", VB + "Spine1", "bip_spine_2", VB + "Spine2"),
    ("bip_spine_2", VB + "Spine2", "bip_spine_3", VB + "Spine4"),
    ("bip_spine_3", VB + "Spine4", "bip_neck", VB + "Neck1"),
    ("bip_neck", VB + "Neck1", "bip_head", VB + "Head1"),
    ("bip_head", VB + "Head1", None, None),
]


def limb(side: str) -> List[Tuple[str, str, Optional[str], Optional[str]]]:
    s = side
    return [
        (f"bip_collar_{s}", f"{VB}{s}_Clavicle", f"bip_upperArm_{s}", f"{VB}{s}_UpperArm"),
        (f"bip_hip_{s}", f"{VB}{s}_Thigh", f"bip_knee_{s}", f"{VB}{s}_Calf"),
        (f"bip_knee_{s}", f"{VB}{s}_Calf", f"bip_foot_{s}", f"{VB}{s}_Foot"),
        (f"bip_foot_{s}", f"{VB}{s}_Foot", f"bip_toe_{s}", f"{VB}{s}_Toe0"),
        (f"bip_toe_{s}", f"{VB}{s}_Toe0", None, None),
    ]


ARM_MAP = None  # the arms and fingers: mdl_rig.bone_map, framed by mdl_rig.canonical


def _left_frames(model: Model, rows, left: Vec, which: int) -> Dict[int, Quat]:
    """Frames of the trunk and limb rows of one skeleton (which: 0 TF2's names, 1 GMod's)."""
    rest = model.world(model.rest())
    out = {}
    for row in rows:
        name, child = row[which], row[2 + which]
        i = model.index[name]
        q = rest[i][1]
        if child is not None:
            length = model.bones[model.index[child]].pos
        else:  # a leaf: the way from its parent, in its own axes
            pp = rest[model.bones[i].parent][0]
            d = (rest[i][0][0] - pp[0], rest[i][0][1] - pp[1], rest[i][0][2] - pp[2])
            length = qrot(qconj(q), d)
        out[i] = frame_quat(length, qrot(qconj(q), left))
    return out


def _body_left(model: Model, left_hip: str, right_hip: str) -> Vec:
    rest = model.world(model.rest())
    a, b = rest[model.index[left_hip]][0], rest[model.index[right_hip]][0]
    return unit((a[0] - b[0], a[1] - b[1], a[2] - b[2]))


def corrections(tf: Model, gm: Model) -> List[Tuple[int, int, Quat]]:
    """(TF2 bone, GMod bone, C) for every paired bone, parents first; gm_world = tf_world * C."""
    from mdl_rig import bone_map
    rows = TRUNK + limb("L") + limb("R")
    tf_left = _body_left(tf, "bip_hip_L", "bip_hip_R")
    gm_left = _body_left(gm, VB + "L_Thigh", VB + "R_Thigh")
    src = _left_frames(tf, rows, tf_left, 0)
    dst = _left_frames(gm, rows, gm_left, 1)
    pairs = [(r[0], r[1]) for r in rows]
    for side in "LR":
        arm = bone_map(side)
        src.update(canonical(tf, [a for a, _ in arm]))
        dst.update(canonical(gm, [b for _, b in arm]))
        pairs += arm
    out = []
    for a, b in pairs:
        i, j = tf.index[a], gm.index[b]
        out.append((i, j, qmul(src[i], qconj(dst[j]))))
    # parents before children, as the GMod model orders its bones
    return sorted(out, key=lambda t: t[1])


def leg_length(model: Model, hip: str, knee: str, foot: str) -> float:
    return sum(math.dist((0, 0, 0), model.bones[model.index[n]].pos) for n in (knee, foot))


# The pose parameters a frame is sampled at when the caller names none: standing, aiming level, running
# forward where the sequence runs (move_x, move_y: TF2's own, in its animation model)
NEUTRAL = {"body_pitch": 0.0, "body_yaw": 0.0, "move_x": 1.0, "move_y": 0.0}


def layered(anims: Model, base: str, frame: int, layer: Optional[str] = None, cycle: float = 0.0,
            params: Optional[Dict[str, float]] = None):
    """The engine's pose of BASE at its frame (its blend grid at the pose parameters, its autolayers), with a
    gesture LAYER added at its own cycle (Sampler: CalcPose, AccumulatePose, CalcAutoplaySequences)."""
    from mdl_rig import Sampler
    sampler = _SAMPLERS.get(anims.name) or _SAMPLERS.setdefault(anims.name, Sampler(anims))
    values = dict(NEUTRAL, **(params or {}))
    seq = sampler.by_label[base]
    pose = sampler.sample(base, frame / max(1, seq.frames - 1), values)
    if layer is None:
        return pose
    return sampler.sample(layer, cycle, values, pose, 1.0)


_SAMPLERS: Dict[str, object] = {}


def tf_world(tf: Model, local) -> List[Tuple[Vec, Quat]]:
    """TF2's world pose for every bone of the class model: its animations name fewer bones than it has
    (scout.mdl's hlp_forearm_* are its own), which sit at rest under their parents, or are solved."""
    full = list(local) + [(b.pos, b.quat) for b in tf.bones[len(local):]]
    w = tf.world(full)
    for j in range(len(local), len(tf.bones)):
        if tf.bones[j].proctype == PROC_QUATINTERP:
            w[j] = quatinterp(tf, j, dict(enumerate(w)))
    return w


def solve(tf: Model, tf_world, gm: Model, corr=None, scale: Optional[float] = None) -> Pose:
    """Every GMod bone from TF2's: the paired turned, the pelvis placed, helpers solved, the rest at rest."""
    corr = corr or corrections(tf, gm)
    if scale is None:
        scale = (leg_length(gm, VB + "L_Thigh", VB + "L_Calf", VB + "L_Foot")
                 / leg_length(tf, "bip_hip_L", "bip_knee_L", "bip_foot_L"))
    paired = {j: (i, c) for i, j, c in corr}
    out: Pose = {}
    for j, b in enumerate(gm.bones):
        if j in paired:
            i, c = paired[j]
            q = qmul(tf_world[i][1], c)
            if b.parent < 0 or b.parent not in out:
                p = tf_world[i][0]
                out[j] = ((p[0] * scale, p[1] * scale, p[2] * scale), q)
                continue
        elif b.proctype == PROC_QUATINTERP:
            continue  # after its control is placed
        else:
            q = None
        pp, pq = out[b.parent]
        if q is None:
            q = qmul(pq, b.quat)
        r = qrot(pq, b.pos)
        out[j] = ((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), q)
    for j, b in enumerate(gm.bones):
        if j not in out and b.proctype == PROC_QUATINTERP:
            out[j] = quatinterp(gm, j, out)
    return out


def grip(tf_world, tf: Model) -> Tuple[Vec, Quat]:
    """weapon_bone in bip_hand_R's axes."""
    hp, hq = tf_world[tf.index["bip_hand_R"]]
    wp, wq = tf_world[tf.index["weapon_bone"]]
    return qrot(qconj(hq), (wp[0] - hp[0], wp[1] - hp[1], wp[2] - hp[2])), qmul(qconj(hq), wq)


def weapon_place(pose: Pose, gm: Model, hand_corr: Quat, held: Tuple[Vec, Quat]) -> Tuple[Vec, Quat]:
    """Where weapon_bone goes on the GMod model: the right hand's frame, turned back to TF2's hand axes
    by the correction, times the grip."""
    hp, hq = pose[gm.index[VB + "R_Hand"]]
    tf_hand = qmul(hq, qconj(hand_corr))
    r = qrot(tf_hand, held[0])
    return (hp[0] + r[0], hp[1] + r[1], hp[2] + r[2]), qmul(tf_hand, held[1])


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=("corrections", "check"))
    ap.add_argument("models", nargs="+")
    ap.add_argument("--vpk", action="append", type=Path)
    a = ap.parse_args(argv)
    lib = Library(a.vpk or DEFAULT_VPKS)
    if a.command == "corrections":
        tf, gm = lib.model(a.models[0]), lib.model(a.models[1])
        for i, j, c in corrections(tf, gm):
            axis, angle = axis_angle(c)
            print(f"{tf.bones[i].name:18s} -> {gm.bones[j].name:30s} {angle:6.1f} deg about "
                  f"({axis[0]:+.2f} {axis[1]:+.2f} {axis[2]:+.2f})")
        return 0
    tf, anims, gm = lib.model(a.models[0]), lib.model(a.models[1]), lib.model(a.models[2])
    base, layer = a.models[3], (a.models[4] if len(a.models) > 4 else None)
    corr = corrections(tf, gm)
    seq = next(s for s in anims.sequences if s.label == base)
    worst: Dict[str, Tuple[float, str]] = {}

    def note(key, value, at):
        if value > worst.get(key, (-1.0, ""))[0]:
            worst[key] = (value, at)

    paired = [(i, j, c) for i, j, c in corr]
    for f in range(seq.frames):
        local = layered(anims, base, f, layer, f / max(1, seq.frames - 1))
        w = tf_world(tf, local)
        pose = solve(tf, w, gm, corr)
        at = f"{base}@{f}"
        # a paired bone's length axis points where TF2's does
        for i, j, c in paired:
            kids_tf = [k for k in range(len(tf.bones)) if tf.bones[k].parent == i]
            kids_gm = [k for k in range(len(gm.bones)) if gm.bones[k].parent == j and k in {jj for _, jj, _ in paired}]
            if not kids_gm:
                continue
            gk = kids_gm[0]
            tk = next((ii for ii, jj, _ in paired if jj == gk), None)
            if tk is None or tk not in kids_tf:
                continue
            dg = unit(tuple(pose[gk][0][k] - pose[j][0][k] for k in range(3)))
            dt = unit(tuple(w[tk][0][k] - w[i][0][k] for k in range(3)))
            note("bone direction off TF2's (deg)", math.degrees(math.acos(max(-1, min(1, sum(x * y for x, y in zip(dg, dt)))))),
                 f"{at} {gm.bones[j].name}")
        for side in "LR":
            foot = pose[gm.index[f"{VB}{side}_Foot"]][0][2]
            tf_foot = w[tf.index[f"bip_foot_{side}"]][0][2]
            note("foot height against TF2's scaled (units)", abs(foot - tf_foot * gm_scale(tf, gm)), f"{at} {side}")
        if "weapon_bone" in tf.index:
            held = grip(w, tf)
            hand_corr = next(c for i, j, c in corr if gm.bones[j].name == VB + "R_Hand")
            wp, _ = weapon_place(pose, gm, hand_corr, held)
            # the left hand against where TF2's sits on the weapon
            lp, lq = w[tf.index["bip_hand_L"]]
            tw = w[tf.index["weapon_bone"]]
            on_gun = qrot(qconj(tw[1]), tuple(lp[k] - tw[0][k] for k in range(3)))
            wq = weapon_place(pose, gm, hand_corr, held)[1]
            target = tuple(wp[k] + qrot(wq, on_gun)[k] for k in range(3))
            note("left hand off its place on the weapon (units)", math.dist(target, pose[gm.index[VB + "L_Hand"]][0]), at)
    for key, (value, where) in sorted(worst.items()):
        print(f"{key:44s} {value:8.3f}  {where}")
    return 0


def gm_scale(tf: Model, gm: Model) -> float:
    return (leg_length(gm, VB + "L_Thigh", VB + "L_Calf", VB + "L_Foot")
            / leg_length(tf, "bip_hip_L", "bip_knee_L", "bip_foot_L"))


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RigError as e:
        print(f"body_rig: {e}", file=sys.stderr)
        sys.exit(1)
