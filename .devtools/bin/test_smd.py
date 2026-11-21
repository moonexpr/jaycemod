import io
import math
import random
import unittest

from mdl_rig import axis_angle, euler_quat, qconj, qmul
from smd import Smd, SmdError, Vertex, quat_euler, read, write


def apart(a, b):
    return axis_angle(qmul(qconj(a), b))[1]


def random_quat(rng):
    x, y, z, w = (rng.gauss(0, 1) for _ in range(4))
    n = math.sqrt(x * x + y * y + z * z + w * w)
    return (x / n, y / n, z / n, w / n)


class EulerTest(unittest.TestCase):
    def test_quat_euler_inverts_angle_quaternion(self):
        rng = random.Random(7)
        for _ in range(2000):
            q = random_quat(rng)
            self.assertLess(apart(q, euler_quat(*quat_euler(q))), 1e-4)  # degrees; acos near 1 is noisy

    def test_gimbal_lock_still_round_trips(self):
        for pitch in (math.pi / 2, -math.pi / 2):
            q = euler_quat(0.3, pitch, -1.1)
            self.assertLess(apart(q, euler_quat(*quat_euler(q))), 1e-4)


class FileTest(unittest.TestCase):
    def test_a_skeleton_its_frames_and_triangles_come_back(self):
        rng = random.Random(11)
        nodes = [("root", -1), ("ValveBiped.Bip01_R_Hand", 0), ("weapon_bone", 1)]
        frames = [[((rng.uniform(-20, 20), rng.uniform(-20, 20), rng.uniform(-20, 20)), random_quat(rng)) for _ in nodes]
                  for _ in range(4)]
        v = [Vertex(1, (1.0, 2.0, 3.0), (0.0, 0.0, 1.0), (0.25, 0.75), [(1, 0.6), (2, 0.4)]) for _ in range(3)]
        out = io.StringIO()
        write(Smd(nodes, frames, [("models/weapons/c_items/c_scattergun", tuple(v))]), out)
        back = read(out.getvalue())
        self.assertEqual(back.nodes, nodes)
        self.assertEqual(len(back.frames), 4)
        for fa, fb in zip(frames, back.frames):
            for (pa, qa), (pb, qb) in zip(fa, fb):
                self.assertLess(math.dist(pa, pb), 1e-5)
                self.assertLess(apart(qa, qb), 1e-3)
        self.assertEqual(back.triangles[0][0], "models/weapons/c_items/c_scattergun")
        self.assertEqual(back.triangles[0][1][0].links, [(1, 0.6), (2, 0.4)])

    def test_a_frame_missing_a_bone_is_refused(self):
        with self.assertRaises(SmdError):
            write(Smd([("a", -1), ("b", 0)], [[((0, 0, 0), (0, 0, 0, 1))]]), io.StringIO())


if __name__ == "__main__":
    unittest.main()
