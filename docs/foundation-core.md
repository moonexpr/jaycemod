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

The full index of core, with each module's API, is in the repository's
`CLAUDE.md` ("foundation.core index"). Core is split into `structs/` (data
structures), `parsers/` (format readers, beside `encoding`, the writers),
`meta/` (classes and interfaces), and algorithms and formalisms at its root.

## The two abstract bases

**Pathfinder.** `core.pathfinder` owns the step loop, the budget per call,
the expansion cap, the status (`RUNNING`, `FOUND`, `FAILED`) and the route
back from the goal or the node that came closest. `Pathfinder.Solver(name)`
makes a solver class that supplies `Begin`, `Next` and `Expand`, reporting
progress with `Reach(node, parent)` and `Approach(node, distance)`.
`foundation.pathfinder.astar` is NavAreaBuildPath, the first solver.

**Tactics.** `core.tactics.ENGINE` is the port (a `core.meta.port`) of what a soldier's orders
ask a tactics engine: shared contact, bounding overwatch, flanking and
falling back. `foundation.wartactics`, the AI war's engine, checks itself
against it as it loads.

## Left where it is, for now

- hfsm's own `NameList` and `NameSet`: a chart may declare no events or
  queries, and a named set refuses an empty list.
- `nodegraph.Candidates` and `Bridges` are one *k*-nearest-pairs search with
  different filters; a `core.structs.grid` query could serve both.
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
