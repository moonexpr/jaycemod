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
3. **`sv_next_soldiers.lua`'s soldier** still plans in its look with the
   engine's search. Move it onto the same `PlanRoute` and `MeshSearch`, which
   belong in `features/npc/bot_steering.lua` beside `StandOnRoute`, not in
   the war's class.
4. **A fixed benchmark.** One saved 8v8 scenario (`dev.scenario.save`),
   replayed several times a condition, so before and after are the same
   fight. Every comparison in §2 lacks this. Beside it, the pass line
   (§8.6): a saved 16v16 scenario on the operator's MacBook Pro (M1 Pro),
   the war's p99 a tick under 10 ms and no tick over 15.
5. **The searches' slice overruns.** With a body's fit asked as a Lua rule,
   one step of a search took up to 15.7 ms against its 2 ms slice (a cold
   hull trace an area and a link, sixteen expansions between looks at the
   clock). Body fit as data on the mesh (§5.1) removes it; until then a
   smaller step for a request with a body would bound it.
6. **Asking costs the look 0.7 ms.** `RequestRoute` finds the nearest areas,
   refreshes the blockers and consults the reach memo before it queues. It
   could queue first and do those in the searches' slice.

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
2. §5.2's calendar in foundation (§8.3's policy), Lua twin first, then the
   looks and the route plans moved onto it.
3. §5.1's mesh columns, the room column first, then body fit as data.
4. The look split into its jobs, the sight pass made native.
5. `docs/places-plan.md`'s room graph and occupation on §5.1.
6. §5.3, a problem at a time.

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
