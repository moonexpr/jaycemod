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
