#!/usr/bin/env python3
"""Analytic two-bone IK on a posed skeleton: an arm (upper arm, forearm, hand) put on a target.

The elbow stays in the plane it is in (the plane of the shoulder, the target and the elbow before), so
the arm bends the way the animation bent it; the upper arm and forearm turn by the least rotation that
points them at the new elbow and the target, their twist kept; the hand takes the target's rotation.
Every bone below each moved bone is carried with it, rigidly: lengths never change. A target out of
reach leaves the arm straight toward it and returns the distance it falls short.
"""
from __future__ import annotations

import math
from typing import Dict, Optional, Tuple

import numpy as np

from mdl_rig import PROC_QUATINTERP, Model, qconj, qmul, qrot, quatinterp

Vec = Tuple[float, float, float]
Quat = Tuple[float, float, float, float]
Pose = Dict[int, Tuple[Vec, Quat]]
REACH_MARGIN = 1e-4  # units kept short of full extension, so the elbow's plane stays defined


def between(a: np.ndarray, b: np.ndarray) -> Quat:
    """The least rotation taking direction a to direction b."""
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    c = np.cross(a, b)
    d = float(np.dot(a, b))
    if d < -1 + 1e-9:  # opposite: any axis across a
        axis = np.cross(a, [1.0, 0.0, 0.0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0.0, 1.0, 0.0])
        axis /= np.linalg.norm(axis)
        return (axis[0], axis[1], axis[2], 0.0)
    w = 1 + d
    q = np.array([c[0], c[1], c[2], w])
    q /= np.linalg.norm(q)
    return tuple(float(x) for x in q)


def _subtree(model: Model, root: int):
    yield root
    for c, b in enumerate(model.bones):
        if b.parent == root:
            yield from _subtree(model, c)


def turn_subtree(model: Model, pose: Pose, root: int, delta: Quat, pivot) -> None:
    """Every bone from root down turned by delta about pivot (world)."""
    pv = np.asarray(pivot, dtype=float)
    for c in _subtree(model, root):
        p, q = pose[c]
        r = qrot(delta, tuple(np.asarray(p) - pv))
        pose[c] = (tuple(pv + np.asarray(r)), qmul(delta, q))


def two_bone(model: Model, pose: Pose, upper: int, fore: int, hand: int, target: Vec,
             rotation: Optional[Quat] = None) -> float:
    """The arm put on target (the hand's position) and, if given, the hand turned to rotation, in place.
    Returns how far the hand falls short of the target (0 within reach)."""
    s = np.asarray(pose[upper][0])
    e = np.asarray(pose[fore][0])
    h = np.asarray(pose[hand][0])
    t = np.asarray(target, dtype=float)
    a, b = float(np.linalg.norm(e - s)), float(np.linalg.norm(h - e))
    st = t - s
    dist = float(np.linalg.norm(st))
    reach = a + b - REACH_MARGIN
    d = min(max(dist, abs(a - b) + REACH_MARGIN), reach)
    along = st / dist if dist > 1e-9 else (h - s) / np.linalg.norm(h - s)
    side = (e - s) - np.dot(e - s, along) * along
    if np.linalg.norm(side) < 1e-9:  # straight: bend toward where the forearm points away from the line
        side = np.cross(along, [0.0, 0.0, 1.0])
    side /= np.linalg.norm(side)
    cos_a = max(-1.0, min(1.0, (a * a + d * d - b * b) / (2 * a * d)))
    elbow = s + a * (cos_a * along + math.sqrt(1 - cos_a * cos_a) * side)
    turn_subtree(model, pose, upper, between(e - s, elbow - s), s)
    e = np.asarray(pose[fore][0])
    h = np.asarray(pose[hand][0])
    wrist = s + d * along
    turn_subtree(model, pose, fore, between(h - e, wrist - e), e)
    if rotation is not None:
        hq = pose[hand][1]
        turn_subtree(model, pose, hand, qmul(rotation, qconj(hq)), pose[hand][0])
    return max(0.0, dist - reach)


def solve_helpers(model: Model, pose: Pose) -> None:
    for j, b in enumerate(model.bones):
        if b.proctype == PROC_QUATINTERP:
            pose[j] = quatinterp(model, j, pose)
