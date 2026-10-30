# Places: occupation and room classes over the rooms

The layer above `wartactics.rooms` (`docs/special-missions-plan.md` §2.1):
the map as a graph of rooms, which team holds each and how that changes,
and what each room is for (a team's stronghold, common ground, a
thoroughfare, ...). Lanes and the special missions are to be rebased on it:
a lane becomes a route through rooms, not over nav areas, and a mission a
question asked of the places. The test of the layer: ambushes, assaults and
remote bases fall out of it as plain queries (§4), with no geometry of
their own.

Starts once the rooms are stable enough (§6).

## 1. What exists

- **Rooms** (`wartactics.rooms`): big blocks indoors and outdoors, on
  levels, with stairwells, the corridors between them, doors and windows;
  found once per map and saved (`features/aiwar/sv_rooms.lua`).
- **Occupation, from the spawns only.** `npcs:SpawnRoomTeam(area)`
  (`features/npc/sv_blockers.lua`) answers the team whose
  `func_respawnroom` holds an area. Lanes refuse the enemy's spawn rooms,
  soldiers' routes refuse them, the flag drops in its own. Nothing else
  says who holds what, and nothing changes it but the map switching its
  respawn rooms.
- **What a team knows** (`wartactics.intel`): enemies seen by room, losses,
  traffic, support bases, each fading with time. Earned knowledge, per team.
- **Lanes** (`wartactics.lanes`) route over nav areas from a spawn to the
  objective, flanks and tours apart by a penalty band. Missions find the
  rooms a team's lanes cross by sampling lane points (`LaneRooms`).
- **The zone** (`wartactics.zone`): the ground behind the setup gates, a
  flood from the attackers' spawns held at the gates.

## 2. The model

All pure, in `wartactics/`, tested first; the controller gathers inputs from
the map and feeds them in.

### 2.1 The room graph (`wartactics.places`, its graph)

Rooms are nodes. An edge is a way between two rooms: a door, a corridor
(its length, and the doors at either end), a window (seen through, shot
through, crossed once broken), a stairwell's flight. Each edge carries its
kind, width, length and where it is. Built once from the saved partition;
the nav mesh is not read again.

Static measures of each room, from the graph alone:

| Measure | What |
|---|---|
| ways | its doors, corridors and windows, by kind |
| betweenness | how many of the shortest routes between the map's key rooms (spawns, objectives) pass through it |
| depth | how far it lies from the nearest way on: 0 for a room on a route, more for rooms off it; a dead end is the far room of a branch |
| floor, level | from the rooms |

### 2.2 Occupation (`wartactics.occupation`)

Who holds each room, as evidence weighed, not a flag set once. A room's
holder is the team whose claim passes `HOLD` and beats the other's by a
margin; otherwise it is contested (both claim) or open (neither).

Claims come from sources, each with its strength and how it fades:

| Source | Claim | Changes when |
|---|---|---|
| Spawn | a team's active `func_respawnroom` over the room, or its enabled `info_player_teamspawn` in it: the strongest claim, never fades | the map enables, disables or re-teams a respawn room or spawn point (the I/O the gamerules harness already traces) |
| Objective | a control point a team owns, the room its capture area stands in | `game_point_captured`, a round's reset |
| Presence | a team's soldiers and players in the room, no enemy with them, held for `HOLD_TIME`: grows while they stay, fades after they leave | sightings and positions each slow tick |
| Works | a team's turret, dispenser or teleporter standing in it | built, destroyed |

Initial occupation is the spawns, as today. The systems that change it are
the rows below the first: captures move a point's room (and, when the map
re-teams spawns with it, the spawn rooms), presence lets a squad take and
hold ground, works dig a team in. A round's reset sets every claim back to
the spawns.

Occupation is the truth of the board, kept by the controller; a team plans
on its own knowledge of it: its own holdings it knows, the enemy's as its
`intel` saw them (`Guarded`, support bases). Missions read the team's view,
never the truth (knowledge is earned, `docs/aiwar-command.md` decision 6).

### 2.3 Room classes (`wartactics.places`)

What a room is for, from its measures and its occupation; a room may be of
more than one. Static classes are found once a map; dynamic ones as
occupation changes.

| Class | A room that | Found from |
|---|---|---|
| Stronghold | a team holds and the enemy cannot reach without passing through others it holds: its spawn rooms and what lies behind them | occupation, and the graph cut at the team's frontier |
| Frontier | a team holds next to rooms the enemy holds or contests | occupation and edges |
| Contested | both teams claim | occupation |
| Common | neither holds, wide and well connected: the open ground the fight crosses | floor, ways, betweenness, occupation |
| Thoroughfare | the routes between the key rooms pass through, for its size: corridors' rooms, stairwells, a hall between wings | betweenness over floor |
| Dead end | one way in (depth past a single door) | ways, depth |
| Objective | holds a capture point, the cart's track, a flag | the map's entities |
| Overlook | looks over another room through a window or from a level above | windows, levels |

The tuning (what high betweenness is, how wide is wide) is constants,
derived in tests from the fixtures, never pinned.

## 3. The rebase

- **Lanes through rooms.** A lane becomes a route over the room graph
  (spawn room to objective room, flanks and tours by penalising the rooms
  and ways of the routes before it), walked door to door: its waypoints are
  the doors and corridor ends it passes. The nav mesh is walked only within
  a room, by the soldier's own pathing. Lanes refuse the enemy's
  strongholds (today: its spawn rooms).
- **The zone** becomes the attackers' strongholds before the gates open.
- **Missions** read classes and the team's view of occupation instead of
  sampling lane points.

## 4. Missions as queries

Each mission kind is a filter and an order over rooms, and a door to go in
by; nothing more.

| Mission | The rooms | The door |
|---|---|---|
| Ambush | thoroughfares or dead ends on the enemy's lanes (their routes through rooms), not held by the enemy, its traffic high (`intel:Traffic`); ordered by traffic | the one the enemy's route comes in by; the squad waits at the others |
| Assault | rooms the team's view says the enemy holds, guarded within the squad's odds (`intel:Guarded`), not strongholds; ordered by worth to the team's lanes (on them first) | the room's way nearest the team's own holdings |
| Remote base | rooms the team holds on its frontier, on its lanes, with one or two ways in (easy to hold), not contested; ordered by how far forward | where the builders set up: the room's centre, away from its ways |
| Topple a support base | rooms with enemy works the team knows of | as an assault |

## 5. Steps

1. **The room graph and its measures** (`wartactics.places`): pure, tested
   on fixtures (two halls and a corridor; a dead end; a stairwell between
   levels), drawn by `rooms_view.py` (betweenness as shading, classes as
   labels) and the overlay.
2. **Occupation** (`wartactics.occupation`): claims, sources, holding and
   contesting; spawns first (the `func_respawnroom` and spawn points of each
   room), then objectives (point captures), presence and works. The
   controller feeds it from map I/O and the slow tick; the overlay shows
   each room's holder.
3. **Classes**: static ones once a map, dynamic ones on occupation's
   changes; shown on the overlay's labels.
4. **Missions as queries** (`wartactics.mission`'s `Choose` on places): the
   table of §4, replacing `LaneRooms` and the hand-built specs in
   `sv_missions.lua`.
5. **Lanes through rooms** (`wartactics.lanes`): routes over the room graph,
   waypoints at doors; the zone as strongholds.

Each step is checked on cs_office and one TF2 map (pl_upward, which has the
spawn rooms, gates and points) before the next.

## 6. When the rooms are stable enough

The layer stands on the rooms, so they hold first:

- the operator has looked at cs_office's rooms on the overlay in game and
  in `rooms_view.py`'s picture, and agrees with its rooms, stairwells,
  corridors and levels;
- the same on pl_upward (cliffs, yards, spawn rooms) and one CTF map;
- every door and window between two rooms is found (none missing where a
  soldier walks or shoots from one into the other);
- a map's rooms come out the same each time it is found (ids and all), so
  saved knowledge and missions keep meaning the same rooms.

## 7. Open questions for the operator

- The classes' names and which matter first: stronghold, common and
  thoroughfare are the operator's; frontier, contested, dead end, objective
  and overlook are proposed.
- Whether presence alone should make a room a team's (a squad holding a
  hall for a minute), or only spawns, objectives and works.
