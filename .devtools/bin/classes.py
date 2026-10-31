"""Room classes from the incursion: what each room is for when a round starts (docs/places-plan.md §2.3).

In order, each stage on what the ones before it found:

1. RESTRICTED rooms (places.Restricted: spawn rooms sealed by respawn
   visualizers, and what lies only behind them) and HIGHWAYS: a room
   holding an objective, or one at least HIGHWAY_SHARE of each team's
   incursion highways cross. A room holding a team's spawns is never one,
   objective or not: every route starts in its own team's, and it is its
   team's ground first (cs_office keeps its hostages and its rescue zone
   in the spawns).
2. The incursion spanning tree of each team lifted onto the spaces (rooms
   and corridors): each hangs from the space its team's walk enters it
   from (SpaceTree, Branches). Lanes are to be planned on it.
3. Buildings and occupation: the places (places.Places), a building or
   grounds owned by the team whose spawns it holds.
4. STRONGHOLDS and COMMONS, a gradient between the highways and the
   buildings: a room of a team's building is its stronghold; any other
   room is on the side of the team whose walk reaches it first (a highway
   in a team's building counts as highway, not as its building) (no one's
   within margin of both: COMMONS), and its gradient is how much nearer it
   is to that team's buildings than to the highways, d_highway /
   (d_highway + d_building): from 1 at the building to 0 on the highway. At
   half or more it is the team's STRONGHOLD, below it COMMONS. A room
   farther than far from both is no one's ground: UNOCCUPIED indoors,
   WILDS outdoors.
5. Junctions: where a team's tree forks in a corridor or in unoccupied
   ground, the floor within reach of the fork, in the same space, is carved
   into a room of its own if it has floor enough (Junctions): the places
   the ways part, to plan lanes and ambushes on.

Spaces are ("room" | "passage", id); walks go over incursion.Edges.
"""
import math
from dataclasses import dataclass

import incursion
from places import COMMONS, HIGHWAY, OUTPOST, RESTRICTED, STRONGHOLD, UNOCCUPIED, WILDS  # noqa: F401

# A highway: half or more of each team's highways cross it.
HIGHWAY_SHARE = 0.5


@dataclass(frozen=True)
class Classed:
    cls: str
    team: object      # the team it belongs to, or None
    gradient: float   # 1 at the team's building, 0 on the highway


def Highways(routes: list, region: dict, objectives: list, restricted: dict, spawns: dict) -> set:
    """The highway rooms: room keys. routes: incursion.Route; region: area id -> its space; spawns: team ->
    its spawn areas, whose rooms are no highways."""
    spawn_rooms = {region.get(a) for areas in spawns.values() for a in areas}
    highways = {region[a] for a in objectives if region.get(a, (None,))[0] == "room"}
    teams = {r.team for r in routes if not r.alternative}
    count, crossed = {t: 0 for t in teams}, {}
    for route in routes:
        if route.alternative:
            continue
        count[route.team] += 1
        for space in {region.get(a) for a in route.areas}:
            if space is not None and space[0] == "room":
                crossed.setdefault(space, {}).setdefault(route.team, 0)
                crossed[space][route.team] += 1
    for space, by in crossed.items():
        if teams and all(by.get(t, 0) >= HIGHWAY_SHARE * count[t] for t in teams):
            highways.add(space)
    return {s for s in highways if s not in restricted and s not in spawn_rooms}


@dataclass(frozen=True)
class Branches:
    team: str
    roots: tuple      # the spaces the team spawns in
    parent: dict      # space -> the space its walk enters it from
    children: dict    # space -> the spaces entered from it, ascending
    entry: dict       # space -> the area the walk first reaches it by


def SpaceTree(tree: incursion.Tree, region: dict) -> Branches:
    """A team's incursion tree lifted onto the spaces."""
    entry = {}
    for area in sorted(tree.distance, key=lambda a: (tree.distance[a], a)):
        space = region.get(area)
        if space is not None and space not in entry:
            entry[space] = area
    parent = {}
    for space, area in entry.items():
        above = area
        while above in tree.parent and region.get(above) == space:
            above = tree.parent[above]
        if region.get(above) != space and region.get(above) is not None:
            parent[space] = region[above]
    roots = tuple(sorted(s for s in entry if s not in parent))
    children = {s: [] for s in entry}
    for space, up in parent.items():
        children[up].append(space)
    return Branches(tree.team, roots, parent, {s: tuple(sorted(k)) for s, k in children.items()}, entry)


def Gradient(to_highway: float, to_building: float) -> float:
    """1 at the building, 0 on the highway: d_highway / (d_highway + d_building); with no building in reach
    0, with no highway 1."""
    if math.isinf(to_building):
        return 0.0
    if math.isinf(to_highway):
        return 1.0
    return to_highway / (to_highway + to_building)


def Classify(edges: dict, region: dict, fields: dict, restricted: dict, highways: set, owner: dict,
             outdoor: set, margin: float, far: float) -> dict:
    """Each room's class: room key -> Classed. fields: team -> its incursion walk; owner: space -> the team
    whose building or grounds it is in, or None; outdoor: the outdoor room keys."""
    areas = {}
    for area, space in region.items():
        if space[0] == "room":
            areas.setdefault(space, []).append(area)
    building = {}
    for team in fields:
        starts = [a for a, s in region.items()
                  if owner.get(s) == team and s[0] == "room" and s not in highways and a in edges]
        building[team] = incursion.Incursion(edges, starts).distance if starts else {}
    highway = incursion.Incursion(edges, [a for a, s in region.items() if s in highways and a in edges]).distance

    def Nearest(distance, mine):
        return min((distance.get(a, math.inf) for a in mine), default=math.inf)

    found = {}
    for space, mine in sorted(areas.items()):
        if space in restricted:
            found[space] = Classed(RESTRICTED, restricted[space], 1.0)
        elif space in highways:
            found[space] = Classed(HIGHWAY, None, 0.0)
        elif owner.get(space) is not None:
            found[space] = Classed(STRONGHOLD, owner[space], 1.0)
        else:
            reach = sorted((Nearest(f.distance, mine), team) for team, f in fields.items())
            side = None if len(reach) > 1 and reach[1][0] - reach[0][0] <= margin else reach[0][1]
            to_highway = Nearest(highway, mine)
            to_building = Nearest(building[side], mine) if side else min(Nearest(b, mine) for b in building.values())
            gradient = Gradient(to_highway, to_building)
            if to_highway > far and to_building > far:
                found[space] = Classed(WILDS if space in outdoor else UNOCCUPIED, None, gradient)
            elif side is not None and gradient >= 0.5:
                found[space] = Classed(STRONGHOLD, side, gradient)
            else:
                found[space] = Classed(COMMONS, None, gradient)
    return found


@dataclass(frozen=True)
class Junction:
    space: tuple      # the corridor or unoccupied room it is carved out of
    areas: tuple      # its areas, ascending
    fork: int         # the fork it is carved around


def Junctions(forks: list, graph: dict, edges: dict, region: dict, classed: dict, reach: float,
              floor: float) -> list:
    """The rooms carved around the forks that stand in a corridor or in unoccupied ground (UNOCCUPIED,
    WILDS): the areas of the fork's space within reach of it, when their floor is at least floor; a fork
    already carved into one is not carved again."""
    carved, found = set(), []
    for fork in forks:
        space = region.get(fork)
        if fork in carved or space is None:
            continue
        if space[0] != "passage" and classed.get(space, Classed(None, None, 0)).cls not in (UNOCCUPIED, WILDS):
            continue
        near = incursion.Incursion({a: [s for s in steps if region.get(s.to) == space]
                                    for a, steps in edges.items()}, [fork]).distance
        mine = tuple(sorted(a for a, d in near.items() if d <= reach and a not in carved))
        if sum(graph[a]["floor"] for a in mine) >= floor:
            found.append(Junction(space, mine, fork))
            carved.update(mine)
    return found
