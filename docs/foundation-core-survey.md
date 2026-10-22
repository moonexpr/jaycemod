# foundation.core survey: hand-rolled structures and algorithms

A sweep of `foundation/` (outside core), `features/` and `ws/` (vendor/ left
out) for data structures and algorithms written by hand that core could
express formally, ahead of core becoming a binary module whose structures
are userdata handles. Taken on 2026-10-22, after `51f25cf` (pair map,
ground distance, clamp).

Each finding names its sites, what core would offer, and what it is built
from, so structures grow from the primitives up. Nothing here is migrated
yet; the call sites are listed for that work.

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
