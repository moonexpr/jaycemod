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


def Spot_(area, sees, x=None, y=1.0):
    """A hiding spot in area, at (x, y) * CELL (x the area's own by default), seeing the areas in sees
    standing up from it."""
    return Spot((area * CELL if x is None else x * CELL, y * CELL, 0.0), area, frozenset(sees))


class EntrancesTest(unittest.TestCase):
    def test_an_entrance_is_where_an_enemy_path_steps_into_a_room_its_approach_the_walk_before(self):
        graph = Corridor()
        edges, _ = Fields(graph)
        entrances = ambush.Entrances([(BLU, tuple(range(1, 10)))], incursion.Crossings(edges), REGION,
                                     approach=2.5 * CELL)
        self.assertEqual(len(entrances), 1)
        door = entrances[0]
        self.assertEqual((door.team, door.outside, door.inside, door.room), (BLU, 5, 6, ("room", 1)))
        self.assertEqual(door.approach, ((3.5 * CELL, 0.0, 0.0), (4.5 * CELL, 0.0, 0.0)),
                         "the crossings walked through up to the doorway, within the approach, the farthest first")
        self.assertEqual((door.via, door.width, door.heading), ((5.5 * CELL, 0.0, 0.0), CELL, (1.0, 0.0)))
        self.assertEqual(door.paths, 1)

    def test_the_paths_through_one_entrance_are_counted_once_an_entrance(self):
        graph = Corridor()
        edges, _ = Fields(graph)
        path = (BLU, tuple(range(1, 10)))
        entrances = ambush.Entrances([path, path], incursion.Crossings(edges), REGION, approach=CELL)
        self.assertEqual([e.paths for e in entrances], [2])

    def test_a_room_stepped_into_straight_from_the_spawn_has_no_approach_and_is_no_entrance(self):
        graph = Corridor()
        edges, _ = Fields(graph)
        self.assertEqual(ambush.Entrances([(BLU, (5, 6))], incursion.Crossings(edges), REGION, approach=CELL), [])

    def test_stepping_into_a_corridor_is_no_entrance(self):
        graph = Corridor()
        edges, _ = Fields(graph)
        region = {i: ("passage", 1 if i < 6 else 2) for i in range(1, 10)}
        self.assertEqual(ambush.Entrances([(BLU, tuple(range(1, 10)))], incursion.Crossings(edges), region,
                                          approach=CELL), [])


class AmbushesTest(unittest.TestCase):
    """The doorway is the step 5-6, at x = 5.5 cells, a cell wide (y -0.5 to 0.5); BLU walks up the corridor
    along y = 0. Through it the approach sees a wedge of the room straight ahead; beside the door, behind
    the wall the doorway is cut in, it sees nothing."""

    def setUp(self):
        graph = Corridor()
        edges, self.fields = Fields(graph)
        self.door = ambush.Entrances([(BLU, tuple(range(1, 10)))], incursion.Crossings(edges), REGION,
                                     approach=2.5 * CELL)[0]

    def marks(self, spots):
        return ambush.Ambushes([self.door], spots, self.fields, REGION, near=0.5 * CELL, far=3 * CELL)

    def test_a_spot_beside_the_door_out_of_the_approachs_sight_through_it_is_an_ambush(self):
        found = self.marks([Spot_(6, {6}, x=6, y=1.5)])
        self.assertEqual([(m.team, m.spot.area) for m in found], [(RED, 6)])

    def test_a_spot_ahead_of_the_door_the_squad_sees_through_it(self):
        self.assertEqual(self.marks([Spot_(7, {6}, x=7, y=0.6)]), [], "in the wedge seen through the doorway")

    def test_far_up_the_approach_the_wedge_is_narrow_near_the_door_wide_and_the_spot_must_be_out_of_both(self):
        self.assertEqual(self.marks([Spot_(6, {6}, x=6.5, y=0.9)]), [], "seen from the doorway's mouth")

    def test_a_spot_that_does_not_see_inside_the_entrance_covers_nothing(self):
        self.assertEqual(self.marks([Spot_(6, {7, 8}, x=6, y=1.5)]), [], "no line of fire on the doorway")

    def test_a_spot_outside_the_room_is_none(self):
        self.assertEqual(self.marks([Spot_(4, {6}, x=4.5, y=1.5)]), [], "on the squad's side of the door")

    def test_a_spot_out_of_range_of_the_entrance_is_none(self):
        self.assertEqual(self.marks([Spot_(6, {6}, x=5.6, y=0.3)]), [], "too near the doorway")
        self.assertEqual(self.marks([Spot_(9, {6}, x=9, y=3)]), [], "too far from it")

    def test_the_defenders_must_reach_the_spot_before_the_enemy_reaches_the_entrance(self):
        region = {**REGION, 2: ("room", 1)}   # a far corner of the room, by BLU's spawn
        found = ambush.Ambushes([self.door], [Spot_(2, {6}, x=6, y=1.5)], self.fields, region, near=0.5 * CELL,
                                far=3 * CELL)
        self.assertEqual(found, [], "BLU is there first; RED could never set it up")


if __name__ == "__main__":
    unittest.main()
