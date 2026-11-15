#!/usr/bin/env python3
"""Source's SMD: a skeleton, its frames and a mesh's triangles, written for studiomdl and read back.

A bone's frame is its parent-space (pos, quat); SMD keeps the rotation as a RadianEuler (x, y, z), the
matrix Rz(z) Ry(y) Rx(x), which mathlib's AngleQuaternion turns into the quaternion mdl_rig.euler_quat
gives. quat_euler is its inverse, so a frame written and read back is the frame (to the six decimals
the text keeps).
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import IO, List, Optional, Sequence, Tuple

from mdl_rig import euler_quat

Vec = Tuple[float, float, float]
Quat = Tuple[float, float, float, float]
Frame = List[Tuple[Vec, Quat]]  # one (pos, quat) a bone, parent space, the nodes' order


class SmdError(Exception):
    pass


def quat_euler(q: Quat) -> Vec:
    """The RadianEuler of a rotation: AngleQuaternion's inverse (QuaternionAngles). The quaternion is made unit
    first: one composed many times drifts off it, and the matrix read from it would not be a rotation."""
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    x, y, z, w = (c / n for c in q)
    m00 = 1 - 2 * (y * y + z * z)
    m10 = 2 * (x * y + w * z)
    m20 = 2 * (x * z - w * y)
    m21 = 2 * (y * z + w * x)
    m22 = 1 - 2 * (x * x + y * y)
    pitch = math.asin(max(-1.0, min(1.0, -m20)))
    if abs(m20) < 1 - 1e-9:
        return (math.atan2(m21, m22), pitch, math.atan2(m10, m00))
    # gimbal lock: the roll folds into the yaw
    m01, m11 = 2 * (x * y - w * z), 1 - 2 * (x * x + z * z)
    return (0.0, pitch, math.atan2(-m01, m11))


@dataclass
class Vertex:
    parent: int
    pos: Vec
    normal: Vec
    uv: Tuple[float, float]
    links: List[Tuple[int, float]]  # (bone, weight)


@dataclass
class Smd:
    nodes: List[Tuple[str, int]]                     # (name, parent index, -1 for none)
    frames: List[Frame] = field(default_factory=list)
    triangles: List[Tuple[str, Tuple[Vertex, Vertex, Vertex]]] = field(default_factory=list)


def _num(x: float) -> str:
    s = f"{x:.6f}"
    return "0.000000" if s == "-0.000000" else s


def write(smd: Smd, out: IO[str]) -> None:
    out.write("version 1\nnodes\n")
    for i, (name, parent) in enumerate(smd.nodes):
        if '"' in name:
            raise SmdError(f"a bone's name holds a quote: {name}")
        out.write(f'{i} "{name}" {parent}\n')
    out.write("end\nskeleton\n")
    for t, frame in enumerate(smd.frames):
        if len(frame) != len(smd.nodes):
            raise SmdError(f"frame {t} has {len(frame)} bones for {len(smd.nodes)} nodes")
        out.write(f"time {t}\n")
        for i, (p, q) in enumerate(frame):
            r = quat_euler(q)
            out.write(f"{i} {_num(p[0])} {_num(p[1])} {_num(p[2])} {_num(r[0])} {_num(r[1])} {_num(r[2])}\n")
    out.write("end\n")
    if smd.triangles:
        out.write("triangles\n")
        for material, verts in smd.triangles:
            out.write(material + "\n")
            for v in verts:
                links = " ".join(f"{b} {_num(w)}" for b, w in v.links)
                out.write(f"{v.parent} {_num(v.pos[0])} {_num(v.pos[1])} {_num(v.pos[2])} "
                          f"{_num(v.normal[0])} {_num(v.normal[1])} {_num(v.normal[2])} "
                          f"{_num(v.uv[0])} {_num(v.uv[1])} {len(v.links)} {links}\n")
        out.write("end\n")


def read(text: str) -> Smd:
    lines = [ln.strip() for ln in text.splitlines()]
    k = 0

    def expect(word: str) -> None:
        nonlocal k
        while k < len(lines) and not lines[k]:
            k += 1
        if k >= len(lines) or lines[k] != word:
            raise SmdError(f"line {k + 1}: expected {word}, found {lines[k] if k < len(lines) else 'the end'}")
        k += 1

    if not lines or not lines[0].startswith("version 1"):
        raise SmdError("not an SMD (version 1)")
    k = 1
    expect("nodes")
    nodes = []
    while lines[k] != "end":
        first, rest = lines[k].split('"', 1)
        name, parent = rest.rsplit('"', 1)
        nodes.append((name, int(parent)))
        k += 1
    k += 1
    expect("skeleton")
    frames: List[Frame] = []
    while lines[k] != "end":
        if lines[k].startswith("time"):
            frames.append([((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0))] * len(nodes))
        else:
            f = lines[k].split()
            i = int(f[0])
            frames[-1][i] = ((float(f[1]), float(f[2]), float(f[3])), euler_quat(float(f[4]), float(f[5]), float(f[6])))
        k += 1
    k += 1
    smd = Smd(nodes, frames)
    while k < len(lines) and not lines[k]:
        k += 1
    if k < len(lines) and lines[k] == "triangles":
        k += 1
        while lines[k] != "end":
            material = lines[k]
            verts = []
            for j in range(3):
                f = lines[k + 1 + j].split()
                n = int(f[9])
                links = [(int(f[10 + 2 * m]), float(f[11 + 2 * m])) for m in range(n)]
                verts.append(Vertex(int(f[0]), (float(f[1]), float(f[2]), float(f[3])),
                                    (float(f[4]), float(f[5]), float(f[6])), (float(f[7]), float(f[8])), links))
            smd.triangles.append((material, tuple(verts)))
            k += 4
    return smd
