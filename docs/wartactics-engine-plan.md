# War tactics engine: review, what was done, and the restructure

A handoff, written 2026-11-11, for whoever continues: the operator or an
agent with none of the session behind it. It records what a review of the
tactics engine found, what was changed and measured, what is left of that
work, and the plan for the restructure the operator wants to discuss next.

Nothing in §5 onward is built. The operator has agreed to its direction in
conversation, not to its details; §8 records his answers to the questions
it left open.

## 1. What the review found

The code under `addons/wartactics/` is a library, not an engine.

- `wartactics/` is about 3,900 lines of stateless modules. Only `intel`,
  `hazards`, `mission` and the scenario registry construct anything, and
  none of it has a clock.
- The state and the tick are in `features/aiwar/`, about 12,500 lines: 40
  parts writing some 80 fields onto one controller table, driven by seven
  separate `Think` and `Tick` hooks, each with its own interval
  (`sv_field.lua` 0.25 s, `sv_intel.lua` 1 s, `sv_bots.lua` 0.2 s a bot, ...).
- A squad's state is ad hoc: about 40 fields (`missionWanted`, `sprung`,
  `stackedAt`, `breachAt`, ...) written onto fire-team tables from the
  controller, the orders and the tactics modules alike.
- The nav mesh is copied several times: the engine's own, the
  `wetsands.navsearch` snapshot, the room graph `sv_rooms.lua` builds, the
  incursion's densely numbered graph, and about a dozen side tables keyed by
  area id (doors, hazards, blockers, spawn rooms, shut doors). `Classes()`
  builds the whole room graph again, traces included, that `Rooms()` built.
- "Rooms" means two things: in `navsearch` the spawn rooms by team, in
  `wartactics.rooms` the partition of the map.

## 2. What it costs, measured

`.devtools/bin/aiwar_tick_probe.lua` (`WarProbe.Start(60)`, then `Summary`,
`Hooks`, `Methods`) wraps the controller, the bot soldier and the war's
hooks for a window. All figures: cp_dustbowl, bot players, single 60 s runs
of different fights, so differences under about 30 ms/s are noise.

| | 7 soldiers | 8v8, before | 8v8, after §3 |
|---|---|---|---|
| War, all hooks | 129 ± 10 ms/s | 265 ± 13 | 284 ± 11 |
| Route searches (`Think/ws_npc_spawners`) | 0.9 ms/s | 0.8 | 15.7 |
| War in a tick, p99 | not taken | 29.7 ms | 15.4 |
| War in a tick, worst | not taken | 63 ms | 31 |
| Ticks over 30 ms, of 4,001 | not taken | 138 | 58 |

The searches' row is outside the war's: the bots' routes moved there from
the looks, so the two rows together are what compares, about 300 ms/s
against 266. The tail is what improved, not the total.

The tick is 15 ms. What the measurements say:

- **The mean is linear in soldiers** (about 18 ms/s a bot). Nothing grows
  faster than that.
- **The trouble at 8v8 was the tail.** A wave's bots all looked in one tick
  (8 looks of about 1.5 ms), and any of them could plan a route in it.
- **Room lookups are not a runtime cost.** Every `navmesh.GetNearestNavArea`
  on the server together was 0.3 ms/s. Unifying rooms with the mesh is worth
  doing for structure (§5.1), not for the tick as it is today.
- **What is left is steady, per bot:** `Drive` (the keys, every tick: about
  100 ms/s at 8v8), the look's sight traces, steering along the route, and
  the field survey (`Survey`, 17 ms/s: rebuilt four times a second though
  what it reads changes on game events).

Older baselines: `docs/ns-performance-baseline.md` (15v15, NPC soldiers and
the first bot leg), `docs/combat-repath-optimization.md` (the repath stall,
now measured and addressed by §3).

## 3. What was changed

On `main`, pushed. Each has its tests, written first.

| Commit | What |
|---|---|
| `5ab19a13` | `dev.reload` reloads feature roots again (the reformat had broken its adoption of the live controller) |
| `4c333a7a` | `aiwar_tick_probe.lua` |
| `d84019b8` | Looks spread over the ticks (`features.aiwar.looks`); the map's buildings and monsters kept a look's interval (`sv_fighters.lua`); routes priced natively; the whole route plan run off the look on `Controller.plans`, a `list.schedule` at 2 ms a tick |
| `d13ac5d5` | Nav ladders in `wetsands.navsearch`, both twins |
| `defab284` | The map's ladders in the mesh snapshot, a walker's body as a search rule, ladders as waypoints |
| `9b027a3b` | A bot's routes come from the war's own asynchronous search (`npcs:RequestRoute`); `ns_bots_routes_engine 1` keeps the engine's for comparison |
| `5635c827` | No navigator entity is made for a bot that plans on the war's own search |
| `ba389f6f` | The fixed benchmark (`aiwar_bench.py`) and its 16v16 scenario; scenarios load bot soldiers |
| `a113c8a` (`addons/sandcastle`) | Route searches keep to their slice; a route's points laid out in the planning time |

## 4. What is left of that work

1. **Done 2026-11-11: `gmsv_wetsands` rebuilt, the dev server restarted on
   it.** Start it with `dt srcds start --gamemode wetsands --map <map>`: the
   default gamemode is the base `sandcastle`, which has no war. A server
   elsewhere needs the same rebuild before it loads a map with nav ladders,
   or every route search on that map fails at the mesh snapshot.
2. **Bots climbing a ladder in play is not yet seen.** Checked in game on the
   rebuilt module: cp_dustbowl at 8v8 (every bot with a goal on a route, no
   navigators, no errors), and on de_nuke the search itself (12 ladder links
   laid from its 5 ladders; a climber's route goes foot, head, goal up one,
   a walker that climbs none is refused it). A war on de_nuke stayed between
   rounds (its defuse scenario gave the bots no goals), so no bot walked a
   ladder route. Walk one map more with a round running, then delete the
   engine path: `ns_bots_routes_engine`, `BotSoldier:EngineSearch`,
   `RouteCost`, `Navigator`, `PrepareRoutes`, and the `ws_bot_navigator`
   entity. A bot's body has no ladder handling of its own: it walks the two
   points and relies on a player's own climb.

   The map to check it on is gm_construct_13_beta (the operator, 2026-11-12):
   it has ladders, and some need a crouch to get on or off. That is the
   body's to handle (`nextsoldier.body.player_body`), not the war's. Today
   the body ducks only on a nav crouch area under its feet
   (`sense.crouchArea`), under a lintel it senses ahead, or in a crouch jump.
   On a ladder it stands on no area, so none of those fire. A climb wants
   the duck held while the ladder's top or bottom opens onto a crouch area,
   or while the headroom past the rung is under a standing hull.

   **Run-jumps, from the systems there are** (the operator, 2026-11-12: no
   run-jump model of its own). The case is cp_steel's last point, which the
   attackers can capture and the defenders cannot reach: their routes run
   into its glass instead. What exists to build it from:
   - `nextsoldier.world.nav_gaps` finds pairs of areas a seam apart (up to
     `GAP_MAX`, a sample step or two) with where to cross, and the server
     sweeps a walker across before it links them (`ws/sv_nav.lua`). A
     run-jump is the same candidate at a run's reach, its sweep an arc, its
     link marked a jump;
   - the path costs already price a jump (`wetsands.path`'s
     `JUMP_PENALTY`, the walker's own in `native/wetsands`), so a marked
     link is priced without a new rule;
   - `nextsoldier.body.player_body` jumps when its orders ask (`sense.hop`)
     and crouches in the air after (`CROUCH_JUMP_TIME`). What it lacks is
     arriving at the lip at a run: not at a walk, facing the landing, the
     hop pressed at the lip's edge and not before.
   Still to find out on cp_steel: whether the defenders' way to the point
   is a gap or a ledge, and why their routes cross the glass (a window the
   rooms count as a passage, or a link through it priced as open).
3. **`sv_next_soldiers.lua`'s soldier** still plans in its look with the
   engine's search. Move it onto the same `PlanRoute` and `MeshSearch`, which
   belong in `features/npc/bot_steering.lua` beside `StandOnRoute`, not in
   the war's class.
4. **Done 2026-11-12: the fixed benchmark** (`ba389f6f`).
   `.devtools/bin/aiwar_bench.py --save NAME` saves a warmed war as a
   scenario; `--scenario NAME --conditions "a=convar 0;b=convar 1"` replays
   it for each replication and condition in turn (a b b a ...), measures a
   window with the probe's hooks alone, and reports each condition as the
   mean of its replications with a 95 % t interval, and the pass line (§8.6)
   on every replication. The scenario is
   `.devtools/scenarios/cp_dustbowl/aiwar_bench_16v16.json` (32 bots, 29
   alive when saved). 16v16 needs a server of 33 slots or more (the quota
   keeps one free): `srcds.py start --gamemode wetsands --map cp_dustbowl
   --maxplayers 34`. The baseline, five replications, asynchronous search:

   | 16v16 | async | engine |
   |---|---|---|
   | War | 453 ± 53 ms/s | 486 ± 18 |
   | Route searches | 22 ± 9 ms/s | 0.8 ± 0.3 |
   | A tick, war and searches, p99 | 29.4 ± 3.4 ms | 30.4 ± 1.8 |
   | A tick, worst | 50 ± 4 ms | 71 ± 33 |
   | Ticks over 15 ms, of about 2,000 | 181 ± 43 | 190 ± 25 |

   The pass line fails by about three times, as §8.6 foresaw: at this size
   the tick is the war's own time, not the searches'. On time, the two
   searches show no difference (§8.5's parity on routes found and bots
   stuck is not measured yet: the bench has no such count).
5. **Done 2026-11-12: the searches keep to their slice** (`a113c8a` in
   `addons/sandcastle`). The smaller step for a request with a body
   (`features.npc.search_step`) went in first and was not shown to help:
   timed live, the steps were bounded (max 0.5 ms) but the answer was not.
   A route's points (`RouteWaypoints`) were laid out in the search's task in
   one go, p99 2.4 ms and up to 10.7 ms. They are laid out now in the war's
   planning time, giving way between areas (`plan:Lay`): the searches' p99
   a tick fell from 3.9 to 2.0 ms (their 2 ms slice), their time from 22 to
   13 ms/s. That work moved into the war's share (502 ± 11 ms/s); the
   tick's p99 shows no difference. Body fit as data (§5.1) is still what
   removes the traces.
6. **Asking costs the look about 13 ms/s at 16v16.** Timed live: 535
   requests in 30 s (31 bots, about one route a bot every 1.7 s), p50
   0.45 ms, p99 3.7 ms. `RequestRoute` finds the nearest areas, refreshes
   the blockers and consults the reach memo before it queues; it could
   queue first and do those in the searches' slice. How often a bot asks
   (`REPATH_LEAST`, `REPATH_MOST`) is the other lever.

Known gaps in the workbench, found on the way:

- `WS.require` on a feature root (`features.aiwar.sv`) silently builds a
  second controller and rebinds every hook to it. It should refuse.
- `dev.reload` replaces a class a feature part returns (`BotSoldier`) but
  leaves live instances on the old one. It patches module classes only.
- The dev server is running Lua newer than the map it booted: a module
  indexed since (`system.names`) had to be published by hand. A `changelevel`
  makes it consistent.

## 5. The restructure

What "engine" should mean here, in the operator's words: a simulation over
the nav mesh and the rooms' geometry, annotated with live targets (enemies,
health kits, other things worth noting), solving stated problems (assigning
work to squads, solo missions, each team's occupation), run inside the
Source engine's tick but doing only a bounded amount of work in any one.

Three layers, bottom up.

### 5.1 The world model: one mesh, with columns

One sealed mesh with dense area numbers, which `native/wetsands`'s `NavMesh`
already has, and everything known of an area as a column on it: room,
passage, spawn-room team, door, hazard, body fit by hull. Then:

- the mesh is read from the engine once a map, not once for the searches and
  twice more for the rooms and their classes;
- "which room is this area in" is an array read on both twins;
- a search prices a step from data alone, with no Lua rule asked (today a
  bot's body fit is still a Lua rule an area and a link);
- it is the base `docs/places-plan.md` wants: the room graph, lanes routed
  through rooms, occupation by room.

Over it, one annotation store by room for what is live, replacing the five
places that hold it now (`intel`, `marks`, `hunt`, `camps`, `Fighters`):
each note a kind, a team that knows it, a place, when it was learned and how
long it is believed.

A table of which rooms see each other, computed once a map, would let a
look skip the trace to an enemy whose room is hidden from its own. How many
traces that saves is not measured.

### 5.2 The work buffer: a formalism in foundation

The operator's design: the engine runs at the tick but takes a limited
amount of work from a buffer each time. A soldier's look need not run every
0.2 s: it fixes its attention on one thing and looks again when its
attention span runs out.

`list.schedule` is half of it already: cooperative tasks sharing a slice of
time, with a native twin. It models one-off tasks, first in first out, and
carries a `TODO` for a sorter the caller supplies. What recurring work needs
is a sibling formalism, with no game nouns:

- **a calendar of jobs** on `tree.heap`: each a period, a priority and when
  it is next due;
- **a budget a tick**, by count or by time, the most overdue of the highest
  priority first;
- **lateness as output**: each job's delay past its due time, so a starved
  budget is a number to read and not a hitch to feel.

`features.aiwar.looks` (`Share`, `Due`) is this policy for one kind of job
and would be replaced by it. So would the seven hooks' private intervals.

A look today is five jobs under one timer, and they want different periods:
sight on the current contact (often), a scan for new ones (seldom), a
repath (on need: goal moved, stalled), the weapon and ammunition checks
(every few seconds), the nav area under its feet.

Where Rust pays is not the scheduling, which is small in either language:

1. a job whose body is native never enters Lua (as `LOOK_AT` runs in Rust
   today, Lua only configuring it);
2. sixteen bots each testing range and view cone against sixteen enemies is
   one native pass over arrays, with only the survivors needing a trace,
   which stays on the engine's side;
3. §5.1's room visibility as a prefilter for that pass.

By the project's rules it is a Lua twin (the oracle, what clients run) and a
whole native twin, the same tests in both passes, a `Twin` index line.

"Asynchronous" here is cooperative, not threaded: no worker threads is the
operator's decision of 2026-10-29 (`docs/native-foundation-plan.md`).

### 5.3 The decision problems

Stated as problems over the model, solved on the slow lane, each answer a
transaction: assigning squads to missions, solo missions, occupation by
team (`docs/places-plan.md` §2.2: claims weighed, with hysteresis). A
squad's state becomes a value the engine owns, not fields scattered on a
fire-team table.

### 5.4 Simulation methods the operator asked to be considered

| Method | Where it fits |
|---|---|
| Next-event simulation | §5.2's calendar: work happens when it is due, not when a hook polls. `Survey` is the first candidate: points, carts and gates change on events |
| Monte Carlo | §5.3: a mission's outcome rolled forward on the room graph a few hundred times before a squad is committed |
| Random number generation | Seeded streams a team and a purpose, so a simulation replays and two policies are compared on the same draws |
| Discrete random variables | Which of the best few missions a squad takes (`math.weighted` exists) |
| Continuous random variables | Travel and fight durations in the roll-forward |
| Sample statistics, output analysis | The benchmark: batch means with a confidence interval, as the probe reports now; replications of one saved scenario (§4.4) |

## 6. A suggested order

1. §4.1 to §4.4: finish and verify what is in flight, with the benchmark.
   Done but §4.2 (a bot seen on a ladder) and §4.3; the bench still lacks
   §8.5's count of routes found and bots stuck.
2. Done 2026-11-12: where the war's time goes at 16v16 (the probe's
   `Methods`, 30 s on the benchmark's scenario, 458 ± 25 ms/s; inclusive,
   so nested rows overlap; `.devtools/artifacts/aiwar_probe_16v16.txt`):

   | Where | ms/s | Calls | Mean |
   |---|---|---|---|
   | `Drive`, a bot's keys every tick | 158 | 57,383 | 83 µs |
   | `Look` (within `LookAround`, 170) | 136 | 4,102 | 1.0 ms |
   | of which `Steer` | 51 | 4,102 | 372 µs |
   | The planning time (the bots' `Think` less `LookAround`) | about 52 | | |
   | The controller's `Think` | 43 | 2,001 | 642 µs |
   | of which `Fighters` (every tick) | 18 | 1,977 | 277 µs |
   | of which `Survey` (four times a second) | 17.5 | 118 | 4.5 ms |
   | `Tick/ws_aiwar_move` | 17 | 2,001 | 261 µs |

   `Drive` profiled (§8.1): 65 to 95 µs a call in the tick. NextSoldier's
   `player_body` `Command` is 27 µs of it and builds a new output table
   each call (0.57 KB); gathering the senses is about 13 µs warm and more
   in the tick; in all `Drive` allocates 1.38 KB a call, 3 MB/s.

   What it means for the order: the war is 6.9 ms in every tick on
   average. A calendar spreads work and cannot lower that mean, and the
   pass line's p99 under 10 ms leaves about 3 ms for everything uneven. So
   the total must come down as well as be spread: `Drive` at 10 to 20 Hz
   with the last command replayed (§8.1; its turn and aim, cheap, could
   still run each tick) is the largest single cut, then the look's split
   (step 5). The calendar (step 3) still comes first, since it is what
   gives `Drive`'s lower rate and the look's jobs their places.
3. §5.2's calendar in foundation (§8.3's policy), Lua twin first, then the
   looks and the route plans moved onto it. Built 2026-11-12: `list.calendar`,
   both twins (`tests/list_calendar_test.lua`, both passes). A job's answer
   sets its next time (nil: its period, phase kept; seconds: an attention
   span; false: done); `Wake` brings one sooner (a repath on need). Not yet
   built on: the looks, the route plans and the hooks' intervals are still
   their own.
4. §5.1's mesh columns, the room column first, then body fit as data.
5. The look split into its jobs, the sight pass made native.
6. `docs/places-plan.md`'s room graph and occupation on §5.1.
7. §5.3, a problem at a time.

## 6a. The controller split into its parts' objects (for review)

The operator, 2026-11-12: the war's controller (`features/aiwar/sv.lua`)
is bloated; plan a refactor before any code. Nothing here is built.

### What it is now, measured

The root table declares 72 fields, written and read by 26 `sv_*` parts
(8,030 lines, 209 `Controller:` methods), driven by seven `Think` and `Tick`
hooks. How the fields are used:

- **26 are shared**, read by two parts or more: `war` (16 parts),
  `soldiers` (13), `scenario` (10), `gates` (6), then `rooms`, `bench`,
  `paused`, `winner`, `laneSets`, `shutDoors`, `baseCache` (4 each),
  `doorFlags`, `nextRelations`, `losers`, `lanePlans`, `zones`,
  `postCache`, `waitingFor` (3), and `bots`, `intel`, `swapFactions`,
  `heroes`, `roomExits`, `scenarios`, `behaviors`, `scenarioEntry` (2).
- **The other 46 are one part's own**, nobody else reads them. Each
  such part is an object whose state is laid on the controller.
- **About ten of those are hand-rolled timers**: a `next*` time a `Think`
  checks against `CurTime()`, each with its own interval.

| Part | Its own fields | Its timers, and what drives them |
|---|---|---|
| `sv_hazards.lua` | `hazardStore`, `footAreas`, `hazards`, `hazardsSaved`, `newlyDisabled`, `separationCheck`, `separationAgain`, `hazardsApplied` | `separationAgain` |
| `sv_obstacles.lua` | `cartBounds`, `trains`, `doorOpened`, `openedDoors`, `shutDoorStamp`, `shutDoorAreas` | `DOOR_OPEN_INTERVAL` 1 s |
| `sv_field.lua` | `tracks`, `cartEntities`, `waypointCache`, `nextThink`, `nextWatch` | its `Think`: `THINK_INTERVAL` 0.25 s (`Survey`), `WATCH_INTERVAL`, `RELATIONSHIP_INTERVAL` 1 s |
| `sv_bots.lua` | `plans`, `calendar`, `lookFighters`, `lookFightersAt`, `botSerial`, `nextQuota` | its `Think`: the quota 1 s; the looks (on the calendar, uncommitted) |
| `sv_slots.lua` | `slots`, `slotStore`, `slotViewers`, `slotSignature`, `nextSlotSync` | `SLOT_SYNC_INTERVAL` 0.5 s |
| `sv_classes.lua` | `classes`, `classesFinding`, `classesFailed` | none (a transaction on the slow lane) |
| `sv_rooms.lua` | `roomStore`, `roomsFinding`, `nextRoomsDebug` | `ROOMS_DEBUG_INTERVAL` 5 s |
| `sv_marks.lua` | `marks`, `nextMarkReport` | `ENEMY_EVERY` 2 s |
| `sv_lanes.lua` | `musterStore`, `musters` | none |
| `sv_relations.lua` | `gadgets`, `monsters` | `HEAR_INTERVAL` 0.5 s |
| `sv_probe.lua` | `probes`, `probeReport` | a `timer` |
| `sv_report.lua` | `nextDebug` | `DEBUG_INTERVAL` 0.5 s |
| `sv_commands.lua` | `tuner` | none |

Parts with no fields of their own but a hook on the clock:
`sv_intel.lua` (`Think`, `INTEL_INTERVAL` 1 s), `sv_gestures.lua`
(`Think`, `CALM_INTERVAL` 0.5 s), `sv_responserules.lua` (two `Think`s,
`GREET_INTERVAL` 0.5 s), `sv_enlist.lua` (`Tick`, `ws_aiwar_move`).

### The shape proposed

1. **A part with fields of its own becomes an object of its own.** Its
   state is one table on the controller (`Controller.hazards`), its
   methods those of a class the part file returns (`Hazards`), and the
   root declares one field for it in place of its several. What it needs
   of the rest it is handed when made (the controller's shared fields it
   reads, the calendar), as `Part (...)` hands parts their arguments now.
   The 26 shared fields stay on the root: they are what a controller is
   for.
2. **Its timers become calendar jobs in the same change.** Each `next*`
   field and the `Think` that tests it go; the object adds its job to
   `Controller.calendar` under a system of its own, with its interval as
   the period. That is §6's step 3 for the hooks' private intervals, done
   a part at a time. A job's work that changes on events (`Survey`, §5.4)
   can later be `Wake`d by the event instead of polled.
3. **A live reload keeps the state and takes the new methods.** The root
   keeps each object's table across a reload (`Controller.hazards =
   Controller.hazards or Hazards.New (...)`), and sets its metatable to the
   part's class as it loads, every time. Without that line, a reload
   leaves the live object on the old class, the gap §4 records for
   `BotSoldier`. A test holds it: every object field the root declares is
   re-pointed in the root.
4. **The checks that hold it.** `tests/feature_parts_test.lua` (h) already
   refuses a field a method assigns that the root does not declare; an
   object's own fields are then declared in its class, and (h) is pointed
   at classes too. Each part's own tests move with it.

### The order

One part a commit, each with its tests first, run through the war group
and checked live with `dev.reload`:

1. `sv_bots.lua`'s looks (`lookFighters`, `lookFightersAt`, and the
   calendar's looks system): the change in flight, and the smallest.
2. `sv_hazards.lua`: the most fields (8), one timer, few readers.
3. `sv_slots.lua`, `sv_marks.lua`, `sv_report.lua`, `sv_rooms.lua`'s debug:
   a timer each, small.
4. `sv_obstacles.lua`, then `sv_field.lua` with its `Think` (the `Survey`,
   the largest timer by cost, §6.2).
5. The hooks with no state: `sv_intel.lua`, `sv_gestures.lua`,
   `sv_responserules.lua`, as jobs only.
6. What is left on the root is then measured again against the 26.

### Questions for the operator

- The systems' weights: one system per part, or a few by kind (sight,
  field, talk, debug), so §8.3's scan stays over four or five?
- `sv_enlist.lua`'s `Tick` (the moves, every tick, 17 ms/s at 16v16): a
  calendar job with the tick as its period, or left on its hook as
  `Drive` is (§8.1)?
- The looks change is in the working tree, not yet committed: tests pass
  (the war group at its known 38 failures), not yet checked live. That
  needs a Windows `gmsv_foundation` (`cargo xwin build --release --target
  x86_64-pc-windows-msvc`) and the dev server restarted on it. Commit it
  first as it is, or fold it into step 1 above?

## 7. Pitfalls met in this work

- Run the `features` group after any change to a bot soldier:
  `tests/nbdebug_contract_test.lua` holds its source text.
- `cargo fmt` reformats the whole of `native/wetsands` (there is no
  `rustfmt.toml`, and the code is wider than its default). Do not run it.
- `sv_bots.lua` is near the 600-line limit for a realm file.
- The checks have failures that are not this work's: 38 in `war tooling`, 34
  in `foundation features`, 10 in `nextsoldier`, from the split of the
  gamemode into Sandcastle and Wetsands and from the MvM tests. Compare
  against those counts.
- A measurement on the dev server changes it. Check that the war is
  thinking (`C.nextThink` close to `CurTime()`) before believing a number.
- Since 2026-11-12 (`d0edcd23`) the addons are submodules, each its own
  repository under moonexpr: a change to the gamemode is committed in
  `addons/sandcastle` and pushed there, then the superproject's pointer is
  committed with the tests (they stay in the superproject's `tests/`).
- The war's feature loads only once a war starts (`mp_aiwar_start`):
  `WS.FeatureLoaded ("aiwar")` is false on a fresh map until then.
- The probe's window is the server's time: at 16v16 the server runs behind
  its ticks, and a 30 s window takes 35 to 40 s of ours.

## 8. The operator's answers, 2026-11-11

The questions this section held, answered in conversation. Each is now the
plan's direction; its details are still to be written where it is built.

1. **`Drive` is NextSoldier's.** The tactics engine decides what a bot is
   to do; driving its keys is the body's (`nextsoldier.body.player_body`
   already holds a bot player's moves, aim and fire as keys). The cost stays
   the largest steady one, so NextSoldier's driving takes a share of the
   tick's calendar as a system of its own (point 3), or its peaks land in
   the war's ticks from outside. Before it moves, profile it: about 95 µs a
   call is much for pressing keys. A usercmd is due every tick, but what
   steering computes need not be: computed at 10 to 20 Hz and the last
   command replayed between is the likely saving.
2. **No threads, for the sight pass too.** Not raised against, so it
   stands; correct it here if not. Sixteen bots' range and cone tests
   against sixteen enemies are microseconds of arithmetic; the cost is the
   traces, which stay on the engine's thread whatever is decided.
3. **One calendar, fair across systems, earliest deadline within.** Neither
   one flat queue (the looks would starve the transactions) nor a buffer a
   system (no system would know what the others spent, and their peaks
   would meet in one tick, as the 8v8 tail did). The policy:
   - each system (the war, the route searches, the transactions,
     NextSoldier's driving) has a weight and a virtual runtime, charged its
     actual spend over its weight, and a tick serves the one furthest
     behind: the group fairness of Linux's CFS. With four or five systems
     this is a scan, not a tree;
   - within a system, its periodic jobs on `tree.heap` by due time, the
     earliest first (EDF), as §5.2 has it;
   - lateness is reported a job and a system.
   CFS alone was considered and not taken: it shares among tasks always
   ready to run, and has no notion of a job not yet due, which is most of
   ours. Nor is it needed for O(log N): the heap already is, and at tens to
   hundreds of jobs the bound is not where the time goes. Being
   cooperative, the calendar charges a job only after it overruns, so its
   fairness holds only for jobs bounded by construction (§4.5).
4. **The calendar first, with §4.5's stopgap now.** Lateness as output makes
   every later change a number to read. The calendar cannot bound one
   search step of 15.7 ms, so the smaller step for a request with a body
   goes in at once, until body fit as data (§5.1) removes the cause. Both
   wait on §4.4's benchmark: with single runs and noise of about 30 ms/s,
   neither could be shown to help.
5. **The engine path is deleted once three things hold, not on maps
   walked by eye:** a bot seen climbing a ladder route with a round running
   (§4.2); the benchmark's scenario showing the asynchronous search at
   parity with the engine's on routes found and bots stuck, not only on
   time; and `sv_next_soldiers.lua`'s soldier moved off the engine's search
   (§4.3), which still uses `RouteCost` and `Navigator`. Then it goes whole,
   switch and all: a comparison nobody runs only rots.

6. **The target is 32 bots, 16 a team, on the operator's MacBook Pro
   (M1 Pro), without the server slowing to a crawl.** The pass line is
   §4.4's benchmark on a saved 16v16 scenario: the war's p99 a tick under
   10 ms, and no tick over the 15 ms tick. At about 18 ms/s a bot (§2), 32
   bots are some 580 ms/s, near 9 ms of every tick before searches or
   spikes, so at this size the restructure is for the tick, not only for
   its structure. Play quality (how soon a soldier sees a new enemy,
   objectives taken) is out of this pass: it is tuned by other means, and
   §5.2's attention span is judged here by its cost alone.
