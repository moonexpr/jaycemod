# CLAUDE.md

Sandcastle: a Garry's Mod gamemode hosting TF2 (and later CS:S) modes, with
NextSoldier, the AI-war's NextBot soldiers. The gamemode lives at
`addons/sandcastle/gamemodes/sandcastle/gamemode/` (below: `gamemode/`).

## Layout

| Path | What |
|---|---|
| `gamemode/shared_loader.lua` | Runs first: the gamemode's `WS.require`, then foundation's namespace indexes, each named by hand |
| `gamemode/foundation/<namespace>/` | The generic base: data structures, algorithms, codecs, maths, classes, loaded at start and published as globals (`list.queue`) by `sh_index.lua` (index below) |
| `gamemode/games/<namespace>/` | Models built on foundation: pure Lua systems, no GMod globals, I/O through ports (the gamemode core, gameplay, NPCs, timers, the world's I/O), published as globals by `sh_init.lua` and loaded on first read (index below) |
| `gamemode/nextsoldier/` | NextSoldier, the soldier itself (movement, senses, body, behaviours): its own subsystem on foundation and games that runs without the tactics engine, published as `nextsoldier.<module>` by `sh_init.lua` and loaded on first read (index below) |
| `gamemode/wartactics/` | The AI war's tactics engine: the strategy soldiers are organised by (fire teams, squads, lanes, posts, scenarios), on NextSoldier, published as `wartactics.<module>` (index below) |
| `gamemode/foundation/` | Nothing but its namespaces and three plain globals at its root (`transaction`, `configstore`, `nodegraph`): foundation is copied to the globals, so it stays small and generic. A feature's or mode's model is the feature's `model.lua` and its parts (`docs/foundation-game-split-plan.md`) |
| `gamemode/features/<feature>/` | Controllers: `sv.lua`/`cl.lua`/`sh.lua` composition roots and their `<realm>_<part>.lua` parts |
| `gamemode/ws/` | Always-loaded glue |
| `gamemode/entities/` | Map entity bindings |
| `addons/teamtint/` | Team Tint, its own addon: RED/BLU NPCs in TF2's shading, a tuning tool and debug views; pure modules in `lua/includes/modules/`, textures baked by `.devtools/bin/teamtint_bake.py` (`docs/team-theming-plan.md`) |
| `tests/*_test.lua` | LuaJIT tests, `tests/harness.lua`; `tests/foundation_layers_test.lua` guards foundation's layers |
| `native/` | Rust binary modules, each a drop-in that a server's `require` installs over the globals its Lua twins publish: `foundation` (foundation's structures), `wetsands` (foundation.wetsands' systems, on the foundation crate), `ws_profile` (the sampling profiler); `vendor/source-sdk-2013` the raw Source SDK headers they read Source's values from (`docs/native-foundation-plan.md`) |
| `docs/` | Design notes; `docs/research/foundation-admission-rule.md` decides what belongs in foundation |
| `.devtools/bin/` | Project tools; `.devtools/artifacts/` generated output |

Game events (`WS.Events`, `foundation.events`) are namespaced by kind, and
the registry refuses any other name: `system_` for the gamemode core's own
(`system_client_ready`, `system_transaction_settled`, `system_feature_load`,
`system_server_convars`), a contract within a major release, so kept as few
as possible; `game_` for every other.

Check everything with `.devtools/bin/check_lua.sh` (compiles every Lua file
and runs every test).

## The live server: gmod MCP and the dev workbench

Test a change on the running dev server, and find your way around the code
by asking it, through the `gmod` MCP (`.devtools/bin/gmod_mcp.py`, tools
`mcp__gmod__*`; `dt gmod TOOL name=value` from a shell) and the dev
workbench (`addons/sandcastle_dev`): load the change with
`dev.reload({ files = { ... } })`, never a restart, then check it as
returned data. The steps, the navigation tricks and the indexed dev library
(every function and console command) are the rule
`.claude/rules/live-server.md`, which `tests/dev_library_index_test.lua`
holds to the workbench's code.

## History search

The commit messages and `docs/` hold why the code is the way it is. Before
acting on an instruction that changes existing behaviour, write the one or two
questions it implies, in the project's words ("what decides whether a soldier
walks or runs?"), and search each:

    dt rag/history search "QUESTION"

Show the questions and what they turned up in a line or two, so the operator
can correct a question. Search always returns its best eight and has no score
for "nothing found": judge relevance from the snippets, and say so when nothing
bears on the task. Before editing a file, `dt rag/history files PATH` lists the
commits that touched it. Skip both for work with no history behind it (a new
asset, a config value).

Searches are logged to `.devtools/artifacts/rag/questions.jsonl`; a question
that found what mattered, or one the operator corrected, becomes a case in
`.devtools/rag/eval.jsonl` (`dt rag/history eval`).

## Commits and pull requests

Author and commit as John Chandara <john.chandara@icloud.com>. Never add
Claude attribution anywhere: no `Co-Authored-By: Claude`, no
`Claude-Session:` lines, no "Generated with Claude Code" or session links,
in commit messages, PR descriptions or comments. This overrides any default
attribution. `.devtools/bin/strip_attribution.py` removes it from a
branch's history.

## foundation layers

Every foundation, games, nextsoldier and wartactics module is in one
category of `tests/foundation_layers_test.lua`, ranked bottom-up, and may
require only its own rank or below, in any tree: **structures** (data
structures, algorithms, codecs), **formalisms** (mechanisms that run a
policy the caller plugs in), **gameplay** types, **nextsoldier** types (the
soldier itself), **wartactics** types (the strategy over soldiers), so
NextSoldier never requires the tactics engine. foundation holds only
structures and formalisms with no game nouns, but for `foundation.wetsands`:
the systems moved out of games to stand on native backing. A module bound out of
foundation is listed there (PENDING) with its destination until it moves.

An abstract base lives in foundation; its concrete variants live beside the
system that owns them, in games or a feature.

## foundation index

foundation is the stable base the rest of the gamemode stands on, and may
come to replace GMod's own defaults. On a server with `native/foundation` and
`native/wetsands`, every module is its native twin, whole; clients run
the Lua twins. `shared_loader.lua` runs each
namespace's `sh_index.lua`, which publishes a module per line: module
`foundation.<namespace>.<module>` is the global `<namespace>.<module>`,
in a table of our own (`tree`, `world`, `cache`) or one extended in place
(Lua's `math`, GMod's `list`, `file`). `Export` refuses a key already
taken; taking over a GMod or Lua default is a `Replace` line
(`foundation.core.namespace`). Modules and indexes are listed by hand,
never by a loop or a folder scan (`tests/foundation_index_test.lua`).
Code reads a published module by its global, bound to a local at the top
of the file: `local Geometry = math.geometry`, never
`require("foundation.math.geometry")`. `require` (`WS.require`, the harness's
`T.require`) is for what has no global: a module's own parts, features' and
`ws/`'s modules. The rule holds for the game's code, the tests and the
tools alike: only the loader, the indexes and the test harness require a
published module by name (`tests/foundation_index_test.lua`;
`.devtools/bin/foundation_globals.py` rewrites old requires).
foundation's namespaces load in `shared_loader.lua` after every namespace
their modules read. The harness publishes the globals before any test, as
the game does.
Tests are `tests/<namespace>_<module>_test.lua`.

### core: classes, interfaces, namespaces

| Module | API |
|---|---|
| `core.class` | `Extend(parent, fields)` (a subclass carries its parent's metamethods and `__index` function), `New(class, fields)`, `IsA(value, class)`, `Guard(class, check)` (refuses new keys on subclasses and their instances), `Construct(class, ...)` (each own `Init`, base first), `Destroy(instance, ...)` (each own `Destroy`, derived first) |
| `core.port` | `New(name, methods)` → an interface: `Check(value)`, `Facade(value)`, `Methods`, `Name`; `Is(value)` |
| `core.constants` | `New(name, constants)` → a `ConstantSet`: upper-case names read as fields at plain-table speed; an unknown name read, or a new one set, is refused naming the set; `set(token)` parses a name from outside (or nil; `Has`); `pairs` gives only the constants; `Names` (sorted), `tostring`/`Name`, `__len`. Values may repeat (layout sizes, colours) |
| `core.enum` | `New(name, first, names)` → an `Enum` (a `ConstantSet`) numbering names from `first`: `enum[value]` → its name (`NameOf`), `enum(token)` parses a value or a name (or nil; `Valid`), `Check`, `tostring` → "0 Default, 1 Electro" for a convar's help (`Describe`), `First`, `Last`, `Count` (`__len`), `Names` (value order) |
| `core.namespace` | What an index runs: `Namespace(globals, name)` (the global table, made if absent), `Export(ns, key, value)` (refuses a key something else holds), `Replace(ns, key, value)` (takes a default over on purpose), `Twin(ns, key, lua)` (the native twin a binary put there, only whole), `Defer(ns, key, load)` (loaded on first read), `Environment(globals, require)`. A key once set is the namespace's own, so a reload sets it again |

### list: lists, queues, slots

| Module | API |
|---|---|
| `list.queue` | `New()` → double-ended queue: `PushBack`, `PushFront`, `PopFront`, `PopBack`, `Front`, `Back`, `Size`, `Values` |
| `list.ring` | `New(capacity)` → the last values pushed: `Push`, `Size`, `Ordered` (oldest first), `Newest` (a table pushed is given back, to change in place) |
| `list.slots` | `New()` → whole-number slots for arrays kept by slot: `pool()` (`Alloc`; a freed one first), `Free` (refuses one not in use), `InUse`, `Size` (`__len`), `High`, `Clear`, `tostring` |
| `list.chain` | `New()` → slots in an order, linked by two arrays: `PushFront`, `PushBack`, `Unlink`, `MoveFront`, `Front`, `Back`, `After`, `Before`, `Has`, `for slot in chain()` (`Ordered`), `Size` (`__len`), `Clear`, `tostring` |
| `list.select` | Which item a score or an order picks; lower is better and a tie goes to the earlier item: `Lowest(list, score[, keep])` and `Highest` → item, score, place; `Nearest(list, from[, position[, keep]])` → item, distance, place; `TopK(list, k, before)` (the first k in order, n log k); `Order(list, before)` (places, stable); `Ranks(list, before)` (from 1) |
| `list.window` | `New(span)` → numbers added with their time, summed over the last `span` seconds: `Add(at, value)` (in time order), `Sum(now)`, `Count(now)` (an entry exactly `span` old counts; older ones let go), `Size`, `Clear`; the sum is kept running |
| `list.schedule` | `New(clock)` → cooperative tasks in a time slice: `Spawn(fn, ...)`, `Run(seconds)`, `CheckYield` (in a task: yield once the slice is spent), `Yield`, `Wait(ready)` (park until ready), `Limit(task, countdown, onExpire)` (a task unfinished when its countdown elapses is ended at its next turn and onExpire told), `Count`. `WS.Transactions` is each realm's, run every tick |

### tree

| Module | API |
|---|---|
| `tree.heap` | `Heap()` (`New`) → values keyed by numbers: `Push(key, value)`, `Pop`/`Peek` → value, key (lowest key first, ties in push order), `Size`, `Clear` |
| `tree.avl` | `Avl()` (`New`) → ordered map of number keys on an AVL tree: `Insert`, `Get`, `Remove`, `Min`, `Max`, `Floor`, `Ceiling`, `Pairs` (in order), `Size`, `Height` |

### world: lookups (beside games' world I/O)

| Module | API |
|---|---|
| `world.pairmap` | `New()` → values by an ordered pair of whole numbers (0..`MAX_KEY`, a link's two area ids) under one number a pair, no key built: `Get(a, b)` (unchecked, for hot paths), `Set(a, b, value)` (nil removes; refuses a bad key), `Size`, `Clear`; `Unordered()` → the same where (a, b) and (b, a) are one pair |
| `world.bucket` | `New(capacity, seconds, now)` → a token bucket, full at `now`, refilled at `capacity` per `seconds`: `Take(now)` (spends one or is refused; a refusal spends nothing), `Tokens(now)`. Time is the caller's and does not go back. The events' rate limits (`games.system.events`) are one per sender and event |
| `world.lease` | `New()` → keys held by one holder for a term: `Holder`, `FreeFor`, `Take`, `Release`, `ReleaseAll` |
| `world.grid` | `New(size)` → spatial hash on number keys: `Put`, `PutBox`, `Near` (3×3 cells), `Buckets`; `Thin(points, size)` keeps one point per cube; `Spread(items, spacing[, limit[, position]])` keeps each item, in order, not within `spacing` (3D) of one already kept; `Isolated(...)` the same but against every earlier item, kept or not (TF2's SelectSeparatedShuffleSet) |
| `world.sets` | `Named(name, members)` → a named set, a closed vocabulary parsed once: `Has`, `Check` (an unknown member is our bug, blamed on the caller), `Match` (case-free prefix), `Members`, `Name`. Plain `value → true` sets: `Of`, `Copy`, `Union`, `Intersect`, `Subtract`, `Count`, `Sorted` |

### cache

| Module | API |
|---|---|
| `cache.base` | Base class (`core.class`) of the caches, on slots and a chain; alone, first in first out. `New{ capacity, release(key, value, reason) }` → `cache[key]` (`Get`; a key named like a method needs `Get`), `cache[key] = v` (`Put`; nil: `Remove`), `for key, value in cache()` (newest first; `Keys`), `tostring`, `Size` (`__len`), `Peek`, `Take` (ownership to the caller, unreleased), `Clear`; `Class.Destroy(cache)`. Each value leaving is released once: `EVICTED`, `EXPIRED`, `REPLACED`, `REMOVED`, `CLEARED`, `DESTROYED`. Subclasses fill `Touch`, `Rewrite`, `Admitting`, `Admitted`, `Stale`, `Dropped`, their fields in `State(cache)` |
| `cache.lru` | `New{ capacity, release }` → a cache evicting the least recently used (reads and writes are uses, `Peek` is not) |
| `cache.expiring` | `New{ clock, term, release }` → a cache whose entries last `term` seconds from their last write: `Prune`; reads and walks skip the expired |
| `cache.memo` | `New{ [capacity], release }` → a cache of computed values: `Fetch(key, stamp, compute)` recomputes when the stamp changes |

### graph

| Module | API |
|---|---|
| `graph.search` | `Flood(starts, neighbors, admit, limit[, stop])` → reached, cut; `Components(nodes, neighbors)` → node → group number; `Distances(starts, edges, limit)` → node → cheapest walk from the nearest start (Dijkstra; `edges(node)` → `{ node, cost }`s) |
| `graph.pathfinder` | NavAreaBuildPath's A* over a graph port (`Neighbors`, `Cost`, `Estimate`): `New(graph, start, goal[, maxExpanded])` → a search (`status`, `expanded`, `maxExpanded`, `start`, `goal`, `closest`, `parent`, `Step(budget)`, `Route([last])`, `CostSoFar(node)`), `Find`; `RUNNING`, `FOUND`, `FAILED`, `MAX_EXPANDED`, `NAN_COST`. The routes of HL2 NPCs (`features/npc/sv_routes.lua`) |

### math, in Lua's math table

| Module | API |
|---|---|
| `math.geometry` | On `{ x, y, z }` points (missing z is 0): `Distance`, `Distance2D` (across the ground), `Toward`, `Add`, `Sub`, `Scale`, `Dot`, `Cross`, `Length`, `Normalize` (nil for the zero vector), `DistanceSquared`; across the ground, height left out of the direction and a point's own z kept: `Normalize2D`, `Left2D`, `Offset2D(p, from, along, across)` (p moved away from `from` and to the left of that way), `ClosestOnSegment(p, a, b)`, `Polar(center, radius, angle)`, `Circle(center, radius, count, start)` |
| `math.scalar` | `Clamp(value, low, high)` (an empty range is the caller's mistake), `Saturate(value)` (0..1), `Lerp(a, b, t)` (t unheld), `InverseLerp(a, b, value)` and `Remap(value, a, b, c, d)` (held to the span; a span with no length is the caller's mistake) |
| `math.interval` | Ranges [low, high] of one number line: `Overlaps(alo, ahi, blo, bhi)` (touching counts), `Intersect(...)` → low, high (low above high when apart) |
| `math.box` | Axis-aligned boxes by their corners (missing z is 0): `Overlaps(aMins, aMaxs, bMins, bMaxs)`, `Contains(mins, maxs, p)`, `Extent(points)` → mins, maxs (nil for none), `LongestAxis2D(mins, maxs)` → "x" or "y" |
| `math.choice` | Shuffling and drawing with a random source the caller gives, `randomInt(low, high)`: `Shuffle(list, randomInt)` (a new list; the last place swaps with a draw from those before it), `Draw(list, count, randomInt)` (up to `count` drawn without replacement, the last filling the place of the one drawn); a source answering outside the range is refused |
| `math.stats` | `Mean(list)`, `Percentile(list, p)` (nearest rank) |
| `math.weighted` | `PickWeighted(items, weight, r)`, `r` drawn by the caller |
| `math.polynomial` | Coefficients from the constant up: `Evaluate`, `Derivative`, `Roots` (real, ascending, up to a cubic) |
| `math.matrix` | `New(rows)`, `Identity(n)` → `Rows`, `Cols`, `Get`, `Transpose`, `Multiply`, `Determinant`, `Inverse` (nil if singular), `Solve(b)` |
| `math.polyline` | `New(points)` → a path measured along its length: `Length`, `Leg`, `PointAt`, `Offset`, `DistanceOf` |

### file and encoding: binary values and text formats

| Module | API |
|---|---|
| `file.buffer` | Values as bytes, written and read back. Writers: `Byte`, `Int16`, `Int32`, `Float32` (little-endian, IEEE 754), `Varint` (ULEB128), `String` (varint length + bytes), `Utf8(code)`, `Crc32(s)`; `Writer()` gathers them (`Bytes`, `Size`). `Reader(data)` → `Byte`, `Int16`, `UInt16`, `Int32`, `Float32`, `Varint`, `String`, `Consumed` |
| `encoding.gma` | GMod's addon archive: `Write(name, files)` → bytes (`files`: `{ path, data }`s), `Read(bytes)` → `{ name, files }` |
| `encoding.cursor` | `New(text)` → a parser's position: `Literal(s[, ignoreCase])`, `Pattern`, `Peek`, `Whitespace`, `Save`/`Restore`/`Commit`, `Position`, `AtEnd`, `Rest` |
| `encoding.utf16` | `Decode(raw)`: UTF-16LE → UTF-8 |
| `encoding.keyvalues` | `Read(text, visit(path, key, value))`: Valve KeyValues |
| `encoding.consolecfg` | `Commands(text)`: cfg text → console commands, chained `;` refused |
| `encoding.cvarfile` | `Write(names, values)` → cfg text, a `name "value"` a line; `Read(text, names)` → name → value for only those names. Client settings saved in data/ (`WS.PersistClientConVars`) |

### generator, analysis, and the root

| Module | API |
|---|---|
| `generator.state_machine` | Flat state machine: `Define(spec)` → `New(initial)`: `Transition`, `Enter`, `Think`, `Can`, `State`, `Is` |
| `generator.state_chart` | Hierarchical statechart (NextBot's engine without stacks): `Chart{ name, port, events, queries, initial }` → `State(name)` (hooks `Init`, `InitialContainedAction`, `OnStart`, `Update`, `OnEnd`; results `Continue`, `ChangeTo`, `Done`, `Try*`; `QueryBelow`), `Owns`, `New(actor, states)` → a machine: `Update`, `Event`, `Query`, `Describe`, `Stack`, `Watch`, `Destroy`. An engine with more extends `State`, `Root` and `transitions` and makes charts with `ChartsOf{ state, root, lifecycle }` |
| `analysis.analytics` | Timers, counters, tick pressure, memory samples; clock and memory are ports |
| `analysis.memory` | `Measure(roots)` → estimated bytes per named root (each object once); `Format(report, rows)`. `ws_analytics_memory` runs it over the loaded foundation modules |
| `transaction` | Exchanges between user and system or between modules, settling once as committed (value), declined (a refusal: the caller's mistake) or failed (our bug). Refusals: `Refuse(kind, detail)`, `IsRefusal(err, kinds)`, `Message`, `Explain`, `Detail`. `New()` → `Commit`/`Decline`/`Fail`, `State`, `Value`, `Refusal`, `Error`, `OnSettle`, `Await(scheduler)` (in a task); `Run(fn, ...)`, `Spawn(scheduler, fn, ...)` with `fn(work, ...)` and `work:Undo(fn)` compensations; `All(list)`. A spawned transaction is a coroutine object: `tx:Within(countdown)` gives it a deadline, a started `timer.countdown`, and one unfinished when it elapses is ended at its next turn, its steps undone, and declined as `TIMED_OUT`; `tx:Remaining()`; its work yields (`work:Yield`, `CheckYield`, `Wait`, `WaitFor(countdown)`, `Await(tx)`, `Remaining`), so systems that need not run every tick (admin operations, the gamerules, the tactics engine, anti-cheat) run on `WS.SlowTransactions` with a `WS.Deadline(seconds)` and leave the tick to combat, pathfinding and feedback. The scheduler's `Limit(task, countdown, onExpire)` is what ends a task out of time. Wire: `Ledger()` (`Open`, `Settle`, `Expire`, `Count`), `Reply(tx[, kinds])`. Over the network: `WS.Events.Transact` (client) and `WS.Events.Serve` (server), events defined with `transaction = true` |
| `configstore` | Named whole-number values, each held to a range and guarded by what the caller names: `New(name)` → `Range(key, min, max, guard)`, `Switch(key, guard)`, `store[key]` (`Get`; read-only `min`, `max`, `guard`), `Has`, `for key, entry in store()` (key order; `Keys`), `Size` (`__len`), `tostring`, `Allowed(key, holds)`, `Parse(key, text)` → text or nil and why. The menus' settings are one (`ws.settings`, guards are privileges) |
| `nodegraph` | An HL2 AI node graph made from the nav mesh: picks nodes, proposes links, assigns zones, reads and writes `maps/graphs/<map>.ain`. `PickNodes`, `Candidates`, `Bridges` break ties by index |

### wetsands: systems on native backing

The systems moved out of `games/` because native backing speeds them up
(`native/wetsands`, `docs/native-foundation-plan.md`); the Lua is the oracle
the native code is tested against, and what runs without the binary.

| Module | API |
|---|---|
| `wetsands.navsearch` | Route searches on a nav mesh snapshot: `Mesh()` (`Area`, `Link`, `Seal`), `New(mesh, strategy, limits, bot, start, goal, goalPos, maxExpanded[, told[, rules]])` → `graph.pathfinder`'s search; told: closed areas, uncrossable links, rooms, estimates, or a held `Told` of the mesh (read no table a search); rules asked once an area or link. `Distances(mesh, starts, limit, limits[, told])`: graph.search's walks on the mesh (walkable rises, `told.uncrossable`). `Told(mesh, told)` → what a team's computations know, held; `Calculator(known, strategy, limits, bot)` → the cost `Path:Compute` takes, the strategy's model priced over a Told (the engine asked only area ids and the cost so far) |
| `wetsands.path` | Path costs: a NextBot's IPathCost as strategies, parts `ground`, `hl2`, `scatter`, `tfbot` (`require("foundation.wetsands.path.<name>")`), each `Cost(step, limits, bot)` and `Model(limits, bot)` (the native search's walker); `IMPASSABLE`, `JUMP_PENALTY`, `Walkable` |

## games index

`gamemode/games/<namespace>/<module>.lua`: the specialised code built on
foundation (named `games/`, not `game/`: GMod has a `game` library, and
`module(...)` builds a module's dotted path in the globals).
`shared_loader.lua` runs each namespace's `sh_init.lua`, which `Defer`s a
module a line: module `games.<namespace>.<module>` is the global
`<namespace>.<module>`, loaded the first time it is read, so a map pays only
for what it uses. A module's parts (`gameplay/rounds/state`) load through it
and are not published. A namespace may be foundation's (`list`,
`world`, `generator`) or GMod's (`timer`, `system`). games may require foundation,
never features or ws; a published foundation module never requires games;
`tests/foundation_layers_test.lua` ranks every tree. Tests are
`tests/games_<namespace>_<module>_test.lua`.

| Namespace | Modules |
|---|---|
| `system` | The gamemode core: `events` (the game event registry, `WS.Events`), `features` (per-map feature loading), `gamemode`, `permissions`, `play_mode`, `spawn_manager`, `idle` |
| `gameplay` | `rounds` (+ `state`, `timer`, `limits`), `teams`, `players` (+ `attributes`, `condition_effects`), `spawn`, `spectate`, `respawn_modifiers`, `arrivals`, `loadout`, `economy`, `kill_credit`, `kill_icons`, `vote`, `reports`, `player_analytics`, `capture` (+ `area`, `master`, `point_timer`), `combat` (+ 9 parts), `projectile` (+ 4 parts), `tactics`, `movement` (TF2's player movement, the standard), `standing` (which team is nearer to completing its objective), `handicap`, `capabilities`, `css_weapons` (+ `scripts`: CS:S's weapon scripts, written by `.devtools/bin/css_weapons.py`) |
| `npc` | `nextbot` (the NextBot NPC system), `actor`, `combatant`, `targeting` |

| Module | API |
|---|---|
| `timer.countdown` | NextBot's CountdownTimer on a clock port (`Now()`): `New(clock)` → `Start(duration)`, `Reset`, `Invalidate`, `HasStarted`, `IsElapsed` (an unstarted one has), `GetElapsedTime`, `GetRemainingTime`, `GetCountdownDuration`. `hfsm` hands it on as `CountdownTimer` |
| `timer.interval` | NextBot's IntervalTimer: `New(clock)` → `Start`, `Reset`, `Invalidate`, `HasStarted`, `GetElapsedTime` (`INTERVAL_UNSTARTED` when unstarted), `IsLessThen`, `IsGreaterThen`. `hfsm` hands it on as `IntervalTimer` |
| `world.snapshot` | A model's state as plain data and back: `Spec{ name, skip, times, machines }`, `Take(model, spec, now[, refs])`, `Apply(model, snapshot, spec, now[, refs])`. Times kept as seconds from now, cfsm machines as their state (`Machine:Restore`), entities and other non-data through `refs` (`Encode`, `Decode`), weak tables as data; Apply writes raw and clears what the snapshot lacks. The models' `Snapshot`/`Restore` (the dev workbench's capture) |
| `generator.hfsm` | NextBot Action/Behavior engine: `generator.state_chart` with stacks. `Action` adds `SuspendFor`/`TrySuspendFor`, `OnSuspend`/`OnResume`, buried actions hearing events and queries after the one covering them; `Behavior`; `Chart` as state_chart's; NextBot's timers as `CountdownTimer`, `IntervalTimer` |
| `world.io` | A map's entity lookups and output connections, through a world port |
| `gameplay.tactics` | The tactics engine interface: `ENGINE` (a port), `Check(engine)` |
| `gameplay.css_weapons` | CS:S's weapons from the game's own scripts (`css_weapons/scripts`), the rest (recoil, second modes, ammo, knife, grenades) as tuning: `CLASSES` (buy order), `WEAPONS[class]` (`kind` `GUN`/`KNIFE`/`GRENADE`, `team`, `price`, `damage`, `accuracy`, `alt`, `second`, `kick`, GMod's c_ `viewModel`, ...), `For(team)`, `Damage(weapon, distance, hitgroup)` (falloff and `HITGROUPS`), the accuracy model (`Accuracy`, `Base`, `Inaccuracy`, `Fired`, `Landed`, `Recover`), `Spray(inaccuracy, spread, bullets, random)`, `Kick`, `Backstab`, `KnifeDamage`, `FlashBlind`, `Throw`. Played by the SWEPs `weapon_css_base` (CS:S's class names: `weapon_ak47`, ...), `weapon_knife`, `weapon_css_grenade_base` and `base_css_grenade`'s projectiles (`ws/sh_css_weapons.lua`), by bots through `features.aiwar.arms` and by NPCs through `nextsoldier.weapons` |
| `list.drawlist` | `New()` → draw callbacks named by dotted paths, run in order (by order, a tie by path): `Add(path, order, draw[, when])` (a path again replaces it), `HideElements(path)`/`ShowElements(path)` (the code's: a path hides all under it), `SetHidden(paths)` (the player's, apart), `Draw(...)`, `Entries()`; `ParseNames(text)`. The HUD's (`WS.HUD`, `cl_hud_hidden`) |

Rationale, what stays out of foundation's namespaces, and what to evaluate
next (native backing): `docs/foundation-core.md`. The split into
foundation and game: `docs/foundation-game-split-plan.md`.

## nextsoldier index

`gamemode/nextsoldier/<module>.lua`: NextSoldier, the soldier itself, its
own subsystem beside foundation and games, built on both, which runs
without the war's tactics engine (`docs/ns-split.md`, issue #8).
`shared_loader.lua` runs `nextsoldier/sh_init.lua` after games' inits, which
`Defer`s a module a line: module `nextsoldier.<module>` is the global of
that name, loaded on first read. Its module names are its globals', so
`module(...)` builds a module's table at its key in the `nextsoldier`
namespace as it loads, the same table the deferred load keeps
(`tests/foundation_index_test.lua`). nextsoldier may require foundation and
games, never wartactics, features or ws; neither foundation nor games
requires it (`tests/foundation_layers_test.lua`). Tests are
`tests/nextsoldier_<module>_test.lua`.

| Modules | |
|---|---|
| Movement (on `wetsands.path`'s costs) | `brushes`, `clip`, `detour`, `doors`, `leap`, `noise`, `portal`, `probe` (a path follower walking points), `rappel`, `reach_memo`, `route_record`, `route_walk` (a route walked waypoint by waypoint), `corners` (a route's turns pushed out until the body passes them), `nav_gaps` |
| Senses and body | `hearing`, `vision` (seen or heard, recognized, remembered: the contact, pursued out of sight when asked), `player_body` (a bot player's moves, aim and fire as a player's keys), `speech` (its criteria for the response rules) |
| Behaviours | `chart` (the contract every behaviour is a state of), `soldier` (the port behaviours drive a soldier through), `behaviors` (the registry the hosting mode gives its behaviours through), `monitor` |
| The base | `base` (the interface NextSoldier's own NextBot base implements) |

| Module | API |
|---|---|
| `nextsoldier.base` | The interface our code keeps of DrGBase's NextBot, names and hook contracts only, which NextSoldier's own base implements from scratch, native where it pays: `COMPONENTS` as TF2's NextBot in source-sdk-2013 (`NEXTBOT`: life and relations, `LOCOMOTION`, `BODY`, `POSTURE` (the body's, optional while DrGBase's classes stand in), `VISION`, `INTENTION`), each with `methods` (a `core.port`), `hooks` and `fields` (named sets, or nil); `METHODS` (every required method), `Has(soldier, c)` (an optional component, whole or refused), `HOOKS`, `FIELDS`, `Hooks(c)`, `Fields(c)`, `ComponentOf(name)`, `REPLACED` (DrGBase names the base drops, with what replaces each: no coroutine, as TF2). `.devtools/bin/drg_interface.py check` refuses a DrGBase name our code uses that it does not declare |
| `nextsoldier.chart` | NextSoldier's chart (`generator.hfsm`'s `Chart`): `CHART` over `nextsoldier.soldier`'s port, with `EVENTS` (what the soldier and the war tell its behaviours: `OnInjured`, `OnSight`, `OnLostSight`, `OnContact`, `OnContactLost`, `OnNavAreaChanged`, `OnHeard`, `OnOtherKilled`) and `QUERIES` (`ShouldAttack`, `ShouldHurry`, `ShouldRetreat`, `ShouldPickUp`, `SelectMoreDangerousThreat`). A behaviour is `CHART:State(name)`; an undeclared `On*` on one is refused as it is written. The orders' actions, the monitors and a scenario's monitor are its states |
| `nextsoldier.behaviors` | The behaviours a soldier runs, which the mode hosting it owns and gives NextSoldier (the AI war's orders register theirs, their monitors among them): `New()` → a registry (`Shared` is the war's): `Register{ name, behavior }` (a state of NextSoldier's chart, else refused; a name again replaces it), `Compile()` → fixed: `Get(name)` (unknown refused), `Has`, `Names`. The war compiles it with its scenarios (`CompileRegistries`) and gives each soldier it, whose root is its `NextSoldier` |
| `nextsoldier.soldier` | The soldier port: `METHODS` (the names), `PORT` (a `core.port`). The controller implements it over an npc_nextsoldier and a bot player; `tests/fake_soldier.lua` fakes it |
| `nextsoldier.monitor` | A monitor: a behaviour (npc.nextbot Action) holding the soldier's state and containing one: `New(name, contains)`, `Passthrough(name, contains)` (left out of the debug layer's TDBN) |

## wartactics index

`gamemode/wartactics/<module>.lua`: the AI war's tactics engine, the
high-level strategy NextSoldier's soldiers are organised by, standing on
NextSoldier and never under it. `shared_loader.lua` runs
`wartactics/sh_init.lua` after NextSoldier's; it publishes
`wartactics.<module>` and loads each on first read, as NextSoldier's does.
wartactics may require foundation, games and nextsoldier, never
features or ws. Tests are `tests/wartactics_<module>_test.lua`.

| Modules | |
|---|---|
| Fire teams and squads | `fireteam` (a fire team's doctrine in a fight, the engine `gameplay.tactics` names), `squad` |
| The field | `lanes`, `posts` (where a line is established), `zone` (the ground behind the setup gates), `explore`, `hunt` (post-round carnage) |
| The war | `scenarios`, `bot_quota` (tf_bot_quota's rules, `docs/aiwar-bots.md`), `tuning` (live tuning of fireteam, lanes and squad), `hazards` (nav areas that keep forcing soldiers to respawn, disabled and saved until inspected) |

| Module | API |
|---|---|
| `wartactics.scenarios` | The scenarios soldiers play, which any script registers while the game loads: `New()` → a registry (`Shared` is the war's): `Register{ name, priority, mode?, active?(context), scenario (a Scenario class or its module, required when chosen), monitor? (the name of a behaviour registered with NextSoldier, which ScenarioMonitor runs in place of the doctrine's sides), behaviors? (the names of those it relies on) }` (a name again replaces it); `Compile(behaviors)` at the game's beginning, against NextSoldier's compiled behaviours (an entry naming one not among them is refused) → an immutable structure, entries by priority and indexed by mode, all a decision mid-game reads: `Choose(context)` → the active entry of highest priority (context: `mode`, `field`; never the map's name), `Class(entry)`, `Behaviors(entry)`, `Entries()`. The AI war's own register at `MODE_PRIORITY` and compile when it starts (`features.aiwar.scenario`) |

## Adding to foundation

A structure or algorithm goes in the namespace that fits it
(`foundation/<namespace>/<module>.lua`: a list in `list/`, a format reader
in `encoding/`, maths in `math/`, a metatable mechanism in `core/`), with
its test written first, an entry in `tests/foundation_layers_test.lua`, a
line in its namespace's `sh_index.lua`, and a line in the index above. A
new namespace is a line in `shared_loader.lua`. foundation names no mode,
feature or game noun.

New data structures and algorithms use or extend foundation. A server
runs foundation in Rust and a client in Lua, never a module part one and
part the other: a new module gets its Lua twin (what clients run, and the
oracle) and a whole native twin in `native/foundation` (or
`native/wetsands`), held by the same tests in both passes, and its index
line is a `Twin` (`docs/native-foundation-plan.md`). The twins answer to
one interface, both ways: the same module keys, classes, constants and
metamethods, and what their constructors make the same methods
(`tests/foundation_twin_parity_test.lua`, where a new `Twin` gets a recipe
or a `LIBRARIES` line; a native-only test seam is a `NATIVE_ONLY` line).

A structure's behaviour goes in its metamethods first (indexing, assigning,
calling to walk or parse, `tostring`), with named methods as proxies
(`.claude/rules/lua-metamethods.md`); the structures are to become userdata
handles in a binary module, which honour all of them. LuaJIT ignores
`__len`, `__pairs` and `__gc` on plain tables, so define `__len` and keep
`Size` working today. Build a structure from the smaller ones (`cache` on
`slots` and `chain`), its entries in arrays by slot rather than a table
each, and give every value it owns back exactly once (a `release` callback,
`Class.Destroy`).
