import unittest

from aiwar_ab_bench import Leg


class LegParse(unittest.TestCase):
    def test_an_implementation_alone_keeps_npc_soldiers(self):
        self.assertEqual(Leg.parse("native"), Leg("native", "npc"))

    def test_an_implementation_and_an_actor(self):
        self.assertEqual(Leg.parse("lua:bot"), Leg("lua", "bot"))

    def test_the_label_names_both(self):
        self.assertEqual(Leg.parse("native:bot").label, "native:bot")

    def test_an_unknown_implementation_is_refused(self):
        with self.assertRaises(ValueError):
            Leg.parse("rust:bot")

    def test_an_unknown_actor_is_refused(self):
        with self.assertRaises(ValueError):
            Leg.parse("native:drgbase")

    def test_more_than_two_parts_is_refused(self):
        with self.assertRaises(ValueError):
            Leg.parse("native:bot:npc")

    def test_npc_soldiers_set_only_the_actor(self):
        self.assertEqual(Leg.parse("native:npc").convars, {"ns_soldiers_actor": "npc"})

    def test_bots_join_with_no_human_on_the_server(self):
        self.assertEqual(Leg.parse("lua:bot").convars,
                         {"ns_soldiers_actor": "bot", "tf_bot_join_after_player": "0"})

    def test_the_soldier_count_reads_what_the_actor_makes(self):
        self.assertIn("IsNextBot", Leg.parse("native:npc").soldiers_lua)
        self.assertIn("player.GetBots", Leg.parse("native:bot").soldiers_lua)


if __name__ == "__main__":
    unittest.main()
