"""Incursion: how each team walks into the map from its spawns (docs/places-plan.md §2.1).

A team's incursion field is its walk from its spawn areas over the nav mesh,
TF2's incursion distance (CTFNavArea::GetIncursionDistance): each area's
distance from the nearest of the team's spawns, along the links the mesh
gives, one way where the mesh is (a drop is walked down, never up). A
team's routes to one of the enemy's spawn areas are its highway, the
shortest walk, and its other options: each found by walking again with the
areas the routes before it took made PENALTY times as costly, kept while
it is a new way and no more than DETOUR longer than the highway, up to
ALTERNATIVES in all (the penalty method for diverse routes). The routes
together are the baseline traffic, before any objective or any choice of
a soldier's. The front is where the two teams' walks meet:
an area is the side of the team that reaches it first, and no one's within
the margin of both.

Walks go centre to the middle of the shared edge to centre, over the graph
rooms_dump.lua prints.
"""
import heapq
import math
from dataclasses import dataclass

# Up to four ways from a team's spawns to each enemy spawn area, each at
# most half again as long as the shortest; an area a way already takes
# costs three times as much to the next.
ALTERNATIVES, DETOUR, PENALTY = 4, 0.5, 3.0


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


def Plain(step: Step) -> float:
    return step.cost


def Incursion(edges: dict, starts: list, weight=Plain) -> Field:
    """The walk from the starts (Dijkstra; ties to the earlier start), each step costing weight(step)."""
    distance, parent = {s: 0.0 for s in starts}, {}
    heap = [(0.0, i, s) for i, s in enumerate(starts)]
    heapq.heapify(heap)
    order = len(heap)
    while heap:
        d, _, node = heapq.heappop(heap)
        if d > distance[node]:
            continue
        for step in edges[node]:
            nd = d + weight(step)
            if nd < distance.get(step.to, math.inf):
                distance[step.to], parent[step.to] = nd, node
                heapq.heappush(heap, (nd, order, step.to))
                order += 1
    return Field(distance, parent)


@dataclass(frozen=True)
class Tree:
    """A team's walk as the tree it is (the shortest-path tree): rooted at its spawns, each area a child of
    the area it is reached from, weighted by the floor reached through it, so its trunk is the way most of
    the map is reached by and its twigs the ends."""
    team: str
    roots: tuple      # the spawn areas, ascending
    parent: dict      # area id -> the area it is reached from (a root has none)
    children: dict    # area id -> the areas reached from it, ascending
    weight: dict      # area id -> the floor of it and of everything reached through it

    def Forks(self, share: float) -> list:
        """The areas where a branch splits into ways each carrying at least share of the tree's floor."""
        total = sum(self.weight[r] for r in self.roots)
        return sorted(a for a, kids in self.children.items()
                      if sum(1 for k in kids if self.weight[k] >= share * total) >= 2)


def Grow(field: Field, team: str, graph: dict) -> Tree:
    """The tree of a team's walk (field), weighted by the areas' floors in graph."""
    reached = sorted(field.distance, key=lambda a: (field.distance[a], a))
    children = {a: [] for a in reached}
    for area in reached:
        if area in field.parent:
            children[field.parent[area]].append(area)
    weight = {}
    for area in reversed(reached):
        weight[area] = graph[area]["floor"] + sum(weight[k] for k in children[area])
    return Tree(team, tuple(sorted(a for a in reached if a not in field.parent)), dict(field.parent),
                {a: tuple(sorted(k)) for a, k in children.items()}, weight)


@dataclass(frozen=True)
class Route:
    team: str
    areas: tuple      # from the team's spawn to the enemy's spawn area
    length: float
    alternative: bool # one of the other options, not the highway


def Fields(edges: dict, spawns: dict) -> dict:
    """Each team's incursion field: team -> Field."""
    return {team: Incursion(edges, [a for a in starts if a in edges]) for team, starts in sorted(spawns.items())}


def Length(edges: dict, path: tuple) -> float:
    """A path's own walk, step by step."""
    return sum(min(s.cost for s in edges[a] if s.to == b) for a, b in zip(path, path[1:]))


def Ways(edges: dict, team: str, starts: list, target: int, highway: Field) -> list:
    """A team's routes from its starts to target: the highway (the shortest walk), then its other options."""
    path = highway.Path(target)
    if path is None:
        return []
    routes = [Route(team, path, highway.distance[target], False)]
    ends = set(starts) | {target}
    taken = set(path) - ends
    while len(routes) < ALTERNATIVES:
        walk = Incursion(edges, starts, lambda step: step.cost * (PENALTY if step.to in taken else 1))
        path = walk.Path(target)
        length = Length(edges, path)
        if any(r.areas == path for r in routes) or length > (1 + DETOUR) * routes[0].length:
            break
        routes.append(Route(team, path, length, True))
        taken |= set(path) - ends
    return routes


def Routes(edges: dict, spawns: dict, fields: dict = None) -> list:
    """Each team's routes to each enemy spawn area its walk reaches, highway and other options. spawns:
    team -> area ids."""
    fields = fields or Fields(edges, spawns)
    routes = []
    for team, field in fields.items():
        starts = [a for a in spawns[team] if a in edges]
        for enemy, targets in sorted(spawns.items()):
            if enemy == team:
                continue
            for target in sorted(set(targets)):
                routes.extend(Ways(edges, team, starts, target, field))
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
