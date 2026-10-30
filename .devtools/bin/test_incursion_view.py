import unittest

from incursion_view import Bezier, Pieces


class BezierTest(unittest.TestCase):
    def test_the_curve_runs_from_its_start_to_its_end(self):
        points = Bezier((0, 0), (5, 10), (10, 0), 8)
        self.assertEqual(points[0], (0, 0))
        self.assertEqual(points[-1], (10, 0))
        self.assertEqual(len(points), 9)

    def test_halfway_it_is_pulled_toward_the_control_point_halfway(self):
        points = Bezier((0, 0), (5, 10), (10, 0), 2)
        self.assertEqual(points[1], (5, 5), "a quarter of each end and half the control")


class PiecesTest(unittest.TestCase):
    def test_a_route_is_a_piece_in_each_area_from_the_edge_in_to_the_edge_out(self):
        self.assertEqual(Pieces((1, 2, 3)), [(None, 1, 2), (1, 2, 3), (2, 3, None)])

    def test_a_route_of_one_area_has_no_piece(self):
        self.assertEqual(Pieces((1,)), [])


if __name__ == "__main__":
    unittest.main()
