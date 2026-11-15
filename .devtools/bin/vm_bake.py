#!/usr/bin/env python3
"""The viewmodel's bake: TF2 class arms' frames as a c_arms skeleton's, ready to compile.

A frame is the retarget (mdl_rig.solve), the fingers held to the c_arms' own range (sibling_limits,
learned from GMod's own animations as rig_gate's envelope is), both hands put back on the weapon
(ik.two_bone), then the thumbs held to their own range (sibling_limits.apply_joints): the weapon stays
exactly where TF2's arms carry it, and each hand goes where TF2's does, turned as TF2's is through the hand's correction. Every stock c_arms model has this skeleton
to the 0.000 unit (docs/tf2-hands-spike.md), so the frames are exact for all of them.
"""
from __future__ import annotations

from typing import Callable, Dict, List, Tuple

from mdl_rig import Library, Model, bone_map, canonical, corrections, qmul, solve
import ik
import rig_gate
import sibling_limits

VB = "ValveBiped.Bip01_"


def thumb_limits(lib: Library, hands: Model):
    """The thumbs' joints held to their own native range (their frames, and the limits)."""
    from mdl_rig import EmptyStream, STUDIO_DELTA
    frames = {}
    for side in "RL":
        frames.update(canonical(hands, [b for _, b in bone_map(side)]))
    joints = [hands.index[f"{VB}{s}_Finger0{x}"] for s in "RL" for x in ("", "1", "2")]
    native = []
    sources = [lib.model(rig_gate.NATIVE_ANIMATIONS)] + [lib.model(f"models/weapons/c_{w}.mdl") for w in rig_gate.NATIVE_WEAPONS]
    for m in sources:
        for s in m.sequences:
            if s.anim < 0 or s.label in rig_gate.NATIVE_EXCLUDED or s.flags & STUDIO_DELTA:
                continue
            for f in range(s.frames):
                try:
                    pose = rig_gate.merged(hands, m, s.label, f)
                except EmptyStream:
                    continue
                if pose is None:
                    break
                native.append(pose)
    return frames, sibling_limits.learn_joints(hands, frames, joints, native)


def pipeline(lib: Library, arms: Model, hands: Model) -> Callable:
    """pose_of(arms_world) -> (the c_arms pose, the hands' shortfall from their grips {side: units})."""
    from rig_view import load_mesh
    mesh = load_mesh(lib, hands)
    limit = rig_gate.candidate_limits(lib, hands, mesh)
    thumbs = thumb_limits(lib, hands)
    hand_corr = {}
    for side in "RL":
        for i, j, c in corrections(arms, hands, side):
            if hands.bones[j].name == f"{VB}{side}_Hand":
                hand_corr[side] = c

    def pose_of(w) -> Tuple[Dict, Dict[str, float]]:
        pose = limit(solve(arms, w, hands))
        short = {}
        for side in "RL":
            tf_hand = arms.index[f"bip_hand_{side}"]
            target, rot = w[tf_hand][0], qmul(w[tf_hand][1], hand_corr[side])
            short[side] = ik.two_bone(hands, pose, hands.index[f"{VB}{side}_UpperArm"], hands.index[f"{VB}{side}_Forearm"],
                                      hands.index[f"{VB}{side}_Hand"], target, rot)
        sibling_limits.apply_joints(hands, thumbs[0], thumbs[1], pose)
        ik.solve_helpers(hands, pose)
        for j, (p, q) in pose.items():  # a rotation composed many times drifts off unit length (1e-6 measured)
            n = sum(c * c for c in q) ** 0.5
            pose[j] = (p, (q[0] / n, q[1] / n, q[2] / n, q[3] / n))
        return pose, short

    return pose_of
