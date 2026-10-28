# NextSoldier performance baseline (2026-10-16)

What a 15v15 AI war costs the server today, and what causes the cost,
before NextSoldier and the tactics engine take on more behaviour. This
identifies causes only; solutions are for a later discussion.

## Setup

- Dedicated server (CrossOver bottle GModServer, port 27025), pl_upward,
  66 ticks/s (15 ms tick budget), no players.
- AI war at `mp_aiwar_team_size 15`: 30 soldiers (15 Combine; 13 rebels and
  2 vortigaunt medics).
- Mid-game state: BLU owns cap_1 (minecart_path_44's OnPass outputs fired);
  the cart teleported to minecart_path_74, 272 u short of cap_2, the middle
  point. 18 of 30 soldiers fought within 1500 u of the cart.
- Tools: `.devtools/bin/profile_server.lua` (wraps hooks, entity methods,
  feature controller methods, module functions and NS actions; self and
  inclusive time per coroutine, worst single call), plus one-off probes run
  through `server_lua.py`, each named below. Wrapper overhead was measured at
  0.4 µs per call; `SysTime` costs 0.16 µs under Wine.

## Where the time goes (default settings)

| Cost | Size | Shape |
|---|---|---|
| Lua route search (`Think/ws_npc_spawners`, `ThinkSearches`) | 0.2 to 4.3 ms per tick | follows demand; saturated, it spends its 2 ms budget and overshoots to 3 to 4 ms |
| AI war think (`Think/ws_aiwar`): soldiers' behaviour trees and the controller | 1.4 to 1.9 ms per tick | steady; the trees are about 60 % of it |
| Cart riders (`aiwar:CarrySeated`, in `Tick/ws_aiwar_move`) | 0.4 ms per tick | steady, twice a tick |
| Respawn (`Reinforce` → `Draft` → `Enlist` → `RelateToFactions`) | 80 to 200 ms in one tick | hitch at every respawn wave |

Process CPU (`stats`, Wine overhead included): about 65 % with the full war.

## Hypotheses and tests

Each was stated before its experiment, with the result that would refute it.

| # | Hypothesis | Experiment | Result | Verdict |
|---|---|---|---|---|
| H1 | The search queue is full because requests are many, not because searches are big | A: every request's fate and size for 60 s | 25 requests in a quiet window (0.2 ms/tick); the queue never emptied in busy windows | Supported: demand comes in bursts |
| H2 | Most expansions belong to failed searches that hit the cap | A | 2 of 3198 expansions failed; none hit the cap | Refuted |
| H3 | Engine calls in `FillStep` make an expansion expensive | B: 12 captured real requests replayed with each part timed; engine calls benchmarked | Engine calls 0.05 to 0.3 µs each; warm replay 19 to 46 µs per expansion against about 100 to 200 µs live | Refuted as the main cause |
| H6 | Cold caches (neighbours, centres, spawn rooms) slow live searches | D: replay with each cache cleared | Neighbours and centres: no change; spawn rooms: ×2, but it clears only at round changes | Refuted for steady play |
| H7a/b | GC or the JIT explains the replay's run-to-run spread | E: interleaved rounds, blocked by JIT on and off | GC on 20 µs, off 12 µs per expansion; JIT on and off alike when warmed | GC is a minor share; JIT not decisive in replay |
| H9 | Under live conditions the GC makes searches slow | F: live, GC on and off in 15 s blocks (ABAB), injected load | 99.5 / 101.2 / 101.6 / 96.3 µs per expansion | Refuted |
| H10 | The big hitches are GC atomic phases | F: long ticks against memory drops | 6 of 9 long ticks came with GC stopped; 2 of 9 with a drop | Refuted |
| H11 | Round-robin 16-expansion steps are slow in themselves | Replay round-robin against whole searches | 15 to 18 µs either way | Refuted |
| H12 | Live, the JIT makes the Lua slower | G: whole-server JIT on and off, 15 s ABAB blocks | On 97.2 / 116.5 µs per expansion, off 21.5 / 23.2; tick p95 36 / 35 ms on, 18 / 18 off; CPU 79 / 92 % on, 55 / 48 % off | Supported |
| H12a | The JIT thrashes because it runs out of capacity (traces, machine code) | I: defaults, then capacity ×8 (`maxtrace`, `maxmcode`, `maxrecord`, `maxside`, `maxsnap`, `sizemcode`), then less eager, then defaults again | 68.2 → 24.3 → 34.4 → 86.9 µs per expansion; it reverses when the defaults return | Supported |
| H12b | The JIT thrashes on aborted recordings, not capacity | I (less eager: `hotloop` 300, `hotexit` 60) | Helps (34.4) but less than capacity (24.3) | Weaker; fits capacity pressure |
| — | The capacity effect holds for the natural war, not only injected load | J: natural war, defaults against capacity ×8, 20 s ABAB | War think 123.4 / 114.8 ms/s on the defaults, 58.4 / 77.0 with capacity | Supported: the war's main cost halves |
| H5 | The `ws_aiwar` hitch is one periodic controller task | K: controller methods timed with worst call | Worst calls: `Think` 219 ms ⊃ `Reinforce` 197 ⊃ `Draft` 127 (mean 83) ⊃ `Enlist` 95 (mean 57) ⊃ `RelateToFactions` 50 (mean 28); 23 respawns a minute | Supported: respawning is the hitch |

GMod disables LuaJIT's introspection (`jit.attach`: "vmevent API disabled";
`jit.util.traceinfo` returns nil), so H12a rests on intervention, not on a
trace count. The values restored after experiments I and J are LuaJIT
2.1's stock defaults; GMod's own are not readable, and a map change resets
the VM in any case.

## Control: what NextSoldier itself costs

Your proposed control (map loaded, no units) also removes 30 NextBots'
engine work (locomotion, animation, physics, sensing) and DrGBase's AI, so
it can't separate NextSoldier from having units at all. Experiment L holds
the 30 bodies and the scenario fixed and removes only NextSoldier's
decisions: every soldier's behaviour tree stops updating and its steering
targets are cleared, so DrGBase's own AI drives the same bodies. Respawns,
cart riding and the rest of the controller keep running. 20 s blocks,
alternating:

| Block | War think | Movement | Search | Tick p95 | CPU |
|---|---|---|---|---|---|
| full | 60.1 ms/s | 5.7 | 221.6 | 29.9 ms | 64 / 66 % |
| NS ablated | 10.0 | 38.8 | 83.8 | 18.3 | 46 / 43 % |
| full | 67.0 | 8.0 | 224.6 | 29.1 | 65 / 65 % |
| NS ablated | 8.4 | 21.3 | 197.1 | 18.8 | 56 / 47 % |

So NextSoldier's decisions are about 15 to 20 points of the server's
roughly 65 % CPU, and they take the slow-tick p95 from about 18 ms to about
29 ms. Search demand is that of whole queued searches; it fell in the first
ablated block and stayed high in the second while the backlog from the full
block drained. Movement rose when ablated: DrGBase's own chasing moves the
bodies more.

Not yet run from the control design: the think-rate dose (×1, ×½, ×¼ at a
fixed unit count) and the unit-count dose (6, 10, 15 per team). They would
give the cost per soldier and whether it grows faster than linearly, which
matters before adding behaviour.

## Conclusions (identification only)

1. **The JIT's capacity is the largest single factor.** With LuaJIT's
   default limits the server's Lua runs several times slower than it can:
   the route search 3 to 5 times, the war's think about 2 times. Raising
   capacity, or even turning the JIT off, beats the defaults. Every Lua
   system pays this, so new NS behaviour will make it worse.
2. **Route search is the largest demand-driven cost.** Saturated, it spends
   3 to 4 ms of each 15 ms tick: its 2 ms deadline is checked only between
   16-expansion steps, and one step costs 1.5 to 3.3 ms live (worst 17.7 ms).
3. **NextSoldier's decisions are about a quarter to a third of the server's
   CPU** at 15v15 (control L), mostly in the behaviour trees (`Travel`,
   `StrategyMonitor`, `TacticalMonitor`) and the search they ask for.
4. **Respawning causes the hitches**: 80 to 200 ms in one tick per respawn
   wave, in spawning the DrGBase entity, enlisting it, and setting its
   DrGBase faction relationships.

Smaller items: `CarrySeated` at 26.5 ms/s; `Soldier:Blocker` at 9.6 ms/s over
17.5k calls. `query ShouldHurry` shows 23 to 42 µs per call in play against
1 to 2 µs in a benchmark; that gap is unexplained but small (about 1 % of a
core). A vortigaunt's `OnDeath` (287 to 430 ms) is not a cost: it pauses its
coroutine for the ragdoll handoff, and the profiler counts the pause.

## Sampling profiler (wsprofile)

`native/ws_profile` builds `gmsv_wsprofile_win64.dll`. It drives LuaJIT's
sampling profiler (`luaJIT_profile_start`), which GMod's `lua_shared.dll`
exports though no GMod Lua library exposes it, and counts samples natively by
VM state and by stack. `foundation.core.analytics` (`SampleReport`,
`FormatSamples`) turns the counts into a report, and `ws_analytics_sample
<seconds>` runs a window and prints it. Nothing is wrapped, so tiny hot
functions are measured without the wrappers' distortion.

**How to read it.** The profiler samples wall-clock time on the server
thread at a steady ~665 Hz: 39,620 samples in 60 s with the war running,
9,970 in 15 s with the soldiers paused. A sample taken while the server is
outside Lua (engine C++, physics, NextBot locomotion, Wine, idle between
ticks) is charged to the next Lua entry point, the hook dispatcher
(`lua/ulib/shared/hook.lua:98`). So that frame's own share is time outside
Lua, and every other frame is Lua's share of the server thread, C calls it
makes included.

- **H16 (refuted):** the dispatcher's large own share is compiled listeners
  inlined into its trace. With the JIT off it grew, from 22.9 % to 53.9 %.
- **H17 (supported):** it is time outside Lua. Paused soldiers, prediction:
  it rises. It rose from 22.9 % to 59.9 %, and the sample rate stayed fixed.

| Condition | Lua's share of the server thread | VM states |
|---|---|---|
| 15v15, JIT on (defaults) | about 77 % | C 51.5, compiled 23.8, interpreted 18.1, JIT compiler 4.2, GC 2.4 |
| 15v15, JIT off | about 46 % | C 85.0, interpreted 12.0, GC 2.9 |
| soldiers paused, JIT on | about 40 % | C 87.7, interpreted 5.5, compiled 4.4, GC 1.7, compiler 0.8 |

The JIT compiler itself took 4.2 % of the server thread during the war: the
first direct sight of the JIT's own work, which experiments G to J only
inferred.

Where Lua's time goes (15v15, JIT on, share of the server thread):

| Inclusive | Path |
|---|---|
| 22.7 % | Lua route search: `ThinkSearches` → `Step` → `Expand` (17.9) → `Relax` (13.5) → `Cost` (7.0) → `FillStep` (4.0); the heap's `Pop`/`Before` 3.2 |
| 17.3 % | DrGBase entity think (`shared.lua:233`): aiming (`GetShootPos`), animation, `ShouldRun` → NS `Query` |
| 10.0 % | AI war controller think (`sv_field.lua:Think`): behaviour trees 6.2, respawns (`Reinforce`/`Draft`) 4.1 |
| 8.7 % | DrGBase behaviour coroutine → `OnIdle` → `NSSteer` → `FollowPath` (6.9) → the engine's path compute with our Lua cost (`path.lua:75`) |
| 4.1 % | DrGBase `UpdateRelationshipWith` |
| 4.0 % | DrGBase detection (`detection.lua:173`, `SpotEntity`) |
| 2.3 % | cart riders (`CarrySeated` → `SetPos`) |

## Treatments A and B: a 2×2 experiment

- **Treatment A**, `mp_aiwar_revive_enabled 1` (now the default; the old
  remove-and-respawn pattern is `ns_use_regular_spawns 1`)
  (`features/aiwar/reserve.lua`, `sv_reserve.lua`): a soldier the respawn
  system drafted that falls while waves run lies dormant (`NSRest`, hidden
  and not solid, its DrGBase death coroutine held before the removal), and
  the next wave revives the same entity (`NSRevive`) instead of creating
  one. Admins' and players' soldiers die as before.
- **Treatment B**, `ws_jit_enabled 0` (`ws/sv_jit.lua`): LuaJIT's compiler
  off for the whole server.

Run with `.devtools/bin/experiment_2x2.lua`: 15v15 at mid-game on
pl_upward, 60 s blocks in ABBA order (control, A, B, AB, AB, B, A, control),
the first 10 s of each block left out, CPU sampled twice per block. Times in
ms.

| # | Cond. | Tick p95 | >50 ms ticks | Deaths | Drafts (revived) | Draft mean / max | Worst wave | Lua share | CPU |
|---|---|---|---|---|---|---|---|---|---|
| 1 | control | 54.4 | 284 | 32 | 29 (0) | 58.5 / 115 | 331 | 92.7 % | 100.7 / 89.2 |
| 2 | A | 38.1 | 131 | 20 | 22 (22) | 44.6 / 77 | 163 | 84.8 % | 94.0 / 99.3 |
| 3 | B | 17.3 | 19 | 15 | 15 (0) | 53.3 / 82 | 142 | 42.6 % | 45.8 / 48.2 |
| 4 | AB | 50.8 | 232 | 18 | 17 (17) | 35.3 / 70 | 107 | 60.7 % | 47.2 / 68.6 |
| 5 | AB | 17.4 | 24 | 13 | 14 (14) | 47.2 / 62 | 177 | 42.8 % | 45.8 / 46.3 |
| 6 | B | 18.6 | 123 | 14 | 15 (0) | 58.0 / 113 | 143 | 50.4 % | 46.7 / 75.6 |
| 7 | A | 37.2 | 46 | 12 | 11 (11) | 55.7 / 66 | 130 | 63.2 % | 70.7 / 52.3 |
| 8 | control | 35.9 | 28 | 5 | 5 (0) | 83.0 / 92 | 93 | 66.6 % | 71.1 / 80.9 |

By condition (mean of its two blocks; drafts weighted by count):

| Cond. | Tick p95 | Lua share | CPU | Draft mean |
|---|---|---|---|---|
| control | 45.2 | 79.7 % | 85.5 | 62.1 |
| A | 37.7 | 74.0 % | 79.1 | 48.3 |
| B | 18.0 | 46.5 % | 54.1 | 55.7 |
| AB | 34.1 | 51.8 % | 52.0 | 40.7 |

- **B is the large effect**, as G to J found: Lua's share of the server
  thread falls from about 80 % to about 47 %, CPU from about 85 % to about
  54 %, and the tick p95 from 45 to 18 ms. With the JIT off the VM runs
  interpreted (9 to 14 %), never compiled.
- **A makes a respawn about a quarter cheaper**: a draft costs 48 ms
  against 62 with the JIT on, and 41 against 56 with it off. Every draft in
  the A and AB blocks was a revive (64 of 64). A revive still costs 35 to
  56 ms, so most of a respawn's cost is not the entity's creation. It is
  `Enlist` (relationships, slot, squad, orders), which experiment K measured
  at 57 ms with `RelateToFactions` 28 of it. Waves still hitch for 100 to
  180 ms.
- **Interaction:** none clear. A's saving looks similar on both JIT
  settings.
- **Caution:** the fighting tapered off over the session (32 deaths in the
  first block, 5 in the last). ABBA cancels steady drift, but two blocks
  per condition settle only the large effects. Block 4 (AB, 232 long ticks)
  and block 6 (B, 123) are outliers the treatments don't explain.

## Treatment A2: a revive that keeps what the body already has

Question: can a respawn wave cost less by using the body as it is (moved,
shown, NextSoldier's main action restarted) instead of setting it up again?

**Step costs in one revive** (60 s, revives on, 4 drafted soldiers killed
every 8 s; 35 drafts, every one a revive):

| Step | Mean | Max |
|---|---|---|
| Draft (all of it) | 34.85 ms | 74.4 |
| `Revive` (reserve, `NSRevive`: move, show, death flags, fresh behaviour coroutine) | 0.23 | 0.93 |
| `Enlist` | 34.60 | 74.1 |
| `RelateToFactions` | **33.67** | 72.9 |
| `PassTeammates` | 0.81 | 1.3 |
| `war:Enlist`, `slots:Fill`, `Soldier.New`, `Npc.New`, `WS.SetTeamMember`, `JoinSquad` | under 0.05 each | |
| `Discharge` at death (all of it) | 0.08 | 0.23 |

Moving the body, showing it and restarting NextSoldier's main action is
already cheap; 97 % of a revive is `RelateToFactions`. DrGBase's
`SetFactionRelationship` records the rule and then `UpdateRelationships`,
which walks every entity on the map (`ents.GetAll`), once per faction. The
rules live on the entity and don't change while it is dormant.

**The leak this exposed.** `PassTeammates` makes a `logic_collision_pair`
for the soldier and each living teammate, and the pairs go only when an
entity is removed. A revived body is enlisted again but never removed, so
every life added pairs: 2,706 of the map's 3,860 entities after a few
minutes of treatment A, which made every `ents.GetAll` walk (the
relationship pass included: 34 → 99 ms) dearer.

**A2**:
- `RelateToFactions` keeps on the soldier the dispositions it last gave it
  (`NSRelations`) and calls DrGBase again only when they differ: a new
  soldier, another team, or the losers changed.
- `PassThrough` keeps one pair per two soldiers (`NSPasses`).

Result (same load, 60 s):

| | Control | A | A2 |
|---|---|---|---|
| Draft mean | 62 ms | 48 ms | **0.25 ms** (max 0.5) |
| Revived | 0 | 64 of 64 | 37 of 37 |
| Relationship passes | every enlist | every enlist | 37 skipped (0.008 ms), 0 full |
| Collision pairs / entities | | 2,706 / 3,860 and growing | **210 / 1,365, stable** (2 × C(15, 2) = 210) |

All 51 revived soldiers checked in an earlier run still hated a live enemy,
were hated back, and liked a teammate. No Lua errors.

## Treatment B, closer: which code the JIT slows

`wsprofile` sampled four 60 s windows, JIT on, off, on, off (10 s warm-up
each). Samples come at a fixed wall-clock rate, so a function's sample count
is its time. Lua's share of the server thread replicated: 79.1 and 81.9 %
on, 45.8 and 46.9 % off.

Own time (self samples per 60 s window), JIT on against off:

| Slower with the JIT | On | Off | × |
|---|---|---|---|
| `route.lua:Expand` | 1957 | 70 | 28 |
| `route.lua:Relax` | 1978 | 229 | 8.6 |
| `route.lua:Pop` / `Before` / `PopOpen` | 883 / 738 / 411 | 61 / 69 / 20 | 14 / 11 / 21 |
| `sv_routes.lua:Cost` / `Center` | 1193 / 372 | 435 / 74 | 2.7 / 5 |
| `hfsm.lua:Query` / `_InvokeUpdate` / `_IsOutOfScope` | 498 / 425 / 299 | 36 / 19 / 5 | 14 / 22 / 66 |
| `orders.lua:_InvokeUpdate` | 367 | 18 | 21 |
| `lanes.lua:Cost` | 329 | 80 | 4.1 |

| Faster with the JIT | On | Off | × |
|---|---|---|---|
| `path.lua:75` (the engine's path compute calling our cost) | 1811 | 2665 | 0.7 |
| DrGBase `awareness.lua:SpotEntity` | 396 | 1022 | 0.4 |
| DrGBase `detection.lua:173` | 411 | 690 | 0.6 |
| DrGBase `movements.lua:FollowPath` | 988 | 1160 | 0.9 |

Inclusive: the Lua route search 10,956 on against 2,737 off (×4); the war's
think 2,344 against 259 (×9).

**H18 (selective JIT beats both):** the JIT on, but off (`jit.off(fn,
true)`) for the 213 functions reachable from route, hfsm, orders, lanes, npc
and the npc controller, local helpers included. Six 60 s windows, ABCCBA:

| Mode | Lua share | Tick p95 | p99 | >50 ms ticks per min | Search | NS think | DrGBase think | DrGBase detection |
|---|---|---|---|---|---|---|---|---|
| on | 63.7 % | 34.7 | 47.2 | 22 | 4719 | 2869 | 6217 | 4112 |
| selective | 42.4 % | 19.0 | 25.2 | 7 | 424 | 596 | 5056 | 4732 |
| off | 40.8 % | 17.3 | 20.0 | 2 | 527 | 247 | 5137 | 5322 |

Refuted, narrowly: the selective JIT takes about 94 % of the gain of turning
it off, but off stays best on every tick measure. NextSoldier's think is
still 2.4× its interpreted time under the selective JIT, so more of our code
(the war controller, tactics) thrashes outside the modules picked. DrGBase
nets about even: the JIT helps its detection but slows its think.

## Treatment C: what batching route searches could share

Before building batched solvers, this measures how much requests could share.
Every Lua route request was captured for 180 s at the same mid-game, after
the 2×2 experiment: its source, team, start and goal nav areas, when it was
asked and answered, its expansions, and whether it found the goal.

The soldiers' route cost (`npc.path.hl2` → `tfbot`) is additive per step and
does not depend on the soldier: they ask for the fastest route, so the
per-soldier scatter (`entIndex`, `now`) drops out, and `fromCostSoFar` is
only the running total. It depends on the team (spawn rooms, a round won),
the limits, and `avoid` (under the cart, doors shut to the team). So
requests of one team to one goal area could share a single search back from
the goal, which gives every start its exact best route. The independent
groups are therefore the distinct (source, team, goal area) keys.

| Measure | Result |
|---|---|
| Requests | 144 (0.8 per s): soldiers 121, lane legs 23, gates 0 |
| Expansions | 113,230: soldiers 85,892 (about 710 each, 3 not found); lanes 27,338 (about 1,190 each, **19 of 23 not found**) |
| Sharing, same goal key | 1 s windows: 1.5 requests for 1.4 keys (1.07×); 5 s: 4.2 for 3.1 (1.35×); 15 s: 12 for 5.7 (2.1×) |
| Sharing, goals within 256 / 768 u | 3.1 / 2.6 clusters per 5 s window (against 4.2 requests) |
| Independent groups at once | up to 4 searches running, never sharing a goal key: 4 solvers would cover the peak |
| Re-plans | **41 of 121** soldier requests (34 %) were the same soldier asking for the same goal area again within 5 s |
| Request to answer | median 0.15 s, p90 2.0 s, worst 5.1 s |

- Grouping by shared goal saves little at this load: about 1.1× within a
  second, about 1.35× within 5 s.
- The larger savings are elsewhere: a third of soldier searches repeat one
  the same soldier asked moments before, and lane legs spend a quarter of
  all expansions mostly failing.
- **Limit:** the fighting had quietened by then (see the 2×2 caution).

### A busy phase: the 120 s after a round restart

Captured from `mp_round_restart`, each soldier re-plan tagged by its
`Travel:Plan` call site.

| Measure | Result |
|---|---|
| Requests | 123 (1.0 per s): soldiers 60, lane legs 63 |
| Expansions | soldiers 18,232 (10 not found); **lanes 106,423, 86 % of all (51 of 63 not found)** |
| Why soldiers asked | **all 60 were stuck re-plans** (`Unstick`); none for a new trip, none for a moved goal |
| Sharing | first 20 s (the respawn burst): 35 requests for 13 goal keys (2.7×); after: 1.10× per 1 s, 1.24× per 5 s |
| Independent groups at once | up to 4 searches, never sharing a goal key |
| Request to answer | median 0.18 s, p90 4.8 s, worst 6.2 s |

- **Soldiers ask for a route only once stuck:** they walk straight at
  their goal (`Chase`) and turn to a route when that fails. So soldier
  demand follows how often they get stuck.
- **H19 (lane legs fail behind the shut setup gates): refuted.** They kept
  failing at a steady rate until t = 100 s, well after setup.
- **H20 (the stops can't be reached under the lanes' own rules): supported
  for most of them.** 43 of 51 failed legs (84 %) end inside the enemy's
  spawn room, which TF2's bot cost makes impassable to the team, so each
  search spends everything reachable (about 2,000 expansions) before failing.
  Of the other 8, BLU kept aiming at two areas (5289 and 13944) for a reason
  not yet found. None was off the mesh, in a door wall or under the cart.
- **For sizing solvers:** 4 independent searches at most, even in the
  respawn burst. Sharing by goal is worth up to 2.7× only in that burst. The
  larger savings are not sending lane legs at stops that can't be reached,
  and fewer stuck soldiers.

## Lanes: planned once, kept until a change that lasts touches them

Lanes have purposes and keep them: direct and flanks come at the objective,
and tours go round through the enemy's defenses to its spawn, pushing the
battle lines back and undoing the defenses. The cost was in planning them,
not in their purposes.

**What drove re-planning** (120 s mid-game, every `PlanLanes` with its
trigger): all 21 plans were "blockers changed". The blocker generation rose
from 7 to 47 in two minutes, once every 3 s, because the set of blocked nav
areas changes whenever a door opens or shuts anywhere. Each time, both teams
planned all five lanes again.

**What made planning costly:** a stop the team's route cannot reach, inside
the enemy's spawn room (TF2's bot cost makes it impassable), so the leg's
search spends everything reachable before giving up. Not only tours: on
payload a defender's front is the enemy cart, which starts deep inside the
attackers' spawn room, so RED's direct lane and both flanks aimed there too.

Attempts, each measured the same way (120 s from `mp_round_restart`,
`.devtools/bin/capture_routes.lua`):

| | Lane plans | Legs | Not found | Lane expansions | Stops in enemy room |
|---|---|---|---|---|---|
| baseline | (21 per 120 s mid-game, all from blocker churn) | 63 | 51 | 106,423 | 43 of the failures |
| 1st: stale only on a change in the band or a wall; tours end at the spawn threshold | 23 (20 blockers) | 157 | 133 | 145,586 | 70 |
| 2nd: walls count once open WALL_SETTLE; any stop in the room moves out | 16 (12 blockers) | 116 | 100 | 106,125 | 33 |
| 3rd (kept): every watched area's change must last CHANGE_SETTLE; the threshold search widens | **7 (5 front moved, 2 first)** | **42** | 30 | **76,510** | **0** |

Why the first two fell short, found by testing each guess:

- **Band too wide for door flicker.** Lanes start at the team's own spawn,
  and the attackers' spawn doors lie in the defenders' band (their lanes head
  for the attackers' spawn exit). Every door cycle in a band counted as a
  change. Fixed by snapshotting each watched area's blocking when the lanes
  are planned and counting a difference only once it has lasted
  `CHANGE_SETTLE` (5 s, `Lanes.Settled`): a door that stays shut across a
  lane, or a setup gate that stays open, re-plans; a spawn door that opens
  and shuts again does not.
- **No threshold in reach.** `navmesh.Find` floods out from the stop over the
  mesh; from the cart's start, all 114 areas within 1,500 units of travel
  were in BLU's spawn room. The search now widens to 3,000, then 6,000
  units, and each stop area keeps its threshold for the round
  (`OutsideRoom`, `roomExits`).
- Refuted along the way: that the thresholds were cached before the rooms
  had their teams (H21, all three were outside their rooms); that the
  remaining failures were BLU's behind its setup gates (H22: those were few).

**Kept:** `foundation.aiwar.lanes` `Settled`, `CHANGE_SETTLE`, `Threshold`
(tested); `foundation.npc.doors` `Changed` (tested); the npc controller's
blocker change log (`NoteBlockerChange`, `BlockerChangesSince`, `DoorWalls`,
`AreaBlocked`); the AI war's `BlockersStale`, `OutsideRoom`.

**Still open:**
- **A door judged a wall that isn't one.** `door_mid_exit1`, at RED's spawn,
  is opened by map logic through something the door model does not follow
  (no trigger it can see opens it), so while shut it is a wall. Lanes avoid
  walls, so RED's lane searches then stay in RED's spawn: cheap (42
  expansions each) but lane-less until the next plan. The fix belongs in the
  door model: follow indirect openers, or judge a door a wall only once it
  has stayed shut.
- A few legs still search widely before failing (about 4,000 expansions),
  among them BLU's to area 5289, the other unexplained stop.
- A one-line race fixed on the way: a round restart dropped the lane plans
  while a leg's search ran, and its callback indexed them (Lua error).

**Item 3, short queries back onto the lane, not built.** A lane leader
already walks its lane waypoint by waypoint, and when stuck re-plans to the
next waypoint, about 300 units ahead (`Travel:LaneTarget`, `Unstick`), so
the short query back onto the lane exists. Soldiers without a lane job ask
for routes only when stuck (all 16 requests in the last capture), and they
spent 4,228 expansions against the lanes' 76,510, so a change there would
gain little now.

## Lanes: would small deltas pay? Which legs a re-plan repeats

Question: a payload step moves the front a little, so could a re-plan add or
remove waypoints instead of routing every lane again? `capture_routes.lua`
now tags each lane leg with why its plan ran, its lane's kind, its leg, and
whether it starts and ends within 64 u of the same leg of the team's last
plan (the legs a re-plan could keep as they are).

Mid-game, 300 s, no restart (8 plans, all front moved): 86,140 lane
expansions. Tours' legs that failed: **55,852 (65 %)**; direct and flank legs
found: 15,463 (18 %); legs with the same ends: 6 of 62. A small-delta
re-plan would save little; the cost was legs that cannot succeed.

**The failures were stops in pockets.** A tour's last stop is the enemy
spawn's threshold (`OutsideRoom`). For BLU it was area 6376, outside RED's
room but one of two areas that only the room leads into; later 6425, in a
31-area region that BLU enters only by climbing 97 to 150 u (soldiers step
18 u and do not jump). RED's 4972 and 415 were in a 28-area pocket of BLU's
room. Each search spent everything reachable (about 4,000 expansions) before
failing, at every re-plan. Found by testing, in turn, that the stop is in no
room and under no door wall, that no route rule (lanes or plain HL2, nothing
avoided) reaches it, that the bare graph does, and then which edges the
height rule cuts.

**Fix:** a threshold must be open to the field: `Lanes.Enclosed` floods back
from a candidate through areas outside the room that a soldier can walk into
it from (`Path.Walkable`, the climb and drop rule the cost functions now
share) and calls it a pocket when fewer than `POCKET_LIMIT` (128) lead in.
`Lanes.Threshold` asks it nearest first.

After, 300 s from `mp_round_restart` (14 plans: 9 front moved, 3 blockers,
2 first): lane expansions 92,503; tour leg 2 (post to spawn) on front moves
12,712 (31,745 and 51,937 in the runs before), its failures 2 of 18, and
RED's tours into BLU's spawn found every time. Legs with the same ends:
front moved 12 of 63 (14,160 expansions, 15 %), blockers changed 14 of 21
(20,343). Direct and flank legs never keep their ends (their stops move
with the front).

**What remains, by size:** BLU's tours to RED's post area 13944 fail at
about 4,400 expansions each (22,188, 24 %), likely another post that only a
jump reaches; keeping legs whose ends are unchanged would save about 15 %;
splicing direct and flank lanes onto the moved front at most about 8 %.

## Soldiers jump and crouch

Soldiers could only step 18 u, and every TF2 crouch or jump area was
closed to them: pl_upward has 230 climbs of 18 to 72 u between nav areas,
and 66 crouch areas, 41 of them too low for a standing soldier. Now
(`foundation.npc.path.hl2`): a soldier's route climbs up to
`SOLDIER_JUMP_HEIGHT` (56 u, an HL2 player's crouch jump) and crosses crouch
and jump areas; DrGBase's own path to each waypoint climbs the same ledges
(`ClimbLedges`), and the soldier jumps them along `foundation.npc.leap`'s
arc. It crouches in a crouch area (`OnNavAreaChanged`).

Found by experiment on the live server:
- A NextBot's hull does not catch on a low ceiling, so a soldier only needs
  to crouch for its model; its collision bounds stay as they are.
- A physics jump (`loco:Jump`, then velocity set in the air) pushed at the
  wall hits its face and falls back: 23 of 92 landed. The arc is set each
  tick instead, as DrGBase moves its own climbs, after checking the way
  straight up and across to the landing (a hull from step height, inset
  2 u). Tracing every step from where gravity had pulled the body hit the
  wall face; the hull's lowest corners dug into sloped floors.
- With the checks: every jump taken landed (14 of 14, then 7 of 7); a
  jump is declined when a wall or another soldier stands where it would
  land (5 of 12), and not tried again for a second.

Lanes after (300 s from `mp_round_restart`): 65,501 expansions (92,503 before
jumping); tours' second legs never failed. Soldiers' stuck re-routes were
93 (46 to 50 in the runs before), not yet explained.

## Tools considered: gmod_perfutils

[wrefgtzweve/gmod_perfutils](https://github.com/wrefgtzweve/gmod_perfutils)
(no license, so none of it can be copied into this repo; its ideas can be
reimplemented). Three of its scripts were run on a live 15v15, 15 s each,
from a copy in `.devtools/artifacts/perfutils/`.

| Script | What it measures | Here | Verdict |
|---|---|---|---|
| `sh_hookperf`, `sh_sentperf`, `sh_physobjperf` | time per hook, entity method, physics method, by `SysTime` wrappers | what `profile_server.lua` already does (coarse mode) | not needed |
| `sh_indexcounter` | entity `__index` calls by origin | top: `IsValid` 164,738 (its skip of `IsValid` doesn't catch these, so they're charged to `util.lua` itself), DrGBase `weapons.lua:35` 68,000, our per-tick move loop (`sv_enlist.lua:344`) 30,000, `ws_pickup_base` 30,000, `func_respawnroomvisualizer` 54,000 | new, but small: about 0.5 % of a core |
| `sh_garbage` | `Vector`/`Angle`/`Color` created by origin | about 700 per s, mostly `sv_soldier`/`sv_map` | negligible next to GC's 2.4 % |
| `sh_gcperf` | KB allocated per hook and entity method (`collectgarbage("count")` before and after) | hooks: route search 12.2 MB, the war's think 9.4 MB, the move tick 4.5 MB in 15 s (matches experiment E's 1.5 KB per expansion); entity methods: unusable (DrGBase's `YieldCoroutine` "2.94 GB", 3.2 GB in all against about 50 MB held) | the idea is worth keeping, its numbers are not: a yield puts others' garbage in the after reading, nested wrappers count it again, and calls during a collection are dropped |
| `sh_netperf`, net logger, net dumper | net messages received: bytes, time | not run: these tests have no players | useful once clients join |

**Verdict:** not as an addition. Most of it duplicates our tooling, and
its garbage numbers are wrong exactly where our costs are (in coroutines).
Two ideas are worth building in: allocation per top-level hook (outermost
calls only, no coroutines, so the figures hold), and, once clients are in
the tests, net message cost.

## Treatment D: route searches replayed offline, and what failed searches teach

Measuring a route-search change no longer needs a live war.
`.devtools/bin/record_routes.lua` (through `server_lua.py`) records each Lua
route search with what its graph answered (areas untraversable, links
uncrossable, spawn rooms, estimates, as engine floats) and saves the mesh;
`.devtools/bin/route_replay.lua` replays the recording under plain LuaJIT
with the gamemode's own A* and cost strategies (`foundation.npc.route_record`).

**Parity.** pl_upward, 120 s from a round restart, 47 searches: 47 replay
exactly (status, expansions, route). Offline an expansion costs 4 µs, against
about 100 µs live with the JIT on.

**What the searches were** (same recording): 28,783 expansions, 25,575 of them
(89 %) in failed searches, none at the cap: each ran out of areas, walking
the whole region its start reaches (42, 243 and 4,413 areas). 35 of 42 lane
legs failed, and so did all 3 soldier searches. 35 of the failed searches
share 14 start and goal pairs.

**Demand has moved.** Soldiers now chase with DrGBase's own path planning
(`orders.lua`: a soldier port that `PlansRoutes` chases), so the Lua search
serves mostly lane planning, which runs once per team and again only when a
lasting change touches the lanes (above). A 180 s mid-game recording held no
Lua route search at all; treatment C's 41 of 121 repeated soldier requests
are gone. A memo of found routes, keyed by request and checked step by step
before reuse, was built and replayed against both recordings: no hit, at a
5 s or a 30 s term, so it was not kept.

**The reach memo** (`foundation.npc.reach_memo`, in `sv_routes.lua`'s
`RequestRoute`, `ns_routes_reach`): a failed search that ran out of areas
has walked exactly the region its start leads to. A later request from
inside it to a goal beyond is answered from the region's area nearest the
goal (where the search would have come closest): by the failed search's
own way there when the start is the same, else by a search to that area. A
region is used only while every refusal at its edge (an area closed to the
asker, a link it cannot cross) still holds for the new asker. It survives
blocker changes, which only open or close areas and so show in that check,
but not a change to the mesh's links (`BlockerChangesSince` returns nil).
Keying regions on the blockers' generation instead threw away the same
243-area region four times in the first 15 s, as setup's doors moved.

Replayed against the restart recording (`route_replay.lua --reach 30`): of
42 lane legs, 22 answered without a search (14 with exactly the route the
search found) and 6 sent to a nearer goal, **none wrong** (no goal called out
of reach that the live search reached); 3,186 of the 28,783 expansions saved
(11 %). The 4,413-area failures are the largest: sent to the region's nearest
area, a search costs 1,208 and 2,239 expansions instead of 4,413. Live, an
earlier build answered 24 requests and sent 18 to a nearer goal in about 20
minutes. A live A/B against the restart was attempted and gave nothing:
after the first plans, restarts asked for no lane legs, and later the war
stopped drafting soldiers at all (not traced; the route search is not on
the drafting path).

**Where route cost sits now.** The soldiers' per-link hook (`OnComputePath`
in `ws/sh_war_soldier.lua`, inside DrGBase's path compute, the profile's
`path.lua:75`) asks `WS.NavLinkCrossable` (already cached by link) and
`NSAreaClosed`, which walks every shut door the war noted, with an
`IsValid` each, for every link a path weighs. A per-team cache of closed
areas, renewed with the blockers' generation and the shut doors, is the next
candidate; its cost was not measured yet.

## Native foundation against the Lua twins (2026-10-27)

Every foundation module now has a whole native twin on the server
(`docs/native-foundation-plan.md`). `.devtools/bin/aiwar_ab_bench.py` runs
the same war with the DLLs installed and without them, in alternating
legs: pl_upward, 15v15 (30 soldiers), JIT on with its defaults, a fresh
map and war each leg, 90 s of warm-up, then 60 s measured. Instance 1, on
port 27025, after a host OS update; the A/B is the comparison that holds,
since the earlier sections' numbers predate that update.

| Leg | CPU | FPS | Tick p50 / p95 / p99 / max | Ticks later than 1.5 intervals | Lua's share of the server thread | VM states |
|---|---|---|---|---|---|---|
| native | 63.7 % | 64.5 | 14.4 / 35.8 / 69.2 / 278 ms | 395 of 4052 | 58.9 % | C 72.2, interpreted 15.1, compiled 9.3, compiler 1.9, GC 1.5 |
| Lua | 80.9 % | 45.7 | 12.3 / 42.4 / 72.0 / 391 ms | 483 of 4058 | 78.4 % | C 51.3, compiled 23.3, interpreted 19.4, compiler 4.2, GC 1.8 |
| native | 54.7 % | 54.4 | 14.5 / 36.2 / 68.6 / 100 ms | 374 of 4054 | 56.3 % | C 72.8, interpreted 14.5, compiled 9.3, compiler 1.9, GC 1.5 |
| Lua | 77.3 % | 39.7 | 12.8 / 39.5 / 68.2 / 760 ms | 436 of 4008 | 76.8 % | C 50.1, compiled 25.1, interpreted 18.7, compiler 4.2, GC 1.9 |

Averaged over the two legs of each:

- **Process CPU: 59 % native against 79 % Lua**, 20 points, a quarter less.
- **Lua's share of the server thread: 58 % against 78 %.** The Lua leg
  matches the October baseline's 77 %.
- **Slow ticks: p95 36 against 41 ms, 385 against 460 late ticks** (16 %
  fewer). The p99 is unchanged at about 69 ms, and the worst tick fell
  from 391 and 760 ms to 278 and 100 ms. The median tick reads a little
  higher natively (14.5 against 12.5 ms), which fits fewer late ticks
  each followed by a short catch-up tick (not checked).
- **The JIT's own work halves** (compiler 4.2 % to 1.9 %): less Lua to trace.
- Lua memory at the window's end: 41 and 35 MB against 44 and 39 MB.

Where the Lua leg's time went, and what is left natively (inclusive share
of the server thread, the mean of each leg's two windows):

| Path | Lua | native |
|---|---|---|
| Route search: `sv_routes.lua:313` (`pathfinder` `Step`, `Expand`, `Relax`; `navsearch` `Cost`) | 14.5 % | gone from the top 25 |
| The behaviour engine: `state_chart` `_InvokeUpdate`, `orders` | 8.4 % | gone from the top 25; `nextbot.lua:Update` 7.6 → 4.4 % |
| AI war controller think (`sv_field.lua:Think`) | 8.1 % | 5.2 % |
| DrGBase entity think (`shared.lua:403`, `233`, `HandleEnemy`) | 19.0 % | 19.4 % |
| `FollowPath` → the engine's path compute with a Lua cost (`path.lua:75`) | 9.8 % | 10.7 % |

What the native foundation took is what foundation ran: the route
search and the behaviour engine. What is left is DrGBase's entity think
and the engine's `Path:Compute`, whose cost function is Lua and is called
per area. Neither is foundation's code, so the port could not reach them;
the cost callback is the next candidate (a native cost, as
`wetsands.path`'s `Model` gives the route search).

## The soldiers' path cost, natively (2026-10-27)

DrGBase's path generator (`path.lua:75`, a Lua closure the engine's
`Path:Compute` calls once per link) was the largest piece of foundation-shaped
work left on the thread. Soldiers now hand the engine
`wetsands.navsearch.Calculator` instead: the strategy their routes are
planned with (HL2Path at `SOLDIER_LIMITS`), priced natively over the
team's told tables, the engine asked only area ids and the cost so far.
Live, 16 soldiers' computes to the same goals took 29.6 ms with the
calculator against 84.2 ms with DrGBase's generator.

The same bench, two native legs, against the morning's two native legs:

| | Before | With the calculator |
|---|---|---|
| Path compute (`path.lua:Compute`, inclusive) | 10.7 % of the thread | 3.8 % |
| DrGBase's generator (`path.lua:75`) | 10.7 % | gone |
| Tick p95 / p99 | 36 / 69 ms | 34 / 44 ms |
| Late ticks (of about 4050) | 395, 374 | 334, 354 |
| Process CPU | 63.7, 54.7 % | 58.9, 62.0 % |

Process CPU moves as much between legs of one kind as between kinds here, so
it shows no change. The tail ticks show the gain.

## DrGBase's NPCs against bot players (2026-10-27)

With foundation native, DrGBase's entity think was most of the Lua left on
the thread. The war's soldiers can be bot players instead
(`ns_soldiers_actor bot`, f2eaa19, 74316fc), which use none of DrGBase. The
bench now takes the soldiers per leg (`native:npc`, `native:bot`); bot legs
set `tf_bot_join_after_player 0`, as no human is on the server. pl_upward,
15 a side, 90 s warm-up, 60 s window, native in every leg. Three NPC legs
(one from a run whose bot leg failed before that setting) and one bot leg;
the second bot leg's server died silently mid-window (the log ends on a
normal `stats` line).

| | NPC legs (DrGBase) | Bot leg |
|---|---|---|
| Process CPU | 73.2, 64.5, 65.8 % | 84.5 % |
| Server FPS | 42.1, 58.5, 88.5 | 23.4 |
| Tick p95 / p99 / max | 38.0 / 53.0 / 128, 34.8 / 47.4 / 97, 35.6 / 46.5 / 99 ms | 38.1 / 54.8 / 141 ms |
| Late ticks (of about 4050) | 451, 371, 358 | 544 |
| Lua's share of the thread | 70.3, 60.4, 61.2 % | 64.2 % |

What fills the thread (inclusive):
- NPC legs: DrGBase's think (`shared.lua:233`) 19 to 23 %, `shared.lua:403`
  11 to 12 %, `HandleEnemy` 9 to 10 %, `FollowPath` 7 to 8 %, detection and
  awareness about 1 to 2 % each.
- Bot leg: none of DrGBase. Driving the bots (`sv_bots.lua`: `Drive`,
  `Look`, `LookAround`) 22 %, `player_body`'s `Command` 5 %.

So bot players take DrGBase out of the Lua profile, and their own driving
costs about what DrGBase's think did. But the process works harder (CPU
up 10 to 20 points, server FPS halved, more late ticks): a bot player is a
whole player to the engine (movement, user commands, lag compensation),
which no Lua profile shows. One bot leg is one sample; repeat it before
deciding on it, and find why the second one's server died.

## Reproducing

```
python3 .devtools/bin/server_lua.py -f .devtools/bin/profile_server.lua
python3 .devtools/bin/server_lua.py 'return WSProfile.Start(60, WSProfile.ACTIONS)'
python3 .devtools/bin/server_lua.py 'return WSProfile.Report(30)'
```

Route searches (treatment D), on the server, then offline:

```bash
python3 .devtools/bin/server_lua.py -f .devtools/bin/record_routes.lua
python3 .devtools/bin/server_lua.py 'return WSRouteRecord.Start(120, true)'
python3 .devtools/bin/server_lua.py 'return WSRouteRecord.Save("pl_upward_restart")'
luajit .devtools/bin/route_replay.lua RECORD.dat --reach 30
```

The recording lands in the server root's `garrysmod/data/ws_routes/`.

The native against Lua A/B (about 15 minutes; puts the DLL links back as
they were, then change level to load them again):

```bash
python3 .devtools/bin/aiwar_ab_bench.py --legs native,lua,native,lua
python3 .devtools/bin/aiwar_ab_bench.py --legs native:npc,native:bot,native:npc,native:bot
```

Experiments B to L were one-off probes run through `server_lua.py`; each
restored what it patched.
