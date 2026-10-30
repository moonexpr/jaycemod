"""Ambush hints: hiding spots from which a team can catch an enemy squad coming through an entrance.

An entrance is where an enemy's path (an incursion route or breach) steps
into a room: from the area outside (through a doorway, a window) into the
area inside. Its approach is the walk up to it, the last stretch of each
path through it. A hiding spot (the nav mesh's) is an ambush for the
defenders (the other team) at an entrance when

- standing up from it, a player sees just inside the entrance (sees);
- crouched at it, a player is in sight of none of the approach (seen): the
  squad does not see it coming, though it may be in plain sight of a
  player standing;
- it is off the squad's walk, and between near and far of the entrance;
- the defenders' walk from their spawns reaches it before the enemy's
  reaches the entrance: there is time to set it up.

Positions are (x, y, z); a path is (team, its areas from its spawn).
"""
import math
from dataclasses import dataclass


@dataclass(frozen=True)
class Spot:
    pos: tuple
    area: int
    sees: frozenset   # the areas a player standing up from it sees
    seen: frozenset   # the areas from which a player standing sees one crouched at it


@dataclass(frozen=True)
class Entrance:
    team: str         # the enemy coming through
    outside: int      # the area before the entrance
    inside: int       # the area through it, in the room
    room: tuple       # the room it enters, ("room", id)
    via: tuple        # where it crosses: the doorway's middle, the window
    approach: tuple   # the areas walked up to it, within the approach of the outside, outside last
    line: tuple       # the walk's crossings around it, the squad's line through it
    paths: int        # how many paths come through it


@dataclass(frozen=True)
class Ambush:
    team: str         # the defenders lying in wait
    spot: Spot
    entrance: Entrance
    distance: float   # from the spot to the entrance


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
            back, walked, j = [outside], 0.0, i - 1
            while j > 0:
                walked += crossings[(areas[j - 1], areas[j])].cost
                if walked > approach:
                    break
                back.append(areas[j - 1])
                j -= 1
            line, walked, k = [crossings[(outside, inside)].via], 0.0, i
            while k + 1 < len(areas) and walked <= approach:
                step = crossings[(areas[k], areas[k + 1])]
                line.append(step.via)
                walked += step.cost
                k += 1
            line = [crossings[(back[n + 1], back[n])].via for n in reversed(range(len(back) - 1))] + line
            key = (team, outside, inside)
            if key not in found:
                order.append(key)
                found[key] = Entrance(team, outside, inside, room, crossings[(outside, inside)].via,
                                      tuple(reversed(back)), tuple(line), 0)
            e = found[key]
            found[key] = Entrance(e.team, e.outside, e.inside, e.room, e.via, e.approach, e.line, e.paths + 1)
    return [found[k] for k in order]


def OffLine(p: tuple, line: tuple) -> float:
    """How far p is from the polyline through line's points, across the ground."""
    if len(line) == 1:
        return math.dist(p[:2], line[0][:2])
    best = math.inf
    for a, b in zip(line, line[1:]):
        ax, ay, bx, by = a[0], a[1], b[0], b[1]
        dx, dy = bx - ax, by - ay
        t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(p[0] - ax - t * dx, p[1] - ay - t * dy))
    return best


def Ambushes(entrances: list, spots: list, fields: dict, near: float, far: float) -> list:
    """The ambushes the spots give at the entrances, nearest the entrance first for each. fields: team ->
    its incursion walk (incursion.Field), to tell who reaches a spot or an entrance first."""
    found = []
    for door in entrances:
        enemy_at = fields[door.team].distance.get(door.outside, math.inf)
        for team, field in sorted(fields.items()):
            if team == door.team:
                continue
            here = []
            for spot in spots:
                distance = math.dist(spot.pos, door.via)
                if (door.inside in spot.sees and not (spot.seen & set(door.approach))
                        and near <= distance <= far and OffLine(spot.pos, door.line) >= near
                        and field.distance.get(spot.area, math.inf) < enemy_at):
                    here.append(Ambush(team, spot, door, distance))
            found.extend(sorted(here, key=lambda a: (a.distance, a.spot.pos)))
    return found
