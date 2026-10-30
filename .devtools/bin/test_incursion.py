import unittest

import incursion
from incursion import Edges, Field, Route

RED, BLU = "RED", "BLU"
CELL = 100.0


def Area(x, y=0.0, z=0.0, links=()):
    """An area at (x, y) * CELL, linked to the ids in links (one way: give the other side its own)."""
    return {"center": {"x": x * CELL, "y": y * CELL, "z": z}, "links": [{"to": to} for to in links]}


def Middles(graph):
    """Each link's middle halfway between the two centres, as the dump gives it."""
    for area in graph.values():
        for link in area["links"]:
            a, b = area["center"], graph[link["to"]]["center"]
            link["middle"] = {k: (a[k] + b[k]) / 2 for k in "xyz"}
    return graph


def Line(n=5):
    """Areas 1..n in a row, each linked both ways to the next: RED spawns at 1, BLU at n."""
    return Middles({i: Area(i, links=[j for j in (i - 1, i + 1) if 1 <= j <= n]) for i in range(1, n + 1)})


class FieldTest(unittest.TestCase):
    def test_a_teams_incursion_is_its_walk_from_its_spawns(self):
        field = incursion.Incursion(Edges(Line()), [1])
        self.assertEqual(field.distance[1], 0)
        self.assertAlmostEqual(field.distance[5], 4 * CELL)

    def test_the_walk_is_from_the_nearest_of_several_spawns(self):
        self.assertAlmostEqual(incursion.Incursion(Edges(Line()), [1, 4]).distance[5], CELL)

    def test_a_path_runs_from_the_spawn_to_the_area(self):
        field = incursion.Incursion(Edges(Line()), [1])
        self.assertEqual(field.Path(4), (1, 2, 3, 4))
        self.assertIsNone(incursion.Incursion(Edges(Line()), [1]).Path(99), "an area the walk never reached")


class RoutesTest(unittest.TestCase):
    def test_each_team_has_a_route_to_each_enemy_spawn_area(self):
        routes = incursion.Routes(Edges(Line()), {RED: [1], BLU: [5]})
        self.assertEqual(sorted((r.team, r.areas) for r in routes),
                         [(BLU, (5, 4, 3, 2, 1)), (RED, (1, 2, 3, 4, 5))])
        self.assertAlmostEqual(routes[0].length, 4 * CELL)

    def test_a_drop_goes_one_way_so_the_two_teams_routes_differ(self):
        # the line, and a ledge from RED's spawn dropping straight to BLU's: down only
        graph = Line()
        graph[1]["links"].append({"to": 5})
        routes = {r.team: r for r in incursion.Routes(Edges(Middles(graph)), {RED: [1], BLU: [5]})}
        self.assertEqual(routes[RED].areas, (1, 5), "RED drops")
        self.assertEqual(routes[BLU].areas, (5, 4, 3, 2, 1), "BLU walks round: it cannot climb the drop")

    def test_an_enemy_spawn_no_walk_reaches_has_no_route(self):
        graph = Line()
        graph[9] = Area(9, 9)
        routes = incursion.Routes(Edges(Middles(graph)), {RED: [1], BLU: [5, 9]})
        self.assertEqual(sorted(r.areas[-1] for r in routes if r.team == RED), [5])


def Ways(detours):
    """RED's spawn (1) and BLU's (2), CELL * 10 apart, joined straight and by each detour: an area off to
    the side making the way that much longer (a share of the straight way's length)."""
    graph = {1: Area(0, links=[3]), 2: Area(10, links=[3]), 3: Area(5, links=[1, 2])}
    for i, detour in enumerate(detours):
        aid = 10 + i
        side = ((5 * (1 + detour)) ** 2 - 25) ** 0.5   # 2 * hypot(5, side) = 10 * (1 + detour)
        graph[aid] = Area(5, side * (1 if i % 2 == 0 else -1), links=[1, 2])
        graph[1]["links"].append({"to": aid})
        graph[2]["links"].append({"to": aid})
    return Middles(graph)


class AlternativesTest(unittest.TestCase):
    def test_a_second_way_a_little_longer_is_a_route_too(self):
        routes = incursion.Routes(Edges(Ways([0.2])), {RED: [1], BLU: [2]})
        self.assertEqual(sorted(r.areas for r in routes if r.team == RED), [(1, 3, 2), (1, 10, 2)])
        self.assertTrue(all(r.alternative == (r.areas != (1, 3, 2)) for r in routes if r.team == RED),
                        "the shortest is the highway, the other an option")

    def test_a_way_far_longer_than_the_shortest_is_none(self):
        far = incursion.DETOUR + 0.2
        routes = incursion.Routes(Edges(Ways([far])), {RED: [1], BLU: [2]})
        self.assertEqual([r.areas for r in routes if r.team == RED], [(1, 3, 2)])

    def test_no_more_routes_a_pair_than_ALTERNATIVES(self):
        routes = incursion.Routes(Edges(Ways([0.1] * (incursion.ALTERNATIVES + 2))), {RED: [1], BLU: [2]})
        self.assertEqual(len([r for r in routes if r.team == RED]), incursion.ALTERNATIVES)

    def test_a_routes_length_is_its_own_walk_not_the_penalised_one(self):
        routes = incursion.Routes(Edges(Ways([0.2])), {RED: [1], BLU: [2]})
        second = next(r for r in routes if r.team == RED and r.alternative)
        self.assertAlmostEqual(second.length, 10 * CELL * 1.2)


def Floors(graph, floor=1.0):
    for area in graph.values():
        area["floor"] = floor
    return graph


class TreeTest(unittest.TestCase):
    def fork(self):
        """RED's spawn 1, a hall 2, and from it two ways: 3-4 and 5."""
        graph = {1: Area(0, links=[2]), 2: Area(1, links=[1, 3, 5]), 3: Area(2, 1, links=[2, 4]),
                 4: Area(3, 1, links=[3]), 5: Area(2, -1, links=[2])}
        return Floors(Middles(graph))

    def test_the_tree_is_the_walk_each_area_a_child_of_the_area_it_is_reached_from(self):
        graph = self.fork()
        tree = incursion.Grow(incursion.Incursion(Edges(graph), [1]), RED, graph)
        self.assertEqual(tree.roots, (1,))
        self.assertEqual(tree.children[2], (3, 5), "the fork")
        self.assertEqual(tree.children[4], (), "a leaf")
        self.assertEqual(tree.parent[4], 3)

    def test_a_branchs_weight_is_the_floor_reached_through_it(self):
        graph = self.fork()
        tree = incursion.Grow(incursion.Incursion(Edges(graph), [1]), RED, graph)
        self.assertEqual((tree.weight[1], tree.weight[2], tree.weight[3], tree.weight[5]), (5, 4, 2, 1))

    def test_each_spawn_is_a_root_of_its_own_and_areas_go_to_the_nearer(self):
        graph = Floors(Line())
        tree = incursion.Grow(incursion.Incursion(Edges(graph), [1, 5]), RED, graph)
        self.assertEqual(tree.roots, (1, 5))
        self.assertEqual((tree.weight[1], tree.weight[5]), (3, 2), "the middle, tied, to the earlier spawn")

    def test_the_forks_are_where_a_branch_splits_into_ways_each_carrying_a_share(self):
        graph = self.fork()
        tree = incursion.Grow(incursion.Incursion(Edges(graph), [1]), RED, graph)
        self.assertEqual(tree.Forks(share=0.2), [2], "1 of 5 floor down the short way is a fifth: a way")
        self.assertEqual(tree.Forks(share=0.3), [], "below that share, only a twig")


class BreachesTest(unittest.TestCase):
    def tree(self, graph, starts):
        return incursion.Grow(incursion.Incursion(Edges(graph), starts), RED, graph)

    def test_the_fewest_paths_from_the_spawn_covering_the_whole_map_one_a_leaf(self):
        tree = self.tree(TreeTest.fork(None), [1])
        self.assertEqual([b.areas for b in incursion.Breaches(tree, 1.0)], [(1, 2, 3, 4), (1, 2, 5)])

    def test_the_path_covering_the_most_comes_first_and_enough_of_them_to_cover_the_share(self):
        tree = self.tree(TreeTest.fork(None), [1])
        breaches = incursion.Breaches(tree, 0.8)
        self.assertEqual([b.areas for b in breaches], [(1, 2, 3, 4)], "4 of 5 floor")
        self.assertEqual(breaches[0].gain, 4)

    def test_a_later_path_counts_only_the_floor_it_adds(self):
        tree = self.tree(TreeTest.fork(None), [1])
        self.assertEqual([b.gain for b in incursion.Breaches(tree, 1.0)], [4, 1], "1 and 2 already covered")

    def test_ground_within_reach_of_a_path_is_covered_by_it(self):
        tree = self.tree(TreeTest.fork(None), [1])
        near = incursion.Near(Edges(TreeTest.fork(None)), reach=1.5 * CELL)
        breaches = incursion.Breaches(tree, 1.0, near)
        self.assertEqual([b.areas for b in breaches], [(1, 2, 3, 4)], "5 lies within reach of 2: one path does")
        self.assertEqual(breaches[0].gain, 5)

    def test_each_spawn_starts_its_own_paths(self):
        graph = Floors(Line())
        self.assertEqual([b.areas for b in incursion.Breaches(self.tree(graph, [1, 5]), 1.0)], [(1, 2, 3), (5, 4)])


def Window(a, b, graph):
    """A breakable window halfway between areas a and b, as the dump gives it."""
    ca, cb = graph[a]["center"], graph[b]["center"]
    return {"from": a, "to": b, "pos": {k: (ca[k] + cb[k]) / 2 for k in "xyz"}, "breakable": True}


class WindowTest(unittest.TestCase):
    def test_a_window_is_a_way_through_both_ways_costing_the_break(self):
        graph = Line()
        graph[9] = Area(2, 1)   # a room behind glass beside area 2, no link to it
        edges = Edges(Middles(graph), [Window(2, 9, graph)])
        there = next(s for s in edges[2] if s.to == 9)
        self.assertTrue(there.window)
        self.assertAlmostEqual(there.cost, CELL + incursion.WINDOW_COST)
        self.assertTrue(any(s.to == 2 and s.window for s in edges[9]), "and back")

    def test_a_window_no_one_can_break_is_no_way_through(self):
        graph = Line()
        graph[9] = Area(2, 1)
        window = dict(Window(2, 9, graph), breakable=False)   # an areaportal window: seen through only
        self.assertFalse(any(s.to == 9 for s in Edges(Middles(graph), [window])[2]))

    def test_a_window_too_high_to_climb_to_is_only_a_way_down(self):
        graph = Line()
        graph[9] = Area(2, 1, z=3 * incursion.CLIMB)
        edges = Edges(Middles(graph), [Window(2, 9, graph)])
        self.assertFalse(any(s.to == 9 for s in edges[2]), "no climbing up to it")
        self.assertTrue(any(s.to == 2 for s in edges[9]), "jumping out of it down")

    def test_a_route_breaks_through_a_window_where_it_is_the_way_in(self):
        graph = Line()
        graph[9] = Area(5, 1)   # BLU's spawn behind glass beside area 5, no link to it
        edges = Edges(Middles(graph), [Window(5, 9, graph)])
        routes = incursion.Routes(edges, {RED: [1], BLU: [9]})
        self.assertEqual(next(r for r in routes if r.team == RED).areas, (1, 2, 3, 4, 5, 9))

    def test_a_step_carries_where_it_crosses_the_shared_edge_or_the_window(self):
        graph = Line()
        graph[9] = Area(2, 1)
        edges = Edges(Middles(graph), [Window(2, 9, graph)])
        self.assertEqual(next(s for s in edges[1] if s.to == 2).via, (150.0, 0.0, 0.0))
        self.assertEqual(next(s for s in edges[2] if s.to == 9).via, (200.0, 50.0, 0.0))


class TrafficTest(unittest.TestCase):
    def test_traffic_counts_the_routes_through_each_area_by_team(self):
        # BLU spawns at 5 and at 6 beside it; both of RED's routes come through 2-4
        graph = Line()
        graph[6] = Area(5, 1, links=[5])
        graph[5]["links"].append({"to": 6})
        routes = incursion.Routes(Edges(Middles(graph)), {RED: [1], BLU: [5, 6]})
        traffic = incursion.Traffic(routes)
        self.assertEqual(traffic[3], {RED: 2, BLU: 1}, "RED's two routes; BLU's one, to RED's one spawn area")
        self.assertEqual(traffic[6], {RED: 1}, "BLU's route starts from its spawn nearer RED's")


class FrontTest(unittest.TestCase):
    def test_each_area_is_the_side_of_the_team_whose_walk_reaches_it_first_the_middle_no_ones(self):
        edges = Edges(Line())
        fields = {RED: incursion.Incursion(edges, [1]), BLU: incursion.Incursion(edges, [5])}
        side = incursion.Front(fields, margin=CELL / 2)
        self.assertEqual([side[i] for i in range(1, 6)], [RED, RED, None, BLU, BLU])


if __name__ == "__main__":
    unittest.main()
