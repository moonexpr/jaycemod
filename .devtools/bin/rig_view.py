#!/usr/bin/env python3
"""See where the TF2 arms, the player's hands and the weapon are: their meshes skinned and drawn.

  rig_view.py frame ARMS ANIMS HANDS GUN LABEL@FRAME...   one picture a frame: the viewmodel's
                                                           camera above, three plans below
  rig_view.py sheet ARMS ANIMS HANDS GUN LABEL [--count N] the camera on N frames of a sequence
  rig_view.py dump DUMP.json                               what tf_weapons_dump saved from the game
  rig_view.py where ARMS ANIMS HANDS GUN LABEL[@FRAME]     text: hands and grips in the weapon's axes
  --ascii                     the camera as characters on stdout, besides or instead of (--no-png)
  --ghost                     the TF2 arms drawn too, translucent over the rest
  --fit                       the camera zoomed onto the meshes (the eye unmoved) instead of as in game
  --body N,N                  the hands' body group models (default 0 each)
  --out PATH                  the picture (default .devtools/artifacts/rig_view/<what>.png)
  --vpk PATH                  as mdl_rig.py

The hands are posed as mdl_rig.solve poses them, which tests/tf_weapons_rig_test.lua holds the
addon's rig.lua to; the weapon's c_model is bone-merged onto the arms by name, as the engine merges
it. Meshes come from the .mdl (body parts, models, meshes), .vvd (vertices, weights) and .dx90.vtx
(strips), skinned with each bone's poseToBone. Space is the viewmodel's: x forward from the eye,
y to the left, z up; the camera is the eye looking down x with GMod's viewmodel field of view (a 4:3
horizontal angle, so a wide picture sees more to the sides). In the plans the player's right is
always drawn to the right.

The ASCII camera draws the hands as #+ (lit, shaded), the weapon as =-, the TF2 arms (--ghost) as
o. and marks joints: R and L the TF2 hands, r and l the player's, W the weapon bone, M the muzzle.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from mdl_rig import DEFAULT_VPKS, Library, Model, RigError, qconj, qmul, qrot, solve

REPO = Path(__file__).resolve().parents[2]
OUT_DIR = REPO / ".devtools" / "artifacts" / "rig_view"

VIEWMODEL_FOV = 54.0  # degrees, horizontal at 4:3 (tf_weapon_base's ViewModelFOV)
CAMERA_SIZE = (1280, 720)
PLAN_SIZE = (426, 320)
SHEET_CELL = (480, 270)
ASCII_SIZE = (120, 40)
LIGHT = np.array([0.45, 0.35, 0.82])  # toward the light, camera axes (right, up, toward the eye)
AMBIENT = 0.35
GHOST_ALPHA = 0.4

HANDS_COLOR = (214, 170, 130)
GUN_COLOR = (120, 132, 150)
ARMS_COLOR = (90, 230, 120)
HANDS_BONE_COLOR = (0, 200, 255)
ARMS_BONE_COLOR = (255, 120, 0)
MARK_COLOR = (255, 40, 120)
BACKGROUND = (28, 30, 36)

VERTEX_SIZE = 48
VVD_HEADER = 64
VTX = {"body": 8, "model": 8, "lod": 12, "mesh": 9, "group": 25, "strip": 27, "vertex": 9}
STRIP_TRILIST, STRIP_TRISTRIP = 0x01, 0x02

Vec = Tuple[float, float, float]
Quat = Tuple[float, float, float, float]
Pose = Dict[int, Tuple[Vec, Quat]]


def _i32(d: bytes, p: int) -> int:
    return struct.unpack_from("<i", d, p)[0]


# ---- meshes: .mdl body parts, .vvd vertices, .vtx triangles ----

@dataclass
class Mesh:
    """A model's LOD 0 triangles over its vertices, with each vertex's bones and weights."""
    positions: np.ndarray  # (n, 3) bind pose
    normals: np.ndarray    # (n, 3)
    bones: np.ndarray      # (n, 3) bone indices
    weights: np.ndarray    # (n, 3)
    triangles: np.ndarray  # (m, 3) vertex indices


def _vvd(data: bytes) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    if data[:4] != b"IDSV":
        raise RigError("not a .vvd")
    lod_vertices, fixups, fixup_start = _i32(data, 16), _i32(data, 48), _i32(data, 52)
    vertex_start, tangent_start = _i32(data, 56), _i32(data, 60)
    count = (tangent_start - vertex_start) // VERTEX_SIZE
    rec = np.dtype([("w", "<f4", 3), ("b", "u1", 3), ("n", "u1"), ("p", "<f4", 3), ("nm", "<f4", 3), ("uv", "<f4", 2)])
    verts = np.frombuffer(data, dtype=rec, count=count, offset=vertex_start)
    if fixups:
        order = []
        for k in range(fixups):
            lod, source, num = struct.unpack_from("<iii", data, fixup_start + k * 12)
            if lod >= 0:
                order.extend(range(source, source + num))
        verts = verts[np.array(order)]
    else:
        verts = verts[:lod_vertices]
    weights = verts["w"].astype(np.float64).copy()
    weights[np.arange(3)[None, :] >= verts["n"][:, None]] = 0.0
    return verts["p"].astype(np.float64), verts["nm"].astype(np.float64), verts["b"].astype(np.int64), weights


def _strip_triangles(indices: Sequence[int], flags: int) -> List[Tuple[int, int, int]]:
    if flags & STRIP_TRISTRIP:
        out = []
        for k in range(len(indices) - 2):
            a, b, c = indices[k], indices[k + 1], indices[k + 2]
            out.append((a, c, b) if k % 2 else (a, b, c))
        return out
    return [tuple(indices[k:k + 3]) for k in range(0, len(indices) - 2, 3)]


def load_mesh(lib: Library, model: Model, body: Sequence[int] = ()) -> Mesh:
    stem = model.name[:-len(".mdl")]
    positions, normals, bones, weights = _vvd(lib.read(stem + ".vvd"))
    vtx = lib.read(stem + ".dx90.vtx")
    md = model.d
    tris: List[Tuple[int, int, int]] = []
    parts, part_base = _i32(md, 232), _i32(md, 236)
    vtx_parts = _i32(vtx, 32)
    for p in range(parts):
        mp = part_base + p * 16
        nmodels, model_index = _i32(md, mp + 4), _i32(md, mp + 12)
        choice = body[p] if p < len(body) else 0
        if not 0 <= choice < nmodels:
            raise RigError(f"{model.name}: body part {p} has no model {choice}")
        mm = mp + model_index + choice * 148
        model_vertex, nmeshes, mesh_index = _i32(md, mm + 84) // VERTEX_SIZE, _i32(md, mm + 72), _i32(md, mm + 76)
        vp = vtx_parts + p * VTX["body"]
        vm = vp + _i32(vtx, vp + 4) + choice * VTX["model"]
        vl = vm + _i32(vtx, vm + 4)  # LOD 0
        vmeshes = vl + _i32(vtx, vl + 4)
        for m in range(nmeshes):
            mesh_offset = _i32(md, mm + mesh_index + m * 116 + 12)
            vmesh = vmeshes + m * VTX["mesh"]
            for g in range(_i32(vtx, vmesh)):
                vg = vmesh + _i32(vtx, vmesh + 4) + g * VTX["group"]
                nverts, vert_off, nidx, idx_off, nstrips, strip_off = struct.unpack_from("<6i", vtx, vg)
                orig = [struct.unpack_from("<H", vtx, vg + vert_off + k * VTX["vertex"] + 4)[0] for k in range(nverts)]
                index = struct.unpack_from(f"<{nidx}H", vtx, vg + idx_off)
                for s in range(nstrips):
                    vs = vg + strip_off + s * VTX["strip"]
                    count, first = _i32(vtx, vs), _i32(vtx, vs + 4)
                    flags = vtx[vs + 18]
                    for a, b, c in _strip_triangles(index[first:first + count], flags):
                        base = model_vertex + mesh_offset
                        tris.append((base + orig[a], base + orig[b], base + orig[c]))
    return Mesh(positions, normals, bones, weights, np.array(tris, dtype=np.int64).reshape(-1, 3))


# ---- posing ----

def matrix(pos: Vec, quat: Quat) -> np.ndarray:
    x, y, z, w = quat
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y), pos[0]],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x), pos[1]],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y), pos[2]],
        [0.0, 0.0, 0.0, 1.0]])


def skin(model: Model, mesh: Mesh, pose: Pose) -> Tuple[np.ndarray, np.ndarray]:
    """The mesh's vertices and normals placed by the bones' world transforms."""
    skins = np.zeros((len(model.bones), 4, 4))
    for i in range(len(model.bones)):
        p2b = np.vstack([np.array(model.pose_to_bone(i)).reshape(3, 4), [0, 0, 0, 1]])
        skins[i] = matrix(*pose[i]) @ p2b
    v = np.hstack([mesh.positions, np.ones((len(mesh.positions), 1))])
    out = np.zeros((len(v), 3))
    nrm = np.zeros((len(v), 3))
    for k in range(3):
        m = skins[mesh.bones[:, k]]
        w = mesh.weights[:, k:k + 1]
        out += w * np.einsum("nij,nj->ni", m[:, :3, :], v)
        nrm += w * np.einsum("nij,nj->ni", m[:, :3, :3], mesh.normals)
    return out, nrm


def merged(gun: Model, arms: Model, arms_world: Sequence[Tuple[Vec, Quat]]) -> Pose:
    """The engine's bone merge: a bone named as one of the arms' takes its transform, the rest follow."""
    out: Pose = {}
    for j, b in enumerate(gun.bones):
        if b.name in arms.index:
            out[j] = arms_world[arms.index[b.name]]
        elif b.parent >= 0:
            pp, pq = out[b.parent]
            r = qrot(pq, b.pos)
            out[j] = ((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, b.quat))
        else:
            out[j] = (b.pos, b.quat)
    return out


def attachment(model: Model, pose: Pose, name: str) -> Optional[Vec]:
    for att, bone, local in _attachments(model):
        if att == name:
            p, q = pose[bone]
            r = qrot(q, local)
            return (p[0] + r[0], p[1] + r[1], p[2] + r[2])
    return None


def _attachments(model: Model):
    d, base = model.d, _i32(model.d, 244)
    for k in range(_i32(d, 240)):
        o = base + k * 92
        local = struct.unpack_from("<12f", d, o + 12)
        yield model.attachments[k][0], _i32(d, o + 8), (local[3], local[7], local[11])


# ---- the scene ----

@dataclass
class Layer:
    model: Model
    mesh: Mesh
    pose: Pose
    color: Tuple[int, int, int]
    wire: bool = False
    scale: float = 1.0  # the skinned mesh scaled about the origin (a ghost brought to another's size)


def posed(layer: Layer) -> Tuple[np.ndarray, np.ndarray]:
    v, n = skin(layer.model, layer.mesh, layer.pose)
    return v * layer.scale, n


@dataclass
class Scene:
    title: str
    layers: List[Layer]
    skeletons: List[Tuple[Model, Pose, Tuple[int, int, int], List[str]]] = field(default_factory=list)
    marks: Dict[str, Vec] = field(default_factory=dict)
    camera: Optional[object] = None  # a function of the picture's size giving its eye; None: the viewmodel's
    camera_name: str = ""


def oracle_scene(lib: Library, names: Sequence[str], label: str, frame: int, ghost: bool, body: Sequence[int]):
    arms, anims, hands, gun = (lib.model(n) for n in names)
    arms_world = arms.world(anims.pose(label, frame))
    return build_scene(lib, arms, hands, gun, dict(enumerate(arms_world)), solve(arms, arms_world, hands),
                       merged(gun, arms, arms_world), f"{label}@{frame}", ghost, body)


def build_scene(lib, arms, hands, gun, arms_pose, hands_pose, gun_pose, title, ghost, body) -> Scene:
    layers = [Layer(hands, load_mesh(lib, hands, body), hands_pose, HANDS_COLOR),
              Layer(gun, load_mesh(lib, gun), gun_pose, GUN_COLOR)]
    if ghost:
        layers.append(Layer(arms, load_mesh(lib, arms), arms_pose, ARMS_COLOR, wire=True))
    arm_chain = [n for n in (b.name for b in arms.bones) if n.startswith("bip_") and "collar" not in n]
    hand_chain = [b.name for b in hands.bones if "Clavicle" not in b.name and "Spine" not in b.name]
    scene = Scene(title, layers, [(arms, arms_pose, ARMS_BONE_COLOR, arm_chain), (hands, hands_pose, HANDS_BONE_COLOR, hand_chain)])
    for key, model, pose, bone in (("R", arms, arms_pose, "bip_hand_R"), ("L", arms, arms_pose, "bip_hand_L"),
                                   ("r", hands, hands_pose, "ValveBiped.Bip01_R_Hand"),
                                   ("l", hands, hands_pose, "ValveBiped.Bip01_L_Hand"),
                                   ("W", gun, gun_pose, "weapon_bone")):
        if bone in model.index:
            scene.marks[key] = pose[model.index[bone]][0]
    muzzle = attachment(gun, gun_pose, "muzzle")
    if muzzle:
        scene.marks["M"] = muzzle
    return scene


THIRD_EYE = (75.0, -55.0, 58.0)     # in front of the player and to its right, a little above
THIRD_TARGET = (0.0, 0.0, 38.0)


def third_scene(lib: Library, names: Sequence[str], base: str, frame: int, layer: Optional[str], ghost: bool,
                layer_cycle: Optional[float] = None) -> Scene:
    """A TF2 class's player animation on a GMod player model by body_rig's transformer, the weapon on
    its right hand by TF2's grip, the TF2 model a ghost brought to the GMod model's size."""
    import body_rig
    tf, anims, gm, gun = (lib.model(n) for n in names)
    seq = next(s for s in anims.sequences if s.label == base)
    cycle = layer_cycle if layer_cycle is not None else frame / max(1, seq.frames - 1)
    local = body_rig.layered(anims, base, frame, layer, cycle)
    w = body_rig.tf_world(tf, local)
    corr = body_rig.corrections(tf, gm)
    pose = body_rig.solve(tf, w, gm, corr)
    scale = body_rig.gm_scale(tf, gm)
    hand_corr = next(c for i, j, c in corr if gm.bones[j].name == body_rig.VB + "R_Hand")
    held = body_rig.grip(w, tf)
    wp, wq = body_rig.weapon_place(pose, gm, hand_corr, held)
    gun_pose: Pose = {}
    for j, b in enumerate(gun.bones):
        if b.name == "weapon_bone":
            gun_pose[j] = (wp, wq)
        else:
            pp, pq = gun_pose[b.parent]
            r = qrot(pq, b.pos)
            gun_pose[j] = ((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, b.quat))
    layers = [Layer(gm, load_mesh(lib, gm), pose, HANDS_COLOR), Layer(gun, load_mesh(lib, gun), gun_pose, GUN_COLOR)]
    if ghost:
        layers.append(Layer(tf, load_mesh(lib, tf), dict(enumerate(w)), ARMS_COLOR, wire=True, scale=scale))
        # TF2's own weapon where TF2's skeleton carries it, brought to the same size: what our right hand misses
        tf_gun = {j: w[tf.index[b.name]] if b.name in tf.index else None for j, b in enumerate(gun.bones)}
        for j, b in enumerate(gun.bones):
            if tf_gun[j] is None:
                pp, pq = tf_gun[b.parent]
                r = qrot(pq, b.pos)
                tf_gun[j] = ((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, b.quat))
        layers.append(Layer(gun, load_mesh(lib, gun), tf_gun, ARMS_COLOR, wire=True, scale=scale))
    chain_tf = [b.name for b in tf.bones if b.name.startswith("bip_") and "dogtag" not in b.name and "pack" not in b.name]
    chain_gm = [b.name for b in gm.bones if b.name.startswith(body_rig.VB)]
    scaled_w = {i: ((p[0] * scale, p[1] * scale, p[2] * scale), q) for i, (p, q) in enumerate(w)}
    title = f"{base}@{frame}" + (f" + {layer}" if layer else "") + f"  ({gm.name.split('/')[-1]} as {tf.name.split('/')[-1]})"
    scene = Scene(title, layers, [(tf, scaled_w, ARMS_BONE_COLOR, chain_tf), (gm, pose, HANDS_BONE_COLOR, chain_gm)],
                  camera=lambda size: LookCamera(size, THIRD_EYE, THIRD_TARGET), camera_name="third person")
    scene.marks["r"] = pose[gm.index[body_rig.VB + "R_Hand"]][0]
    scene.marks["l"] = pose[gm.index[body_rig.VB + "L_Hand"]][0]
    scene.marks["W"] = wp
    # where TF2's left hand sits on the weapon, carried onto ours: the left hand's IK target
    tw = w[tf.index["weapon_bone"]]
    lp = w[tf.index["bip_hand_L"]][0]
    on_gun = qrot(qconj(tw[1]), tuple(lp[k] - tw[0][k] for k in range(3)))
    t = qrot(wq, on_gun)
    scene.marks["T"] = (wp[0] + t[0], wp[1] + t[1], wp[2] + t[2])
    return scene


def dump_scene(lib: Library, path: Path, ghost: bool, body: Sequence[int]) -> Scene:
    """A frame tf_weapons_dump saved: each model's bones in the viewmodel's space, as the game had them."""
    dump = json.loads(path.read_text())
    arms, hands, gun = lib.model(dump["arms"]), lib.model(dump["hands"]), lib.model(dump["gun"])

    def pose(rows) -> Pose:
        return {i: ((r[0], r[1], r[2]), (r[3], r[4], r[5], r[6])) for i, r in enumerate(rows)}

    title = f"{path.stem}: {dump.get('sequence', '?')} cycle {dump.get('cycle', 0):.2f}"
    return build_scene(lib, arms, hands, gun, pose(dump["bones"]["arms"]), pose(dump["bones"]["hands"]),
                       pose(dump["bones"]["gun"]), title, ghost, body or dump.get("body", ()))


# ---- projection and drawing ----

class Camera:
    """The eye at the origin looking down +x; screen right is -y, up is +z. Nothing nearer than NEAR."""

    NEAR = 2.0

    def __init__(self, size: Tuple[int, int]):
        self.w, self.h = size
        tan_v = math.tan(math.radians(VIEWMODEL_FOV / 2)) * 3 / 4
        self.f = (self.h / 2) / tan_v
        self.cx, self.cy = self.w / 2, self.h / 2

    def project(self, p: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        depth = np.maximum(p[:, 0], 0.5)
        sx = self.cx - p[:, 1] / depth * self.f
        sy = self.cy - p[:, 2] / depth * self.f
        return np.stack([sx, sy], axis=1), depth

    def fit(self, points: np.ndarray, margin: float = 0.06, near: float = 10.0) -> None:
        """Zoomed and shifted onto the points, the eye where it was: the same picture, closer. What is
        nearer than `near` (the upper arms by the eye, which would fill it) is left out of the picture."""
        self.NEAR = near
        xy, depth = self.project(points)
        xy = xy[depth > near]
        lo, hi = xy.min(axis=0), xy.max(axis=0)
        zoom = min(self.w * (1 - 2 * margin) / max(hi[0] - lo[0], 1), self.h * (1 - 2 * margin) / max(hi[1] - lo[1], 1))
        mid = (lo + hi) / 2
        self.f *= zoom
        self.cx = self.w / 2 + (self.cx - mid[0]) * zoom
        self.cy = self.h / 2 + (self.cy - mid[1]) * zoom

    def to_view(self, v: np.ndarray) -> np.ndarray:
        """Directions in camera axes (right, up, toward the eye)."""
        return np.stack([-v[:, 1], v[:, 2], -v[:, 0]], axis=1)


class LookCamera(Camera):
    """A perspective eye anywhere, looking at a target, z up: a third person's view."""

    def __init__(self, size, eye, target, fov=60.0):
        super().__init__(size)
        self.eye = np.array(eye, dtype=float)
        f = np.array(target, dtype=float) - self.eye
        self.fwd = f / np.linalg.norm(f)
        left = np.cross([0.0, 0.0, 1.0], self.fwd)
        self.left = left / np.linalg.norm(left)
        self.up = np.cross(self.fwd, self.left)
        self.f = (self.h / 2) / math.tan(math.radians(fov / 2))
        self.NEAR = 1.0

    def _local(self, p):
        d = p - self.eye
        return np.stack([d @ self.fwd, d @ self.left, d @ self.up], axis=1)

    def project(self, p):
        return super().project(self._local(np.asarray(p, dtype=float)))

    def to_view(self, v):
        return super().to_view(np.stack([v @ self.fwd, v @ self.left, v @ self.up], axis=1))

    def fit(self, points, margin=0.06, near=1.0):
        Camera.fit(self, points, margin, near)


class Plan:
    """An orthographic view: axes picked from x, y, z, each signed; depth grows away from the viewer."""

    NEAR = -math.inf

    def __init__(self, size, right: Tuple[int, float], up: Tuple[int, float], toward: Tuple[int, float], name: str):
        self.w, self.h = size
        self.right, self.up, self.toward, self.name = right, up, toward, name
        self.scale, self.center = 1.0, (0.0, 0.0)

    def axes(self, p):
        return p[:, self.right[0]] * self.right[1], p[:, self.up[0]] * self.up[1], p[:, self.toward[0]] * self.toward[1]

    def fit(self, points: np.ndarray, margin: float = 0.08) -> None:
        r, u, _ = self.axes(points)
        span = max(r.max() - r.min(), (u.max() - u.min()) * self.w / self.h, 1e-3)
        self.scale = self.w * (1 - 2 * margin) / span
        self.center = ((r.max() + r.min()) / 2, (u.max() + u.min()) / 2)

    def project(self, p: np.ndarray):
        r, u, t = self.axes(p)
        sx = self.w / 2 + (r - self.center[0]) * self.scale
        sy = self.h / 2 - (u - self.center[1]) * self.scale
        return np.stack([sx, sy], axis=1), -t

    def to_view(self, v: np.ndarray) -> np.ndarray:
        r, u, t = self.axes(v)
        return np.stack([r, u, t], axis=1)


def plans(size) -> List[Plan]:
    return [Plan(size, (1, -1), (0, 1), (2, 1), "from above (forward up)"),
            Plan(size, (0, 1), (2, 1), (1, -1), "from the right (forward right)"),
            Plan(size, (1, -1), (2, 1), (0, 1), "from in front, as the eye (right right)")]


def _shade(color, normals_view) -> List[Tuple[int, int, int]]:
    n = normals_view / np.maximum(np.linalg.norm(normals_view, axis=1, keepdims=True), 1e-9)
    lit = AMBIENT + (1 - AMBIENT) * np.clip(np.abs(n @ LIGHT), 0, 1)
    c = np.clip(np.outer(lit, color), 0, 255).astype(int)
    return [tuple(row) for row in c]


def _paint(view, layers, skinned, size, background) -> Image.Image:
    """The layers' triangles, far to near (painter's order), flat-shaded."""
    img = Image.new("RGBA", size, background)
    pen = ImageDraw.Draw(img)
    solid = []  # (depth, polygon, color)
    for layer, (verts, _) in zip(layers, skinned):
        tri = layer.mesh.triangles
        xy, depth = view.project(verts)
        a, b, c = verts[tri[:, 0]], verts[tri[:, 1]], verts[tri[:, 2]]
        colors = _shade(layer.color, view.to_view(np.cross(b - a, c - a)))
        mean_depth = depth[tri].mean(axis=1)
        seen = depth[tri].min(axis=1) > view.NEAR
        for k in np.nonzero(seen)[0]:
            solid.append((mean_depth[k], [tuple(xy[tri[k, j]]) for j in range(3)], colors[k] + (255,)))
    solid.sort(key=lambda t: -t[0])
    for _, poly, color in solid:
        pen.polygon(poly, fill=color)
    return img


def draw_view(view, scene: Scene, skinned, size, font, labels: bool = True) -> Image.Image:
    solid = [(l, sk) for l, sk in zip(scene.layers, skinned) if not l.wire]
    ghost = [(l, sk) for l, sk in zip(scene.layers, skinned) if l.wire]
    img = _paint(view, [l for l, _ in solid], [sk for _, sk in solid], size, BACKGROUND + (255,))
    if ghost:
        over = _paint(view, [l for l, _ in ghost], [sk for _, sk in ghost], size, (0, 0, 0, 0))
        alpha = over.getchannel("A").point(lambda v: int(v * GHOST_ALPHA))
        over.putalpha(alpha)
        img = Image.alpha_composite(img, over)
    img = img.convert("RGB")
    pen = ImageDraw.Draw(img)
    for model, pose, color, chain in scene.skeletons:
        for name in chain:
            i = model.index[name]
            parent = model.bones[i].parent
            if parent < 0 or model.bones[parent].name not in chain:
                continue
            seg, depth = view.project(np.array([pose[parent][0], pose[i][0]]))
            if depth.min() <= view.NEAR:
                continue
            pen.line([tuple(seg[0]), tuple(seg[1])], fill=color, width=2)
    for key, p in scene.marks.items():
        pt, depth = view.project(np.array([p]))
        if depth[0] <= view.NEAR:
            continue
        x, y = pt[0]
        pen.ellipse([x - 4, y - 4, x + 4, y + 4], outline=MARK_COLOR, width=2)
        if labels:
            pen.text((x + 6, y - 6), key, fill=MARK_COLOR, font=font)
    return img


def picture(scene: Scene, with_plans: bool = True, fit: bool = False) -> Image.Image:
    font = ImageFont.load_default()
    skinned = [posed(l) for l in scene.layers]
    eye = scene.camera(CAMERA_SIZE) if scene.camera else Camera(CAMERA_SIZE)
    if fit:
        eye.fit(np.vstack([v for v, _ in skinned]))
    camera = draw_view(eye, scene, skinned, CAMERA_SIZE, font)
    framing = "framed on the meshes" if fit else (scene.camera_name or f"as in game, fov {VIEWMODEL_FOV:g}")
    ImageDraw.Draw(camera).text((10, 8), f"{scene.title}  (the eye; {framing})", fill=(255, 255, 255), font=font)
    _legend(ImageDraw.Draw(camera), font, CAMERA_SIZE)
    if not with_plans:
        return camera
    every = np.vstack([v for v, _ in skinned] + [np.array(list(scene.marks.values()))])
    row = Image.new("RGB", (CAMERA_SIZE[0], PLAN_SIZE[1]), BACKGROUND)
    for k, plan in enumerate(plans(PLAN_SIZE)):
        plan.fit(every)
        img = draw_view(plan, scene, skinned, PLAN_SIZE, font)
        pen = ImageDraw.Draw(img)
        pen.text((6, 6), plan.name, fill=(255, 255, 255), font=font)
        _ruler(pen, font, plan)
        row.paste(img, (k * PLAN_SIZE[0], 0))
    out = Image.new("RGB", (CAMERA_SIZE[0], CAMERA_SIZE[1] + PLAN_SIZE[1]), BACKGROUND)
    out.paste(camera, (0, 0))
    out.paste(row, (0, CAMERA_SIZE[1]))
    return out


def _ruler(pen, font, plan: Plan) -> None:
    """A bar 5 units long, for scale."""
    length = 5 * plan.scale
    y = plan.h - 14
    pen.line([(8, y), (8 + length, y)], fill=(255, 255, 255), width=2)
    pen.text((12 + length, y - 6), "5 units", fill=(255, 255, 255), font=font)


def _legend(pen, font, size) -> None:
    items = [("your model (hands or player)", HANDS_COLOR), ("weapon", GUN_COLOR), ("TF2's model, translucent (--ghost)", ARMS_COLOR),
             ("your model's bones", HANDS_BONE_COLOR), ("TF2's bones", ARMS_BONE_COLOR),
             ("R/L TF2 hand  r/l yours  W weapon bone  M muzzle  T left hand's target", MARK_COLOR)]
    y = size[1] - 16 * len(items) - 6
    for text, color in items:
        pen.rectangle([10, y + 3, 20, y + 13], fill=color)
        pen.text((26, y + 2), text, fill=(230, 230, 230), font=font)
        y += 16


# ---- text ----

def ascii_camera(scene: Scene, size=ASCII_SIZE, fit: bool = False) -> str:
    """The camera as characters: a cell's nearest triangle decides it; marks over everything."""
    w, h = size
    cam = Camera((w, h * 2))  # a character is about twice as tall as wide
    if fit:
        cam.fit(np.vstack([posed(l)[0] for l in scene.layers]))
    grid = [[" "] * w for _ in range(h)]
    zbuf = np.full((h, w), np.inf)
    chars = {HANDS_COLOR: "#+", GUN_COLOR: "=-", ARMS_COLOR: "o."}
    for layer in scene.layers:
        verts, _ = posed(layer)
        xy, depth = cam.project(verts)
        xy[:, 1] /= 2
        tri = layer.mesh.triangles
        face = np.cross(verts[tri[:, 1]] - verts[tri[:, 0]], verts[tri[:, 2]] - verts[tri[:, 0]])
        n = cam.to_view(face)
        lit = np.abs((n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)) @ LIGHT)
        bright, dim = chars[layer.color]
        for k in range(len(tri)):
            if depth[tri[k]].min() <= cam.NEAR:
                continue
            pts = xy[tri[k]]
            d = depth[tri[k]].mean()
            x0, x1 = int(max(0, np.floor(pts[:, 0].min()))), int(min(w - 1, np.ceil(pts[:, 0].max())))
            y0, y1 = int(max(0, np.floor(pts[:, 1].min()))), int(min(h - 1, np.ceil(pts[:, 1].max())))
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    if _inside(pts, x + 0.5, y + 0.5) and d < zbuf[y, x]:
                        zbuf[y, x] = d
                        grid[y][x] = bright if lit[k] > 0.5 else dim
    for key, p in scene.marks.items():
        pt, _ = cam.project(np.array([p]))
        x, y = int(pt[0, 0]), int(pt[0, 1] / 2)
        if 0 <= x < w and 0 <= y < h:
            grid[y][x] = key
    border = "+" + "-" * w + "+"
    return "\n".join([scene.title, border] + ["|" + "".join(r) + "|" for r in grid] + [border])


def _inside(pts, x, y) -> bool:
    (ax, ay), (bx, by), (cx, cy) = pts
    d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by)
    d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy)
    d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def where(lib: Library, names: Sequence[str], label: str, frames: Sequence[int]) -> str:
    """Hands and TF2 hands in the weapon bone's axes (forward x, left y, up z), and how far apart."""
    arms, anims, hands, gun = (lib.model(n) for n in names)
    rows = [f"{label}: positions in weapon_bone's axes (x forward, y left, z up), units",
            f"{'frame':>5}  {'TF2 R hand':>22}  {'hands R':>22}  {'dR':>5}  {'TF2 L hand':>22}  {'hands L':>22}  {'dL':>5}"]
    wb = arms.index["weapon_bone"]
    for frame in frames:
        w = arms.world(anims.pose(label, frame))
        out = solve(arms, w, hands)
        bp, bq = w[wb]

        def local(p):
            r = qrot(qconj(bq), (p[0] - bp[0], p[1] - bp[1], p[2] - bp[2]))
            return r

        cells = [f"{frame:>5}"]
        for side in "RL":
            s = local(w[arms.index[f"bip_hand_{side}"]][0])
            h = local(out[hands.index[f"ValveBiped.Bip01_{side}_Hand"]][0])
            fmt = lambda v: "({:+6.2f} {:+6.2f} {:+6.2f})".format(*v)  # noqa: E731
            cells += [f"{fmt(s):>22}", f"{fmt(h):>22}", f"{math.dist(s, h):5.2f}"]
        rows.append("  ".join(cells))
    return "\n".join(rows)


# ---- the command line ----

def _frames(spec: str) -> Tuple[str, int]:
    if "@" not in spec:
        return spec, 0
    label, frame = spec.rsplit("@", 1)
    return label, int(frame)


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=("frame", "sheet", "dump", "where", "third"))
    ap.add_argument("--layer", default=None)
    ap.add_argument("--third", action="store_true", help="sheet: the third-person scene (body_rig)")
    ap.add_argument("args", nargs="+")
    ap.add_argument("--vpk", action="append", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--ascii", action="store_true")
    ap.add_argument("--no-png", action="store_true")
    ap.add_argument("--ghost", action="store_true")
    ap.add_argument("--fit", action="store_true")
    ap.add_argument("--count", type=int, default=8)
    ap.add_argument("--body", default="")
    a = ap.parse_args(argv)
    lib = Library(a.vpk or DEFAULT_VPKS)
    body = [int(x) for x in a.body.split(",") if x]
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    if a.command == "where":
        names, (label, frame) = a.args[:4], _frames(a.args[4])
        seq = next(s for s in lib.model(names[1]).sequences if s.label == label)
        frames = [frame] if "@" in a.args[4] else list(range(0, seq.frames, max(1, seq.frames // 12)))
        print(where(lib, names, label, frames))
        return 0
    if a.command == "dump":
        scenes = [dump_scene(lib, Path(a.args[0]), a.ghost, body)]
        stems = [Path(a.args[0]).stem]
    elif a.command == "third":
        names = a.args[:4]
        scenes, stems = [], []
        for spec in a.args[4:]:
            label, frame = _frames(spec)
            scenes.append(third_scene(lib, names, label, frame, a.layer, a.ghost))
            stems.append(f"third_{label}@{frame}" + (f"+{a.layer}" if a.layer else ""))
    elif a.command == "frame":
        names = a.args[:4]
        scenes, stems = [], []
        for spec in a.args[4:]:
            label, frame = _frames(spec)
            scenes.append(oracle_scene(lib, names, label, frame, a.ghost, body))
            stems.append(f"{label}@{frame}")
    else:
        names, label = a.args[:4], a.args[4]
        seq = next(s for s in lib.model(names[1]).sequences if s.label == label)
        picks = sorted({round(k * (seq.frames - 1) / max(1, a.count - 1)) for k in range(a.count)})
        cols = 4 if len(picks) > 4 else len(picks)
        rows = math.ceil(len(picks) / cols)
        sheet = Image.new("RGB", (cols * SHEET_CELL[0], rows * SHEET_CELL[1]), BACKGROUND)
        for k, frame in enumerate(picks):
            if a.third:
                scene = third_scene(lib, names, label, frame, a.layer, a.ghost)
            else:
                scene = oracle_scene(lib, names, label, frame, a.ghost, body)
            cell = picture(scene, with_plans=False, fit=a.fit).resize(SHEET_CELL, Image.LANCZOS)
            sheet.paste(cell, ((k % cols) * SHEET_CELL[0], (k // cols) * SHEET_CELL[1]))
        out = a.out or OUT_DIR / (f"{'third_' if a.third else ''}{label}{'+' + a.layer if a.layer else ''}_sheet.png")
        sheet.save(out)
        print(out)
        return 0
    for scene, stem in zip(scenes, stems):
        if a.ascii:
            print(ascii_camera(scene, fit=a.fit))
        if not a.no_png:
            out = a.out if a.out and len(scenes) == 1 else OUT_DIR / f"{stem}.png"
            picture(scene, fit=a.fit).save(out)
            print(out)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RigError as e:
        print(f"rig_view: {e}", file=sys.stderr)
        sys.exit(1)
