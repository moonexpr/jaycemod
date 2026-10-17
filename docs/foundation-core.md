# foundation.core

`foundation/core/` holds Sandcastle's data structures, algorithms and codecs
(category 1, *structures*, of `docs/research/foundation-admission-rule.md`),
and the mechanisms that run a policy their caller plugs in (category 2,
*formalisms*). Nothing in core names a mode, a feature or a game noun.
Concrete variants live outside core, beside the system that owns them:
`foundation.pathfinder.<solver>`, `foundation.wartactics`.

`tests/foundation_layers_test.lua` places every module in a category and
fails on an upward dependency.

## Modules

| Module | Category | What it is | Taken from |
|---|---|---|---|
| `core.sets` | structures | Named set: a closed vocabulary parsed once (`Has`, `Check`, `Match`, `Members`) | hand-built `KNOWN` tables in reports, vote, permissions, loadout, events, `npc.debug`, cfsm |
| `core.port` | structures | Interface: the methods a value must have (`Check`, `Facade`) | hfsm's `Port` |
| `core.heap` | structures | Binary heap ordered by the caller's rule | the A* open list |
| `core.ring` | structures | The last *n* values pushed | analytics |
| `core.stats` | structures | Mean, nearest-rank percentile | analytics |
| `core.lease` | structures | Keys held by one holder for a term | squad claims |
| `core.grid` | structures | Spatial hash on number keys (`Put`, `PutBox`, `Near`, `Buckets`), `Thin` | nodegraph, nav_gaps, explore |
| `core.graph` | structures | Breadth-first `Flood`, connected `Components` | aiwar zone, lanes, nodegraph zones |
| `core.polyline` | structures | Path of points measured along its length | `aiwar.track` |
| `core.geometry` | structures | `Distance`, `Toward` | `foundation.geometry`, tactics |
| `core.random` | structures | `PickWeighted` with the random number passed in | aiwar zone |
| `core.crc32` | structures | CRC32 (zlib's, GMod's `util.CRC`) | events |
| `core.utf16` | structures | UTF-16LE to UTF-8 | localization |
| `core.keyvalues` | structures | Valve KeyValues reader | localization |
| `core.binary` | structures | Little-endian ints and IEEE singles, a reader | nodegraph's `.ain` codec |
| `core.consolecfg` | structures | cfg text to commands | `foundation.consolecfg` |
| `core.refusal` | structures | Named refusals (the player's fault, not ours) | `foundation.refusal` |
| `core.analytics` | structures | Timers, counters, tick pressure | (already in core) |
| `core.pathfinder` | structures | The search a path solver fills in (template method) | `foundation.npc.route` |
| `core.tactics` | formalisms | The tactics engine interface, as a port | new |
| `core.cfsm`, `core.hfsm`, `core.map_io` | formalisms | State machines, entity I/O | (already in core) |

## The two abstract bases

**Pathfinder.** `core.pathfinder` owns the step loop, the budget per call,
the expansion cap, the status (`RUNNING`, `FOUND`, `FAILED`) and the route
back from the goal or the node that came closest. `Pathfinder.Solver(name)`
makes a solver class that supplies `Begin`, `Next` and `Expand`, reporting
progress with `Reach(node, parent)` and `Approach(node, distance)`.
`foundation.pathfinder.astar` is NavAreaBuildPath, the first solver.

**Tactics.** `core.tactics.ENGINE` is the port of what a soldier's orders
ask a tactics engine: shared contact, bounding overwatch, flanking and
falling back. `foundation.wartactics`, the AI war's engine, checks itself
against it as it loads.

## Left where it is, for now

- hfsm's own `NameList` and `NameSet`: a chart may declare no events or
  queries, and a named set refuses an empty list.
- `nodegraph.Candidates` and `Bridges` are one *k*-nearest-pairs search with
  different filters; a `core.grid` query could serve both.
- `aiwar.squad.Key`: a spot's claim key, a kind and a grid cube.
- `events`' typed wire schema: a formalism already, with its own registry.
- wartactics keeps its state on the fire team table; an engine that owns
  per-team state would need the orders to hold an engine instance.

## To evaluate next

Now that the structures are formal types, decide which to back natively.
`docs/ns-performance-baseline.md` names route search as the largest
demand-driven cost (0.2 to 4.3 ms a tick, about 100 µs an expansion live).
That makes `foundation.pathfinder.astar` the first candidate, behind the
same solver contract, with the Lua solver as the oracle for parity tests.
The floods and the grid come next. The cost strategies (`npc/path/*`) would
have to become data a native solver evaluates, since a Lua callback per edge
would cancel the gain.
