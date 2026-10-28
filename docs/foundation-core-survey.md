# foundation.core survey: hand-rolled structures and algorithms

A sweep of `foundation/` (outside core), `features/` and `ws/` (vendor/ left
out) for data structures and algorithms written by hand that core could
express formally, ahead of core becoming a binary module whose structures
are userdata handles. Taken on 2026-10-22, after `51f25cf` (pair map,
ground distance, clamp).

Each finding names its sites, what core would offer, and what it is built
from, so structures grow from the primitives up. When it was written,
nothing here was migrated; the call sites were listed for that work.

## Status, 2026-10-27

The work is tracked in epic #12 (moonexpr/sandcastle), which has every
checklist item, its commit and each decision not to do one. The paths below
are from before the foundation/games split (`foundation/<x>.lua` sites now
live under `games/`, `features/`); #12 has the current ones. Each module
below was built with its Lua and native twins (the modules added since this
survey are in CLAUDE.md's foundation index).

| Finding | Now |
|---|---|
| Caches, constants, enums at their sites | Done, bar two: `NavGraph:Neighbors` is already dropped whole with the mesh generation (the survey's "never invalidated" was wrong), and `KitReachable` is weak-keyed by entity |
| Bounded logs and windows | `list.ring:Newest` and `list.window` built; `BehaviorLog` and the bosses' damage per second moved. The kill feed, the blocker log, the teleport trail and `profile.lua`'s samples stay (removal from the middle, indexed reads, five points, no ageing) |
| Selection (`list.select`) | Built: `Lowest`, `Highest`, `Nearest`, `TopK`, `Order`, `Ranks`; fourteen sites moved |
| Random choice | `math.choice` built as `Shuffle` and `Draw` (named so because `math.random` is Lua's own function); `Pick` is not, as `list[me:RandomInt(1, #list)]` is shorter than the helper and its adapter. The four hand-written draws were not one operation |
| `math.apportion` | Not built: one ten-line pure function with one caller |
| Spatial | `world.grid:Spread` and `Isolated` (TF2's rule), `math.interval`, `math.box` built and moved; `grid:Nearest` is not (its only caller is `nodegraph`, which has its own native implementation); `Thin` keeps its string key |
| Ground-plane vectors, scalars | `math.geometry` and `math.scalar` extended; the by-hand copies moved, but for those that need the reach with the direction (`leap`), a point a tick (`hover`), or the deltas again (`orders` HopOn, `nbdebug` Pick) |
| Already in core, not yet used | Done (percentile, set counts, clamps), except the three `Contains` scans, which run over constants of five or lists built per call |
| Counting (`world.counter`) | Not built: the six tallies read six different sources, and none is hot |
| Rate limiting | `world.bucket` built; the events' rate limits use it |
| Pair keys | `world.pairmap:Unordered` built; two of three sites moved (`nodegraph`'s packed key is the oracle of a native twin) |

### Benched, 2026-10-27

`.devtools/bin/bench_foundation.lua` times each module against the code it
replaced, copied as it was. Run on the dev server (ctf_2fort, empty, JIT on,
the native twins: its DLL reloads on a map change) the best of five, in ns an
operation:

| Operation | Old code | Module | Module / old |
|---|---|---|---|
| Nearest of 128 points | 26,100 | `Select.Nearest` | 0.47 |
| Top 5 of 1000 | 520,000 | `Select.TopK` | 0.16 |
| Order 200 | 81,400 | `Select.Order` | 0.79 |
| Spread, 300 points, 24 posts | 59,800 | `Grid.Spread` | 0.26 |
| Spread, 2000 points, no limit | 208,000,000 | `Grid.Spread` | 0.004 |
| Isolated, 150 areas | 1,617,000 | `Grid.Isolated` | 0.05 |
| Damage per second over a 300-hit window, a tick | 9,160 | `list.window` | 0.014 |
| Bounded log of 64, a push | 168 | `list.ring` | 0.81 |
| Lowest of 128 by a score function | 208 | `Select.Lowest` | **29** |
| Draw 8 of 30 | 948 | `math.choice.Draw` | **2.0** |
| Seen-pair set, 511 pairs | 68,400 | `pairmap.Unordered` | **2.0** |
| Rate limit, a take | 2 | `world.bucket` | **39** (97 ns) |
| `Saturate`, `box.Overlaps` | 1 | the module | **100 and 430 ns** |

What it says:

- Where the module replaces a scan or a sort, native wins, from 1.3 times to
  more than 200: top-k, spread, isolated, the window, nearest.
- Where the operation is a few nanoseconds that the JIT compiles inline, or
  the module calls the caller's Lua once an item (`Lowest`, `Draw`), a
  native call loses. A crossing is about 100 ns on the server, and a call
  from native back into Lua about 25 ns (`Lowest` makes two an item: 47 ns
  an item against the JIT-compiled loop's 1.6). In absolute terms every loss
  is under 10 µs a call; the worst, the bosses' `Nearest` through `Lowest`
  over 128 targets, would cost 0.04 % of a core even if it ran every tick.
- This Mac, JIT on, agrees on the direction but flatters the Lua: there the
  Lua twin of `Nearest` beats the native by 3 to 10 times. With the JIT off
  (a thrashing server's interpreter, baseline H12) the native wins nearly
  everywhere, `box.Overlaps` and `Lowest` apart. The server's own JIT is on
  for this run. Local results are in `.devtools/artifacts/bench-foundation-*.txt`.

The operator's rule (a module is whole native on a server) holds in every
row; the rows above 1.0 are the argument for letting a module stay Lua when
it is a few nanoseconds of inline arithmetic or a loop over the caller's
own callbacks. That is the operator's call, and not made here.

A live check of the moved sites in play (a round, a war) is not done: only
the bench ran on the server.

## Built in this pass

| Module | From | For |
|---|---|---|
| `structs.slots` | — | whole-number slots, freed ones reused: the allocator under every struct-of-arrays structure |
| `structs.chain` | — | an order over slots in two arrays: O(1) unlink and move-to-front, no node tables |
| `structs.cache` | slots, chain, `meta.class` | the cache base: `cache[key]`, `cache[key] = v`, `cache()` to walk; one release protocol (each value given back once: evicted, expired, replaced, removed, cleared, destroyed); FIFO on its own |
| `structs.lru` | cache | least recently used out |
| `structs.expiring` | cache, `meta.port` (clock) | entries live a term from their last write |
| `structs.memo` | cache | a value kept while the stamp it was computed under holds |
| `meta.constants` | `meta.class` | a closed constant set: unknown reads and new names refused, `set(token)` parses |
| `meta.enum` | constants | numbered names: `enum[value]` → name, `enum(token)` parses, `tostring` → a convar's help text |

`meta.class.Extend` now copies a parent's metamethods (and an `__index`
function) to its subclasses, which Lua never reads through `__index`.

### Where they apply

| Site | Today | Becomes |
|---|---|---|
| `foundation/kill_credit.lua` `History` | each damager once, latest first, capped at `HISTORY`, rebuilt as a new list on every hit | `lru` keyed by damager |
| `foundation/npc/halloween_boss.lua` `RememberAttacker` (and merasmus's `NameKillers` over it) | attackers kept once with their latest hit, a linear scan per hit | `lru` (or `expiring` with `KILLER_WINDOW`) |
| `foundation/aiwar/hunt.lua` `Board:Sightings` | subject → sighting, forgotten past `HUNT_MEMORY` on read | `expiring` with term `HUNT_MEMORY` |
| `features/aiwar/sv_posts.lua` `CachedPosts` | `kind .. team` → `{ key, posts }`, recomputed when the key changes | `memo`, stamp = that key |
| `features/npc/sv_routes.lua` `NavGraph:Neighbors` | area id → neighbour ids, never invalidated | `memo` stamped by the mesh's generation |
| `features/aiwar/sv_obstacles.lua` `KitReachable` | weak entity → bool | `memo` (a weak-keyed variant if entities must not be held) |
| `foundation/events.lua` allowances | sender → name → `{ tokens, at }` | a token bucket (below) inside an `expiring` per sender |
| `ws/cl_hits.lua` `tf_dingalingaling_effect` | help text "0 Default, 1 Electro, …" and range `#HitSound.EFFECTS - 1` written by hand | `meta.enum`: `tostring(EFFECTS)`, `EFFECTS:First()`, `EFFECTS:Last()` |
| `ws/cl_menu_inventory.lua` layout and colours (and every menu's like them) | loose `local` constants | `meta.constants` sets, a misspelt name caught |

## Still hand-rolled

Ordered by how much they would gain from native backing, then by count.

### Bounded logs and windows (built on `ring` and `queue`)

- `features/npc/sv_blockers.lua:200` and `ws/cl_kill_feed.lua:86` trim a list
  with `table.remove(list, 1)`: O(n) per push. `structs.ring` already does it.
- `foundation/npc/debug.lua:614` `BehaviorLog`: a ring that coalesces a
  repeat of its newest entry ("x3"), shifting the whole array to drop the
  oldest. Needs a ring that reads and replaces its newest (`ring:Newest()`,
  `ring[-1]`).
- `foundation/npc/halloween_boss.lua:99` DPS: samples rebuilt into a new list
  every update to drop those older than `DPS_WINDOW`. A **time window**
  (`structs.window`: a queue of `{ at, value }` with a running sum, popped
  from the front as they age) answers in O(expired).
- `features/npc/profile.lua` samples grow without bound for a profiling
  window: the same window.
- `foundation/vote.lua:183` a vote queue popped with `remove(queue, 1)`:
  `structs.queue`.
- `features/aiwar/reserve.lua` team → class → list of handles, taken oldest
  first with `remove(list, 1)` and lazily skipped once forgotten: a keyed set
  of queues, or one `chain` per class over `slots` with O(1) `Forget`.

### Selection algorithms (new `core.select`, on `heap`)

- **Arg-min / arg-max loops**, about fifteen: `sv_lanes.Nearest`,
  `spectate.Nearest`, `explore.Nearest`, `hunt.Nearest`/`Quarry`,
  `control_points.Nearest`, `freeform.Nearest`, `headless_hatman.Nearest`,
  `merasmus.Nearest`, `eyeball_boss.FindClosestVisibleVictim`,
  `health.PickKit`, `npc/debug.Pick`, `sv_obstacles.SpreadSpawns`,
  `lanes.Siblings`, `lanes.Farthest`. One `Best(list, score[, keep])` (and
  `Nearest(list, pos, position[, keep])` over it) replaces them; a native
  one scores without a Lua call per item when the score is a distance.
- **Sort then take k**: `npc/debug.NearestFirst`, `teams.PickBalanceSwitches`,
  `posts.Pick`, `nodegraph.Candidates`/`Bridges` (per node). `TopK(list, k,
  before)` on a bounded heap: O(n log k), not O(n log n).
- **Stable arg-sort / ranks**: `capture.Ranks`, `capture/master.ByPriority`
  (sort indices, ties by index). `Order(list, before)`, `Ranks(list, before)`.
- **Lowest free index**, three in `foundation/aiwar.lua` (`FreeSlot`,
  `FreePlace`, `FreeIndex`): build a taken-set, count up. A `slots` variant
  that hands out the lowest free (a min-heap free list) or a bitset's
  first clear bit.

### Random choice (extend `math.random`)

- `list[RandomInt(1, #list)]`, 22 sites: `random.Pick(list, randomInt)`.
- Fisher–Yates by hand: `merasmus.SeparatedShuffle` → `random.Shuffle(list,
  randomInt)`.
- **Draw without replacement**, done four ways: `merasmus` swap-remove
  (1101, 1344), `capture/master.ChooseRound` remove-and-retry,
  `rounds.MapVoteChoices` (`Draw`). `random.Draw(list, count, randomInt)`.
- `aiwar.PickRole`: the role furthest below its weighted share, a
  largest-deficit apportionment. `math.apportion` (not random; deterministic).

### Spatial (extend `structs.grid`, add `math.box`)

- **Greedy spread** (keep candidates in priority order, skip any within a
  spacing of one kept): `posts.Pick` (O(n·k) pair checks),
  `merasmus.SeparatedShuffle` (O(n²)), `nodegraph.PickNodes` (already on a
  grid), and `features/nodegraph/sv.lua:239`, which re-runs it with a
  growing spacing until under a node limit. `grid.Spread(points, spacing,
  limit)`; the grid makes it O(n).
- **k nearest within a radius**: `nodegraph.Candidates`/`Bridges` (already
  noted in `foundation-core.md`). `grid:Nearest(p, k, radius[, keep])`.
- **Axis-aligned boxes**, the same overlap test twice
  (`rounds/sv_gamerules.Overlap`, `npc/sv_blockers.Overlapping`) and a 2D one
  (`aiwar/overlay.Overlaps`); `npc/portal`'s span intersections and clamps;
  `aiwar/spawns.Split`'s bounds and longest axis. `math.interval`
  (`Overlaps`, `Intersect`, `Clamp`) under `math.box` (`Overlaps`,
  `Contains`, `Union`, `Extent`, `LongestAxis`), which `grid:PutBox` would
  take too.

### Ground-plane vector maths (extend `math.geometry`)

About fifteen `sqrt(dx * dx + dy * dy)` by hand:
`orders.Across` and `wartactics.FlankPoint` (the same perpendicular
offset), `orders.Behind` and `wartactics.FallbackPoint` (the same push
away), `lanes.FixedFlanks`, `lanes.InFlankRange`, `hover:Approach`,
`leap`, `nodegraph.Distance`, `posts.Apart`, `npc/debug.Pick`. Wanted:
`Normalize2D`, `Left2D` (perpendicular), `Offset2D(p, from, along,
across)`, `DistanceSquared` (for `hearing.LookAt` and the `DistToSqr`
comparisons), `ClosestOnSegment` (`ctf.ToSegment`), `Circle(center,
radius, count, start)` for the three point rings (`orders.Ring` with the
golden angle, `nbdebug` `Ring`, `cl_ui` `Ring`).

### Scalar maths (extend `math.scalar`)

- `Lerp`: `npc/leap.lua`, `cl_ui.Lerp2`.
- `InverseLerp`/`Remap` clamped: `merasmus.RemapValClamped`,
  `weapon_balance.lua:130`, `payload.lua:139`.
- `Saturate` (0..1): `health.Clamp01`.
- Ten `min(max(...))` clamps where `scalar.Clamp` exists: `aiwar.lua:192`,
  `payload.lua:257`, `rounds.lua:368`, `marksmanship.lua:25`, `koth.lua:151`.

### Already in core, not yet used

- `features/npc/profile.lua:49` `Percentile` is `math.stats.Percentile`.
- `foundation/reports.lua:44` counts a set's keys: `structs.sets.Count`.
- `foundation/holiday.lua:62`, `features/flag/sv.lua:326`,
  `capture/master.lua:185` scan a list for a value (`Contains`) where a set
  or `sets.Of` would do.

### Counting (new `structs.counter`)

Tallies by key, built and thrown away each call: `vote.Counts`,
`aiwar.RoleCounts`, `gamemode/sv.TeamCounts`, `capture/sv_areas.Counts`,
`features/aiwar/reserve:Count`. A bag (`counter[key]` reads, `counter[key]
= counter[key] + 1` writes, `counter()` walks, `Most`) kept up to date
where the members change would replace the recounts.

### Rate limiting (new `structs.bucket`)

`foundation/events.lua:443` refills and spends a token bucket per sender
and event by hand. A bucket on a clock port (`bucket(now)` spends one or
refuses) is a primitive the admin reports and votes could share.

### Pair keys

String keys built for unordered pairs: `features/nodegraph/sv.lua:126`
(`min .. ":" .. max`), `nav_gaps.lua:61` (`a.id .. ":" .. b.id`);
`nodegraph.lua` packs `a * 65536 + b`. `structs.pairmap` takes ordered pairs
without a string; an unordered form (or a `pairset`) would serve all three.

## Left as they are

- Weak entity-keyed side tables (`__mode = "k"`, about 34): they hold Lua
  references to entities, which a native structure cannot hold safely.
- `now - x.since >= CONSTANT` checks (about 30): fields on a model's own
  state; `core.timers` exists for those that need starting and resetting.
- `aiwar/overlay.Layout`, `payload.HillSegments`, `ns/inspect`'s angular
  sort: one caller each, and the formal piece under them (boxes, intervals
  on a polyline) is listed above.
