# foundation and game: plan

Split `gamemode/foundation/` in two. `foundation/` keeps the generic code
(data structures, algorithms, codecs, math, classes): the stable base the
rest of the gamemode stands on, which may come to replace GMod's own
defaults, and which the coming binary module will back. `game/` takes the
specialised code built from it (timers, the world's I/O, the NS brain,
gameplay). Both publish their modules as globals.

## Decisions (operator, 2026-10-22)

1. **foundation loads eagerly, game lazily.** `shared_loader.lua` loads
   every foundation namespace when the gamemode starts. game's namespaces
   are declared at start, and each module loads the first time a member is
   read, so a map still pays only for the gameplay it uses.
2. **Extend the existing tables.** `math` (Lua's), `list`, `file`, `timer`
   (GMod's) are extended in place: `math.geometry`, `list.queue`,
   `file.buffer`, `timer.countdown`.
3. **Replacing a GMod default is deliberate.** foundation may take over a
   GMod function, but only by declaring it (`Replace`). Writing a key that
   is already taken is otherwise refused, naming the namespace and key.
4. **Every module is listed by hand.** The loader and the indexes name each
   module on its own line: no folder scans, no loops. A replaced GMod
   function then shows in the diff that replaced it. A test fails an index
   or the loader that loops or scans.
5. **Plan, then stage 1 in a worktree** (`foundation-split`), away from
   uncommitted work on main.
6. **A module `PENDING` lists for `features/` goes there**, not to `game/`
   (spells among them).
7. **`list.schedule`'s greedy sorter** is a TODO in the code for now.
8. **The abstract path search is `graph.pathfinder`**, not `npc.pathfinder`.

## Status

- Stage 1: done.
- Stage 2: done but for the hfsm split. `hfsm` moved whole to
  `game/generator/hfsm`; drawing `generator.state_chart` out of it into
  foundation is its own step.
- Stage 3: not started.

## The loader

`gamemode/shared_loader.lua`, included first by `shared.lua` (and sent to
clients by `init.lua`). It holds Lua 5.1's `require` for the gamemode's
`module(...)` files (moved from `ws/sh_core.lua`, which keeps `WS.require`
as the same function), then runs each namespace's index, one line each:

```lua
Index("foundation/core")
Index("foundation/math")
Index("foundation/list")
-- ...
```

`Index(dir)` runs `<dir>/sh_index.lua` on both realms, and `sv_index.lua`
or `cl_index.lua` on its realm when present (game's are `sh_init.lua`,
`sv_init.lua`, `cl_init.lua`). An index is a chunk of explicit calls, run
with these in its environment:

| Call | Does |
|---|---|
| `Namespace(name)` | The global table `name`, made if absent (`list` outside GMod, `cache`) |
| `Export(ns, key, value)` | `ns[key] = value`; refuses a key already holding something it did not export |
| `Replace(ns, key, value)` | The same over a key that is taken: the declared replacement of a default |
| `Defer(ns, key, module)` | game only: `ns[key]` is `require(module)` the first time it is read |
| `require` | The loader's |

```lua
-- foundation/list/sh_index.lua
local list = Namespace("list")
Export(list, "queue", require("foundation.list.queue"))
Export(list, "Queue", list.queue.New) -- a factory used often enough
```

A module may ask for a plain global too: `Export(_G, "DrawList", ...)`.

The rules live in `foundation/core/namespace.lua` (pure, tested under
LuaJIT). Which keys it exported is a module field
(`Exported = Exported or {}`), and `module(...)` reuses its table on a
reload, so running an index again (a live reload, GMod's auto refresh)
re-exports its own keys without refusal.

`Defer` sets an `__index` on the namespace table. A namespace table that
already has a metatable is refused at load (our bug), so the first run in
game shows whether GMod's `list` or `timer` carries one.

Callers keep `require("foundation.list.queue")`. A global is the same
table, for code that wants it.

## Where each module goes

### Stage 1: foundation (eager)

| Now (`foundation/core/...`) | Becomes (`foundation/...`) | Global |
|---|---|---|
| `meta/class` | `core/class` | `core.class` |
| `meta/port` | `core/port` | `core.port` |
| `meta/constants` | `core/constants` | `core.constants` |
| `meta/enum` | `core/enum` | `core.enum` |
| (new) | `core/namespace` | `core.namespace` |
| `math/geometry` | `math/geometry` | `math.geometry` |
| `math/scalar` | `math/scalar` | `math.scalar` |
| `math/stats` | `math/stats` | `math.stats` |
| `math/random` | `math/weighted` | `math.weighted` (`math.random` is Lua's) |
| `math/polynomial` | `math/polynomial` | `math.polynomial` |
| `math/matrix` | `math/matrix` | `math.matrix` |
| `structs/polyline` | `math/polyline` | `math.polyline` |
| `structs/queue` | `list/queue` | `list.queue` |
| `structs/ring` | `list/ring` | `list.ring` |
| `structs/chain` | `list/chain` | `list.chain` |
| `structs/slots` | `list/slots` | `list.slots` |
| `scheduler` | `list/schedule` | `list.schedule` |
| `structs/heap` | `tree/heap` | `tree.heap` |
| `structs/tree` | `tree/avl` | `tree.avl` |
| `structs/sets` | `map/sets` | `map.sets` |
| `structs/pairmap` | `map/pairmap` | `map.pairmap` |
| `structs/grid` | `map/grid` | `map.grid` |
| `structs/lease` | `map/lease` | `map.lease` |
| `graph` | `graph/search` | `graph.search` |
| `structs/cache` | `cache/base` | `cache.base` |
| `structs/lru` | `cache/lru` | `cache.lru` |
| `structs/expiring` | `cache/expiring` | `cache.expiring` |
| `structs/memo` | `cache/memo` | `cache.memo` |
| `cfsm` | `generator/state_machine` | `generator.state_machine` |
| `parsers/cursor` | `encoding/cursor` | `encoding.cursor` |
| `parsers/utf16` | `encoding/utf16` | `encoding.utf16` |
| `parsers/keyvalues` | `encoding/keyvalues` | `encoding.keyvalues` |
| `parsers/consolecfg` | `encoding/consolecfg` | `encoding.consolecfg` |
| `parsers/cvarfile` | `encoding/cvarfile` | `encoding.cvarfile` |
| `gma` | `encoding/gma` | `encoding.gma` |
| `buffer` | `file/buffer` | `file.buffer` |
| `analytics` | `analysis/analytics` | `analysis.analytics` |
| `memory` | `analysis/memory` | `analysis.memory` |
| `pathfinder` | `graph/pathfinder` | `graph.pathfinder` |
| `transaction` | `transaction` | `transaction` |

Names that would read `x.x` are renamed (`cache.base`, `graph.search`,
`tree.avl`), as is `math.random`. Tests follow their module:
`tests/core_<old>_test.lua` becomes `tests/<namespace>_<module>_test.lua`.

`.devtools/bin/foundation_rename.py` holds this table, moves the files
with `git mv` and rewrites every dotted and slashed name in the Lua files
and the layers test. It refuses a destination that exists and finds
nothing to do on a second run. Run it again over main's uncommitted files
after the merge.

### Stage 2: game (lazy), from what stays in core

| Now | Becomes | Global |
|---|---|---|
| `core/drawlist` | `game/list/drawlist` | `list.drawlist` |
| `core/timers` | `game/timer/countdown`, `game/timer/interval` | `timer.countdown`, `timer.interval` |
| `core/map_io` | `game/world/io` | `world.io` |
| `core/snapshot` | `game/world/snapshot` | `world.snapshot` |
| `core/hfsm` | `foundation/generator/state_chart` + `game/generator/hfsm` | `generator.state_chart`, `generator.hfsm` |
| `core/tactics` | `game/gameplay/tactics` | `gameplay.tactics` |
| `pathfinder/astar` | `game/npc/astar` | `npc.astar` |

The hfsm split is real work: the Action/Behavior engine (states, events,
queries, transitions) becomes `state_chart`, and NextBot's action stack on
top of it stays `hfsm`. It gets its own plan.

Here `list`, `generator` and `npc` are shared between the two trees: game
adds members to the table foundation made.

### Stage 3: the rest of foundation into game

About 90 gameplay and NS modules (rounds, teams, players, npc, aiwar,
combat, ...). `tests/foundation_layers_test.lua` already sends most of the
mode-specific ones to `features/` and `ws/` (`PENDING`), spells among
them. Those go where PENDING says (decision 6). Stage 3 moves the
categorised ones (formalisms, gameplay, ns) into `game/`.

### Later

- `list/schedule`'s greedy sorter: new behaviour (the order tasks run in,
  chosen by a function the caller hands in), written test first. A TODO
  in the module marks it.

## Tests and checks

- `tests/core_namespace_test.lua`: Export, Replace, refusal of a taken key,
  re-export after a reload, Defer loading once, refusal of a metatable.
- `tests/foundation_index_test.lua`: every index runs under LuaJIT and
  installs its modules; every module file under a namespace is listed in
  its index (the test scans; the loader never does); no index and not the
  loader holds `for`, `while`, `pairs` or `file.Find`.
- `tests/foundation_layers_test.lua`: keys renamed by the script; the
  layers keep their ranks.
- `.devtools/bin/check_lua.sh` green at the end of each stage.
- In game, after each stage: the server loads a map with no Lua errors,
  and `lua_run print(list.queue, math.geometry, file.buffer)` prints three
  tables.

## Risks

- **Live reload across the rename.** Old names stay in `package.loaded`
  until the map changes. Change map once after merging; do not reload live
  across it.
- **Merge with main's uncommitted work.** Ten of main's modified files
  require foundation modules. The rename script, run again after the
  merge, rewrites them.
- **A GMod table with a metatable** stops `Defer` (stage 2) at load, by
  design; the fix is then a namespace of our own for that tree.
