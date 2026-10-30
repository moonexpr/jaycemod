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
| incursion | each team's walk to it from its active spawn rooms over the room graph (TF2's incursion distance, `tf_nav_area.h` `GetIncursionDistance`, per room instead of per area); walked again only on a capture, setup's end, a point's unlock and a round's reset. Comparing the two teams' says which reaches a room first |
| flow | how much of the movement between the key rooms (spawns, objectives) passes through it: every route, not the one shortest (a second route nearly as short would score nothing); the team's planned lanes through it, or current-flow betweenness, one solve a map |
| entries | for an objective room, the fewest doors that part it from the enemy's spawn: where it is guarded and come at (Killzone 2's playtesters' first complaint was bots guarding the objective instead of its entries) |
| depth | how far it lies off the routes; a dead end is a branch hanging off one room, with no spawn or objective in it |
| floor, level | from the rooms |

Sources and their costs: `docs/research/places-prior-art.md`. Every measure is
a walk or a flood over 20 to 200 rooms, well under a millisecond.

### 2.2 Occupation (`wartactics.occupation`)

Who holds each room, as evidence weighed, not a flag set once. A room's
holder is the team whose claim passes `HOLD` and beats the other's by a
margin; otherwise it is contested (both claim) or open (neither). Holding
has hysteresis, so occupation does not flicker: a room is taken above
`HOLD` and lost only below a lower `LOSE`, and only after its holder has
held it `HOLD_TIME`.

Claims come from sources, each with its strength and how it fades:

| Source | Claim | Changes when |
|---|---|---|
| Spawn | a team's active `func_respawnroom` over the room, or its enabled `info_player_teamspawn` in it, or the spawn base the war placed there on a map without team spawns (`features.aiwar.spawns`, 11abcdd0): the strongest claim, never fades | the map enables, disables or re-teams a respawn room or spawn point (the I/O the gamerules harness already traces) |
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
| Stronghold | a team holds and the enemy cannot reach without passing through others it holds: its spawn rooms and what lies behind them | one flood from the enemy's spawns over rooms the team does not hold: the team's rooms it never reaches (no min-cut needed) |
| Frontier | a team holds next to rooms the enemy holds or contests; before any presence, the rooms where the two teams' incursions meet | occupation and edges; incursion |
| Contested | both teams claim | occupation |
| Common | neither holds, wide and well connected: the open ground the fight crosses | floor, ways, betweenness, occupation |
| Thoroughfare | the movement between the key rooms passes through, for its size: corridors' rooms, stairwells, a hall between wings | flow over floor |
| Dead end | a branch off one room, no spawn or objective in it | ways, depth |
| Objective | holds a capture point, the cart's track, a flag; its entries marked | the map's entities; entries |
| Overlook | looks over another room through a window or from a level above | windows, levels |

The tuning (what high betweenness is, how wide is wide) is constants,
derived in tests from the fixtures, never pinned.

## 3. The rebase

- **Lanes through rooms.** A lane becomes a route over the room graph
  (spawn room to objective room, flanks and tours by penalising the rooms
  and ways of the routes before it), walked door to door: its waypoints are
  the doors and corridor ends it passes. The nav mesh is walked only within
  a room, by the soldier's own pathing. Lanes refuse the enemy's
  strongholds (today: its spawn rooms). As for doors today (8251de92: a
  door opening and shutting again re-planned every lane), a lane is planned
  again only for a lasting change of occupation in the rooms it crosses or
  borders, never for presence coming and going.
- **The zone** becomes the attackers' strongholds before the gates open.
- **Missions** read classes and the team's view of occupation instead of
  sampling lane points.

## 4. Missions as queries

Each mission kind is a filter and an order over rooms, and a door to go in
by; nothing more.

| Mission | The rooms | The door |
|---|---|---|
| Ambush | rooms beside the enemy's route, not on it (TF2's ambush code and FM 3-21.8 both put the ambushers off the kill zone): rooms with a door onto a thoroughfare or objective entry the enemy's traffic is high in (`intel:Traffic`), not held by the enemy; ordered by that traffic | the door onto the enemy's route: the squad waits behind it |
| Assault | rooms the team's view says the enemy holds, guarded within the squad's odds (`intel:Guarded`), not strongholds; ordered by worth to the team's lanes (on them first) | the room's way nearest the team's own holdings |
| Remote base | rooms the team holds on its frontier, with one or two ways in (easy to hold), not contested; where along the frontier is open (§7) | where the builders set up: the room's centre, away from its ways |
| Topple a support base | rooms with enemy works the team knows of | as an assault |

A squad's choice is drawn among the best two or three, not always the
first, so a team does not do the same thing every round; and a team
outnumbered takes fewer missions (Colonel Blotto: the weaker side leaves
some fronts to the enemy).

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
- Where a remote base goes along the frontier: forward on the team's lanes
  (as the plan first had it, and as a TF2 engineer builds where its team
  arrives first), or off the routes the enemy uses, on ground it values
  little (the Army's patrol base doctrine). The research leaves it open.
