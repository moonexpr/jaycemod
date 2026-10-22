# CLAUDE.md

Sandcastle: a Garry's Mod gamemode hosting TF2 (and later CS:S) modes, with
NextSoldier, the AI-war's NextBot soldiers. The gamemode lives at
`addons/sandcastle/gamemodes/sandcastle/gamemode/` (below: `gamemode/`).

## Layout

| Path | What |
|---|---|
| `gamemode/foundation/` | Models: pure Lua systems, no GMod globals, I/O through ports, loaded per map with `WS.require("foundation.x")` |
| `gamemode/foundation/core/` | Data structures, algorithms, codecs and abstract bases (index below) |
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

Every foundation module is in one category of
`tests/foundation_layers_test.lua`, ranked bottom-up, and may require only
its own rank or below: **structures** (data structures, algorithms, codecs:
textbook names, no game nouns), **formalisms** (mechanisms that run a policy
the caller plugs in), **gameplay** types, **ns** types. Modules pending a move
out of foundation are listed there with their destination.

An abstract base lives in core; its concrete variants live beside the system
that owns them, outside core.

## foundation.core index

Module names are `foundation.core.<path>`; tests are
`tests/core_<path with _>_test.lua`.

### structs: data structures

| Module | API |
|---|---|
| `structs.sets` | `Named(name, members)` → a named set, a closed vocabulary parsed once: `Has`, `Check` (an unknown member is our bug, blamed on the caller), `Match` (case-free prefix), `Members`, `Name`. Plain `value → true` sets: `Of`, `Copy`, `Union`, `Intersect`, `Subtract`, `Count`, `Sorted` |
| `structs.heap` | `New(before)` → binary heap: `Push`, `Pop`, `Peek`, `Size`; ties are the rule's to break |
| `structs.ring` | `New(capacity)` → the last values pushed: `Push`, `Size`, `Ordered` (oldest first) |
| `structs.slots` | `New()` → whole-number slots for arrays kept by slot: `pool()` (`Alloc`; a freed one first), `Free` (refuses one not in use), `InUse`, `Size` (`__len`), `High`, `Clear`, `tostring` |
| `structs.chain` | `New()` → slots in an order, linked by two arrays: `PushFront`, `PushBack`, `Unlink`, `MoveFront`, `Front`, `Back`, `After`, `Before`, `Has`, `for slot in chain()` (`Ordered`), `Size` (`__len`), `Clear`, `tostring` |
| `structs.cache` | Base class (`meta.class`) of the caches, on slots and a chain; alone, first in first out. `New{ capacity, release(key, value, reason) }` → `cache[key]` (`Get`; a key named like a method needs `Get`), `cache[key] = v` (`Put`; nil: `Remove`), `for key, value in cache()` (newest first; `Keys`), `tostring`, `Size` (`__len`), `Peek`, `Take` (ownership to the caller, unreleased), `Clear`; `Class.Destroy(cache)`. Each value leaving is released once: `EVICTED`, `EXPIRED`, `REPLACED`, `REMOVED`, `CLEARED`, `DESTROYED`. Subclasses fill `Touch`, `Rewrite`, `Admitting`, `Admitted`, `Stale`, `Dropped`, their fields in `State(cache)` |
| `structs.lru` | `New{ capacity, release }` → a cache evicting the least recently used (reads and writes are uses, `Peek` is not) |
| `structs.expiring` | `New{ clock, term, release }` → a cache whose entries last `term` seconds from their last write: `Prune`; reads and walks skip the expired |
| `structs.memo` | `New{ [capacity], release }` → a cache of computed values: `Fetch(key, stamp, compute)` recomputes when the stamp changes |
| `structs.lease` | `New()` → keys held by one holder for a term: `Holder`, `FreeFor`, `Take`, `Release`, `ReleaseAll` |
| `structs.grid` | `New(size)` → spatial hash on number keys: `Put`, `PutBox`, `Near` (3×3 cells), `Buckets`; `Thin(points, size)` keeps one point per cube |
| `structs.polyline` | `New(points)` → a path measured along its length: `Length`, `Leg`, `PointAt`, `Offset`, `DistanceOf` |
| `structs.queue` | `New()` → double-ended queue: `PushBack`, `PushFront`, `PopFront`, `PopBack`, `Front`, `Back`, `Size`, `Values` |
| `timers` | NextBot's timers on a clock port (`Now()`): `CountdownTimer(clock)` → `Start(duration)`, `Reset`, `Invalidate`, `HasStarted`, `IsElapsed` (an unstarted one has), `GetElapsedTime`, `GetRemainingTime`, `GetCountdownDuration`; `IntervalTimer(clock)` → `Start`, `Reset`, `Invalidate`, `HasStarted`, `GetElapsedTime`, `IsLessThen`, `IsGreaterThen`. `hfsm` hands them on |
| `structs.pairmap` | `New()` → values by an ordered pair of whole numbers (0..`MAX_KEY`, a link's two area ids) under one number a pair, no key built: `Get(a, b)` (unchecked, for hot paths), `Set(a, b, value)` (nil removes; refuses a bad key), `Size`, `Clear` |
| `structs.tree` | `New([less])` → ordered map on an AVL tree: `Insert`, `Get`, `Remove`, `Min`, `Max`, `Floor`, `Ceiling`, `Pairs` (in order), `Size`, `Height` |

### Algorithms

| Module | API |
|---|---|
| `graph` | `Flood(starts, neighbors, admit, limit[, stop])` → reached, cut; `Components(nodes, neighbors)` → node → group number; `Distances(starts, edges, limit)` → node → cheapest walk from the nearest start (Dijkstra; `edges(node)` → `{ node, cost }`s) |
| `pathfinder` | Abstract path search (template method): `Solver(name)` → a solver class filling `Begin`, `Next`, `Expand` (reporting with `Reach`, `Approach`); it gets `New`, `Find`, `Step(budget)`, `Route`. `RUNNING`, `FOUND`, `FAILED`, `MAX_EXPANDED` |

### math

| Module | API |
|---|---|
| `math.geometry` | On `{ x, y, z }` points (missing z is 0): `Distance`, `Distance2D` (across the ground), `Toward`, `Add`, `Sub`, `Scale`, `Dot`, `Cross`, `Length`, `Normalize` (nil for the zero vector) |
| `math.scalar` | `Clamp(value, low, high)` (an empty range is the caller's mistake) |
| `math.stats` | `Mean(list)`, `Percentile(list, p)` (nearest rank) |
| `math.random` | `PickWeighted(items, weight, r)`, `r` drawn by the caller |
| `math.polynomial` | Coefficients from the constant up: `Evaluate`, `Derivative`, `Roots` (real, ascending, up to a cubic) |
| `math.matrix` | `New(rows)`, `Identity(n)` → `Rows`, `Cols`, `Get`, `Transpose`, `Multiply`, `Determinant`, `Inverse` (nil if singular), `Solve(b)` |

### buffer and parsers: binary values and text formats

| Module | API |
|---|---|
| `buffer` | Values as bytes, written and read back. Writers: `Byte`, `Int16`, `Int32`, `Float32` (little-endian, IEEE 754), `Varint` (ULEB128), `String` (varint length + bytes), `Utf8(code)`, `Crc32(s)`; `Writer()` gathers them (`Bytes`, `Size`). `Reader(data)` → `Byte`, `Int16`, `UInt16`, `Int32`, `Float32`, `Varint`, `String`, `Consumed` |
| `gma` | GMod's addon archive: `Write(name, files)` → bytes (`files`: `{ path, data }`s), `Read(bytes)` → `{ name, files }` |
| `parsers.cursor` | `New(text)` → a parser's position: `Literal(s[, ignoreCase])`, `Pattern`, `Peek`, `Whitespace`, `Save`/`Restore`/`Commit`, `Position`, `AtEnd`, `Rest` |
| `parsers.utf16` | `Decode(raw)`: UTF-16LE → UTF-8 |
| `parsers.keyvalues` | `Read(text, visit(path, key, value))`: Valve KeyValues |
| `parsers.consolecfg` | `Commands(text)`: cfg text → console commands, chained `;` refused |
| `parsers.cvarfile` | `Write(names, values)` → cfg text, a `name "value"` a line; `Read(text, names)` → name → value for only those names. Client settings saved in data/ (`WS.PersistClientConVars`) |

### meta: classes, interfaces, table indexing

| Module | API |
|---|---|
| `meta.class` | `Extend(parent, fields)` (a subclass carries its parent's metamethods and `__index` function), `New(class, fields)`, `IsA(value, class)`, `Guard(class, check)` (refuses new keys on subclasses and their instances), `Construct(class, ...)` (each own `Init`, base first), `Destroy(instance, ...)` (each own `Destroy`, derived first) |
| `meta.port` | `New(name, methods)` → an interface: `Check(value)`, `Facade(value)`, `Methods`, `Name`; `Is(value)` |
| `meta.constants` | `New(name, constants)` → a `ConstantSet`: upper-case names read as fields at plain-table speed; an unknown name read, or a new one set, is refused naming the set; `set(token)` parses a name from outside (or nil; `Has`); `pairs` gives only the constants; `Names` (sorted), `tostring`/`Name`, `__len`. Values may repeat (layout sizes, colours) |
| `meta.enum` | `New(name, first, names)` → an `Enum` (a `ConstantSet`) numbering names from `first`: `enum[value]` → its name (`NameOf`), `enum(token)` parses a value or a name (or nil; `Valid`), `Check`, `tostring` → "0 Default, 1 Electro" for a convar's help (`Describe`), `First`, `Last`, `Count` (`__len`), `Names` (value order) |

### Formalisms and runtime

| Module | API |
|---|---|
| `cfsm` | Flat state machine: `Define(spec)` → `New(initial)`: `Transition`, `Enter`, `Think`, `Can`, `State`, `Is` |
| `hfsm` | NextBot Action/Behavior engine: `Action`, `Chart{ name, port, events, queries, initial }` → `State(name)`, `Owns`, `New(actor, state)` → a machine: `Update`, `Event`, `Query`, `Describe` |
| `map_io` | A map's entity lookups and output connections, through a world port |
| `tactics` | The tactics engine interface: `ENGINE` (a port), `Check(engine)` |
| `drawlist` | `New()` → draw callbacks named by dotted paths, run in order (by order, a tie by path): `Add(path, order, draw[, when])` (a path again replaces it), `HideElements(path)`/`ShowElements(path)` (the code's: a path hides all under it), `SetHidden(paths)` (the player's, apart), `Draw(...)`, `Entries()`; `ParseNames(text)`. The HUD's (`WS.HUD`, `cl_hud_hidden`) |
| `scheduler` | `New(clock)` → cooperative tasks in a time slice: `Spawn(fn, ...)`, `Run(seconds)`, `CheckYield` (in a task: yield once the slice is spent), `Yield`, `Wait(ready)` (park until ready), `Count`. `WS.Transactions` is each realm's, run every tick |
| `analytics` | Timers, counters, tick pressure, memory samples; clock and memory are ports |
| `memory` | `Measure(roots)` → estimated bytes per named root (each object once); `Format(report, rows)`. `ws_analytics_memory` runs it over the loaded foundation modules |
| `transaction` | Exchanges between user and system or between modules, settling once as committed (value), declined (a refusal: the caller's mistake) or failed (our bug). Refusals: `Refuse(kind, detail)`, `IsRefusal(err, kinds)`, `Message`, `Explain`, `Detail`. `New()` → `Commit`/`Decline`/`Fail`, `State`, `Value`, `Refusal`, `Error`, `OnSettle`, `Await(scheduler)` (in a task); `Run(fn, ...)`, `Spawn(scheduler, fn, ...)` with `fn(work, ...)` and `work:Undo(fn)` compensations; `All(list)`. Wire: `Ledger()` (`Open`, `Settle`, `Expire`, `Count`), `Reply(tx[, kinds])`. Over the network: `WS.Events.Transact` (client) and `WS.Events.Serve` (server), events defined with `transaction = true` |

### Variants outside core

| Module | Base |
|---|---|
| `foundation.pathfinder.astar` | `core.pathfinder`: NavAreaBuildPath's A*, the routes of HL2 NPCs (`features/npc/sv_routes.lua`) |
| `foundation.wartactics` | `core.tactics`: the AI war's fire-team doctrine (contact, bounding overwatch, flanking, falling back) |
| `foundation.npc.path.*` | the path cost strategies a solver's graph prices steps with |

Rationale, what stays out of core, and what to evaluate next (native
backing): `docs/foundation-core.md`.

## Adding to core

A structure or algorithm goes in `foundation/core/` (a data structure in
`structs/`, a format reader in `parsers/`, maths in `math/`, a metatable
mechanism in `meta/`)
with its test written first and an entry in
`tests/foundation_layers_test.lua`, and a line in the index above. Core names
no mode, feature or game noun.

A structure's behaviour goes in its metamethods first (indexing, assigning,
calling to walk or parse, `tostring`), with named methods as proxies
(`.claude/rules/lua-metamethods.md`); the structures are to become userdata
handles in a binary module, which honour all of them. LuaJIT ignores
`__len`, `__pairs` and `__gc` on plain tables, so define `__len` and keep
`Size` working today. Build a structure from the smaller ones (`cache` on
`slots` and `chain`), its entries in arrays by slot rather than a table
each, and give every value it owns back exactly once (a `release` callback,
`Class.Destroy`).
