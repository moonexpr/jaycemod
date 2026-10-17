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

- **Treatment A**, `mp_aiwar_revive_enabled 1`
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

## Reproducing

```
python3 .devtools/bin/server_lua.py -f .devtools/bin/profile_server.lua
python3 .devtools/bin/server_lua.py 'return WSProfile.Start(60, WSProfile.ACTIONS)'
python3 .devtools/bin/server_lua.py 'return WSProfile.Report(30)'
```

Experiments B to L were one-off probes run through `server_lua.py`; each
restored what it patched.
