import math
import unittest

from aiwar_bench import Condition, Interval, PassLine, interval_of, schedule


def replication(war_rate=0.2, p99=0.008, worst=0.012, over=0):
    return {"war": {"rate": war_rate, "tail": {"p99": p99, "max": worst}},
            "both": {"rate": war_rate, "tail": {"p99": p99, "max": worst}, "over": over}}


class ConditionParse(unittest.TestCase):
    def test_a_name_and_its_convars(self):
        c = Condition.parse("engine=ns_bots_routes_engine 1, sv_foo 2")
        self.assertEqual(c, Condition("engine", (("ns_bots_routes_engine", "1"), ("sv_foo", "2"))))

    def test_a_name_alone_changes_nothing(self):
        self.assertEqual(Condition.parse("base"), Condition("base", ()))

    def test_a_convar_without_a_value_is_refused(self):
        with self.assertRaises(ValueError):
            Condition.parse("engine=ns_bots_routes_engine")

    def test_a_name_must_be_a_word(self):
        with self.assertRaises(ValueError):
            Condition.parse("two words=x 1")


class Schedule(unittest.TestCase):
    def test_conditions_alternate_so_drift_falls_on_each_alike(self):
        a, b = Condition("a", ()), Condition("b", ())
        self.assertEqual([c.name for c in schedule([a, b], 3)], ["a", "b", "b", "a", "a", "b"])

    def test_one_condition_repeats(self):
        a = Condition("a", ())
        self.assertEqual([c.name for c in schedule([a], 2)], ["a", "a"])


class IntervalOf(unittest.TestCase):
    def test_the_mean_and_students_t_half_width(self):
        i = interval_of([1.0, 2.0, 3.0])
        self.assertAlmostEqual(i.mean, 2.0)
        # s = 1, n = 3, t(2) = 4.30
        self.assertAlmostEqual(i.half, 4.30 / math.sqrt(3), places=6)

    def test_one_value_has_no_interval(self):
        i = interval_of([5.0])
        self.assertEqual(i.mean, 5.0)
        self.assertTrue(math.isinf(i.half))

    def test_two_intervals_apart_differ(self):
        self.assertTrue(Interval(1.0, 0.1).apart(Interval(1.5, 0.1)))
        self.assertFalse(Interval(1.0, 0.3).apart(Interval(1.5, 0.3)))


class Pass(unittest.TestCase):
    line = PassLine(p99=0.010, worst=0.015)

    def test_every_replication_under_both_limits_passes(self):
        self.assertEqual(self.line.failures([replication(), replication(p99=0.0099, worst=0.0149)]), [])

    def test_a_p99_at_the_limit_fails(self):
        self.assertEqual(len(self.line.failures([replication(p99=0.010)])), 1)

    def test_a_tick_over_the_tick_fails_even_with_a_low_p99(self):
        failures = self.line.failures([replication(), replication(worst=0.016)])
        self.assertEqual(len(failures), 1)
        self.assertIn("replication 2", failures[0])


if __name__ == "__main__":
    unittest.main()
