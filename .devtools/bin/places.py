"""What each room is for when a round starts (docs/places-plan.md §2.3).

Occupation is then only the spawns, so the starting classes come from the
room graph alone. Each team's ways run from its spawn rooms to every
objective (to the enemy's spawns on a map with none), every route through
the graph at most ROUTE_SLACK longer than the shortest: the traffic it is
expected to bring. A route passes through a room, in by one door and out by
another, so a dead end beside a way is on none. A room is

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

Rooms belong to places above them (Places): a building is the indoor rooms
and corridors joined to each other without going out of doors, grounds the
outdoor ones likewise. A place holding one team's spawns is that team's; one
holding both teams' (two bases joined underground) is split where their
walks meet, the rooms within NEUTRAL_SHARE of the walk between the spawns of
the middle no one's. Inside a team's place, a room the rules above leave
UNOCCUPIED or WILDS is the team's STRONGHOLD, and one the enemy's STRONGHOLD
is COMMONS: to reach it the enemy crosses into the team's ground.

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
# A way is every route from the spawn to the target at most ROUTE_SLACK
# longer than the shortest: players take the bridge as well as the tunnel.
# ROUNDING lets the shortest itself through, its length summed two ways.
ROUTE_SLACK, ROUNDING = 0.1, 1e-9
BUILDING, GROUNDS = "building", "grounds"
# The middle of a building joining both teams' spawns, no one's: the rooms
# whose walks from the two spawns differ by no more than a fifth of the walk
# between them.
NEUTRAL_SHARE = 0.2


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


def Reversed(edges: dict) -> dict:
    """The edges turned round: node -> [(from, length, door's pos)], to walk back from a target."""
    back = {key: [] for key in edges}
    for key, out in edges.items():
        for to, length, pos in out:
            back[to].append((key, length, pos))
    return back


def Way(edges: dict, start: dict, back: dict, target) -> set:
    """The nodes a way to target passes through: start is the walk from the spawns. A node is on it when a
    route through it, in by one door and out by another to a different node, is at most ROUTE_SLACK longer
    than the shortest; a dead end, gone in and out of, is on none."""
    to_target, _ = Walk(back, [target])
    budget = (1 + ROUTE_SLACK + ROUNDING) * start[target]
    on = {target} | {key for key, d in start.items() if d == 0}
    for node, out in edges.items():
        ins = sorted((start[a] + length, a) for a, length, _ in back[node] if a in start)[:2]
        outs = sorted((length + to_target[b], b) for b, length, _ in out if b in to_target)[:2]
        if any(a != b and i + o <= budget for i, a in ins for o, b in outs):
            on.add(node)
    return on


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


@dataclass(frozen=True)
class Place:
    id: int
    kind: str             # BUILDING or GROUNDS
    owner: object         # the team whose place it is, or None
    members: frozenset    # its nodes, ("room" | "passage", id)


def Pieces(nodes: set, edges: dict, joined) -> list:
    """nodes in pieces joined over edges joined(a, b) lets through, each sorted, in order of their first."""
    pieces, seen = [], set()
    for start in sorted(nodes):
        if start in seen:
            continue
        piece, stack = [start], [start]
        seen.add(start)
        while stack:
            node = stack.pop()
            for to, _, _ in edges[node]:
                if to in nodes and to not in seen and joined(node, to):
                    seen.add(to)
                    piece.append(to)
                    stack.append(to)
        pieces.append(sorted(piece))
    return sorted(pieces)


def Places(rooms: list, passages: list, spawns: dict) -> list:
    """The map's places: list of Place. spawns: team -> the nodes its spawns take."""
    edges = Graph(rooms, passages)
    outdoor = {("room", r.id): r.outdoor for r in rooms}
    outdoor.update({("passage", p.id): p.outdoor for p in passages})
    teams = sorted(spawns)
    found = []
    for piece in Pieces(set(edges), edges, lambda a, b: outdoor[a] == outdoor[b]):
        kind = GROUNDS if outdoor[piece[0]] else BUILDING
        inside = set(piece)
        homes = {t: [k for k in spawns[t] if k in inside] for t in teams}
        holding = [t for t in teams if homes[t]]
        if len(holding) < 2:
            found.append((piece, kind, holding[0] if holding else None))
            continue
        reach = {t: Walk(edges, homes[t], lambda key: key in inside)[0] for t in holding}
        between = min(reach[a].get(k, math.inf) for a in holding for b in holding if a != b for k in homes[b])
        label = {}
        for key in piece:
            ds = sorted((reach[t].get(key, math.inf), t) for t in holding)
            label[key] = None if ds[1][0] - ds[0][0] <= NEUTRAL_SHARE * between else ds[0][1]
        for part in Pieces(inside, edges, lambda a, b: label[a] == label[b]):
            found.append((part, kind, label[part[0]]))
    return [Place(i + 1, kind, owner, frozenset(members)) for i, (members, kind, owner) in enumerate(sorted(found))]


def Restricted(edges: dict, home: dict, seals: list) -> dict:
    """Each team's restricted rooms: room key -> team. home: team -> the nodes its spawns take. A team's
    spawn rooms and the rooms the enemy reaches only through them, where every door out of them is sealed
    by a visualizer (seals)."""
    teams = sorted(home)
    restricted = {}
    for t in teams:
        reach, _ = Walk(edges, home[t])
        own, ground = set(home[t]), set()
        for enemy in teams:
            if enemy == t:
                continue
            open_ground, _ = Walk(edges, home[enemy], lambda key: key not in own)
            for key in edges:
                if key in reach and (key in own or key not in open_ground):
                    ground.add(key)
        for key in Enclosed(edges, ground, seals):
            if key[0] == "room":
                restricted[key] = t
    return restricted


def Start(rooms: list, passages: list, spawns: dict, objectives: list, seals: list) -> dict:
    """Each room's class when a round starts: room id -> Placed. spawns: team -> the nodes its spawns
    take, ("room", id) and ("passage", id) for a corridor inside a spawn; seals: the respawn room
    visualizers' boxes, (lo, hi) corners."""
    edges = Graph(rooms, passages)
    outdoor = {r.id for r in rooms if r.outdoor}
    teams = sorted(spawns)
    objective = {("room", rid) for rid in objectives if ("room", rid) in edges}
    home = {t: [key for key in spawns[t] if key in edges] for t in teams}
    reach = {t: Walk(edges, home[t])[0] for t in teams}
    restricted = Restricted(edges, home, seals)
    flow, back = {t: {} for t in teams}, Reversed(edges)
    ways, team_ways, separation = 0, {t: 0 for t in teams}, math.inf
    for t in teams:
        enemies = [e for e in teams if e != t]
        targets = sorted(objective) if objective else [k for e in enemies for k in home[e]]
        for target in targets:
            if target not in reach[t]:
                continue
            ways += 1
            team_ways[t] += 1
            for node in Way(edges, reach[t], back, target):
                flow[t][node] = flow[t].get(node, 0) + 1
        for e in enemies:
            for key in home[e]:
                separation = min(separation, reach[t].get(key, math.inf))
    owner = {key: place.owner for place in Places(rooms, passages, spawns) for key in place.members}
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
        home_team = owner.get(key)
        if home_team is not None and placed.cls in (UNOCCUPIED, WILDS):
            placed = Placed(STRONGHOLD, home_team)
        elif home_team is not None and placed.cls == STRONGHOLD and placed.team != home_team:
            placed = Placed(COMMONS, None)
        classes[key[1]] = placed
    return classes
