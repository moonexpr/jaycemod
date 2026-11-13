#!/usr/bin/env python3
"""Sibling limits: the transformer's translation of TF2's motion into a target model's own range.

A vertex weighted to two sibling bones (two fingers' roots under the hand, the two thighs under the
pelvis) stretches when the siblings turn apart further than the model's own animations ever turn
them (docs/tf2-hands-spike.md, the gate's failures). Per pair of siblings sharing a vertex, the
native range of the difference of their turns from rest (each a rotation vector in the bone's own
canonical axes, which body_rig and mdl_rig build alike for both siblings) bounds that difference;
a pose past it has both siblings turned back toward each other by half the excess, their children
following.
"""
from __future__ import annotations

import math
from typing import Dict, List, Sequence, Tuple

import numpy as np

from mdl_rig import PROC_QUATINTERP, Model, qconj, qmul, qrot, quatinterp

MIN_SHARED_WEIGHT = 0.1   # both siblings at least this much on one vertex
Pose = Dict[int, tuple]


def log(q) -> np.ndarray:
    x, y, z, w = q
    if w < 0:
        x, y, z, w = -x, -y, -z, -w
    s = math.sqrt(x * x + y * y + z * z)
    return np.zeros(3) if s < 1e-12 else np.array([x, y, z]) / s * 2 * math.atan2(s, w)


def exp(v) -> tuple:
    a = float(np.linalg.norm(v))
    if a < 1e-12:
        return (0.0, 0.0, 0.0, 1.0)
    s = math.sin(a / 2) / a
    return (v[0] * s, v[1] * s, v[2] * s, math.cos(a / 2))


def shared_siblings(model: Model, mesh, frames: Dict[int, tuple]) -> List[Tuple[int, int]]:
    """Pairs of sibling bones (one parent), both framed, both weighted on some vertex."""
    pairs = set()
    for v in range(len(mesh.positions)):
        ws = [(int(mesh.bones[v, k]), float(mesh.weights[v, k])) for k in range(3) if mesh.weights[v, k] >= MIN_SHARED_WEIGHT]
        for i in range(len(ws)):
            for j in range(i + 1, len(ws)):
                a, b = sorted((ws[i][0], ws[j][0]))
                if a != b and a in frames and b in frames and model.bones[a].parent == model.bones[b].parent:
                    pairs.add((a, b))
    return sorted(pairs)


def turn(model: Model, frames, pose: Pose, j: int) -> np.ndarray:
    """Bone j's turn from rest against its parent, as a rotation vector in its own canonical axes."""
    p = model.bones[j].parent
    d = qmul(qconj(model.bones[j].quat), qmul(qconj(pose[p][1]), pose[j][1]))
    F = frames[j]
    return log(qmul(qconj(F), qmul(d, F)))


def learn(model: Model, frames, pairs, native_poses) -> Dict[Tuple[int, int], Tuple[np.ndarray, np.ndarray]]:
    lo = {p: np.full(3, np.inf) for p in pairs}
    hi = {p: np.full(3, -np.inf) for p in pairs}
    for pose in native_poses:
        for a, b in pairs:
            d = turn(model, frames, pose, a) - turn(model, frames, pose, b)
            lo[(a, b)] = np.minimum(lo[(a, b)], d)
            hi[(a, b)] = np.maximum(hi[(a, b)], d)
    return {p: (lo[p], hi[p]) for p in pairs}


def _subtree(model: Model, root: int):
    yield root
    for c, b in enumerate(model.bones):
        if b.parent == root:
            yield from _subtree(model, c)


def _set_turn(model: Model, frames, pose: Pose, j: int, r: np.ndarray) -> None:
    """Bone j turned to rotation vector r from rest, its subtree carried rigidly with it."""
    p = model.bones[j].parent
    F = frames[j]
    local = qmul(model.bones[j].quat, qmul(F, qmul(exp(r), qconj(F))))
    new = qmul(pose[p][1], local)
    delta = qmul(new, qconj(pose[j][1]))
    pivot = np.array(pose[j][0])
    for c in _subtree(model, j):
        pc, qc = pose[c]
        moved = qrot(delta, tuple(np.array(pc) - pivot))
        pose[c] = (tuple(pivot + np.array(moved)), qmul(delta, qc))


def apply(model: Model, frames, limits, pose: Pose) -> Pose:
    """The pose with each sibling pair's difference held to its native range; helpers solved again."""
    out = dict(pose)
    for (a, b), (lo, hi) in limits.items():
        ra, rb = turn(model, frames, out, a), turn(model, frames, out, b)
        d = ra - rb
        excess = d - np.clip(d, lo, hi)
        if not excess.any():
            continue
        _set_turn(model, frames, out, a, ra - excess / 2)
        _set_turn(model, frames, out, b, rb + excess / 2)
    for j, bone in enumerate(model.bones):
        if bone.proctype == PROC_QUATINTERP:
            out[j] = quatinterp(model, j, out)
    return out
