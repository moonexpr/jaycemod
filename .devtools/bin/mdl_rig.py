#!/usr/bin/env python3
"""Read a Source model's rig from the VPKs and check the TF2 -> c_arms hands retarget offline.

  mdl_rig.py bones MODEL...            bones: index, parent, flags, procedural type, rest offset
  mdl_rig.py sequences MODEL...        sequences: label, activity, weight, frames, fps, flags
  mdl_rig.py attachments MODEL...      attachments and the bone each rides on
  mdl_rig.py procedural MODEL...       quaternion-interpolation helper bones and their triggers
  mdl_rig.py corrections ARMS HANDS    per-bone axis corrections, rest pose to rest pose
  mdl_rig.py fixture ARMS ANIMS HANDS LABEL@FRAME...
                                       a Lua fixture: both skeletons, and per frame the TF2 bones'
                                       world transforms and every hands bone solved from them
  mdl_rig.py check ARMS ANIMS HANDS [LABEL...]
                                       retarget every frame of the sequences (all by default) and
                                       report the worst elbow, finger, palm and hand-position errors
  --vpk PATH                           a *_dir.vpk to read from (repeatable; default: TF2's
                                       tf2_misc_dir.vpk and GMod's garrysmod_dir.vpk under CrossOver)

The retarget is the hands addon's (addons/tf2hands, docs/tf2-hands-spike.md): rotations only,
each hands bone turned as its TF2 bone is, through a correction built from both rest poses by
the bones' own axes (length toward the child, the bend axis measured from the rest bend),
never from the rest postures, which differ. This tool is the offline oracle for that math.

Reads studiohdr_t v48/v49 (public/studio.h): mstudiobone_t (216 bytes), mstudioseqdesc_t (212),
mstudioanimdesc_t (100), mstudioattachment_t (92), mstudioquatinterpbone_t and its 48-byte
triggers, and in-file animation data (Quaternion48/64, RLE euler and position values).
"""
from __future__ import annotations

import argparse
import math
import struct
import sys
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

from tf2_content import TF_DIR, Vpk

GMOD_VPK = (Path.home() / "Library/Application Support/CrossOver/Bottles/Steam"
            / "drive_c/Steam/steamapps/common/GarrysMod/garrysmod/garrysmod_dir.vpk")
DEFAULT_VPKS = (TF_DIR / "tf2_misc_dir.vpk", GMOD_VPK)

BONE_SIZE, SEQ_SIZE, ANIM_SIZE, ATTACHMENT_SIZE, TRIGGER_SIZE = 216, 212, 100, 92, 48
PROC_QUATINTERP = 2
# animation flags (studio.h)
RAWPOS, RAWROT, ANIMPOS, ANIMROT, DELTA, RAWROT2 = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
MIN_BEND = 3.0  # degrees: a rest bend smaller than this names no axis

Vec = Tuple[float, float, float]
Quat = Tuple[float, float, float, float]


class RigError(Exception):
    pass


# ---- maths: quaternions (x, y, z, w) as Source stores them ----

def qmul(a: Quat, b: Quat) -> Quat:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def qconj(q: Quat) -> Quat:
    return (-q[0], -q[1], -q[2], q[3])


def qrot(q: Quat, v: Vec) -> Vec:
    x, y, z, w = q
    cx, cy, cz = y * v[2] - z * v[1], z * v[0] - x * v[2], x * v[1] - y * v[0]
    ccx, ccy, ccz = y * cz - z * cy, z * cx - x * cz, x * cy - y * cx
    return (v[0] + 2 * (w * cx + ccx), v[1] + 2 * (w * cy + ccy), v[2] + 2 * (w * cz + ccz))


def euler_quat(x: float, y: float, z: float) -> Quat:
    """AngleQuaternion(RadianEuler) of mathlib."""
    sr, cr, sp, cp = math.sin(x / 2), math.cos(x / 2), math.sin(y / 2), math.cos(y / 2)
    sy, cy = math.sin(z / 2), math.cos(z / 2)
    return (sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy,
            cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy)


def dot(a: Sequence[float], b: Sequence[float]) -> float:
    return sum(x * y for x, y in zip(a, b))


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(v: Vec) -> Vec:
    n = math.sqrt(dot(v, v))
    if n < 1e-9:
        raise RigError("a zero-length axis")
    return (v[0] / n, v[1] / n, v[2] / n)


def frame_quat(primary: Vec, secondary: Vec) -> Quat:
    """The rotation whose columns are primary, secondary made orthogonal to it, and their cross."""
    a = unit(primary)
    p = dot(secondary, a)
    b = unit((secondary[0] - p * a[0], secondary[1] - p * a[1], secondary[2] - p * a[2]))
    c = cross(a, b)
    m00, m10, m20, m01, m11, m21, m02, m12, m22 = a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]
    tr = m00 + m11 + m22
    if tr > 0:
        s = math.sqrt(tr + 1) * 2
        return ((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, s / 4)
    if m00 > m11 and m00 > m22:
        s = math.sqrt(1 + m00 - m11 - m22) * 2
        return (s / 4, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
    if m11 > m22:
        s = math.sqrt(1 + m11 - m00 - m22) * 2
        return ((m01 + m10) / s, s / 4, (m12 + m21) / s, (m02 - m20) / s)
    s = math.sqrt(1 + m22 - m00 - m11) * 2
    return ((m02 + m20) / s, (m12 + m21) / s, s / 4, (m10 - m01) / s)


def axis_angle(q: Quat) -> Tuple[Vec, float]:
    """A rotation's axis and its angle in degrees, the angle in 0..180."""
    w = max(-1.0, min(1.0, q[3]))
    s = math.sqrt(max(1e-12, 1 - w * w))
    angle, axis = math.degrees(2 * math.acos(w)), (q[0] / s, q[1] / s, q[2] / s)
    if angle > 180:
        angle, axis = 360 - angle, (-axis[0], -axis[1], -axis[2])
    return axis, angle


def swing_twist(q: Quat, axis: Vec) -> Tuple[float, float]:
    """Degrees of swing off `axis` and of twist about it (signed)."""
    p = dot(q[:3], axis)
    t = (axis[0] * p, axis[1] * p, axis[2] * p, q[3])
    n = math.sqrt(dot(t, t)) or 1.0
    t = (t[0] / n, t[1] / n, t[2] / n, t[3] / n)
    swing = qmul(q, qconj(t))
    return math.degrees(2 * math.acos(min(1.0, abs(swing[3])))), math.degrees(2 * math.atan2(p, q[3]))


# ---- the model file ----

def _i32(d: bytes, p: int) -> int:
    return struct.unpack_from("<i", d, p)[0]


def _cstr(d: bytes, p: int) -> str:
    return d[p:d.index(b"\0", p)].decode("latin-1")


def _half(h: int) -> float:
    return struct.unpack("<e", struct.pack("<H", h))[0]


@dataclass(frozen=True)
class Bone:
    name: str
    parent: int
    pos: Vec
    quat: Quat
    rot: Vec
    posscale: Vec
    rotscale: Vec
    flags: int
    proctype: int
    procindex: int


@dataclass(frozen=True)
class Seq:
    index: int
    label: str
    activity: str
    weight: int
    flags: int
    anim: int
    frames: int
    fps: float


class Model:
    def __init__(self, name: str, data: bytes):
        if data[:4] != b"IDST":
            raise RigError(f"{name}: not a studio model")
        self.name, self.d = name, data
        self.version = _i32(data, 4)
        if self.version not in (48, 49):
            raise RigError(f"{name}: studio version {self.version}")

    @cached_property
    def bones(self) -> List[Bone]:
        d, out = self.d, []
        base = _i32(d, 160)
        for i in range(_i32(d, 156)):
            o = base + i * BONE_SIZE
            f = lambda off, n: struct.unpack_from(f"<{n}f", d, o + off)  # noqa: E731
            out.append(Bone(_cstr(d, o + _i32(d, o)), _i32(d, o + 4), f(32, 3), f(44, 4), f(60, 3), f(72, 3),
                            f(84, 3), _i32(d, o + 160), _i32(d, o + 164), o + _i32(d, o + 168)))
        return out

    @cached_property
    def index(self) -> Dict[str, int]:
        return {b.name: i for i, b in enumerate(self.bones)}

    @cached_property
    def children(self) -> Dict[int, List[int]]:
        out: Dict[int, List[int]] = {i: [] for i in range(len(self.bones))}
        for i, b in enumerate(self.bones):
            if b.parent >= 0:
                out[b.parent].append(i)
        return out

    @cached_property
    def sequences(self) -> List[Seq]:
        d, out = self.d, []
        base, anims = _i32(d, 192), _i32(d, 184)
        for i in range(_i32(d, 188)):
            o = base + i * SEQ_SIZE
            anim = struct.unpack_from("<h", d, o + _i32(d, o + 60))[0] if _i32(d, o + 56) else -1
            frames, fps = 0, 0.0
            if 0 <= anim < _i32(d, 180):
                a = anims + anim * ANIM_SIZE
                frames, fps = _i32(d, a + 16), struct.unpack_from("<f", d, a + 8)[0]
            out.append(Seq(i, _cstr(d, o + _i32(d, o + 4)), _cstr(d, o + _i32(d, o + 8)), _i32(d, o + 20),
                           _i32(d, o + 12), anim, frames, fps))
        return out

    @cached_property
    def attachments(self) -> List[Tuple[str, int]]:
        d, base = self.d, _i32(self.d, 244)
        return [(_cstr(d, base + k * ATTACHMENT_SIZE + _i32(d, base + k * ATTACHMENT_SIZE)),
                 _i32(d, base + k * ATTACHMENT_SIZE + 8)) for k in range(_i32(d, 240))]

    @cached_property
    def includes(self) -> List[str]:
        d, base = self.d, _i32(self.d, 340)
        return [_cstr(d, base + k * 8 + _i32(d, base + k * 8 + 4)) for k in range(_i32(d, 336))]

    def quatinterp(self, bone: int) -> Tuple[int, List[Tuple[float, Quat, Vec, Quat]]]:
        """A helper bone's control bone and its triggers: (inverse tolerance, trigger, pos, quat)."""
        d, p = self.d, self.bones[bone].procindex
        control, count, base = _i32(d, p), _i32(d, p + 4), p + _i32(d, p + 8)
        triggers = []
        for k in range(count):
            f = struct.unpack_from("<f4f3f4f", d, base + k * TRIGGER_SIZE)
            triggers.append((f[0], f[1:5], f[5:8], f[8:12]))
        return control, triggers

    def pose_to_bone(self, bone: int) -> Tuple[float, ...]:
        """mstudiobone_t.poseToBone: the 3x4 matrix, rows first, taking a bind-pose vertex into the bone."""
        return struct.unpack_from("<12f", self.d, _i32(self.d, 160) + bone * BONE_SIZE + 96)

    def rest(self) -> List[Tuple[Vec, Quat]]:
        return [(b.pos, b.quat) for b in self.bones]

    def pose(self, label: str, frame: int) -> List[Tuple[Vec, Quat]]:
        """Local (pos, quat) of every bone in the first blend of sequence `label` at `frame`."""
        seq = next((s for s in self.sequences if s.label == label), None)
        if seq is None or seq.anim < 0:
            raise RigError(f"{self.name}: no animated sequence {label}")
        d = self.d
        ad = _i32(d, 184) + seq.anim * ANIM_SIZE
        if _i32(d, ad + 52):
            raise RigError(f"{self.name}: {label} lives in an external animation block")
        frame = max(0, min(frame, _i32(d, ad + 16) - 1))
        section = _i32(d, ad + 84)
        if section:
            k = frame // section
            p = ad + _i32(d, ad + _i32(d, ad + 80) + k * 8 + 4)
            frame -= k * section
        else:
            p = ad + _i32(d, ad + 56)
        out = self.rest()
        while True:
            bone, flags, step = d[p], d[p + 1], struct.unpack_from("<h", d, p + 2)[0]
            b, q = self.bones[bone], p + 4
            pos, quat = b.pos, b.quat
            if flags & RAWROT2:
                v = struct.unpack_from("<Q", d, q)[0]
                x, y, z = [((v >> s) & 0x1FFFFF) - 1048576 for s in (0, 21, 42)]
                x, y, z = x / 1048576.5, y / 1048576.5, z / 1048576.5
                w = math.sqrt(max(0.0, 1 - x * x - y * y - z * z))
                quat, q = (x, y, z, -w if v >> 63 else w), q + 8
            elif flags & RAWROT:
                a, c, e = struct.unpack_from("<HHH", d, q)
                x, y, z = (a - 32768) / 32768.0, (c - 32768) / 32768.0, ((e & 0x7FFF) - 16384) / 16384.0
                w = math.sqrt(max(0.0, 1 - x * x - y * y - z * z))
                quat, q = (x, y, z, -w if e >> 15 else w), q + 6
            elif flags & ANIMROT:
                offs = struct.unpack_from("<3h", d, q)
                base = (0.0, 0.0, 0.0) if flags & DELTA else b.rot
                quat = euler_quat(*((self._value(q + offs[k], frame, b.rotscale[k]) if offs[k] else 0.0) + base[k]
                                    for k in range(3)))
                q += 6
            if flags & RAWPOS:
                pos = tuple(_half(h) for h in struct.unpack_from("<3H", d, q))
            elif flags & ANIMPOS:
                offs = struct.unpack_from("<3h", d, q)
                base = (0.0, 0.0, 0.0) if flags & DELTA else b.pos
                pos = tuple((self._value(q + offs[k], frame, b.posscale[k]) if offs[k] else 0.0) + base[k]
                            for k in range(3))
            out[bone] = (pos, quat)
            if step == 0:
                return out
            p += step

    def _value(self, p: int, frame: int, scale: float) -> float:
        """ExtractAnimValue: run-length encoded shorts."""
        d, k = self.d, frame
        while True:
            valid, total = d[p], d[p + 1]
            if total == 0:
                return 0.0
            if total > k:
                break
            k -= total
            p += (valid + 1) * 2
        slot = k + 1 if valid > k else valid  # past the valid run, the last value holds
        return struct.unpack_from("<h", d, p + slot * 2)[0] * scale

    def world(self, local: List[Tuple[Vec, Quat]]) -> List[Tuple[Vec, Quat]]:
        out: List[Tuple[Vec, Quat]] = []
        for i, (p, q) in enumerate(local):
            parent = self.bones[i].parent
            if parent < 0:
                out.append((p, q))
            else:
                pp, pq = out[parent]
                r = qrot(pq, p)
                out.append(((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, q)))
        return out


class Library:
    def __init__(self, vpks: Sequence[Path]):
        self.vpks = [Vpk.open(p) for p in vpks if p.exists()]
        if not self.vpks:
            raise RigError("none of the VPKs exist: " + ", ".join(map(str, vpks)))

    def read(self, name: str) -> bytes:
        for v in self.vpks:
            if name in v:
                return v.read(name)
        raise RigError(f"{name}: in none of the VPKs")

    def model(self, name: str) -> Model:
        return Model(name, self.read(name))


# ---- the retarget: TF2 class arms -> ValveBiped hands ----

FINGERS = (("thumb", "0"), ("index", "1"), ("middle", "2"), ("ring", "3"), ("pinky", "4"))


def bone_map(side: str) -> List[Tuple[str, str]]:
    """TF2 bone -> ValveBiped bone, parents before children."""
    out = [(f"bip_upperArm_{side}", f"ValveBiped.Bip01_{side}_UpperArm"),
           (f"bip_lowerArm_{side}", f"ValveBiped.Bip01_{side}_Forearm"),
           (f"bip_hand_{side}", f"ValveBiped.Bip01_{side}_Hand")]
    for tf, vb in FINGERS:
        out += [(f"bip_{tf}_{j}_{side}", f"ValveBiped.Bip01_{side}_Finger{vb}{suffix}")
                for j, suffix in enumerate(("", "1", "2"))]
    return out


def canonical(model: Model, chain: List[str]) -> Dict[int, Quat]:
    """Each bone's canonical frame in its own local axes: length toward the child, then the bend axis.

    chain: upper arm, forearm, hand, then the fingers' three joints each, thumb first, as bone_map.
    """
    ix, rest = model.index, model.rest()
    upper, fore, hand = (ix[n] for n in chain[:3])
    joints = [[ix[n] for n in chain[3 + 3 * f:6 + 3 * f]] for f in range(5)]
    index0, middle0, pinky0 = joints[1][0], joints[2][0], joints[4][0]
    across = tuple(rest[pinky0][0][k] - rest[index0][0][k] for k in range(3))  # index -> pinky
    length = rest[middle0][0]
    palm = cross(unit(length), unit(across))
    out = {hand: frame_quat(length, across)}
    elbow, bend = axis_angle(rest[fore][1])
    if bend < MIN_BEND:  # straight at rest: the bend is across the palm, in the forearm's axes
        elbow = qrot(rest[hand][1], across)
    out[upper] = frame_quat(rest[fore][0], elbow)
    out[fore] = frame_quat(rest[hand][0], elbow)
    for f, ids in enumerate(joints):
        acc: Quat = (0.0, 0.0, 0.0, 1.0)
        length_axis = None
        for k, i in enumerate(ids):
            acc = qmul(acc, rest[i][1])
            length_axis = rest[ids[k + 1]][0] if k + 1 < len(ids) else length_axis
            axis, bend = axis_angle(rest[ids[min(k + 1, len(ids) - 1)]][1])
            if f == 0 or bend < MIN_BEND:  # the thumb bends across the palm, not with the fingers
                axis = qrot(qconj(acc), palm if f == 0 else across)
            out[i] = frame_quat(length_axis, axis)
    return out


def corrections(arms: Model, hands: Model, side: str) -> List[Tuple[int, int, Quat]]:
    """(TF2 bone, hands bone, C) with hands_world = tf2_world * C, for one side."""
    pairs = bone_map(side)
    src = canonical(arms, [a for a, _ in pairs])
    dst = canonical(hands, [b for _, b in pairs])
    return [(arms.index[a], hands.index[b], qmul(src[arms.index[a]], qconj(dst[hands.index[b]]))) for a, b in pairs]


def retarget(arms_world, hands: Model, corr) -> Dict[int, Tuple[Vec, Quat]]:
    """Hands bones in the arms' space: rotations copied, anchored at the upper arm, own lengths."""
    out: Dict[int, Tuple[Vec, Quat]] = {}
    for k, (i, j, c) in enumerate(corr):
        q = qmul(arms_world[i][1], c)
        if k == 0:
            pos = arms_world[i][0]
        else:
            pp, pq = out[hands.bones[j].parent]
            r = qrot(pq, hands.bones[j].pos)
            pos = (pp[0] + r[0], pp[1] + r[1], pp[2] + r[2])
        out[j] = (pos, q)
    return out


def quatinterp(model: Model, bone: int, world: Dict[int, Tuple[Vec, Quat]]) -> Tuple[Vec, Quat]:
    """DoQuatInterpBone (bone_setup.cpp): a helper bone's world transform from its control's rotation."""
    control, triggers = model.quatinterp(bone)
    cp = model.bones[control].parent
    src = world[control][1] if cp < 0 else qmul(qconj(world[cp][1]), world[control][1])
    weights = [max(0.0, 1 - 2 * math.acos(min(1.0, abs(dot(t[1], src)))) * t[0]) for t in triggers]
    scale = sum(weights)
    if scale <= 0.001:
        pos, quat = triggers[0][2], triggers[0][3]
    else:
        acc, pos = [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0]
        for weight, (_, _, tpos, tquat) in zip(weights, triggers):
            if weight > 0:
                s = weight / scale
                sign = -1 if dot(acc, tquat) < 0 else 1
                acc = [acc[k] + sign * s * tquat[k] for k in range(4)]
                pos = [pos[k] + s * tpos[k] for k in range(3)]
        n = math.sqrt(dot(acc, acc))
        quat = tuple(c / n for c in acc)
    pp, pq = world[model.bones[bone].parent]
    r = qrot(pq, pos)
    return (pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, quat)


def solve(arms: Model, arms_world, hands: Model) -> Dict[int, Tuple[Vec, Quat]]:
    """Every hands bone: the paired ones retargeted, their ancestors held to them by rest offsets,
    the procedural helpers solved, the rest under their parents. As tf_weapons/rig.lua's Rig.Solve."""
    out: Dict[int, Tuple[Vec, Quat]] = {}
    mapped = set()
    for side in "RL":
        part = retarget(arms_world, hands, corrections(arms, hands, side))
        out.update(part)
        mapped.update(part)
    kind: Dict[int, str] = {}
    child: Dict[int, int] = {}
    for j in range(len(hands.bones) - 1, -1, -1):
        if j in mapped:
            kind[j] = "mapped"
        parent = hands.bones[j].parent
        if parent >= 0 and kind.get(j) in ("mapped", "above") and parent not in child:
            kind[parent], child[parent] = "above", j
    for j in range(len(hands.bones) - 1, -1, -1):
        if kind.get(j) == "above":
            c = child[j]
            q = qmul(out[c][1], qconj(hands.bones[c].quat))
            r = qrot(q, hands.bones[c].pos)
            out[j] = ((out[c][0][0] - r[0], out[c][0][1] - r[1], out[c][0][2] - r[2]), q)
    for j, b in enumerate(hands.bones):
        if j in kind:
            continue
        if b.proctype == PROC_QUATINTERP:
            out[j] = quatinterp(hands, j, out)
        elif b.parent >= 0:
            pp, pq = out[b.parent]
            r = qrot(pq, b.pos)
            out[j] = ((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, b.quat))
        else:
            out[j] = (b.pos, b.quat)
    return out


def lua_fixture(arms: Model, anims: Model, hands: Model, frames: Sequence[Tuple[str, int]]) -> str:
    """A Lua file returning both skeletons and, for each frame, the TF2 bones' world transforms and
    every hands bone's as solve() places them: tests/tf_weapons_rig_test.lua's oracle."""
    def num(x: float) -> str:
        return repr(round(x, 7))

    def skeleton(m: Model) -> List[str]:
        lines = ["\t{", f"\t\tmodel = \"{m.name}\",", "\t\tbones =", "\t\t{"]
        for i, b in enumerate(m.bones):
            proc = ""
            if b.proctype == PROC_QUATINTERP:
                control, triggers = m.quatinterp(i)
                rows = ", ".join("{ " + ", ".join(num(x) for x in (t[0], *t[1], *t[2], *t[3])) + " }" for t in triggers)
                proc = f", control = {control + 1}, triggers = {{ {rows} }}"
            lines.append(f"\t\t\t{{ \"{b.name}\", {b.parent + 1}, " + ", ".join(num(x) for x in (*b.pos, *b.quat))
                         + proc + " },")
        lines[-1] = lines[-1].rstrip(",")
        return lines + ["\t\t}", "\t}"]

    out = ["-- Generated by .devtools/bin/mdl_rig.py fixture; do not edit.",
           "-- Bones: { name, parent (0 none), px, py, pz, qx, qy, qz, qw [, control, triggers] }.", "return", "{",
           "\tarms ="]
    out += skeleton(arms)
    out[-1] += ","
    out.append("\thands =")
    out += skeleton(hands)
    out[-1] += ","
    out += ["\tframes =", "\t{"]
    for label, frame in frames:
        w = arms.world(anims.pose(label, frame))
        solved = solve(arms, w, hands)
        arm_rows = ", ".join("{ " + ", ".join(num(x) for x in (*p, *q)) + " }" for p, q in w)
        hand_rows = ", ".join("{ " + ", ".join(num(x) for x in (*solved[j][0], *solved[j][1])) + " }"
                              for j in range(len(hands.bones)))
        out += [f"\t\t{{ label = \"{label}\", frame = {frame},",
                f"\t\t\tarms = {{ {arm_rows} }},", f"\t\t\thands = {{ {hand_rows} }} }},"]
    out[-1] = out[-1].rstrip(",")
    return "\n".join(out + ["\t}", "}", ""])


def wrapped(degrees: float) -> float:
    """The size of an angle difference, wrapped into 0..180."""
    return abs((degrees + 180) % 360 - 180)


def check(arms: Model, anims: Model, hands: Model, labels: Sequence[str]) -> Dict[str, Tuple[float, str]]:
    if [b.name for b in anims.bones] != [b.name for b in arms.bones]:
        raise RigError(f"{anims.name}'s bones are not {arms.name}'s")
    worst: Dict[str, Tuple[float, str]] = {}

    def note(key: str, value: float, where: str) -> None:
        if value > worst.get(key, (-math.inf, ""))[0]:
            worst[key] = (value, where)

    for side in "RL":
        pairs = bone_map(side)
        corr = corrections(arms, hands, side)
        src = canonical(arms, [a for a, _ in pairs])
        dst = canonical(hands, [b for _, b in pairs])
        ai, hi = arms.index, hands.index
        # the bend axes, in each joint's own frame: a pure hinge reads the same in parent and child
        elbow_src = qrot(src[ai[pairs[1][0]]], (0, 1, 0))
        elbow_dst = qrot(dst[hi[pairs[1][1]]], (0, 1, 0))
        for label in labels:
            seq = next(s for s in anims.sequences if s.label == label)
            for frame in range(seq.frames):
                local = anims.pose(label, frame)
                w = arms.world(local)
                out = retarget(w, hands, corr)
                at = f"{label}@{frame} {side}"

                def rel(child: str, parent: str) -> Quat:
                    return qmul(qconj(out[hi[parent]][1]), out[hi[child]][1])

                hand_src, hand_dst = w[ai[pairs[2][0]]][0], out[hi[pairs[2][1]]][0]
                note("hand position error (units)", math.dist(hand_src, hand_dst), at)
                swing, twist = swing_twist(rel(pairs[1][1], pairs[0][1]), elbow_dst)
                src_twist = swing_twist(local[ai[pairs[1][0]]][1], elbow_src)[1]
                src_swing = swing_twist(local[ai[pairs[1][0]]][1], elbow_src)[0]
                note("elbow swing off its hinge (deg)", swing - src_swing, at)
                note("TF2's own elbow swing (deg)", src_swing, at)
                note("elbow bend lost (deg)", wrapped(twist - src_twist), at)
                n_src = qrot(w[ai[pairs[2][0]]][1], qrot(src[ai[pairs[2][0]]], (0, 0, 1)))
                n_dst = qrot(out[hi[pairs[2][1]]][1], qrot(dst[hi[pairs[2][1]]], (0, 0, 1)))
                note("palm normal error (deg)", math.degrees(math.acos(max(-1.0, min(1.0, dot(n_src, n_dst))))), at)
                for f in range(1, 5):
                    for k in (1, 2):
                        (sa, da), (sb, db) = pairs[3 + 3 * f + k], pairs[2 + 3 * f + k]
                        hinge_dst = qrot(dst[hi[db]], (0, 1, 0))
                        hinge_src = qrot(src[ai[sb]], (0, 1, 0))
                        swing, twist = swing_twist(rel(da, db), hinge_dst)
                        src_twist = swing_twist(local[ai[sa]][1], hinge_src)[1]
                        src_swing = swing_twist(local[ai[sa]][1], hinge_src)[0]
                        note("finger swing off its hinge (deg)", swing - src_swing, f"{at} {da}")
                        note("TF2's own finger swing (deg)", src_swing, f"{at} {sa}")
                        note("finger curl lost (deg)", wrapped(twist - src_twist), f"{at} {da}")
    return worst


# ---- the command line ----

def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--vpk", action="append", type=Path)
    ap.add_argument("command", choices=("bones", "sequences", "attachments", "procedural", "corrections", "check",
                                        "fixture"))
    ap.add_argument("models", nargs="+")
    a = ap.parse_args(argv)
    lib = Library(a.vpk or DEFAULT_VPKS)
    if a.command == "corrections":
        arms, hands = lib.model(a.models[0]), lib.model(a.models[1])
        for side in "RL":
            for i, j, c in corrections(arms, hands, side):
                axis, angle = axis_angle(c)
                print(f"{arms.bones[i].name:18s} -> {hands.bones[j].name:30s} {angle:6.1f} deg about "
                      f"({axis[0]:+.2f} {axis[1]:+.2f} {axis[2]:+.2f})")
        return 0
    if a.command == "fixture":
        arms, anims, hands = (lib.model(n) for n in a.models[:3])
        frames = [(spec.rsplit("@", 1)[0], int(spec.rsplit("@", 1)[1])) for spec in a.models[3:]]
        sys.stdout.write(lua_fixture(arms, anims, hands, frames))
        return 0
    if a.command == "check":
        arms, anims, hands = (lib.model(n) for n in a.models[:3])
        labels = a.models[3:] or [s.label for s in anims.sequences if s.frames > 1]
        for key, (value, where) in sorted(check(arms, anims, hands, labels).items()):
            print(f"{key:34s} {value:8.2f}  {where}")
        return 0
    for name in a.models:
        m = lib.model(name)
        print(f"== {name} (v{m.version}, includes {m.includes or 'none'})")
        if a.command == "bones":
            for i, b in enumerate(m.bones):
                print(f"{i:3d} {b.parent:3d} {b.flags:#08x} {b.proctype} {b.name:34s} "
                      f"({b.pos[0]:+.3f} {b.pos[1]:+.3f} {b.pos[2]:+.3f})")
        elif a.command == "sequences":
            for s in m.sequences:
                print(f"{s.index:3d} {s.label:34s} {s.activity or '-':36s} w{s.weight:<3d} {s.frames:4d}f "
                      f"{s.fps:5.1f}fps {s.flags:#06x}")
        elif a.command == "attachments":
            for att, bone in m.attachments:
                print(f"{att:24s} on {m.bones[bone].name}")
        else:
            for i, b in enumerate(m.bones):
                if b.proctype == PROC_QUATINTERP:
                    control, triggers = m.quatinterp(i)
                    print(f"{b.name} under {m.bones[b.parent].name}, driven by {m.bones[control].name}:")
                    for inv_tol, trig, pos, quat in triggers:
                        print(f"   tolerance {math.degrees(1 / inv_tol) if inv_tol else 0:6.1f} deg trigger "
                              f"{tuple(round(x, 3) for x in trig)} -> quat {tuple(round(x, 3) for x in quat)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RigError as e:
        print(f"mdl_rig: {e}", file=sys.stderr)
        sys.exit(1)
