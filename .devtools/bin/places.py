"""What each room is for when a round starts (docs/places-plan.md §2.3).

Occupation is then only the spawns, so the starting classes come from the
room graph alone. Each team's ways run from its spawn rooms to every
objective (to the enemy's spawns on a map with none), the shortest over the
graph: the traffic it is expected to bring. A room is

- RESTRICTED (a team's): its spawn rooms, and the rooms the enemy reaches
  only through them;
- STRONGHOLD (a team's): only that team's ways cross it, and it reaches the
  room first;
- HIGHWAY: it holds an objective, or both teams' ways cross it on at least
  HIGHWAY_SHARE of all the ways, or one team's on HIGHWAY_SHARE of its own
  (a team's way across the other's side);
- COMMONS: both teams' ways cross it, on fewer;
- UNOCCUPIED: no way crosses it, and both teams' spawns are at least
  FAR_SHARE of the walk between the spawns away;
- WILDS: any room left, the final pass.

No room is an OUTPOST at the start: an outpost needs a claim. Corridors
carry the ways but are given no class. Walks go centre to door to centre.
The game's own version is to come in Lua (wartactics); this is the tooling's.
"""
import heapq
import math
from dataclasses import dataclass

RESTRICTED, STRONGHOLD, OUTPOST, HIGHWAY = "restricted", "stronghold", "outpost", "highway"
COMMONS, UNOCCUPIED, WILDS = "commons", "unoccupied", "wilds"
# A highway is on two ways in three; unoccupied ground is at least three
# quarters of the walk between the spawns from either.
HIGHWAY_SHARE, FAR_SHARE = 2 / 3, 0.75


@dataclass(frozen=True)
class Door:
    pos: tuple
    leads: tuple          # the room ids beyond it
    passage: object       # the corridor it goes through, or None


@dataclass(frozen=True)
class Space:
    """A room (room=True) or a corridor of the partition."""
    id: int
    room: bool
    center: tuple
    doors: list


@dataclass(frozen=True)
class Placed:
    cls: str
    team: object          # the team it belongs to, or None


def Graph(rooms: list, passages: list) -> dict:
    """Each node (("room" | "passage", id)) and its edges [(to, length)], from its doors: through a
    corridor, the corridor; else the room the door leads to."""
    space = {("room", r.id): r for r in rooms}
    space.update({("passage", p.id): p for p in passages})
    edges = {key: [] for key in space}
    for key, s in space.items():
        for door in s.doors:
            to = ("passage", door.passage) if door.passage is not None else ("room", door.leads[0])
            if to in space and to != key:
                length = math.dist(s.center, door.pos) + math.dist(door.pos, space[to].center)
                edges[key].append((to, length))
    return edges


def Walk(edges: dict, starts: list, admit=lambda key: True) -> tuple:
    """Dijkstra from the starts over the nodes admit lets in: node -> distance, node -> the node before it."""
    distance, parent = {s: 0.0 for s in starts}, {}
    heap = [(0.0, i, s) for i, s in enumerate(starts)]
    heapq.heapify(heap)
    order = len(heap)
    while heap:
        d, _, node = heapq.heappop(heap)
        if d > distance[node]:
            continue
        for to, length in edges[node]:
            nd = d + length
            if admit(to) and nd < distance.get(to, math.inf):
                distance[to], parent[to] = nd, node
                heapq.heappush(heap, (nd, order, to))
                order += 1
    return distance, parent


def Start(rooms: list, passages: list, spawns: dict, objectives: list) -> dict:
    """Each room's class when a round starts: room id -> Placed. spawns: team -> room ids."""
    edges = Graph(rooms, passages)
    teams = sorted(spawns)
    objective = {("room", rid) for rid in objectives if ("room", rid) in edges}
    home = {t: [("room", rid) for rid in spawns[t] if ("room", rid) in edges] for t in teams}
    reach, parents = {}, {}
    for t in teams:
        reach[t], parents[t] = Walk(edges, home[t])
    restricted = {}
    for t in teams:
        own = set(home[t])
        for enemy in teams:
            if enemy == t:
                continue
            open_ground, _ = Walk(edges, home[enemy], lambda key: key not in own)
            for key in edges:
                if key[0] == "room" and key in reach[t] and (key in own or key not in open_ground):
                    restricted[key] = t
    flow = {t: {} for t in teams}
    ways, team_ways, separation = 0, {t: 0 for t in teams}, math.inf
    for t in teams:
        enemies = [e for e in teams if e != t]
        targets = sorted(objective) if objective else [k for e in enemies for k in home[e]]
        for target in targets:
            if target not in reach[t]:
                continue
            ways += 1
            team_ways[t] += 1
            node = target
            while node is not None:
                flow[t][node] = flow[t].get(node, 0) + 1
                node = parents[t].get(node)
        for e in enemies:
            for key in home[e]:
                separation = min(separation, reach[t].get(key, math.inf))
    classes = {}
    for key in sorted(edges):
        if key[0] != "room":
            continue
        crossing = [t for t in teams if flow[t].get(key, 0) > 0]
        total = sum(flow[t].get(key, 0) for t in teams)
        distances = sorted((reach[t].get(key, math.inf), t) for t in teams)
        nearest, nearest_team = distances[0] if distances else (math.inf, None)
        second = distances[1][0] if len(distances) > 1 else math.inf
        if key in restricted:
            placed = Placed(RESTRICTED, restricted[key])
        elif len(crossing) == 1 and crossing[0] == nearest_team and nearest < second:
            placed = Placed(STRONGHOLD, nearest_team)
        elif (key in objective or (len(crossing) > 1 and total >= HIGHWAY_SHARE * ways)
              or any(flow[t].get(key, 0) >= HIGHWAY_SHARE * team_ways[t] > 0 for t in teams)):
            placed = Placed(HIGHWAY, None)
        elif len(crossing) > 1:
            placed = Placed(COMMONS, None)
        elif total == 0 and nearest < math.inf and nearest >= FAR_SHARE * separation:
            placed = Placed(UNOCCUPIED, None)
        else:
            placed = Placed(WILDS, None)
        classes[key[1]] = placed
    return classes
