import math
import unittest

import numpy as np

from rig_view import Camera, Plan, _strip_triangles, matrix, plans


class StripTest(unittest.TestCase):
    def test_a_strip_flips_every_other_triangle_to_keep_its_winding(self):
        self.assertEqual(_strip_triangles([0, 1, 2, 3, 4], 0x02), [(0, 1, 2), (1, 3, 2), (2, 3, 4)])

    def test_a_list_is_read_three_at_a_time(self):
        self.assertEqual(_strip_triangles([0, 1, 2, 3, 4, 5], 0x01), [(0, 1, 2), (3, 4, 5)])


class CameraTest(unittest.TestCase):
    def test_straight_ahead_is_the_middle_and_the_left_is_drawn_left(self):
        cam = Camera((200, 100))
        xy, depth = cam.project(np.array([[10.0, 0.0, 0.0], [10.0, 2.0, 0.0], [10.0, 0.0, 2.0]]))
        self.assertEqual(tuple(xy[0]), (100.0, 50.0))
        self.assertLess(xy[1, 0], 100.0, "+y is the eye's left")
        self.assertLess(xy[2, 1], 50.0, "+z is up, drawn higher")
        self.assertEqual(depth[0], 10.0)

    def test_the_vertical_field_is_the_4_3_horizontal_one(self):
        cam = Camera((160, 90))
        edge = math.tan(math.radians(27)) * 3 / 4 * 10
        xy, _ = cam.project(np.array([[10.0, 0.0, edge]]))
        self.assertAlmostEqual(xy[0, 1], 0.0, places=6)

    def test_fitting_keeps_the_eye_and_fills_the_picture(self):
        points = np.array([[20.0, -1.0, -1.0], [20.0, 1.0, 1.0], [1.0, 0.0, 0.0]])
        cam = Camera((200, 200))
        cam.fit(points, margin=0.0)
        xy, _ = cam.project(points[:2])
        self.assertAlmostEqual(min(xy[:, 0].min(), xy[:, 1].min()), 0.0, places=6)
        self.assertAlmostEqual(max(xy[:, 0].max(), xy[:, 1].max()), 200.0, places=6)
        self.assertEqual(cam.NEAR, 10.0, "what is by the eye is left out")


class PlanTest(unittest.TestCase):
    def test_the_players_right_is_drawn_right_in_every_plan_but_the_side(self):
        right = np.array([[0.0, -5.0, 0.0], [0.0, 5.0, 0.0]])  # the player's right, then left
        for plan in plans((100, 100)):
            plan.fit(np.array([[-5.0, -5.0, -5.0], [5.0, 5.0, 5.0]]))
            xy, _ = plan.project(right)
            if "from the right" in plan.name:
                self.assertAlmostEqual(xy[0, 0], xy[1, 0], msg="seen from the side, right and left line up")
            else:
                self.assertGreater(xy[0, 0], xy[1, 0], plan.name)

    def test_forward_is_up_from_above(self):
        plan = Plan((100, 100), (1, -1), (0, 1), (2, 1), "above")
        plan.fit(np.array([[-5.0, -5.0, 0.0], [5.0, 5.0, 0.0]]))
        xy, _ = plan.project(np.array([[5.0, 0.0, 0.0], [-5.0, 0.0, 0.0]]))
        self.assertLess(xy[0, 1], xy[1, 1])


class MatrixTest(unittest.TestCase):
    def test_a_quarter_turn_about_z_takes_forward_to_left(self):
        m = matrix((1.0, 2.0, 3.0), (0.0, 0.0, math.sqrt(0.5), math.sqrt(0.5)))
        np.testing.assert_allclose(m @ [1, 0, 0, 1], [1, 3, 3, 1], atol=1e-9)


if __name__ == "__main__":
    unittest.main()
