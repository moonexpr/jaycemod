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
2. **Traversal state as native data.** The live rules cost about 70 % of a
   native search (below): the doors' and brushes' closures per team
   (renewed with the blocker generation), the engine's blocked areas, the
   spawn rooms (per round) and `WS.NavLinkCrossable` (fixed per map) become
   masks the mesh holds, set from Lua when they change, so a search asks
   Lua nothing but the request's own `avoid`. That is also what a search
   off the game thread would need.
3. **Floods and distances** (`graph.search`: lanes' pockets, zones, lane
   bands) on the native graph, the filters as closed-area sets.
4. **Grid** (`world.grid`: `Near`, `Thin`; `nav_gaps`, `explore`) and
   `nodegraph`'s nearest pairs.
5. **Tree and caches** (`tree.avl`, `cache.*` on `list.slots`/`list.chain`),
   each after the bench says it pays.
6. **Codecs** (`file.buffer`, `Crc32`, `encoding.keyvalues`).

The foundation DLL installs nothing yet: each structure needs its Lua twin
written to a data contract first (a keyed heap of numbers beside
`tree.heap`'s comparator one, floods over the native graph).

## Measured

| What | Lua | Native |
|---|---|---|
| Recorded pl_upward searches replayed offline (47, all exact) | 2.25 µs an expansion | 0.31 µs |
| Live, dev server, cp_gorge_event, 40 searches alike, JIT on | 40.1 µs | 0.29 µs |
| Live, with the controller's rules as Lua callbacks | | 0.96 µs (0.30 µs a rule call, two an area) |
| Mesh snapshot, 1880 areas | 14.9 ms | 8.5 ms |
| Five live route requests answered | | 30 ms, 3 ticks (stepped 16 expansions a look at the clock) |

Live native searches recorded on the server replay offline exactly through
both implementations (`record_routes.lua`, `route_replay.lua [--native]`).

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

## Binding

The crates resolve Lua's C API by name from whatever process opened them
(`lua_shared.dll` in GMod, the `luajit` running the tests), in about 150
lines (`native/foundation/src/lua.rs`). gmod-rs (WilliamVenner/gmod-rs) was
considered and not taken: it needs a nightly toolchain, and it finds
`lua_shared` by GMod's paths only, so a module could not open in the plain
LuaJIT the oracle tests run in. Its guard that the Lua state is touched
only from the thread that opened it is worth taking once worker threads
come.

What stays Lua: `pairmap`, `ring`, `queue`, `sets`, `geometry`'s per-point
maths, `class`/`port`/`enum`: single-lookup operations or metatable
mechanisms, which a crossing would only slow.
