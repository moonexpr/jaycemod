import unittest

import classes
import incursion
from classes import Classed
from incursion import Route
from test_incursion import Area, Middles

RED, BLU = "RED", "BLU"
CELL = 100.0
R, P = "room", "passage"


def Line(n=13):
    """Areas 0..n-1 in a row, a cell apart, each a cell of floor, linked both ways to the next."""
    graph = {i: Area(i, links=[j for j in (i - 1, i + 1) if 0 <= j < n]) for i in range(n)}
    for area in graph.values():
        area["floor"] = CELL * CELL
    return Middles(graph)


class HighwaysTest(unittest.TestCase):
    REGION = {0: (R, 1), 1: (R, 1), 2: (R, 2), 3: (R, 2), 4: (R, 3), 5: (R, 3), 6: (R, 4), 7: (R, 4), 8: (R, 5)}
    SPAWNS = {RED: [0, 6], BLU: [5]}

    def routes(self):
        """RED spawns in room 1 (area 0), BLU in room 3 (area 5); BLU's second highway goes to another of RED's
        spawn areas, by way of room 3 alone."""
        return [Route(RED, (0, 1, 2, 3, 4, 5), 500, False), Route(BLU, (5, 4, 3, 2, 1, 0), 500, False),
                Route(BLU, (5, 4), 100, False)]

    def test_a_room_half_or_more_of_each_teams_highways_cross_is_a_highway(self):
        self.assertEqual(classes.Highways(self.routes(), self.REGION, [], {}, self.SPAWNS), {(R, 2)})

    def test_a_room_one_team_crosses_from_its_own_spawn_is_none(self):
        self.assertNotIn((R, 1), classes.Highways(self.routes(), self.REGION, [], {}, self.SPAWNS), "RED's exit alone")

    def test_a_room_holding_any_of_a_teams_spawns_is_none_though_no_route_starts_there(self):
        # both teams' only highways cross room 4, where one of RED's spawns stands (area 6)
        routes = [Route(RED, (0, 7, 6, 2, 5), 400, False), Route(BLU, (5, 2, 6, 7, 0), 400, False)]
        found = classes.Highways(routes, self.REGION, [], {}, self.SPAWNS)
        self.assertIn((R, 2), found, "the rule holds elsewhere")
        self.assertNotIn((R, 4), found)

    def test_a_room_holding_an_objective_is_a_highway(self):
        self.assertIn((R, 5), classes.Highways(self.routes(), self.REGION, [8], {}, self.SPAWNS))

    def test_an_objective_in_a_spawn_room_leaves_it_its_teams(self):
        self.assertNotIn((R, 1), classes.Highways(self.routes(), self.REGION, [1], {}, self.SPAWNS),
                         "cs_office's hostages in RED's spawn, its rescue zone in BLU's")

    def test_restricted_ground_is_never_a_highway(self):
        self.assertNotIn((R, 2), classes.Highways(self.routes(), self.REGION, [], {(R, 2): RED}, self.SPAWNS))


class SpaceTreeTest(unittest.TestCase):
    def test_each_space_hangs_from_the_space_its_walk_enters_it_from_corridors_too(self):
        graph = Line(7)
        region = {0: (R, 1), 1: (R, 1), 2: (P, 1), 3: (P, 1), 4: (R, 2), 5: (R, 3), 6: (R, 3)}
        tree = incursion.Grow(incursion.Incursion(incursion.Edges(graph), [0]), RED, graph)
        spaces = classes.SpaceTree(tree, region)
        self.assertEqual(spaces.roots, ((R, 1),))
        self.assertEqual(spaces.parent, {(P, 1): (R, 1), (R, 2): (P, 1), (R, 3): (R, 2)})
        self.assertEqual(spaces.entry[(R, 2)], 4, "the area the walk first reaches it by")
        self.assertEqual(spaces.children[(R, 1)], ((P, 1),))


class GradientTest(unittest.TestCase):
    """RED's building is areas 0-1 and BLU's 11-12; the highway is room 6 (area 6); the rooms between are
    single areas, rooms 2-5 and 7-10; area 20 is a shed far off RED's side."""

    def classify(self, owner=None, outdoor=(), extra=None):
        graph = Line()
        if extra:
            graph.update(extra(graph))
            graph = Middles(graph)
        region = {i: (R, i) for i in graph}
        region.update({0: (R, 0), 1: (R, 0), 11: (R, 11), 12: (R, 11)})
        edges = incursion.Edges(graph)
        fields = {RED: incursion.Incursion(edges, [0]), BLU: incursion.Incursion(edges, [12])}
        owner = owner or {(R, 0): RED, (R, 11): BLU}
        return classes.Classify(edges, region, fields, restricted={}, highways={(R, 6)},
                                owner=owner, outdoor={(R, i) for i in outdoor}, margin=CELL / 2, far=4 * CELL)

    def test_a_teams_building_is_its_stronghold(self):
        found = self.classify()
        self.assertEqual(found[(R, 0)], Classed(classes.STRONGHOLD, RED, 1.0))

    def test_on_a_teams_side_nearer_its_building_than_the_highway_is_its_stronghold(self):
        found = self.classify()
        self.assertEqual((found[(R, 2)].cls, found[(R, 2)].team), (classes.STRONGHOLD, RED))
        self.assertGreater(found[(R, 2)].gradient, 0.5)

    def test_on_a_teams_side_nearer_the_highway_is_commons(self):
        found = self.classify()
        self.assertEqual((found[(R, 5)].cls, found[(R, 5)].team), (classes.COMMONS, None))
        self.assertLess(found[(R, 5)].gradient, 0.5)
        self.assertEqual((found[(R, 9)].cls, found[(R, 9)].team), (classes.STRONGHOLD, BLU), "BLU's side")

    def test_a_highway_inside_a_teams_building_counts_as_highway_not_building(self):
        # RED's building reaches out to the highway (rooms 0 and 6 both RED's): room 5, beside the highway,
        # is measured from RED's spawn room, not from the highway as building
        found = self.classify(owner={(R, 0): RED, (R, 6): RED, (R, 11): BLU})
        self.assertLess(found[(R, 5)].gradient, 0.5)
        self.assertEqual(found[(R, 6)].cls, classes.HIGHWAY)

    def test_the_highway_keeps_its_class(self):
        self.assertEqual(self.classify()[(R, 6)], Classed(classes.HIGHWAY, None, 0.0))

    def test_far_from_both_buildings_and_the_highway_is_unoccupied_indoors_and_wilds_outdoors(self):
        def shed(graph):
            graph[2]["links"].append({"to": 20})
            return {20: Area(2, 6, links=[2])}   # 600 off the line: past far of both
        found = self.classify(extra=shed)
        self.assertEqual(found[(R, 20)].cls, classes.UNOCCUPIED)
        self.assertEqual(self.classify(extra=shed, outdoor=[20])[(R, 20)].cls, classes.WILDS)


class JunctionsTest(unittest.TestCase):
    def test_a_fork_in_a_corridor_carves_a_room_of_the_floor_within_reach(self):
        graph = Line(9)
        region = {i: (P, 1) for i in graph}
        found = classes.Junctions([4], graph, incursion.Edges(graph), region, reach=1.5 * CELL,
                                  floor=3 * CELL * CELL)
        self.assertEqual([j.areas for j in found], [(3, 4, 5)])
        self.assertEqual(found[0].space, (P, 1), "carved out of the corridor")

    def test_too_little_floor_within_reach_carves_nothing(self):
        graph = Line(9)
        region = {i: (P, 1) for i in graph}
        self.assertEqual(classes.Junctions([4], graph, incursion.Edges(graph), region, reach=1.5 * CELL,
                                           floor=4 * CELL * CELL), [])

    def test_a_fork_in_any_room_carves_a_junction_whatever_its_class(self):
        graph = Line(9)
        region = {i: (R, 1) for i in graph}
        found = classes.Junctions([4], graph, incursion.Edges(graph), region, reach=CELL, floor=CELL)
        self.assertEqual([(j.space, j.areas) for j in found], [((R, 1), (3, 4, 5))], "a stronghold's too")

    def test_two_forks_within_one_junction_carve_it_once(self):
        graph = Line(9)
        region = {i: (P, 1) for i in graph}
        found = classes.Junctions([4, 5], graph, incursion.Edges(graph), region, reach=1.5 * CELL,
                                  floor=3 * CELL * CELL)
        self.assertEqual([j.areas for j in found], [(3, 4, 5)])


if __name__ == "__main__":
    unittest.main()
