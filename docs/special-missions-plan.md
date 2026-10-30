# Special missions: ambushes, assaults, support bases, remote bases (issue #4)

The four mission kinds the squad missions left for later
(`docs/squad-missions-plan.md` §6), and the modeling the tactics engine
needs for them. Every one is secondary to the alpha squad on the objective:
only a squad other than the alpha is given one, and only while the alpha is
out (settled with the operator).

| Kind | The squad | Needs |
|---|---|---|
| Ambush | waits hidden at a room's doors on the enemy's way, holds fire until the enemy is inside, then springs it | rooms and their doors; where the enemy passes |
| Assault | stacks at a door of a room known to be heavily guarded, breaches together (a grenade first), clears it | rooms; where the enemy holds |
| Topple a support base | goes for a room where the enemy keeps its turrets, medics and (later) dispensers and teleporters, and destroys them first | rooms; what the enemy has where |
| Remote base | takes a post on the battle line and holds it while its builders set up (a turret today; dispensers and teleporters with `docs/engineers-plan.md`) and its medic tends | posts on the line; a squad with builders |

## 1. What exists

- **No rooms.** The nav mesh knows only spawn rooms (`npcs:SpawnRoomTeam`).
  The converted TF2 meshes carry no place names: `pl_upward`'s 5,410
  areas have none (`area:GetPlace()`, checked 2026-10-30).
- **Sightings, for the hunt only.** `wartactics.hunt`'s `Board` keeps each
  team's latest sighting of each enemy, for the after-round hunt.
  `wartactics.fireteam` keeps a squad's own contact for a few seconds.
- **Builders.** Kits carry gadgets (`sv_gadgets.lua`): the Combine
  metrocop's floor turret and manhack, the Resistance's punt. Medics heal.
  No dispensers or teleporters yet (`docs/engineers-plan.md`, unbuilt).
- **The line.** `wartactics.posts` scores posts for defenders, attackers
  and guards; `field.posts`, `field.forwardPosts`, the front
  (`scenario:Front`).
- **Missions.** `wartactics.mission` (`Issue`, the alpha, `Promote`,
  `Regroup`), its request on the slow lane (`sv_missions.lua`) and the
  leader's muster and lead in the orders.

## 2. The new modeling

All of it pure, in `wartactics/`, tested first; the controller gathers its
inputs from the map and feeds them in.

### 2.1 Rooms (`wartactics.rooms`)

The nav mesh's areas grouped into rooms, joined by doors, found from the
mesh's shape:

- Two linked areas are in one room when the edge they share is at least
  `DOOR_WIDTH` wide: open floor joins, a doorway or a corridor does not.
- A group of areas whose floor is under `ROOM_MIN_FLOOR` is a passage, not a
  room (a corridor cut into pieces by its narrow links): passages join the
  rooms they link.
- A room's doors are its links to another room or to a passage: where they
  are (the middle of the shared edge), how wide, and which room is on the
  other side (through any passage). A map's func_door walls
  (`npcs:DoorWallIn`) are doors whatever their width.
- `Partition(graph)` takes `{ id -> { center, floor, links = { { to, width,
  middle } } } }` and returns the rooms (`id`, `areas`, `center`, `floor`,
  `doors`) and the room of each area. `RoomOf(rooms, areaId)`,
  `Doors(room)`, `Between(rooms, a, b)`.
- Found once per map and saved in the map's data (`WS.MapData` section
  `rooms`, with the mesh's area count to know a stale save). The debug
  overlay draws them (`ns_rooms_debug`), for tuning `DOOR_WIDTH` and
  `ROOM_MIN_FLOOR` by eye.

### 2.2 What a team knows (`wartactics.intel`)

Knowledge is earned (`docs/aiwar-command.md` decision 6): only what its
soldiers saw, heard or suffered, and when.

- `Intel.New()`, per team. `Report(room, kind, subject, now)`: a soldier saw
  an enemy of `kind` (`SOLDIER`, `TURRET`, `MEDIC`, `DISPENSER`,
  `TELEPORTER`) in a room. `Loss(room, now)`: one of ours died there.
- `Guarded(room, now)`: how strongly the enemy holds a room, from fresh
  sightings and our losses there, decaying over `GUARD_MEMORY`.
- `Traffic(room, now)`: how often enemies are seen passing through it,
  decaying over `TRAFFIC_MEMORY`: where an ambush pays.
- `SupportBases(now)`: rooms where enemy support stands (a turret, a medic
  seen healing, later a dispenser or teleporter), strongest first.
- The controller feeds it from what soldiers see (their vision's sightings,
  the hooks `WSSoldierContact` and kin), the turrets and manhacks the
  enemy's gadgets put down (seen like any enemy), and our deaths
  (`OnNPCKilled`, `PlayerDeath`), each placed in a room.

### 2.3 Missions (`wartactics.mission`)

- The kinds `AMBUSH`, `ASSAULT`, `TOPPLE`, `REMOTE_BASE` beside `ADVANCE`.
  A mission gains a `target`: the room (and for an ambush the doors it
  watches, for an assault the door it breaches, for a remote base its post).
  `way` stays the lane it takes there.
- `Issue` chooses for a squad other than the alpha, by utility, each kind's
  score from the team's intel and the field, `ADVANCE` when none scores
  (the scenario's default):
  - Ambush: a room on the enemy's way to our objective with traffic, not
    guarded; defenders favour it.
  - Assault: a guarded room on our way to the objective, not too strongly
    for the squad's size; attackers favour it.
  - Topple: the strongest known enemy support base within reach.
  - Remote base: a free post on our line, for a squad with a builder.
  Two squads of a team never take the same target.
- `Regroup` judges every kind. An ambush that waits `AMBUSH_PATIENCE` with
  no enemy, a toppled base, and a taken room each end the mission well
  (`DONE`): the squad asks again from where it stands.

### 2.4 Leading them (`features.aiwar.orders`)

Each kind is a job the leader leads under the squad's mission, its members
following as they do now:

- **Ambush:** to hiding spots near the doors, facing in (the port's
  `CoverSpot` with the door as the threat's way), crouched (`Pose`); hold
  fire (`ShouldAttack` NO) until an enemy is inside the room or one of them
  is hit; then the squad fights.
- **Assault:** to a stacking spot outside the door, wait for the squad
  (as at a muster), signal forward, a grenade through the door
  (`UseGadget`), then in together; done once the room is clear.
- **Topple:** to the base, the support first (`SelectMoreDangerousThreat`
  answers for a turret, a medic, a dispenser over a soldier).
- **Remote base:** to the post, its builders deploy (`UseGadget`: today the
  turret), its medic stays, the squad holds the post as defenders hold
  theirs (`Defend`).

## 3. Steps

Each ends with its tests green, a live check, a commit and a push.

1. **Rooms.** `wartactics.rooms` (`Partition`, test first), the controller
   building the graph from the nav mesh (shared edge widths) and saving
   the rooms with the map, and `ns_rooms_print` / the overlay to see them.
2. **Intel.** `wartactics.intel`, test first; fed by the controller.
3. **Mission kinds and choice.** `target`, the kinds, `Issue`'s utilities,
   `DONE`.
4. **Ambush** in the orders, then live.
5. **Assault.**
6. **Topple.**
7. **Remote base**, with today's turret; dispensers and teleporters join
   with the engineers plan.

## 4. Questions for the operator

1. Rooms from the mesh's shape: a doorway or corridor narrower than
   `DOOR_WIDTH` (96, a little over two soldiers abreast) separates rooms.
   Good, or should the map's own markings (func_door, the TF2 nav
   attributes once the sidecar keeps them) lead?
2. Until engineers exist, a remote base is a turret from a squad member
   whose kit has one (today the Combine's metrocop support), with a medic
   where the squad has one. Enough to start?
