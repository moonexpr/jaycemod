# Places: occupation and room classes over the rooms

The layer above `wartactics.rooms` (`docs/special-missions-plan.md` §2.1):
the map as a graph of rooms, which team holds each and how that changes,
and what each room is for (a team's restricted ground or stronghold, a
highway, the commons, the wilds, ...). Lanes and the special missions are to be rebased on it:
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
the nav mesh is not read again. A team's teleporter adds an edge of its
own while it stands, one way, for that team alone, from its entrance's room
to its exit's, of no length: the exit's room is then near the team's
ground however far it is to walk (teleporters are `docs/engineers-plan.md`'s,
unbuilt; a map's own teleporting triggers are the same edge for all).

Static measures of each room, from the graph alone:

| Measure | What |
|---|---|
| ways | its doors, corridors and windows, by kind |
| incursion | each team's walk to it from its active spawn rooms over the room graph (TF2's incursion distance, `tf_nav_area.h` `GetIncursionDistance`, per room instead of per area); walked again only on a capture, setup's end, a point's unlock and a round's reset. Comparing the two teams' says which reaches a room first; where they meet is the frontier |
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
| Works | a team's turret, dispenser or teleporter standing in it (a teleporter claims its exit's room too, §2.3) | built, destroyed |

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

The operator's seven. Each room has one class at a time, the first of this
table it answers to, the wilds taking every room left in a final pass. The
first three belong to a team (a room is one team's restricted ground and
the other's way in to it), the rest to no one. Static parts (the
objective's track) are found once a map; the rest on occupation's changes,
and each change is held as occupation is (hysteresis), so a room does not
flicker between classes.

| Class | A room that | Found from |
|---|---|---|
| Restricted | a team's spawns and the well-protected ground behind them: the other team may not enter while the round is played; the class stands after the round ends, when the winners break in (a breach, §2.3 below) | the team's spawn claims (§2.2), and one flood from the enemy's spawns: the team's held rooms it can reach only through restricted ones |
| Stronghold | a team holds, protected and commuted: its own soldiers pass through it, the enemy cannot reach it without crossing the team's rooms | occupation; the same flood stopped at the team's held rooms; the team's own traffic |
| Outpost | a team claims far from its spawns, out on its own, which may reach out of doors | occupation (a remote base's works and presence, §4) where the team's incursion is long and the room is not joined to its strongholds by its own rooms |
| Highway | carries the most traffic, or an objective passes through: the payload's track, a capture point's room | flow; the objective's entities (the cart's path_tracks, the capture areas) |
| Commons | both teams cross, in moderate traffic | each team's traffic through it (its intel's `Traffic` for the enemy, its own soldiers' passing for itself), both above a floor, neither a highway's |
| Unoccupied | far from both teams' active spawns, with little traffic | incursion long for both, traffic below the commons' floor |
| Wilds | any room none of the others take: the final pass | what is left |

Rooms are classed again as the war goes, not once. A team's ground grows
and shrinks by a ladder, each step held as occupation is:

- **Claimed: to outpost.** Any room can be claimed for occupation. A room
  the team claims becomes its outpost: a sentry, turret or other support
  an engineer or support soldier sets up there (the works of §2.2, here
  today), a remote base, a squad holding it, or, once there are
  teleporters, the exit of the team's teleporter from a stronghold (its
  edge makes the room the team's at once, however far). A room the enemy
  holds is claimed only once the team's claim beats the enemy's (§2.2).
- **Commuted: outpost to stronghold.** An outpost the team's own soldiers
  pass through enough (its traffic over `STRONGHOLD_TRAFFIC`, held) becomes
  a stronghold; the rooms next to it the team does not hold become its
  outposts (one the enemy holds only once the team's claim there beats the
  enemy's), so the ground spreads a room at a time.
- **Abandoned: back down.** A stronghold its soldiers stop passing through
  falls back to an outpost, and an outpost with no claim left (its sentry
  or support destroyed, teleporter gone, no one holding) to what it was
  before: the class its measures give.
- **Taken: to the enemy.** A room the enemy comes to hold (§2.2) is lost:
  an outpost at once, a stronghold once the enemy's claim beats the team's.
- **Breached: restricted ground claimed.** Restricted ground can be claimed
  too (the enemy's sentry in a spawn's doorway, a squad camping it). It is
  a breach: the claim is the enemy's outpost as any other, the room stays
  restricted (a class keeps its meaning when the round ends), and the
  tactics engine issues an automatic penalty for it to the director. The
  director decides penalties; until it is built (`docs/director-plan.md`,
  paused), the penalty is fixed:
  - the compromised team respawns sooner (its wait shortened, a reason of
    `gameplay.respawn_modifiers` told on its respawn screen), and its
    players and soldiers spawn ubercharged and crit boosted for a while
    (`players.condition_effects`' `INVULNERABLE` and `CRITBOOSTED`),
  - until it claims back its restricted spawn and the rooms around it.

  The director asks the gamerules to apply it, and the gamerules decide:
  while the round is over they refuse it (a declined transaction, its
  refusal the round's end). So the winners breaking into the losers' spawn
  to finish their SeekAndDestroy is a breach as any other, its penalty
  issued and refused. The hunt's routes then go into the losers' restricted
  ground instead of ending at its door (`wartactics.hunt` today: "routes
  refuse enemy spawn rooms").

  Each breach is also recorded (who breached whom, where, for how long) in
  the war's analytics (`analysis.analytics`) and on the overlay's label.

The measures behind them (§2.1) stay available for queries beside the
class: a room's ways and entries, its depth (a dead end), its flow and
level. The tuning (what high traffic is, how far is far) is constants,
derived in tests from the fixtures, never pinned.

## 3. The rebase

- **Lanes through rooms.** A lane becomes a route over the room graph
  (spawn room to objective room, flanks and tours by penalising the rooms
  and ways of the routes before it), walked door to door: its waypoints are
  the doors and corridor ends it passes. The nav mesh is walked only within
  a room, by the soldier's own pathing. Lanes refuse the enemy's
  restricted ground (today: its spawn rooms). As for doors today (8251de92: a
  door opening and shutting again re-planned every lane), a lane is planned
  again only for a lasting change of occupation in the rooms it crosses or
  borders, never for presence coming and going.
- **The zone** becomes the attackers' restricted ground before the gates open.
- **Missions** read classes and the team's view of occupation instead of
  sampling lane points.

## 4. Missions as queries

Each mission kind is a filter and an order over rooms, and a door to go in
by; nothing more.

| Mission | The rooms | The door |
|---|---|---|
| Ambush | commons and unoccupied rooms (and wilds) beside an enemy highway, not on it (TF2's ambush code and FM 3-21.8 both put the ambushers off the kill zone), the enemy's traffic on that highway high (`intel:Traffic`); ordered by that traffic | the door onto the highway: the squad waits behind it |
| Assault | the enemy's strongholds and outposts as the team's view has them, guarded within the squad's odds (`intel:Guarded`); never restricted ground; ordered by worth to the team's lanes (on them first) | the room's way nearest the team's own rooms |
| Remote base | establishes an outpost in a commons, an unoccupied room, or a place of significance in the wilds: a hiding spot the nav mesh identifies (`area:GetHidingSpots()`, as `features.aiwar.spawns` reads them, 11abcdd0); with one or two ways in (easy to hold), not contested | where the builders set up: the hiding spot in the wilds, else the room's centre, away from its ways |
| Topple a support base | the enemy's outposts and strongholds with works the team knows of | as an assault |

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
   waypoints at doors; the zone as restricted ground.

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

- Whether presence alone should make a room a team's (a squad holding a
  hall for a minute), or only spawns, objectives and works.

## 8. Settled with the operator

- The room classes are the operator's seven: restricted, stronghold,
  outpost, highway, commons, wilds, unoccupied (§2.3).
- Rooms are classed again as the war goes: a claim makes an outpost, the
  team's traffic makes it a stronghold and its neighbours outposts.
- Any room can be claimed, restricted ground too. A sentry or support an
  engineer or support soldier sets up claims its room (as a teleporter's
  exit will, once there are teleporters).
- A class keeps its meaning when the round ends: the winners breaking into
  the losers' spawn for their SeekAndDestroy is a breach.
- The breach penalty, until the director decides penalties: the
  compromised team respawns sooner and spawns ubercharged and crit boosted
  until it claims back its restricted spawn and the rooms around it. The
  penalty is always issued to the director; the gamerules refuse it while
  the round is over.
- The wilds are not found from anything of their own: they are any room
  the other classes have not taken, the final pass.
- A remote base takes a commons, an unoccupied room, or a place of
  significance in the wilds such as an identified hiding spot (§4).
