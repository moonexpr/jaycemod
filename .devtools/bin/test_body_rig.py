import math
import os
import unittest
from pathlib import Path

from mdl_rig import DEFAULT_VPKS, Library, Sampler, axis_angle, qconj, qmul

VPKS = [Path(p) for p in os.environ.get("MDL_RIG_VPKS", "").split(os.pathsep) if p] or list(DEFAULT_VPKS)
REPO = Path(__file__).resolve().parents[2]
SCATTERGUN = REPO / "addons/tf_weapons/lua/weapons/tf_weapon_scattergun.lua"


def apart(a, b):
    return (max(axis_angle(qmul(qconj(p[1]), q[1]))[1] for p, q in zip(a, b)),
            max(math.dist(p[0], q[0]) for p, q in zip(a, b)))


@unittest.skipUnless(all(p.exists() for p in VPKS), "TF2's and GMod's VPKs are not here (MDL_RIG_VPKS)")
class SamplerTest(unittest.TestCase):
    """The engine's sampling of a sequence, as body_rig and rig_gate --third read TF2's player animations."""

    @classmethod
    def setUpClass(cls):
        cls.lib = Library(VPKS)
        cls.anims = cls.lib.model("models/player/scout_animations.mdl")
        cls.sampler = Sampler(cls.anims)

    def test_a_plain_sequence_at_a_whole_frame_is_that_frame(self):
        rot, pos = apart(self.sampler.sample("AttackStand_PRIMARY", 10 / 20, {}), self.anims.pose("AttackStand_PRIMARY", 10))
        self.assertLess(rot, 1e-3)
        self.assertLess(pos, 1e-6)

    def test_a_grid_runs_the_way_its_pose_parameters_say(self):
        forward = self.anims.world(self.sampler.sample("run_PRIMARY", 0.3, {"move_x": 1.0, "move_y": 0.0}))
        backward = self.anims.world(self.sampler.sample("run_PRIMARY", 0.3, {"move_x": -1.0, "move_y": 0.0}))
        rot, _ = apart(forward, backward)
        self.assertGreater(rot, 30, "running forward and backward are different poses")

    def test_the_aim_layer_raises_the_weapon_with_body_pitch(self):
        w = self.anims.index["weapon_bone"]
        low = self.anims.world(self.sampler.sample("stand_PRIMARY", 0, {"body_pitch": -45.0}))[w][0][2]
        high = self.anims.world(self.sampler.sample("stand_PRIMARY", 0, {"body_pitch": 90.0}))[w][0][2]
        self.assertGreater(high - low, 10)

    def test_the_weapon_is_fixed_in_the_right_hand_in_every_base_pose(self):
        import body_rig
        tf = self.lib.model("models/player/scout.mdl")
        ref = None
        for base in ("stand_PRIMARY", "crouch_PRIMARY", "run_PRIMARY", "crouch_walk_PRIMARY"):
            for f in (0, 10, 20):
                held = body_rig.grip(body_rig.tf_world(tf, body_rig.layered(self.anims, base, f)), tf)
                ref = ref or held
                self.assertLess(math.dist(held[0], ref[0]), 1e-3, f"{base}@{f}")


if __name__ == "__main__":
    unittest.main()
