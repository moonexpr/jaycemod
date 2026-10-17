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
| `tests/*_test.lua` | LuaJIT tests, `tests/harness.lua`; `tests/foundation_layers_test.lua` guards foundation's layers |
| `native/` | Rust binary modules (`ws_profile`, the sampling profiler) |
| `docs/` | Design notes; `docs/research/foundation-admission-rule.md` decides what belongs in foundation |
| `.devtools/bin/` | Project tools; `.devtools/artifacts/` generated output |

Check everything with `.devtools/bin/check_lua.sh` (compiles every Lua file
and runs every test).

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
| `structs.sets` | `Named(name, members)` → a named set, a closed vocabulary parsed once: `Has`, `Check` (an unknown member is our bug, blamed on the caller), `Match` (case-free prefix), `Members`, `Name` |
| `structs.heap` | `New(before)` → binary heap: `Push`, `Pop`, `Peek`, `Size`; ties are the rule's to break |
| `structs.ring` | `New(capacity)` → the last values pushed: `Push`, `Size`, `Ordered` (oldest first) |
| `structs.lease` | `New()` → keys held by one holder for a term: `Holder`, `FreeFor`, `Take`, `Release`, `ReleaseAll` |
| `structs.grid` | `New(size)` → spatial hash on number keys: `Put`, `PutBox`, `Near` (3×3 cells), `Buckets`; `Thin(points, size)` keeps one point per cube |
| `structs.polyline` | `New(points)` → a path measured along its length: `Length`, `Leg`, `PointAt`, `Offset`, `DistanceOf` |

### Algorithms

| Module | API |
|---|---|
| `graph` | `Flood(starts, neighbors, admit, limit[, stop])` → reached, cut; `Components(nodes, neighbors)` → node → group number |
| `pathfinder` | Abstract path search (template method): `Solver(name)` → a solver class filling `Begin`, `Next`, `Expand` (reporting with `Reach`, `Approach`); it gets `New`, `Find`, `Step(budget)`, `Route`. `RUNNING`, `FOUND`, `FAILED`, `MAX_EXPANDED` |
| `geometry` | `Distance(a, b)`, `Toward(from, to, distance)` on `{ x, y, z }` |
| `stats` | `Mean(list)`, `Percentile(list, p)` (nearest rank) |
| `random` | `PickWeighted(items, weight, r)`, `r` drawn by the caller |

### encoding and parsers: binary formats and text formats

| Module | API |
|---|---|
| `encoding` | Writers: `Byte`, `Int16`, `Int32`, `Float32` (little-endian, IEEE 754), `Utf8(code)`, `Crc32(s)` |
| `parsers.binary` | `Reader(data)` → `Byte`, `Int16`, `UInt16`, `Int32`, `Float32`, `Consumed` |
| `parsers.utf16` | `Decode(raw)`: UTF-16LE → UTF-8 |
| `parsers.keyvalues` | `Read(text, visit(path, key, value))`: Valve KeyValues |
| `parsers.consolecfg` | `Commands(text)`: cfg text → console commands, chained `;` refused |

### meta: classes, interfaces, table indexing

| Module | API |
|---|---|
| `meta.class` | `Extend(parent, fields)`, `New(class, fields)`, `IsA(value, class)`, `Guard(class, check)` (refuses new keys on subclasses and their instances) |
| `meta.port` | `New(name, methods)` → an interface: `Check(value)`, `Facade(value)`, `Methods`, `Name`; `Is(value)` |

### Formalisms and runtime

| Module | API |
|---|---|
| `cfsm` | Flat state machine: `Define(spec)` → `New(initial)`: `Transition`, `Enter`, `Think`, `Can`, `State`, `Is` |
| `hfsm` | NextBot Action/Behavior engine: `Action`, `Chart{ name, port, events, queries, initial }` → `State(name)`, `Owns`, `New(actor, state)` → a machine: `Update`, `Event`, `Query`, `Describe` |
| `map_io` | A map's entity lookups and output connections, through a world port |
| `tactics` | The tactics engine interface: `ENGINE` (a port), `Check(engine)` |
| `analytics` | Timers, counters, tick pressure, memory samples; clock and memory are ports |
| `refusal` | `Raise(kind, detail)`, `Is`, `Message`, `Explain`, `Detail`: a request declined for the caller's mistake |

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
`structs/`, a format reader in `parsers/`, a metatable mechanism in `meta/`)
with its test written first and an entry in
`tests/foundation_layers_test.lua`, and a line in the index above. Core names
no mode, feature or game noun.
