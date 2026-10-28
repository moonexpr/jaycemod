"""aiwar_fight_watch.py: the war's counts, read once into Fights."""
import unittest

from aiwar_fight_watch import Fights


class FightsTest(unittest.TestCase):
    def test_the_servers_counts_become_fights(self):
        fights = Fights.parse("nextsoldier", "pl_upward",
                              '{"seconds":180.04,"shots":12,"hits":8,"damage":40.25,"deaths":2,"soldiers":16,"enemies":4,"idle":false}')
        self.assertEqual(fights, Fights("nextsoldier", "pl_upward", 180.0, 12, 8, 40.2, 2, 16, 4, False))

    def test_a_count_missing_is_refused(self):
        with self.assertRaises(KeyError):
            Fights.parse("drgbase", "pl_upward", '{"seconds":1,"shots":1}')


if __name__ == "__main__":
    unittest.main()
