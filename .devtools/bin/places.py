"""What each room is for when a round starts (docs/places-plan.md §2.3).

Occupation is then only the spawns, so the starting classes come from the
room graph alone. Each team's ways run from its spawn rooms to every
objective (to the enemy's spawns on a map with none), the shortest over the
graph: the traffic it is expected to bring. A room is

- RESTRICTED (a team's): its spawn rooms, and the rooms the enemy reaches
  only through them, but only where every door out of them is sealed by a
  respawn room visualizer (func_respawnroomvisualizer): a spawn the enemy
  can walk into is no restricted ground;
- STRONGHOLD (a team's): a spawn room of the team's not sealed off, or a
  room only the team's ways cross that it reaches first;
- HIGHWAY: it holds an objective, or both teams' ways cross it on at least
  HIGHWAY_SHARE of all the ways, or one team's on HIGHWAY_SHARE of its own
  (a team's way across the other's side);
- COMMONS: both teams' ways cross it, on fewer;
- UNOCCUPIED: no way crosses it, and both teams' spawns are at least
  FAR_SHARE of the walk between the spawns away;
- the final pass, any room left: WILDS outdoors (open ground and nature),
  UNOCCUPIED indoors.

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
# quarters of the walk between the spawns from either; a door is sealed by a
# visualizer whose box, grown by SEAL_REACH, holds it: a door is where two
# nav areas meet, up to about an area's depth from the brush.
HIGHWAY_SHARE, FAR_SHARE, SEAL_REACH = 2 / 3, 0.75, 128


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
    outdoor: bool


@dataclass(frozen=True)
class Placed:
    cls: str
    team: object          # the team it belongs to, or None


def Graph(rooms: list, passages: list) -> dict:
    """Each node (("room" | "passage", id)) and its edges [(to, length, door's pos)], from its doors:
    through a corridor, the corridor; else the room the door leads to."""
    space = {("room", r.id): r for r in rooms}
    space.update({("passage", p.id): p for p in passages})
    edges = {key: [] for key in space}
    for key, s in space.items():
        for door in s.doors:
            to = ("passage", door.passage) if door.passage is not None else ("room", door.leads[0])
            if to in space and to != key:
                length = math.dist(s.center, door.pos) + math.dist(door.pos, space[to].center)
                edges[key].append((to, length, door.pos))
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
        for to, length, _ in edges[node]:
            nd = d + length
            if admit(to) and nd < distance.get(to, math.inf):
                distance[to], parent[to] = nd, node
                heapq.heappush(heap, (nd, order, to))
                order += 1
    return distance, parent


def Sealed(pos: tuple, seals: list) -> bool:
    """Whether a visualizer's box (lo, hi), grown by SEAL_REACH, holds the door at pos."""
    return any(all(lo[i] - SEAL_REACH <= pos[i] <= hi[i] + SEAL_REACH for i in range(3)) for lo, hi in seals)


def Enclosed(edges: dict, ground: set, seals: list) -> set:
    """The rooms of ground in pieces (rooms joined to each other), keeping the pieces whose every door
    out is sealed."""
    kept, seen = set(), set()
    for start in sorted(ground):
        if start in seen:
            continue
        piece, stack = {start}, [start]
        seen.add(start)
        while stack:
            for to, _, _ in edges[stack.pop()]:
                if to in ground and to not in seen:
                    seen.add(to)
                    piece.add(to)
                    stack.append(to)
        if all(Sealed(pos, seals) for key in piece for to, _, pos in edges[key] if to not in piece):
            kept |= piece
    return kept


def Start(rooms: list, passages: list, spawns: dict, objectives: list, seals: list) -> dict:
    """Each room's class when a round starts: room id -> Placed. spawns: team -> the nodes its spawns
    take, ("room", id) and ("passage", id) for a corridor inside a spawn; seals: the respawn room
    visualizers' boxes, (lo, hi) corners."""
    edges = Graph(rooms, passages)
    outdoor = {r.id for r in rooms if r.outdoor}
    teams = sorted(spawns)
    objective = {("room", rid) for rid in objectives if ("room", rid) in edges}
    home = {t: [key for key in spawns[t] if key in edges] for t in teams}
    reach, parents = {}, {}
    for t in teams:
        reach[t], parents[t] = Walk(edges, home[t])
    restricted = {}
    for t in teams:
        own, ground = set(home[t]), set()
        for enemy in teams:
            if enemy == t:
                continue
            open_ground, _ = Walk(edges, home[enemy], lambda key: key not in own)
            for key in edges:
                if key in reach[t] and (key in own or key not in open_ground):
                    ground.add(key)
        for key in Enclosed(edges, ground, seals):
            if key[0] == "room":
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
        spawned = [t for t in teams if key in home[t]]
        if key in restricted:
            placed = Placed(RESTRICTED, restricted[key])
        elif spawned:
            placed = Placed(STRONGHOLD, spawned[0])
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
            placed = Placed(WILDS if key[1] in outdoor else UNOCCUPIED, None)
        classes[key[1]] = placed
    return classes
