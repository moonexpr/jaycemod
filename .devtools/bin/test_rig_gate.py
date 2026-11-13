import math
import os
import tempfile
import unittest
from pathlib import Path

import rig_gate
from mdl_rig import DEFAULT_VPKS, Library, RigError, qmul

REPO = Path(__file__).resolve().parents[2]
SCATTERGUN = REPO / "addons/tf_weapons/lua/weapons/tf_weapon_scattergun.lua"
# TF2's and GMod's VPKs: the operator's installs, or MDL_RIG_VPKS (paths split by os.pathsep)
VPKS = [Path(p) for p in os.environ.get("MDL_RIG_VPKS", "").split(os.pathsep) if p] or list(DEFAULT_VPKS)


class SwepTest(unittest.TestCase):
    def test_the_arms_and_activities_are_read_from_the_weapon_file(self):
        model, animations = rig_gate.swep_animations(SCATTERGUN)
        self.assertEqual(model, "models/weapons/c_models/c_scout_arms.mdl")
        self.assertEqual(animations["reload"], "ACT_PRIMARY_VM_RELOAD")
        self.assertEqual(len(animations), 6)

    def test_a_file_naming_neither_is_refused(self):
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
            f.write('SWEP.PrintName = "nothing"\n')
        try:
            with self.assertRaises(RigError):
                rig_gate.swep_animations(Path(f.name))
        finally:
            os.unlink(f.name)


@unittest.skipUnless(all(p.exists() for p in VPKS), "TF2's and GMod's VPKs are not here (MDL_RIG_VPKS)")
class GateTest(unittest.TestCase):
    """The gate on the real models: it passes the shipped retarget and fails a broken one."""

    @classmethod
    def setUpClass(cls):
        cls.lib = Library(VPKS)

    def setUp(self):
        self.real = rig_gate.solve

    def tearDown(self):
        rig_gate.solve = self.real

    def test_the_scattergun_passes(self):
        self.assertTrue(rig_gate.gate(self.lib, SCATTERGUN, rig_gate.HANDS))

    def test_a_finger_splayed_25_degrees_fails_the_mesh(self):
        half = math.radians(25) / 2
        turn = (0.0, math.sin(half), 0.0, math.cos(half))

        def splayed(arms, w, hands):
            out = self.real(arms, w, hands)
            for name in ("Finger1", "Finger11", "Finger12"):
                j = hands.index["ValveBiped.Bip01_R_" + name]
                out[j] = (out[j][0], qmul(out[j][1], turn))
            return out

        rig_gate.solve = splayed
        self.assertFalse(rig_gate.gate(self.lib, SCATTERGUN, rig_gate.HANDS))

    def test_a_hand_moved_off_its_forearm_fails_the_lengths(self):
        def moved(arms, w, hands):
            out = self.real(arms, w, hands)
            j = hands.index["ValveBiped.Bip01_R_Hand"]
            (x, y, z), q = out[j]
            out[j] = ((x + 0.5, y, z), q)
            return out

        rig_gate.solve = moved
        self.assertFalse(rig_gate.gate(self.lib, SCATTERGUN, rig_gate.HANDS))


if __name__ == "__main__":
    unittest.main()
