#!/usr/bin/env python3
"""Tests for ns_bench_run.py's stall finding."""
import unittest

import ns_bench_run as R


def sample(at, speed, waypoint=3, waypoints=9, done=False, stuck=False, ground=True):
    return {"at": at, "speed": speed, "pos": [0, 0, at], "waypoint": waypoint, "waypoints": waypoints,
            "done": done, "steer": [1, 2, 3], "stuck": stuck, "ground": ground}


class StallsTest(unittest.TestCase):
    def test_moving_is_no_stall(self):
        self.assertEqual(R.stalls([sample(i * 0.5, 200) for i in range(10)]), [])

    def test_a_short_pause_is_no_stall(self):
        samples = [sample(0, 200), sample(0.5, 0), sample(1, 0), sample(1.5, 200)]
        self.assertEqual(R.stalls(samples), [])

    def test_a_long_pause_is_a_stall_with_its_route_state(self):
        samples = [sample(0, 200)] + [sample(0.5 * i, 0, stuck=i == 3) for i in range(1, 6)] + [sample(3, 200)]
        found = R.stalls(samples)
        self.assertEqual(len(found), 1)
        self.assertEqual((found[0]["from"], found[0]["to"]), (0.5, 2.5))
        self.assertEqual(found[0]["route"], "3/9")
        self.assertTrue(found[0]["stuck"])
        self.assertFalse(found[0]["airborne"])

    def test_a_stall_at_the_end_counts(self):
        found = R.stalls([sample(0.5 * i, 0, waypoints=None) for i in range(5)])
        self.assertEqual(found[0]["route"], "none")

    def test_a_finished_route_says_so(self):
        found = R.stalls([sample(0.5 * i, 5, done=True) for i in range(5)])
        self.assertEqual(found[0]["route"], "done")


if __name__ == "__main__":
    unittest.main()
