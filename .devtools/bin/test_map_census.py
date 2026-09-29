import unittest

from bsp_entities import Entity
from map_census import Census, Provided, entity_classes


def ent(*pairs):
    return Entity(tuple(pairs))


class EntityClasses(unittest.TestCase):
    def test_lowercases_and_dedupes(self):
        ents = [ent(("classname", "TF_Logic_Koth")), ent(("classname", "tf_logic_koth"))]
        self.assertEqual(entity_classes(ents), {"tf_logic_koth"})


class Classify(unittest.TestCase):
    def setUp(self):
        self.provided = Provided(ours={"team_round_timer"}, engine={"trigger_catapult"}, tf2={"tf_logic_koth", "trigger_catapult", "team_round_timer"})

    def test_ours_engine_and_missing(self):
        self.assertEqual(self.provided.status("team_round_timer"), Provided.OURS)
        self.assertEqual(self.provided.status("trigger_catapult"), Provided.ENGINE)
        self.assertEqual(self.provided.status("tf_logic_koth"), Provided.MISSING)

    def test_missing_counts_maps_and_prefixes(self):
        census = Census.of({
            "koth_a": {"tf_logic_koth", "team_round_timer"},
            "koth_b": {"tf_logic_koth"},
            "cp_a": {"trigger_catapult"},
        })
        rows = census.missing(self.provided, prefixes=("koth_", "cp_"))
        self.assertEqual(rows, [("tf_logic_koth", 2, {"koth_": 2, "cp_": 0}, ["koth_a", "koth_b"])])


if __name__ == "__main__":
    unittest.main()
