"""Ambush hints: hiding spots beside the entrances an enemy squad comes through.

An entrance is where an enemy's path (an incursion route or breach) steps
into a room: from the area outside, through a doorway or a window (its
aperture, as wide as the crossing), into the area inside. Its approach is
the walk up to it, the last stretch of each path through it; a room
stepped into straight from the spawn has none, and is no entrance. Walking up,
the squad sees into the room only through the aperture: from each point
of the approach, a wedge (the frustum through the doorway). A hiding spot
(the nav mesh's) is an ambush for the defenders (the other team) at an
entrance when

- it is in the room the entrance opens into, between near and far of it;
- it is outside the frustum from every point of the approach: behind the
  wall the doorway is cut in, unseen until the squad steps through;
- standing up from it, a player sees just inside the entrance (sees): it
  has a line of fire on the doorway;
- the defenders' walk from their spawns reaches it before the enemy's
  reaches the entrance: there is time to set it up.

Positions are (x, y, z), judged across the ground; a path is (team, its
areas from its spawn).
"""
import math
from dataclasses import dataclass


@dataclass(frozen=True)
class Spot:
    pos: tuple
    area: int
    sees: frozenset   # the areas a player standing up from it sees


@dataclass(frozen=True)
class Entrance:
    team: str         # the enemy coming through
    outside: int      # the area before the entrance
    inside: int       # the area through it, in the room
    room: tuple       # the room it enters, ("room", id)
    via: tuple        # the aperture's middle: the doorway's, the window
    width: float      # the aperture's width
    heading: tuple    # the way the squad walks through it, a unit vector across the ground
    approach: tuple   # the points the squad walks through up to it, the farthest first
    paths: int        # how many paths come through it


@dataclass(frozen=True)
class Ambush:
    team: str         # the defenders lying in wait
    spot: Spot
    entrance: Entrance
    distance: float   # from the spot to the entrance


def Heading(a: tuple, b: tuple) -> tuple:
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    return dx / length, dy / length


def Entrances(paths: list, crossings: dict, region: dict, approach: float) -> list:
    """The entrances the paths make into rooms, in order of first use. crossings: (from, to) -> Step
    (incursion.Crossings); region: area id -> the space it is in, ("room" | "passage", id)."""
    found, order = {}, []
    for team, areas in paths:
        for i in range(1, len(areas)):
            outside, inside = areas[i - 1], areas[i]
            room = region.get(inside)
            if room is None or room[0] != "room" or region.get(outside) == room:
                continue
            door = crossings[(outside, inside)]
            points, walked, j = [], 0.0, i - 1
            while j > 0:
                step = crossings[(areas[j - 1], areas[j])]
                walked += step.cost
                if walked > approach:
                    break
                points.append(step.via)
                j -= 1
            if not points:
                continue                 # straight out of the spawn: no approach to lie in wait for
            heading = Heading(points[0], door.via)
            key = (team, outside, inside)
            if key not in found:
                order.append(key)
                found[key] = Entrance(team, outside, inside, room, door.via, door.width, heading,
                                      tuple(reversed(points)), 0)
            e = found[key]
            found[key] = Entrance(e.team, e.outside, e.inside, e.room, e.via, e.width, e.heading, e.approach,
                                  e.paths + 1)
    return [found[k] for k in order]


def Hidden(spot: tuple, door: Entrance) -> bool:
    """Whether spot, beyond the aperture, is out of the squad's sight through it from every point of the
    approach: the line from each point to the spot crosses the aperture's line outside the aperture."""
    hx, hy = door.heading
    nx, ny = -hy, hx                     # along the aperture
    vx, vy = door.via[0], door.via[1]
    ahead = (spot[0] - vx) * hx + (spot[1] - vy) * hy
    if ahead <= 0:
        return False                     # not through the door
    for point in door.approach:
        behind = (point[0] - vx) * hx + (point[1] - vy) * hy   # negative: before the door
        if behind >= 0:
            continue
        t = -behind / (ahead - behind)   # where the line meets the aperture's line
        across = ((point[0] + t * (spot[0] - point[0])) - vx) * nx + ((point[1] + t * (spot[1] - point[1])) - vy) * ny
        if abs(across) <= door.width / 2:
            return False
    return True


def Ambushes(entrances: list, spots: list, fields: dict, region: dict, near: float, far: float) -> list:
    """The ambushes the spots give at the entrances, nearest the entrance first for each. fields: team ->
    its incursion walk (incursion.Field), to tell who reaches a spot or an entrance first; region: area id
    -> its space, as Entrances takes it."""
    found = []
    for door in entrances:
        enemy_at = fields[door.team].distance.get(door.outside, math.inf)
        for team, field in sorted(fields.items()):
            if team == door.team:
                continue
            here = []
            for spot in spots:
                distance = math.dist(spot.pos[:2], door.via[:2])
                if (region.get(spot.area) == door.room and near <= distance <= far
                        and door.inside in spot.sees and Hidden(spot.pos, door)
                        and field.distance.get(spot.area, math.inf) < enemy_at):
                    here.append(Ambush(team, spot, door, distance))
            found.extend(sorted(here, key=lambda a: (a.distance, a.spot.pos)))
    return found
