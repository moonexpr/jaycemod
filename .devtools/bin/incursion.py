"""Incursion: how each team walks into the map from its spawns (docs/places-plan.md §2.1).

A team's incursion field is its walk from its spawn areas over the nav mesh,
TF2's incursion distance (CTFNavArea::GetIncursionDistance): each area's
distance from the nearest of the team's spawns, along the links the mesh
gives, one way where the mesh is (a drop is walked down, never up). A route
is a team's shortest walk from its spawns to one of the enemy's spawn
areas; the routes together are the baseline traffic, before any objective
or any choice of a soldier's. The front is where the two teams' walks meet:
an area is the side of the team that reaches it first, and no one's within
the margin of both.

Walks go centre to the middle of the shared edge to centre, over the graph
rooms_dump.lua prints.
"""
import heapq
import math
from dataclasses import dataclass


@dataclass(frozen=True)
class Step:
    to: int
    cost: float


def Edges(graph: dict) -> dict:
    """Each area's steps out: area id -> [Step], one a link as the dump lists it."""
    def Point(p):
        return p["x"], p["y"], p["z"]
    edges = {}
    for aid, area in graph.items():
        steps = []
        for link in area["links"]:
            to = graph.get(link["to"])
            if to is not None:
                middle = Point(link["middle"])
                steps.append(Step(link["to"], math.dist(Point(area["center"]), middle)
                                  + math.dist(middle, Point(to["center"]))))
        edges[aid] = steps
    return edges


@dataclass(frozen=True)
class Field:
    distance: dict    # area id -> the walk from the nearest start
    parent: dict      # area id -> the area before it on that walk

    def Path(self, end: int):
        """The walk from a start to end, start first; None if the walk never reached it."""
        if end not in self.distance:
            return None
        path = [end]
        while path[-1] in self.parent:
            path.append(self.parent[path[-1]])
        return tuple(reversed(path))


def Incursion(edges: dict, starts: list) -> Field:
    """The walk from the starts (Dijkstra; ties to the earlier start)."""
    distance, parent = {s: 0.0 for s in starts}, {}
    heap = [(0.0, i, s) for i, s in enumerate(starts)]
    heapq.heapify(heap)
    order = len(heap)
    while heap:
        d, _, node = heapq.heappop(heap)
        if d > distance[node]:
            continue
        for step in edges[node]:
            nd = d + step.cost
            if nd < distance.get(step.to, math.inf):
                distance[step.to], parent[step.to] = nd, node
                heapq.heappush(heap, (nd, order, step.to))
                order += 1
    return Field(distance, parent)


@dataclass(frozen=True)
class Route:
    team: str
    areas: tuple      # from the team's spawn to the enemy's spawn area
    length: float


def Fields(edges: dict, spawns: dict) -> dict:
    """Each team's incursion field: team -> Field."""
    return {team: Incursion(edges, [a for a in starts if a in edges]) for team, starts in sorted(spawns.items())}


def Routes(edges: dict, spawns: dict, fields: dict = None) -> list:
    """Each team's routes, one to each enemy spawn area its walk reaches. spawns: team -> area ids."""
    fields = fields or Fields(edges, spawns)
    routes = []
    for team, field in fields.items():
        for enemy, targets in sorted(spawns.items()):
            if enemy == team:
                continue
            for target in sorted(set(targets)):
                path = field.Path(target)
                if path is not None:
                    routes.append(Route(team, path, field.distance[target]))
    return routes


def Traffic(routes: list) -> dict:
    """How many of each team's routes pass through each area: area id -> {team: count}."""
    traffic = {}
    for route in routes:
        for area in route.areas:
            counts = traffic.setdefault(area, {})
            counts[route.team] = counts.get(route.team, 0) + 1
    return traffic


def Front(fields: dict, margin: float) -> dict:
    """Each area's side: area id -> the team whose walk reaches it first, or None within margin of another's."""
    side = {}
    for area in set().union(*(f.distance for f in fields.values())):
        reach = sorted((f.distance.get(area, math.inf), team) for team, f in fields.items())
        first = reach[0]
        side[area] = None if len(reach) > 1 and reach[1][0] - first[0] <= margin else first[1]
    return side
