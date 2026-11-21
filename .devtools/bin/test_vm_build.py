#!/usr/bin/env python3
"""vm_build's compiled-model check, held to a model studiomdl compiled: GMod's own c_smg1, laid out as
ours are (39 bone-merged c_arms bones, then the weapon's root). Its sources are written back out of it
(the reference, every sequence's frames, the QC's activities), so the check must pass it, and fail it
once the sources are changed.

  MDL_RIG_VPKS=tf2_misc_dir.vpk:garrysmod_dir.vpk python3 test_vm_build.py
"""
from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from mdl_rig import DEFAULT_VPKS, STUDIO_DELTA, Library, Model
from rig_view import load_mesh
import smd
import vm_build

VPKS = [Path(p) for p in os.environ.get("MDL_RIG_VPKS", "").split(os.pathsep) if p] or list(DEFAULT_VPKS)
STAND_IN = "models/weapons/c_smg1.mdl"


def sources_of(lib: Library, m: Model, out: Path) -> None:
    """A compiled model's sources as vm_build writes ours: reference.smd, anims/<label>.smd, a QC."""
    nodes = [(b.name, b.parent) for b in m.bones]
    ref = smd.Smd(nodes, [[(b.pos, b.quat) for b in m.bones]])
    mesh = load_mesh(lib, m)
    for t in mesh.triangles:
        verts = []
        for v in (t[0], t[2], t[1]):
            links = [(int(mesh.bones[v, k]), float(mesh.weights[v, k])) for k in range(3) if mesh.weights[v, k] > 0]
            u, w = mesh.uvs[v]
            verts.append(smd.Vertex(links[0][0], tuple(mesh.positions[v]), tuple(mesh.normals[v]),
                                    (float(u), 1.0 - float(w)), links))
        ref.triangles.append(("material", tuple(verts)))
    (out / "anims").mkdir(parents=True)
    with open(out / "reference.smd", "w") as f:
        smd.write(ref, f)
    lines = []
    for s in m.sequences:
        if s.anim < 0 or s.flags & STUDIO_DELTA or not s.activity:
            continue
        with open(out / "anims" / f"{s.label}.smd", "w") as f:
            smd.write(smd.Smd(nodes, [m.pose(s.label, k) for k in range(s.frames)]), f)
        lines.append(f'$sequence "{s.label}" "anims/{s.label}.smd" fps {s.fps:g} activity "{s.activity}" 1')
    (out / "stand_in.qc").write_text("\n".join(lines) + "\n")


@unittest.skipUnless(all(p.exists() for p in VPKS), "TF2's and GMod's VPKs are not here (MDL_RIG_VPKS)")
class CompiledTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lib = Library(VPKS)
        cls.tmp = tempfile.TemporaryDirectory()
        cls.src = Path(cls.tmp.name) / "c_smg1"
        sources_of(cls.lib, cls.lib.model(STAND_IN), cls.src)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def rows(self, src=None):
        return {check: (passed, detail) for check, passed, detail in vm_build.check_compiled(self.lib, src or self.src, STAND_IN)}

    def test_a_model_studiomdl_compiled_passes_against_its_own_sources(self):
        failed = {k: d for k, (p, d) in self.rows().items() if not p}
        self.assertEqual(failed, {})

    def test_a_frame_moved_in_the_sources_fails(self):
        moved = Path(self.tmp.name) / "moved"
        os.system(f"cp -r '{self.src}' '{moved}'")
        anim = smd.read((moved / "anims" / "reload.smd").read_text())
        p, q = anim.frames[10][5]
        anim.frames[10][5] = ((p[0] + 0.5, p[1], p[2]), q)
        with open(moved / "anims" / "reload.smd", "w") as f:
            smd.write(anim, f)
        passed, detail = self.rows(moved)["frames as the sources (position)"]
        self.assertFalse(passed, detail)
        self.assertIn("reload@10", detail)

    def test_an_activity_other_than_the_sources_fails(self):
        swapped = Path(self.tmp.name) / "swapped"
        os.system(f"cp -r '{self.src}' '{swapped}'")
        qc = swapped / "stand_in.qc"
        qc.write_text(qc.read_text().replace('"ACT_VM_RELOAD"', '"ACT_VM_DRAW"'))
        self.assertFalse(self.rows(swapped)["each sequence with its activity"][0])

    def test_a_folder_is_read_before_the_vpks(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / STAND_IN
            path.parent.mkdir(parents=True)
            path.write_bytes(b"loose")
            self.assertEqual(Library(VPKS, [Path(d)]).read(STAND_IN), b"loose")


if __name__ == "__main__":
    unittest.main()
