# Native foundation: plan

foundation's base structures and algorithms move into Rust binary modules,
so every system built on them gets faster without changing; NextSoldier's
heavy work, route search first, is rebuilt on those structures so it gains
with them.

Two crates, two DLLs, one binding:

| Crate | DLL | Holds |
|---|---|---|
| `native/foundation` | `gmsv_foundation_win64.dll` | base, generic structures and algorithms (heap, graph, A\* rule, grid, ...): no game nouns |
| `native/wetsands` | `gmsv_wetsands_win64.dll` | systems moved out of `games/` into `foundation.wetsands` because they gain from native backing; built on the foundation crate as a Rust library |

Each is a drop-in, accelerated foundation for a server that loads it: GMod
opening a DLL installs each native module over the global its Lua twin
publishes (`wetsands.navsearch`), with no namespace of its own, so callers
keep `local NavSearch = wetsands.navsearch` and get the native one. The
server requires the DLLs right after foundation's indexes, before any
module binds a global to a local. For the tests, `luaopen_<crate>` returns
the module's table instead, installing nothing, so the Lua twin stays as
the oracle beside it (`T.native`).

`foundation.wetsands` (the Lua namespace, global `wetsands`) is the one part
of foundation that names game things: TF2's nav mesh rules, the bots' cost
strategies. It is there because the operator put the accelerated systems
there; the rest of foundation stays free of game nouns.

## What crossing costs

`.devtools/bin/native_boundary_bench.lua`, local LuaJIT 2.1 on arm64, best of 5:

| Case | JIT on | JIT off |
|---|---|---|
| empty call: Lua / native | 0.3 / 7.4 ns | 8.6 / 13.8 ns |
| add two numbers: Lua / native | 0.9 / 14.8 ns | 18.8 / 16.5 ns |
| heap push+pop of 20k: `tree.heap` / native | 122 / 79 ns | 651 / 82 ns |

GMod strips LuaJIT's `ffi`, so a binary module is reached only through
`lua_CFunction` calls, which the JIT does not compile into its traces. A call
costs about 7 to 15 ns. So:

- An operation worth one table lookup (`pairmap:Get`, `ring:Push`) loses
  natively with the JIT on: it stays Lua.
- An operation doing real work (a heap's sift, a tree's rebalance, a grid
  query, a codec) wins even called one at a time, and wins by far with the
  JIT off or thrashing, as it is live (`docs/ns-performance-baseline.md`:
  route search runs at 100 µs an expansion live against 3.5 µs replayed).
- A whole operation (a search, a flood, an encode) wins most: one crossing
  for thousands of steps. Callers move to these.

Rerun the bench on the dev server before moving each structure; the numbers
above are a proxy (arm64, not Rosetta and Wine).

## Rules for native structures

- A native module and its Lua twin keep one contract, so the native one can
  replace the Lua in place. Foundation's callback contracts (a heap's
  `before`, a graph port's `Cost`) cannot: a call back into Lua per element
  would cancel the gain. An accelerated module's contract takes data
  (numbers, a strategy's `Model(limits, bot)`), and its Lua twin is written
  to it first.
- They hold numbers: a slot, an id, a cost. What a number stands for stays in
  Lua, in arrays by slot (the CLAUDE.md rule for structures already says
  so). No Lua values are kept natively, so no registry references.
- Rust values are full userdata, one metatable a type, freed by `__gc`.
- The Lua implementation stays: it is the oracle the native one is tested
  against, and what the client and plain LuaJIT without the build run.
  The backend is chosen once, where the module is published, never per call.
- Every API function and entry point is `C-unwind`; a function calling one
  that can raise keeps nothing alive that needs a destructor.
- A native callback into Lua (a traversal rule) is asked at most once per
  area or link per operation, and its answer kept natively.

## Order

1. **Route search: done, live on the dev server.** `wetsands.astar` and
   `wetsands.path` (moved from `games/`), `wetsands.navsearch` (the
   contract, with its Lua twin), the generic A\* and graph in
   `native/foundation`, the mesh, walker and search in `native/wetsands`;
   `features/npc/sv_routes.lua` searches through navsearch on a mesh
   snapshot. See "Measured" below.
2. **Traversal state as data** (done). The live rules cost most of a
   native search: now the npc controller keeps, per team, the areas closed
   to it (doors and brushes, and the engine's blocked flag read for every
   area at once, about a millisecond, when the blockers are taken again)
   and, per round, the spawn rooms' areas (`ClosedFor`, `SpawnRooms`), and
   tells them to each search (`told`), which asks Lua only what the
   request adds (`avoid`, `crossable`). `route_told_check.lua` runs the
   same searches both ways on the live mesh: on cp_ambush_event 80 of 80
   alike, 2.71 µs an expansion with the rules against 0.32 µs told
   (the told tables, 524 room areas and 70 closed, read each search). A
   failed search's region gets its closed edge from the closed set
   (`ClosedEdge`), since the search no longer asks about those areas. The
   told tables are still read per search; held by the mesh, they would
   cost nothing a search, and are what a search off the game thread
   would need.
3. **Floods and distances** (`graph.search`: lanes' pockets, zones, lane
   bands) on the native graph, the filters as closed-area sets. Distances
   done: `navsearch.Distances` walks the mesh snapshot with the walkable
   rise and the told uncrossable links, which the snapshot's build now
   gathers (`WS.NavLinkCrossable` of every link, spread over its slices).
   Lane planning's walks (`PlansAfterDirect`) run on it: on
   cp_ambush_event 15 walks alike to the double, 349 ms by WalkEdges
   (each walk one call, up to 57 ms warm and hundreds cold) against
   4.2 ms. The floods (`FlankGround`, zones, pockets) still call back.
4. **Grid** (`world.grid`: `Near`, `Thin`; `nav_gaps`, `explore`) and
   `nodegraph`'s nearest pairs.
5. **Tree and caches** (`tree.avl`, `cache.*` on `list.slots`/`list.chain`),
   each after the bench says it pays.
6. **Codecs** (`file.buffer`, `Crc32`, `encoding.keyvalues`).

The foundation DLL installs `tree.heap` and `tree.avl` whole and patches
`nodegraph`'s `PickNodes`, `Candidates` and `Bridges`; each has its Lua
twin written to the data contract first, ties included (the nodegraph
searches used `table.sort`, which is unstable: they now break ties by
index, at about 10 % of the Lua twin's time).

## Measured

| What | Lua | Native |
|---|---|---|
| Recorded pl_upward searches replayed offline (47, all exact) | 2.25 µs an expansion | 0.31 µs |
| Live, dev server, cp_gorge_event, 40 searches alike, JIT on | 40.1 µs | 0.29 µs |
| Live, with the controller's rules as Lua callbacks | | 0.96 µs (0.30 µs a rule call, two an area) |
| Live, cp_ambush_event, 80 searches: rules asked, against told as data | | 2.71 µs, against 0.32 µs |
| Mesh snapshot, 1880 areas | 14.9 ms | 8.5 ms |
| Five live route requests answered | | 30 ms, 3 ticks (stepped 16 expansions a look at the clock) |

Live native searches recorded on the server replay offline exactly through
both implementations (`record_routes.lua`, `route_replay.lua [--native]`).

### foundation, on the dev server

`native_bench.lua` on instance 1 (Rosetta and Wine, JIT on and off), ns
an operation, or a call where one call does the whole job:

| Module | Case | Lua (on / off) | Native (on / off) |
|---|---|---|---|
| `tree.heap` | push and pop | 198 / 643 | 118 / 126 |
| `tree.avl` | insert, get, floor, walk, remove | (see below) / 1120–2240 | 112–194 / 115–208 |
| `nodegraph` | `PickNodes`, 6000 areas | 16.1 ms / 19.4 ms | 3.0 ms / 2.9 ms |
| `nodegraph` | `Candidates`, 1500 nodes within 512 | 36.8 ms / 37.6 ms | 3.4 ms / 3.3 ms |
| `nodegraph` | `Bridges`, 1500 nodes within 720 | 24.5 ms / 28.6 ms | 1.8 ms / 1.6 ms |

The node graph build yields between steps to spend at most 4 ms of a tick,
but each of these is one call: in Lua each stalled a tick for 9 to 37 ms
(it varies with the server's load), natively each fits the budget.
`tree.avl`'s Lua twin with the JIT on measured 120 to 260 µs an operation
on the server against 2.6 µs locally: the bench flushes the JIT between
modes and the twin is recompiled from scratch under Rosetta, so that
column is not the game's; the JIT-off column (the twin at its slowest
honest speed) is 8 to 11× the native.

Under the floor, measured in Lua alone against a native call (about 15 ns
locally, 20 on the server): `list.slots` 24 ns (server, JIT on), `chain`
7, `world.pairmap` 40 for a set and a get, `lease` 18, `queue`, `ring`,
`sets.Has`, `geometry`, `scalar`, `polynomial.Evaluate`. No native twin
of an operation that cheap can win; they stay Lua. `math.matrix`,
`math.polynomial.Roots` and `math.stats` do bulk work (a 32×32 inverse
1.4 ms, `Percentile` of 1000 216 µs) but nothing in the game calls them
on a hot path (`analysis.analytics` takes a percentile per report), so
they wait for a caller.

## Threads and caches

Caching pays now; threads do not yet. At the baseline's busiest (113,230
expansions in 180 s), the native search costs about 0.6 ms of CPU a
second where the Lua one cost about 60: route search stops being a tick
cost, so moving it to a worker thread would save little, while it would
need every rule as data, a result queue polled each tick, and the guard
that the Lua state is touched only from its own thread. What pays is
step 2: the rules as native data, which cuts a live search about 4×
again, and is the precondition for a thread should a later load ask for
one. Threads fit better whole-mesh jobs a frame cannot hold (lane
planning's floods over every area, the node graph build), once they
are native.

## Detouring the engine's functions

A binary module can also hook the engine's own functions: find one in
`server.dll`, patch its entry to jump to ours, and keep a trampoline to
the original (https://gmodwiki.com/Binary_Modules_Detouring_Functions,
garrysmod_common's `Detouring::Hook`; in Rust the `retour` crate's
`RawDetour`, which builds on stable). It is a different lever from
everything above: the twins make Lua's own work faster, a detour replaces
or skips engine work.

What the dev server says (instance 1, cp_spookeyridge, the AI war with
16 DrGBase soldiers, `wsprofile` sampling every millisecond for 30 s):
the server runs at 74 FPS on about 28 % of a core, and Lua (compiled,
interpreted, the GC and the JIT together) is about 4 % of a core; the
rest of the samples are time outside the VM, which LuaJIT's profiler
charges to the next Lua entry (`hook.Call`), so they read as one line of
ULib's hook.lua. Most of the server's work is the engine's (physics,
NPC and NextBot movement, traces), not Lua's.

So a detour is worth its cost only aimed at an engine hot path we can
replace with something faster, and nothing yet names one: the Windows
`server.dll` exports almost nothing (a 1 KB export table, no symbols) and
runs translated under Rosetta, so its time cannot yet be attributed to
functions. Its RTTI type descriptors are present (`.?AVCNavArea@@`),
which locate a class's vtable more robustly than a byte signature,
though either breaks when GMod updates the binary. Before any detour:

1. an engine-side profile that names the function (symbols from the
   Linux `server_srv.so` of the same build, matched to the Windows code by
   its RTTI or strings);
2. the drop-in rule kept: a target not found leaves the engine as it was,
   and the Lua and engine paths stay the oracle;
3. the patch made and undone in `gmod13_open`/`gmod13_close`, since a
   changelevel reopens the module.

The nearer use of the same knowledge is reading, not patching: the
traversal state (the engine's blocked areas, the doors) read natively
from the engine's `CNavArea`s, laid out as the vendored `nav_area.h`
says, instead of asked of Lua per area.

## Binding

The crates resolve Lua's C API by name from whatever process opened them
(`lua_shared.dll` in GMod, the `luajit` running the tests), in about 150
lines (`native/foundation/src/lua.rs`). gmod-rs (WilliamVenner/gmod-rs) was
considered and not taken: it needs a nightly toolchain, and it finds
`lua_shared` by GMod's paths only, so a module could not open in the plain
LuaJIT the oracle tests run in. Its guard that the Lua state is touched
only from the thread that opened it is worth taking once worker threads
come.

What stays Lua: `pairmap`, `lease`, `slots`, `chain`, `ring`, `queue`,
`sets`, `geometry`'s per-point maths, `scalar`, `class`/`port`/`enum`:
single-lookup operations or metatable mechanisms, which a crossing would
only slow (measured above).
