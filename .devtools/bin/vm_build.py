#!/usr/bin/env python3
"""Build a TF2 weapon's viewmodel sources for studiomdl: GMod's c_arms skeleton playing TF2's sequences.

  vm_build.py SWEP.lua [--out DIR] [--vpk PATH]...

Laid out as GMod's own c_ weapons are (models/weapons/c_smg1.mdl): the 39 c_arms bones every stock
hands model shares to the 0.000 unit, each bone-merged ($bonemerge, the flag c_smg1's carry), so
gmod_hands rides them; a second root, `weapon_root`, carrying the TF2 c_model's own bones and its
mesh, skins and attachments. Each sequence the weapon's TFAnimations name is baked by vm_bake: the
retarget, the fingers and thumbs held to the c_arms' own range, both hands IK'd onto where TF2's hold
the weapon; the weapon's bones go exactly where TF2's arms carry them. Each takes GMod's own ACT_VM_*
activity (SWEP.TFViewActivities), so a plain SWEP with UseHands plays it.

The files are made from the TF2 and GMod content on this machine into .devtools/artifacts/vm_build/
(never committed: they are Valve's content, reshaped); model_compile.py compiles them.
"""
from __future__ import annotations

import argparse
import math
import re
import struct
import sys
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import numpy as np

import smd
import vm_bake
from mdl_rig import DEFAULT_VPKS, Library, Model, RigError, _cstr, _i32, qconj, qmul, qrot
from rig_view import load_mesh

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / ".devtools" / "artifacts" / "vm_build"
HANDS = "models/weapons/c_arms_citizen.mdl"
ARM_BONES = 39       # c_arms_citizen's first 39: c_smg1's arm bones, without the procedural helpers
WEAPON_ROOT = "weapon_root"
# GMod's activity a TF2 viewmodel activity plays as, by the SWEP's TFAnimations key
GMOD_ACTIVITY = {
    "draw": "ACT_VM_DRAW", "idle": "ACT_VM_IDLE", "fire": "ACT_VM_PRIMARYATTACK",
    "reloadStart": "ACT_SHOTGUN_RELOAD_START", "reload": "ACT_VM_RELOAD", "reloadEnd": "ACT_SHOTGUN_RELOAD_FINISH",
    "hit": "ACT_VM_HITCENTER", "hard": "ACT_VM_SWINGHARD", "miss": "ACT_VM_MISSCENTER",
}
EVENT_SIZE = 80
# What the written files may differ from the bake by: a thousandth of a unit is a tenth of a pixel at the
# viewmodel's distance; a hundredth of a degree moves a 12-unit forearm's end 0.002 units
VERIFY_POSITION = 1e-3
VERIFY_ROTATION = 0.01
LOOPING = 0x1


def swep_fields(path: Path) -> Tuple[str, str, Dict[str, str]]:
    text = path.read_text()
    arms = re.search(r'SWEP\.ViewModel\s*=\s*"([^"]+)"', text)
    gun = re.search(r'SWEP\.TFModel\s*=\s*"([^"]+)"', text)
    block = re.search(r"SWEP\.TFAnimations\s*=\s*\{(.*?)\}", text, re.S)
    if not arms or not gun or not block:
        raise RigError(f"{path}: no SWEP.ViewModel, SWEP.TFModel or SWEP.TFAnimations")
    return arms.group(1), gun.group(1), dict(re.findall(r'(\w+)\s*=\s*"([^"]+)"', block.group(1)))


def events(model: Model, seq_index: int) -> List[Tuple[float, int, str]]:
    """A sequence's events: (cycle, event number, options)."""
    d = model.d
    o = _i32(d, 192) + seq_index * 212
    out = []
    for k in range(_i32(d, o + 24)):
        q = o + _i32(d, o + 28) + k * EVENT_SIZE
        out.append((struct.unpack_from("<f", d, q)[0], _i32(d, q + 4), d[q + 12:q + 76].split(b"\0")[0].decode("latin-1")))
    return out


def textures(model: Model) -> Tuple[List[str], List[str], List[List[int]]]:
    d = model.d
    names = [_cstr(d, _i32(d, 208) + k * 64 + _i32(d, _i32(d, 208) + k * 64)) for k in range(_i32(d, 204))]
    cd = [_cstr(d, _i32(d, _i32(d, 216) + k * 4)) for k in range(_i32(d, 212))]
    refs, families = _i32(d, 220), _i32(d, 224)
    skins = [list(struct.unpack_from(f"<{refs}h", d, _i32(d, 228) + f * refs * 2)) for f in range(families)]
    return names, cd, skins


def attachments(model: Model) -> List[Tuple[str, str, Tuple[float, ...]]]:
    """(name, bone, the 3x4 local matrix's 12 numbers)."""
    d, base = model.d, _i32(model.d, 244)
    return [(_cstr(d, base + k * 92 + _i32(d, base + k * 92)), model.bones[_i32(d, base + k * 92 + 8)].name,
             struct.unpack_from("<12f", d, base + k * 92 + 12)) for k in range(_i32(d, 240))]


def nodes_of(hands: Model, gun: Model) -> List[Tuple[str, int]]:
    nodes = [(b.name, b.parent) for b in hands.bones[:ARM_BONES]]
    if any(p >= ARM_BONES for _, p in nodes):
        raise RigError(f"{hands.name}: an arm bone's parent is a helper bone")
    root = len(nodes)
    nodes.append((WEAPON_ROOT, -1))
    for b in gun.bones:
        nodes.append((b.name, root if b.parent < 0 else root + 1 + b.parent))
    return nodes


def reference(hands: Model, gun: Model, lib: Library) -> smd.Smd:
    """The bind pose (the hands' rest, the weapon at the root), and the weapon's mesh."""
    nodes = nodes_of(hands, gun)
    frame = [(b.pos, b.quat) for b in hands.bones[:ARM_BONES]] + [((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0))]
    frame += [(b.pos, b.quat) for b in gun.bones]
    out = smd.Smd(nodes, [frame])
    mesh = load_mesh(lib, gun)
    names, _, _ = textures(gun)
    first = ARM_BONES + 1
    for t, mat in zip(mesh.triangles, mesh.materials):
        verts = []
        for v in (t[0], t[2], t[1]):  # the strips wind clockwise; an SMD's triangles the other way
            links = [(first + int(mesh.bones[v, k]), float(mesh.weights[v, k])) for k in range(3) if mesh.weights[v, k] > 0]
            u, w = mesh.uvs[v]
            verts.append(smd.Vertex(links[0][0], tuple(mesh.positions[v]), tuple(mesh.normals[v]), (float(u), 1.0 - float(w)),
                                    links))
        out.triangles.append((names[int(mat)], tuple(verts)))
    return out


def animation(hands: Model, gun: Model, arms: Model, anims: Model, label: str, pose_of) -> smd.Smd:
    nodes = nodes_of(hands, gun)
    seq = next(s for s in anims.sequences if s.label == label)
    frames = []
    for f in range(seq.frames):
        w = arms.world(anims.pose(label, f))
        pose, _ = pose_of(w)
        frame = []
        for j, b in enumerate(hands.bones[:ARM_BONES]):
            p, q = pose[j]
            if b.parent >= 0:
                pp, pq = pose[b.parent]
                p, q = qrot(qconj(pq), tuple(np.subtract(p, pp))), qmul(qconj(pq), q)
            frame.append((tuple(p), q))
        frame.append(((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)))
        gw = {}
        for k, b in enumerate(gun.bones):
            if b.name in arms.index:
                gw[k] = w[arms.index[b.name]]
            else:
                pp, pq = gw[b.parent]
                r = qrot(pq, b.pos)
                gw[k] = ((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, b.quat))
            p, q = gw[k]
            if b.parent >= 0:
                pp, pq = gw[b.parent]
                p, q = qrot(qconj(pq), tuple(np.subtract(p, pp))), qmul(qconj(pq), q)
            frame.append((tuple(p), q))
        frames.append(frame)
    return smd.Smd(nodes, frames)


def qc(name: str, gun: Model, anims: Model, sequences: List[Tuple[str, str, str]], hands: Model) -> str:
    texnames, cd, skins = textures(gun)
    lines = [f"// Generated by .devtools/bin/vm_build.py; do not edit.", f'$modelname "tf_weapons/{name}.mdl"',
             '$cdmaterials ""'] + [f'$cdmaterials "{c}"' for c in cd if c] + [
             '$body "studio" "reference.smd"', f'$surfaceprop "{_cstr(gun.d, _i32(gun.d, 308)) or "metal"}"']
    if len(skins) > 1:
        used = sorted({t for fam in skins for t in fam})
        lines.append('$texturegroup "skinfamilies"\n{')
        for fam in skins:
            lines.append("\t{ " + " ".join(f'"{texnames[t]}"' for t in fam) + " }")
        lines.append("}")
    for b in hands.bones[:ARM_BONES]:
        lines.append(f'$bonemerge "{b.name}"')
    for b in gun.bones:
        lines.append(f'$bonemerge "{b.name}"')
    for att, bone, m in attachments(gun):
        x, y, z = m[3], m[7], m[11]
        # the local matrix as a rotation for $attachment: QAngle (pitch, yaw, roll) from its axes
        fwd, left, up = (m[0], m[4], m[8]), (m[1], m[5], m[9]), (m[2], m[6], m[10])
        pitch = math.degrees(math.atan2(-fwd[2], math.hypot(fwd[0], fwd[1])))
        yaw = math.degrees(math.atan2(fwd[1], fwd[0]))
        roll = math.degrees(math.atan2(left[2], up[2]))
        lines.append(f'$attachment "{att}" "{bone}" {x:.6f} {y:.6f} {z:.6f} rotate {pitch:.4f} {yaw:.4f} {roll:.4f}')
    for seq_name, label, activity in sequences:
        seq = next(s for s in anims.sequences if s.label == label)
        body = [f'$sequence "{seq_name}" "anims/{label}.smd" fps {seq.fps:g}' + (" loop" if seq.flags & LOOPING else "")
                + f' activity "{activity}" 1']
        evs = events(anims, seq.index)
        if evs:
            body[0] += " {"
            for cycle, number, options in evs:
                body.append(f'\t{{ event {number} {round(cycle * max(1, seq.frames - 1))} "{options}" }}')
            body.append("}")
        lines += body
    return "\n".join(lines) + "\n"


def build(lib: Library, swep: Path, out_root: Path) -> Path:
    arms_name, gun_name, animations = swep_fields(swep)
    arms, gun, hands = lib.model(arms_name), lib.model(gun_name), lib.model(HANDS)
    anims = lib.model(arms.includes[0]) if arms.includes else arms
    name = swep.stem.replace("tf_weapon_", "v_tf_")
    out = out_root / name
    (out / "anims").mkdir(parents=True, exist_ok=True)
    with open(out / "reference.smd", "w") as f:
        smd.write(reference(hands, gun, lib), f)
    pose_of = vm_bake.pipeline(lib, arms, hands)
    sequences = []
    for key, act in animations.items():
        gmod = GMOD_ACTIVITY.get(key)
        if gmod is None:
            raise RigError(f"{swep.name}: no GMod activity for TFAnimations.{key}")
        for s in anims.sequences:
            if s.activity == act and s.anim >= 0:
                with open(out / "anims" / f"{s.label}.smd", "w") as f:
                    smd.write(animation(hands, gun, arms, anims, s.label, pose_of), f)
                sequences.append((s.label, s.label, gmod))
    (out / f"{name}.qc").write_text(qc(name, gun, anims, sequences, hands))
    return out


def _unit(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def fk(nodes, frame):
    """World (pos, quat) of every node from an SMD frame's parent-space ones."""
    world = []
    for (name, parent), (p, q) in zip(nodes, frame):
        if parent < 0:
            world.append((p, q))
        else:
            pp, pq = world[parent]
            r = qrot(pq, p)
            world.append(((pp[0] + r[0], pp[1] + r[1], pp[2] + r[2]), qmul(pq, q)))
    return world


def verify(lib: Library, swep: Path, out: Path) -> Dict[str, float]:
    """The written files read back against the bake: the worst arm bone off the baked pose, weapon bone off TF2's
    path (units, degrees), and weapon vertex off TF2's own mesh, posed at each frame."""
    from mdl_rig import axis_angle
    from rig_view import skin
    arms_name, gun_name, animations = swep_fields(swep)
    arms, gun, hands = lib.model(arms_name), lib.model(gun_name), lib.model(HANDS)
    anims = lib.model(arms.includes[0]) if arms.includes else arms
    pose_of = vm_bake.pipeline(lib, arms, hands)
    ref = smd.read((out / "reference.smd").read_text())
    worst = {"arm position": 0.0, "arm rotation": 0.0, "weapon position": 0.0, "weapon rotation": 0.0, "weapon vertex": 0.0}
    tf_mesh = load_mesh(lib, gun)
    # the reference's weapon vertices, by position, against TF2's own (bind pose, before any frame)
    ref_pts = np.array([v.pos for _, tri in ref.triangles for v in tri])
    tf_pts = tf_mesh.positions[tf_mesh.triangles[:, [0, 2, 1]].reshape(-1)]
    worst["reference vertex"] = float(np.abs(ref_pts - tf_pts).max())
    first = ARM_BONES + 1
    for path in sorted((out / "anims").glob("*.smd")):
        label = path.stem
        anim = smd.read(path.read_text())
        for f, frame in enumerate(anim.frames):
            world = fk(anim.nodes, frame)
            w = arms.world(anims.pose(label, f))
            baked, _ = pose_of(w)
            for j in range(ARM_BONES):
                worst["arm position"] = max(worst["arm position"], float(np.linalg.norm(np.subtract(world[j][0], baked[j][0]))))
                worst["arm rotation"] = max(worst["arm rotation"], axis_angle(qmul(qconj(_unit(world[j][1])), _unit(baked[j][1])))[1])
            gun_pose = {}
            for k, b in enumerate(gun.bones):
                gw = world[first + k]
                gun_pose[k] = gw
                if b.name in arms.index:
                    t = w[arms.index[b.name]]
                    worst["weapon position"] = max(worst["weapon position"], float(np.linalg.norm(np.subtract(gw[0], t[0]))))
                    worst["weapon rotation"] = max(worst["weapon rotation"], axis_angle(qmul(qconj(_unit(gw[1])), _unit(t[1])))[1])
            ours, _ = skin(gun, tf_mesh, gun_pose)
            theirs, _ = skin(gun, tf_mesh, {k: (w[arms.index[b.name]] if b.name in arms.index else gun_pose[k])
                                            for k, b in enumerate(gun.bones)})
            worst["weapon vertex"] = max(worst["weapon vertex"], float(np.abs(ours - theirs).max()))
    return worst


# What the compiled model may differ from its sources by. studiomdl keeps an animated value as a 16-bit step
# of its bone's scale (rotscale, posscale: a range over 32767), so a full turn is 0.011 degrees a step and
# a 20-unit reach 0.0006 units; these bounds are ten steps of that, derived, not measured on a compile of
# known sources (a model decoded and written back out, test_vm_build's stand-in, differs by 0.00003)
COMPILED_POSITION = 0.01
COMPILED_ROTATION = 0.1


def check_compiled(lib: Library, source: Path, model_name: str) -> List[Tuple[str, bool, str]]:
    """A compiled viewmodel held to the sources it was compiled from: (check, passed, detail) rows."""
    from mdl_rig import axis_angle
    m = lib.model(model_name)
    rows: List[Tuple[str, bool, str]] = []
    ref = smd.read((source / "reference.smd").read_text())
    names = [n for n, _ in ref.nodes]
    missing = [n for n in names if n not in m.index]
    rows.append(("every source bone compiled", not missing, f"missing {missing[:5]}" if missing else f"{len(names)} bones"))
    parents_ok = all((m.bones[m.index[n]].parent < 0) == (p < 0) and (p < 0 or m.bones[m.bones[m.index[n]].parent].name == names[p])
                     for n, p in ref.nodes if n in m.index)
    rows.append(("parents as in the sources", parents_ok, ""))
    unmerged = [n for n in names[:ARM_BONES] if n in m.index and not m.bones[m.index[n]].flags & 0x40000]
    rows.append(("arm bones bone-merged (0x40000, as c_smg1's)", not unmerged, f"not: {unmerged[:5]}" if unmerged else ""))
    qc_text = next(source.glob("*.qc")).read_text()
    wanted = dict(re.findall(r'\$sequence "([^"]+)" .*? activity "([^"]+)"', qc_text))
    have = {s.label: s.activity for s in m.sequences}
    wrong = {k: (v, have.get(k)) for k, v in wanted.items() if have.get(k) != v}
    rows.append(("each sequence with its activity", not wrong, f"{wrong}" if wrong else f"{len(wanted)} sequences"))
    worst_p, worst_r, where_p, where_r = 0.0, 0.0, "-", "-"
    for label in wanted:
        if label not in have:
            continue
        anim = smd.read((source / "anims" / f"{label}.smd").read_text())
        for f, frame in enumerate(anim.frames):
            want = fk(anim.nodes, frame)
            got = m.world(m.pose(label, f))
            for k, (n, _) in enumerate(anim.nodes):
                if n not in m.index:
                    continue
                g = got[m.index[n]]
                dp = float(np.linalg.norm(np.subtract(g[0], want[k][0])))
                dr = axis_angle(qmul(qconj(_unit(g[1])), _unit(want[k][1])))[1]
                if dp > worst_p:
                    worst_p, where_p = dp, f"{label}@{f} {n}"
                if dr > worst_r:
                    worst_r, where_r = dr, f"{label}@{f} {n}"
    rows.append(("frames as the sources (position)", worst_p <= COMPILED_POSITION, f"worst {worst_p:.5f} units ({where_p})"))
    rows.append(("frames as the sources (rotation)", worst_r <= COMPILED_ROTATION, f"worst {worst_r:.4f} deg ({where_r})"))
    mesh = load_mesh(lib, m)
    t = mesh.triangles
    a, b, c = (mesh.positions[t[:, k]] for k in range(3))
    agree = float((np.einsum("ij,ij->i", np.cross(b - a, c - a), mesh.normals[t].sum(axis=1)) > 0).mean())
    rows.append(("triangles wound as Valve's (normals disagree with strip order)", agree < 0.01, f"{agree * 100:.1f}% agree"))
    ref_pts = np.array([v.pos for _, tri in ref.triangles for v in tri])
    ref_uv = np.array([v.uv for _, tri in ref.triangles for v in tri])
    tree = {}
    for p, uv in zip(np.round(ref_pts, 3), ref_uv):
        tree.setdefault(tuple(p), []).append(uv)
    off_uv, unmatched = 0.0, 0
    for p, uv in zip(np.round(mesh.positions, 3), mesh.uvs):
        cands = tree.get(tuple(p))
        if not cands:
            unmatched += 1
            continue
        # the SMD keeps v up; the compiled file, as the original, v down
        off_uv = max(off_uv, min(float(np.abs(np.array([u, 1 - v]) - uv).max()) for u, v in cands))
    rows.append(("compiled vertices at the sources' places", unmatched == 0, f"{unmatched} unmatched of {len(mesh.positions)}"))
    rows.append(("texture coordinates as the sources'", off_uv <= 1e-3, f"worst {off_uv:.5f}"))
    return rows


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("swep", type=Path)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--vpk", action="append", type=Path)
    ap.add_argument("--verify", action="store_true", help="read the files back against the bake")
    ap.add_argument("--compiled", type=Path, metavar="GAME_ROOT",
                    help="check the compiled model under GAME_ROOT (the folder holding models/) against its sources")
    a = ap.parse_args(argv)
    if a.compiled:
        lib = Library(a.vpk or DEFAULT_VPKS, [a.compiled])
        name = a.swep.stem.replace("tf_weapon_", "v_tf_")
        rows = check_compiled(lib, a.out / name, f"models/tf_weapons/{name}.mdl")
        for check, passed, detail in rows:
            print(f"  {'ok  ' if passed else 'FAIL'} {check}: {detail}")
        return 0 if all(p for _, p, _ in rows) else 1
    lib = Library(a.vpk or DEFAULT_VPKS)
    out = build(lib, a.swep, a.out)
    print(out)
    if a.verify:
        ok = True
        for key, value in verify(lib, a.swep, out).items():
            bound = VERIFY_ROTATION if "rotation" in key else VERIFY_POSITION
            ok = ok and value <= bound
            print(f"  {'ok  ' if value <= bound else 'FAIL'} {key:18s} worst {value:.6f} (bound {bound:g})")
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RigError as e:
        print(f"vm_build: {e}", file=sys.stderr)
        sys.exit(1)
