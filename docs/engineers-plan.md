# NextSoldier engineers: sentries, dispensers and teleporters

Both teams field engineers, soldiers on a mission rather than in a squad, who
build a nest (a sentry and a dispenser) where the map's engineer hints or the
nav mesh say, and a teleporter from their spawn to the battle line.

## 0. Decisions

Operator, 2026-10-21:

1. **Buildings.** The sentry stays HL2's `npc_turret_floor`. The Combine's is
   the stock turret (today's metrocop gadget). The Resistance's is the
   citizen-modified one: spawnflag 512, `SF_FLOOR_TURRET_CITIZEN`, which uses
   `models/combine_turrets/citizen_turret.mdl` and skins 1–4
   (`hl2/npc_turret_floor.cpp:270-295`). The dispenser and the teleporters
   are TF2's objects in their team's colour.
2. **Cost.** Building is free. Each engineer has at most one sentry, one
   dispenser, one entrance and one exit, and rebuilds a lost one after a
   cooldown.
3. **Behaviour.** The tree is
   `SquadMonitor > Missionary > ScenarioMonitor > DefenseEngineer | PushEngineer`.
   An engineer is in no squad. The mission takes the place of the doctrine's
   side action, as TF2's `CTFBotScenarioMonitor::DesiredScenarioAndClassAction`
   puts `MISSION_ENGINEER` ahead of the scenario.

Judgment calls in this plan, for the operator to correct:

- **Which mission an engineer runs.** It follows the doctrine's side:
  - `defend` and `defender` run DefenseEngineer.
  - Every other side runs PushEngineer: `attack`, `courier`, `invader`,
    `operative`, and freeform's `attack`.
- **The role.** `AiWar.ENGINEER` is a new role, outside `OFF_ROLES`. Support
  stays off and keeps the manhack. The turret gadget moves from the Combine's
  `SUPPORT` kit to its `ENGINEER` kit.
- **Kits.**
  - Combine engineer: a metrocop with an SMG1.
  - Resistance engineer: a citizen in the `Group03` rebel clothes with a
    shotgun.
- **How many.** `ENGINEERS_PER = 10`: one engineer per ten soldiers on a
  side, at most `ENGINEERS_MAX = 2`, and none on a side below ten. These are
  tuning constants (`T.defined` only).
- **Who teleporters carry.** They carry the team's soldiers and its players.
  Players build nothing yet.

## 1. What exists, and what does not

| Piece | State |
|---|---|
| Turret gadget | `GADGETS.turret`, `features/aiwar/sv_soldier.lua:524`: one per soldier, a hull-checked step toward the target |
| Gadget ownership | `features/aiwar/sv_relations.lua`: `AddGadget`, relations, damage credit, `SweepGadgets` on discharge and round end |
| Hint entities | `bot_hint_sentrygun`, `bot_hint_engineer_nest`, `bot_hint_teleporter_exit`, `func_tfbot_hint` and `func_nobuild` are inert `ws_inert_point` stubs. They keep `enabled` and `team`, but nothing reads them |
| Nav TF attributes | Missing. `nav_convert.py:333` writes sub-version 0 and drops TF2's attribute u32. `nbdebug`'s `NoAttributes` stands in for the sidecar that was planned |
| Posts and the front | `field.posts`, `field.forwardPosts`, `GuardPosts`, `scenario:Front(field, team)`, `Controller:BattleLines` |
| Own spawn | `field.spawns[team]` and `field.bases[team]` |
| Dispenser rates | `mapobj_cart_dispenser.lua`, which uses `tf_obj_dispenser`'s heal and ammo rates |
| TF2 buildings | None |

## 2. Where buildings go

These rules follow TFBot (`tf/bot/behavior/engineer/`). TF2's numbers are
tuning constants in the module that uses them.

**Nest (the sentry).** The first source that answers is used:

1. A `bot_hint_engineer_nest` or `bot_hint_sentrygun` that is enabled, on
   the engineer's team or on none, and not held by another engineer (TF2's
   `IsAvailableForSelection`). The hint is held as a lease (`structs.lease`)
   until the engineer moves its nest.
2. A nav area flagged `TF_NAV_SENTRY_SPOT` (`0x400000`) in the sidecar (§3),
   within the job's reach of the objective.
3. The posts' own candidates (`sv_posts.lua` `CandidateSpots`), scored as
   TFBot's `CollectBuildAreas` scores them:
   - the spot sees the objective,
   - it is not on the point and not more than 150 units below it,
   - it is within the sentry's range × 1.1,
   - it has a clear line of fire from 60 units up.

What changes with the mission:

- **DefenseEngineer** builds against the objective it defends: the next
  checkpoint, the point, or its own flag.
- **PushEngineer** builds behind its side's forward posts. It moves the nest
  once the sentry falls more than 2500 units of travel behind the front
  (TF2's rule).

**Dispenser.** It goes 75 units behind the sentry, away from the objective,
on flat ground (normal z > 0.99), after the sentry, retried every 10 s.

**Entrance.** It goes at the engineer's own spawn exit, on the way out. It is
skipped when the trip from spawn to the nest is 1500 units of travel or less
(`tf_bot_max_teleport_entrance_travel`).

**Exit.** It is retried every 30 s while an entrance stands. The first source
that answers is used:

1. The `bot_hint_teleporter_exit` closest by travel to the nest, within 2500
   units.
2. A spot near the battle line:
   - for DefenseEngineer, its side's posts;
   - for PushEngineer, its forward posts.

The exit is built only when it saves at least
`tf_bot_min_teleport_travel` (3000 units) of travel over walking from the
entrance. TF2's distances may prove too long for GMod's smaller maps. Tuning
belongs to the in-game pass (§6).

**At the nest.** The engineer stands between its buildings and fights from
there. Within reach of a damaged building it repairs it at a rate (no metal),
then rebuilds what was lost after `REBUILD_COOLDOWN`.

## 3. The nav sidecar

`nav_convert.py` writes `maps/<map>.tfnav.txt` beside the converted mesh.
For each area id it records `TF_NAV_PERSISTENT_ATTRIBUTES`
(`tf_nav_area.cpp:785`). The converter keeps area ids, and a test checks
this. The file is text, so GMod can read it from `GAME`.

On the Lua side, `foundation.nav.tf_attributes` parses the sidecar once per
map into `area id → attribute set`: `Has(id, "SENTRY_SPOT")` and
`Areas(attribute)`. It is a gameplay-layer module, because it names TF2.
`nbdebug`'s `NoAttributes` is replaced by it. MvM's needs
(`mvm-pathing-needs`) start here as well. Incursion distances stay outside
this plan.

A map whose mesh was generated (`mp_nav_generate`) has no sidecar, so its
nests come from hints, or from the posts' candidates.

## 4. Modules

Models live in foundation, are pure, and are tested first:

| Module | Job |
|---|---|
| `foundation/nav/tf_attributes.lua` | The sidecar codec and its queries (§3) |
| `foundation/aiwar/engineer.lua` | The model:<br>- the building rules: one of each, cooldowns, rebuild;<br>- the build order: entrance when worth it, sentry, dispenser, exit;<br>- placement as a choice among candidates the controller passes in (hints, flagged areas, post spots, each with its travel distance), returning a spot or a named refusal |
| `foundation/aiwar/buildings.lua` | The dispenser's and teleporter's rules as values:<br>- TF2 level-1 heal and ammo rates;<br>- the teleporter's recharge (10 s);<br>- who a building serves |

Controllers live in `features/aiwar/`:

| File | Job |
|---|---|
| `sv_engineer.lua` (a new `Part`) | Gathers candidates from the hint entities, the sidecar and posts. Leases hints. Spawns and removes buildings through the gadget ledger (`AddGadget` and `SweepGadgets` keep doing ownership, relations, damage credit and cleanup) |
| `sv_soldier.lua` | The port gains `Build(kind, spot)`, `Buildings()` and `Repair(building)`. Each is added to `foundation/aiwar/soldier.lua`'s contract and to `tests/fake_soldier.lua` |
| `sv_enlist.lua` | `ENGINEER` kits for both factions. The turret gadget gets a `citizen` variant for the Resistance |

Entities live in `entities/entities/`:

| Entity | What it is |
|---|---|
| `ws_obj_dispenser` | TF2's `models/buildables/dispenser_light.mdl`, skin by team. It heals and resupplies its team within range, at `buildings.lua`'s rates |
| `ws_obj_teleporter` | `models/buildables/teleporter_light.mdl`, an entrance and exit pair, skin by team. It carries a teammate who stands on a charged entrance |

Model paths and skins are to be checked in game.

Orders live in `foundation/aiwar/orders.lua`:

- `Squad.Kind` answers `missionary` for an engineer.
- `SquadRole("missionary", "Missionary")` contains a ScenarioMonitor whose
  side action is the mission, so the debug path reads
  `.../SquadMonitor/Missionary/ScenarioMonitor/DefenseEngineer/<job>`.
- Its jobs are `BuildNest`, `BuildTeleporterEntrance`,
  `BuildTeleporterExit` and `TendNest`.
- `TacticalMonitor` still comes first: an engineer under fire fights, and
  retreats if it is losing.

**Soldiers using teleporters.** A trip takes a detour through a charged
entrance when two things hold: the entrance is within `TELE_DETOUR` of the
soldier, and walking from the exit to the goal saves `TELE_MIN_GAIN` over
walking from the soldier.

**Seeing it.** Each of these is a follow-up line in its own step:

- The nbdebug overlay draws buildings and their owner, and with `ns_engineers_debug`
  the candidates that were refused.
- `ns_engineers_print` prints each engineer's nest, its buildings and the last
  refusal.

## 5. Steps

The work is one stream, done in order (see `feedback-focus-parallelism`).
Each step ends with `.devtools/bin/check_lua.sh` green and a commit.

1. **The sidecar.** `nav_convert.py` keeps the attributes, with a Python
   test round-tripping a fixture `.nav`. `foundation.nav.tf_attributes` is
   written test first. `nbdebug` reads it.
2. **Hints read.** The hint entities expose enabled, team and kind through
   the controller's candidate gathering. `func_nobuild` volumes refuse spots
   inside them.
3. **Buildings.** The rules in `buildings.lua`, the two `ws_obj_*` entities,
   and the citizen turret variant. Checked in game by spawning each by hand.
4. **The engineer model.** `engineer.lua`, test first: the build order,
   placement precedence and every refusal (no candidate, hint held, too
   little travel saved, inside `func_nobuild`).
5. **The mission.** `ENGINEER` with its allocation in `foundation/aiwar.lua`
   and the scenario stances; kits; `Missionary`, `DefenseEngineer`,
   `PushEngineer` and their jobs; `sv_engineer.lua`. The orders tests cover
   the tree path on each doctrine's sides.
6. **Teleporter use and reporting.** The detour, the overlay and the console.
   Then the in-game pass:
   - pl_ and cp_ maps with hints;
   - one map without a sidecar;
   - one generated mesh;
   - TF2's distances tuned.

## 6. In-game checklist

- On a payload map, each side has its engineers (one per ten soldiers, at
  most two), shown under `Missionary` in TDBN.
- A BLU (pushing) engineer builds an entrance at the spawn exit, and an exit
  and nest behind the forward posts. It moves them as the cart advances
  2500 units past them.
- A RED (defending) engineer nests at a `bot_hint_sentrygun` where the map
  has one. Otherwise it nests at a `SENTRY_SPOT` area, then at a post spot
  that sees the checkpoint.
- The Resistance's sentry is the citizen turret and fires on the Combine;
  the Combine's fires on the rebels. Neither shoots its own team.
- Teammates heal at the dispenser, and soldiers and players ride the
  teleporter. Enemies are neither healed nor carried.
- A destroyed building credits its killer in the feed, and is rebuilt after
  the cooldown. Everything is swept at round end and when its engineer is
  discharged.
- No new per-tick cost shows in `ws_profile`: placement runs on the
  scheduler, not every tick.
