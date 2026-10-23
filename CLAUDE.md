# CLAUDE.md

Sandcastle: a Garry's Mod gamemode hosting TF2 (and later CS:S) modes, with
NextSoldier, the AI-war's NextBot soldiers. The gamemode lives at
`addons/sandcastle/gamemodes/sandcastle/gamemode/` (below: `gamemode/`).

## Layout

| Path | What |
|---|---|
| `gamemode/shared_loader.lua` | Runs first: the gamemode's `WS.require`, then foundation's namespace indexes, each named by hand |
| `gamemode/foundation/<namespace>/` | The generic base: data structures, algorithms, codecs, maths, classes, loaded at start and published as globals (`list.queue`) by `sh_index.lua` (index below) |
| `gamemode/games/<namespace>/` | Models built on foundation: pure Lua systems, no GMod globals, I/O through ports (the gamemode core, gameplay, NPCs, NextSoldier, timers, the world's I/O), published as globals by `sh_init.lua` and loaded on first read (index below) |
| `gamemode/foundation/` | Nothing but its namespaces and three plain globals at its root (`transaction`, `configstore`, `nodegraph`): foundation is copied to the globals, so it stays small and generic. A feature's or mode's model is the feature's `model.lua` and its parts (`docs/foundation-game-split-plan.md`) |
| `gamemode/features/<feature>/` | Controllers: `sv.lua`/`cl.lua`/`sh.lua` composition roots and their `<realm>_<part>.lua` parts |
| `gamemode/ws/` | Always-loaded glue |
| `gamemode/entities/` | Map entity bindings |
| `addons/teamtint/` | Team Tint, its own addon: RED/BLU NPCs in TF2's shading, a tuning tool and debug views; pure modules in `lua/includes/modules/`, textures baked by `.devtools/bin/teamtint_bake.py` (`docs/team-theming-plan.md`) |
| `tests/*_test.lua` | LuaJIT tests, `tests/harness.lua`; `tests/foundation_layers_test.lua` guards foundation's layers |
| `native/` | Rust binary modules (`ws_profile`, the sampling profiler) |
| `docs/` | Design notes; `docs/research/foundation-admission-rule.md` decides what belongs in foundation |
| `.devtools/bin/` | Project tools; `.devtools/artifacts/` generated output |

Game events (`WS.Events`, `foundation.events`) are namespaced by kind, and
the registry refuses any other name: `system_` for the gamemode core's own
(`system_client_ready`, `system_transaction_settled`, `system_feature_load`,
`system_server_convars`), a contract within a major release, so kept as few
as possible; `game_` for every other.

Check everything with `.devtools/bin/check_lua.sh` (compiles every Lua file
and runs every test).

## Dev workbench

To try a Lua change on the dev server, reload it and keep the game where it
is: `dev.reload({ files = { ... } })` (about 20 ms), with the situation saved
once as a scenario (`dev.scenario.save`, `quicksave`) and loaded back as
needed. Reach for it before `changelevel`, and change map only when it
refuses a file. The workbench (`addons/sandcastle_dev`, dev server only)
also captures and restores state (`dev.capture`, `dev.apply`,
`dev.check_roundtrip`), freezes and steps gameplay, and traces the map's
gamerules I/O (`dev_gamerules_harness 1`). Commands, scenario format and
limits: the `dev-workbench` skill (`.claude/skills/dev-workbench/SKILL.md`).

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

Every foundation and games module is in one category of
`tests/foundation_layers_test.lua`, ranked bottom-up, and may require only
its own rank or below, in either tree: **structures** (data structures,
algorithms, codecs), **formalisms** (mechanisms that run a policy the caller
plugs in), **gameplay** types, **nextsoldier** types. foundation holds only
structures and formalisms with no game nouns. A module bound out of
foundation is listed there (PENDING) with its destination until it moves.

An abstract base lives in foundation; its concrete variants live beside the
system that owns them, in games or a feature.

## foundation index

foundation is the stable base the rest of the gamemode stands on, and may
come to replace GMod's own defaults. `shared_loader.lua` runs each
namespace's `sh_index.lua`, which publishes a module per line: module
`foundation.<namespace>.<module>` is the global `<namespace>.<module>`,
in a table of our own (`tree`, `world`, `cache`) or one extended in place
(Lua's `math`, GMod's `list`, `file`). `Export` refuses a key already
taken; taking over a GMod or Lua default is a `Replace` line
(`foundation.core.namespace`). Modules and indexes are listed by hand,
never by a loop or a folder scan (`tests/foundation_index_test.lua`).
Code reads a published module by its global, bound to a local at the top
of the file: `local Geometry = math.geometry`, never
`require("foundation.math.geometry")`. `require` (`WS.require`) is for what
has no global: a module's own parts, features' and `ws/`'s modules. Only
the loader and the indexes require a published module by name
(`tests/foundation_index_test.lua`; `.devtools/bin/foundation_globals.py`
rewrites old requires). foundation's namespaces load in `shared_loader.lua`
after every namespace their modules read. Tests load modules with
`T.require`; the harness publishes the globals first, as the game does.
Tests are `tests/<namespace>_<module>_test.lua`.

### core: classes, interfaces, namespaces

| Module | API |
|---|---|
| `core.class` | `Extend(parent, fields)` (a subclass carries its parent's metamethods and `__index` function), `New(class, fields)`, `IsA(value, class)`, `Guard(class, check)` (refuses new keys on subclasses and their instances), `Construct(class, ...)` (each own `Init`, base first), `Destroy(instance, ...)` (each own `Destroy`, derived first) |
| `core.port` | `New(name, methods)` → an interface: `Check(value)`, `Facade(value)`, `Methods`, `Name`; `Is(value)` |
| `core.constants` | `New(name, constants)` → a `ConstantSet`: upper-case names read as fields at plain-table speed; an unknown name read, or a new one set, is refused naming the set; `set(token)` parses a name from outside (or nil; `Has`); `pairs` gives only the constants; `Names` (sorted), `tostring`/`Name`, `__len`. Values may repeat (layout sizes, colours) |
| `core.enum` | `New(name, first, names)` → an `Enum` (a `ConstantSet`) numbering names from `first`: `enum[value]` → its name (`NameOf`), `enum(token)` parses a value or a name (or nil; `Valid`), `Check`, `tostring` → "0 Default, 1 Electro" for a convar's help (`Describe`), `First`, `Last`, `Count` (`__len`), `Names` (value order) |
| `core.namespace` | What an index runs: `Namespace(globals, name)` (the global table, made if absent), `Export(ns, key, value)` (refuses a key something else holds), `Replace(ns, key, value)` (takes a default over on purpose), `Environment(globals, require)`. A key once set is the namespace's own, so a reload sets it again |

### list: lists, queues, slots

| Module | API |
|---|---|
| `list.queue` | `New()` → double-ended queue: `PushBack`, `PushFront`, `PopFront`, `PopBack`, `Front`, `Back`, `Size`, `Values` |
| `list.ring` | `New(capacity)` → the last values pushed: `Push`, `Size`, `Ordered` (oldest first) |
| `list.slots` | `New()` → whole-number slots for arrays kept by slot: `pool()` (`Alloc`; a freed one first), `Free` (refuses one not in use), `InUse`, `Size` (`__len`), `High`, `Clear`, `tostring` |
| `list.chain` | `New()` → slots in an order, linked by two arrays: `PushFront`, `PushBack`, `Unlink`, `MoveFront`, `Front`, `Back`, `After`, `Before`, `Has`, `for slot in chain()` (`Ordered`), `Size` (`__len`), `Clear`, `tostring` |
| `list.schedule` | `New(clock)` → cooperative tasks in a time slice: `Spawn(fn, ...)`, `Run(seconds)`, `CheckYield` (in a task: yield once the slice is spent), `Yield`, `Wait(ready)` (park until ready), `Count`. `WS.Transactions` is each realm's, run every tick |

### tree

| Module | API |
|---|---|
| `tree.heap` | `New(before)` → binary heap: `Push`, `Pop`, `Peek`, `Size`; ties are the rule's to break |
| `tree.avl` | `New([less])` → ordered map on an AVL tree: `Insert`, `Get`, `Remove`, `Min`, `Max`, `Floor`, `Ceiling`, `Pairs` (in order), `Size`, `Height` |

### world: lookups (beside games' world I/O)

| Module | API |
|---|---|
| `world.pairmap` | `New()` → values by an ordered pair of whole numbers (0..`MAX_KEY`, a link's two area ids) under one number a pair, no key built: `Get(a, b)` (unchecked, for hot paths), `Set(a, b, value)` (nil removes; refuses a bad key), `Size`, `Clear` |
| `world.lease` | `New()` → keys held by one holder for a term: `Holder`, `FreeFor`, `Take`, `Release`, `ReleaseAll` |
| `world.grid` | `New(size)` → spatial hash on number keys: `Put`, `PutBox`, `Near` (3×3 cells), `Buckets`; `Thin(points, size)` keeps one point per cube |
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
| `graph.pathfinder` | Abstract path search (template method): `Solver(name)` → a solver class filling `Begin`, `Next`, `Expand` (reporting with `Reach`, `Approach`); it gets `New`, `Find`, `Step(budget)`, `Route`. `RUNNING`, `FOUND`, `FAILED`, `MAX_EXPANDED` |

### math, in Lua's math table

| Module | API |
|---|---|
| `math.geometry` | On `{ x, y, z }` points (missing z is 0): `Distance`, `Distance2D` (across the ground), `Toward`, `Add`, `Sub`, `Scale`, `Dot`, `Cross`, `Length`, `Normalize` (nil for the zero vector) |
| `math.scalar` | `Clamp(value, low, high)` (an empty range is the caller's mistake) |
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
| `transaction` | Exchanges between user and system or between modules, settling once as committed (value), declined (a refusal: the caller's mistake) or failed (our bug). Refusals: `Refuse(kind, detail)`, `IsRefusal(err, kinds)`, `Message`, `Explain`, `Detail`. `New()` → `Commit`/`Decline`/`Fail`, `State`, `Value`, `Refusal`, `Error`, `OnSettle`, `Await(scheduler)` (in a task); `Run(fn, ...)`, `Spawn(scheduler, fn, ...)` with `fn(work, ...)` and `work:Undo(fn)` compensations; `All(list)`. Wire: `Ledger()` (`Open`, `Settle`, `Expire`, `Count`), `Reply(tx[, kinds])`. Over the network: `WS.Events.Transact` (client) and `WS.Events.Serve` (server), events defined with `transaction = true` |
| `configstore` | Named whole-number values, each held to a range and guarded by what the caller names: `New(name)` → `Range(key, min, max, guard)`, `Switch(key, guard)`, `store[key]` (`Get`; read-only `min`, `max`, `guard`), `Has`, `for key, entry in store()` (key order; `Keys`), `Size` (`__len`), `tostring`, `Allowed(key, holds)`, `Parse(key, text)` → text or nil and why. The menus' settings are one (`ws.settings`, guards are privileges) |
| `nodegraph` | An HL2 AI node graph made from the nav mesh: picks nodes, proposes links, assigns zones, reads and writes `maps/graphs/<map>.ain` |

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
`tests/foundation_layers_test.lua` ranks both trees. Tests are
`tests/games_<namespace>_<module>_test.lua`.

| Namespace | Modules |
|---|---|
| `system` | The gamemode core: `events` (the game event registry, `WS.Events`), `features` (per-map feature loading), `gamemode`, `permissions`, `play_mode`, `spawn_manager`, `idle` |
| `gameplay` | `rounds` (+ `state`, `timer`, `limits`), `teams`, `players` (+ `attributes`, `condition_effects`), `spawn`, `spectate`, `respawn_modifiers`, `arrivals`, `loadout`, `economy`, `kill_credit`, `kill_icons`, `vote`, `reports`, `player_analytics`, `capture` (+ `area`, `master`, `point_timer`), `combat` (+ 9 parts), `projectile` (+ 4 parts), `tactics` |
| `npc` | `nextbot` (the NextBot NPC system), `actor`, `combatant`, `targeting`, `astar` |
| `nextsoldier` | NextSoldier: `tactics` (the AI war's fire-team doctrine, on `gameplay.tactics`), `tuning`, `squad`, `lanes`, `speech`, `hearing`, `explore`, `hunt`, `posts`, `zone`, `nav_gaps`; movement: `path` (+ `ground`, `hl2`, `scatter`, `tfbot`, the cost strategies a solver prices steps with), `brushes`, `clip`, `detour`, `doors`, `leap`, `noise`, `portal`, `probe`, `rappel`, `reach_memo`, `route_record` |

| Module | API |
|---|---|
| `timer.countdown` | NextBot's CountdownTimer on a clock port (`Now()`): `New(clock)` → `Start(duration)`, `Reset`, `Invalidate`, `HasStarted`, `IsElapsed` (an unstarted one has), `GetElapsedTime`, `GetRemainingTime`, `GetCountdownDuration`. `hfsm` hands it on as `CountdownTimer` |
| `timer.interval` | NextBot's IntervalTimer: `New(clock)` → `Start`, `Reset`, `Invalidate`, `HasStarted`, `GetElapsedTime` (`INTERVAL_UNSTARTED` when unstarted), `IsLessThen`, `IsGreaterThen`. `hfsm` hands it on as `IntervalTimer` |
| `world.snapshot` | A model's state as plain data and back: `Spec{ name, skip, times, machines }`, `Take(model, spec, now[, refs])`, `Apply(model, snapshot, spec, now[, refs])`. Times kept as seconds from now, cfsm machines as their state (`Machine:Restore`), entities and other non-data through `refs` (`Encode`, `Decode`), weak tables as data; Apply writes raw and clears what the snapshot lacks. The models' `Snapshot`/`Restore` (the dev workbench's capture) |
| `generator.hfsm` | NextBot Action/Behavior engine: `generator.state_chart` with stacks. `Action` adds `SuspendFor`/`TrySuspendFor`, `OnSuspend`/`OnResume`, buried actions hearing events and queries after the one covering them; `Behavior`; `Chart` as state_chart's; NextBot's timers as `CountdownTimer`, `IntervalTimer` |
| `world.io` | A map's entity lookups and output connections, through a world port |
| `gameplay.tactics` | The tactics engine interface: `ENGINE` (a port), `Check(engine)` |
| `npc.astar` | `graph.pathfinder`'s solver for NavAreaBuildPath's A*, the routes of HL2 NPCs (`features/npc/sv_routes.lua`) |
| `list.drawlist` | `New()` → draw callbacks named by dotted paths, run in order (by order, a tie by path): `Add(path, order, draw[, when])` (a path again replaces it), `HideElements(path)`/`ShowElements(path)` (the code's: a path hides all under it), `SetHidden(paths)` (the player's, apart), `Draw(...)`, `Entries()`; `ParseNames(text)`. The HUD's (`WS.HUD`, `cl_hud_hidden`) |

Rationale, what stays out of foundation's namespaces, and what to evaluate
next (native backing): `docs/foundation-core.md`. The split into
foundation and game: `docs/foundation-game-split-plan.md`.

## Adding to foundation

A structure or algorithm goes in the namespace that fits it
(`foundation/<namespace>/<module>.lua`: a list in `list/`, a format reader
in `encoding/`, maths in `math/`, a metatable mechanism in `core/`), with
its test written first, an entry in `tests/foundation_layers_test.lua`, a
line in its namespace's `sh_index.lua`, and a line in the index above. A
new namespace is a line in `shared_loader.lua`. foundation names no mode,
feature or game noun.

New data structures and algorithms use or extend foundation (to become a binary module), unless that would cost the use case
its performance: such exceptions are reviewed case by case and leave a "Core-rule exception" comment saying why.

A structure's behaviour goes in its metamethods first (indexing, assigning,
calling to walk or parse, `tostring`), with named methods as proxies
(`.claude/rules/lua-metamethods.md`); the structures are to become userdata
handles in a binary module, which honour all of them. LuaJIT ignores
`__len`, `__pairs` and `__gc` on plain tables, so define `__len` and keep
`Size` working today. Build a structure from the smaller ones (`cache` on
`slots` and `chain`), its entries in arrays by slot rather than a table
each, and give every value it owns back exactly once (a `release` callback,
`Class.Destroy`).
