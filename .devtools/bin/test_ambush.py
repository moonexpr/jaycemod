import unittest

import ambush
import incursion
from ambush import Spot
from test_incursion import Area, Middles

RED, BLU = "RED", "BLU"
CELL = 100.0


def Corridor():
    """BLU's spawn 1, a corridor 2-3-4 (the approach), a doorway at 5 into a hall 6-7-8 (room 1), RED's
    spawn 9 behind it. Areas 1-5 are corridor, 6-9 the room."""
    graph = {i: Area(i, links=[j for j in (i - 1, i + 1) if 1 <= j <= 9]) for i in range(1, 10)}
    return Middles(graph)


REGION = {**{i: ("passage", 1) for i in range(1, 6)}, **{i: ("room", 1) for i in range(6, 10)}}


def Fields(graph):
    edges = incursion.Edges(graph)
    return edges, {BLU: incursion.Incursion(edges, [1]), RED: incursion.Incursion(edges, [9])}


def Spot_(area, sees, x=None, y=1.0, seen=None):
    """A hiding spot in area, at (x, y) * CELL (x the area's own by default), seeing the areas in sees
    standing up from it, and seen crouched from the areas in seen (the same by default)."""
    return Spot((area * CELL if x is None else x * CELL, y * CELL, 0.0), area, frozenset(sees),
                frozenset(sees if seen is None else seen))


class EntrancesTest(unittest.TestCase):
    def test_an_entrance_is_where_an_enemy_path_steps_into_a_room_its_approach_the_walk_before(self):
        graph = Corridor()
        edges, _ = Fields(graph)
        entrances = ambush.Entrances([(BLU, tuple(range(1, 10)))], incursion.Crossings(edges), REGION,
                                     approach=2.5 * CELL)
        self.assertEqual(len(entrances), 1)
        door = entrances[0]
        self.assertEqual((door.team, door.outside, door.inside, door.room), (BLU, 5, 6, ("room", 1)))
        self.assertEqual(door.approach, (3, 4, 5), "the walk up to the doorway within the approach")
        self.assertEqual(door.paths, 1)

    def test_the_paths_through_one_entrance_are_counted_once_an_entrance(self):
        graph = Corridor()
        edges, _ = Fields(graph)
        path = (BLU, tuple(range(1, 10)))
        entrances = ambush.Entrances([path, path], incursion.Crossings(edges), REGION, approach=CELL)
        self.assertEqual([e.paths for e in entrances], [2])

    def test_stepping_into_a_corridor_is_no_entrance(self):
        graph = Corridor()
        edges, _ = Fields(graph)
        region = {i: ("passage", 1 if i < 6 else 2) for i in range(1, 10)}
        self.assertEqual(ambush.Entrances([(BLU, tuple(range(1, 10)))], incursion.Crossings(edges), region,
                                          approach=CELL), [])


class AmbushesTest(unittest.TestCase):
    def setUp(self):
        graph = Corridor()
        edges, self.fields = Fields(graph)
        self.door = ambush.Entrances([(BLU, tuple(range(1, 10)))], incursion.Crossings(edges), REGION,
                                     approach=2.5 * CELL)[0]

    def marks(self, spots):
        return ambush.Ambushes([self.door], spots, self.fields, near=0.5 * CELL, far=5 * CELL)

    def test_a_spot_seeing_inside_the_entrance_and_none_of_the_approach_is_an_ambush_for_the_defenders(self):
        found = self.marks([Spot_(7, {6, 7, 8})])
        self.assertEqual([(m.team, m.spot.area) for m in found], [(RED, 7)])

    def test_a_spot_the_approach_sees_gives_itself_away(self):
        self.assertEqual(self.marks([Spot_(7, {4, 6, 7})]), [], "seen from the corridor before the door")

    def test_a_spot_the_approach_would_see_a_player_standing_at_but_not_crouched_is_an_ambush(self):
        found = self.marks([Spot_(7, {4, 6, 7}, seen={6, 7})])
        self.assertEqual([m.spot.area for m in found], [7], "behind a low wall: hidden while crouched")

    def test_a_spot_that_does_not_see_inside_the_entrance_covers_nothing(self):
        self.assertEqual(self.marks([Spot_(8, {8, 9})]), [])

    def test_a_spot_on_the_enemys_own_path_is_no_hiding_place(self):
        self.assertEqual(self.marks([Spot_(7, {6, 7}, y=0)]), [], "standing on the walk itself")

    def test_a_spot_out_of_range_of_the_entrance_is_none(self):
        self.assertEqual(self.marks([Spot_(7, {6}, x=5.4, y=0.3)]), [], "too near the doorway")
        self.assertEqual(self.marks([Spot_(9, {6}, x=12)]), [], "too far from it")

    def test_the_defenders_must_reach_the_spot_before_the_enemy_reaches_the_entrance(self):
        found = self.marks([Spot_(3, {6}, y=1)])   # off the corridor beside 3: BLU's side of the door
        self.assertEqual(found, [], "BLU is there first; RED could never set it up")


if __name__ == "__main__":
    unittest.main()
