# Incursion, room classes and ambush hints in the game

The room tooling (`.devtools/bin/incursion.py`, `classes.py`, `ambush.py`,
drawn by `incursion_view.py` and `classes_view.py`) settled how a map's
rooms are classed from the incursion, how each team's spanning tree is
grown over the rooms (for planning lanes), and where ambushes lie. This
plan moves it into the game, the operator's call of 2026-10-30: Rust for
the generic algorithms, Lua for the war's own rules and the controllers.
The Python stays as the reference the Lua is tested against by fixture.

## Layers

| Layer | What | Where |
|---|---|---|
| foundation, native | `graph.paths`: a weighted directed graph built once (nodes, steps with a cost), and on it the shortest-path tree from a set of starts (each node's distance and parent), a path read off it, alternative paths by the penalty method, each node's ground within a reach, a tree's branch weights and forks, and maximum coverage by paths along a tree | `native/foundation/src/paths.rs` (plain Rust, `cargo test`), `src/bind/paths.rs` (its Lua face) |
| foundation, Lua twin | `foundation/graph/paths.lua`: a stub, each function raising `TODO(Claude)`. Clients never run the war, and the server runs the native twin, so the Lua oracle waits | published by `graph/sh_index.lua` as a `Twin`; its tests run in the native pass only |
| wartactics | `incursion` (the nav graph with breakable windows as steps; each team's walk, routes, front, traffic, tree, breaches), `classes` (restricted and highways, the spanning tree over the rooms, occupation, the gradient, junctions), `ambush` (entrances, frustums, markings) | `wartactics/*.lua`, tests `tests/wartactics_*_test.lua` from the Python's fixtures |
| controllers | the aiwar feature: from the room graph and partition it already builds, on the slow lane, the hiding spots traced, the classes and trees and markings found, kept beside the rooms; `ns_classes_print`; the rooms overlay showing classes, trees and markings | `features/aiwar/sv_classes.lua`, `features/nbdebug/cl_rooms.lua` |

foundation names no game noun: `graph.paths` knows nodes, costs, starts
and floors; teams, rooms, windows and spawns are wartactics'.

## graph.paths, the interface

    local g = graph.paths.New(count)         -- nodes 1..count
    g:Step(from, to, cost)                   -- one way; the order kept
    g:Finish()
    local tree = g:Tree(starts[, penalised]) -- { distance, parent }: node -> ...
    g:Path(tree, node)                       -- starts .. node, or nil
    g:Alternatives(starts, target, k, detour, penalty) -- { { nodes, length } }, shortest first
    g:Near(reach)                            -- node -> the nodes within reach
    graph.paths.Weights(tree, floor)         -- node -> floor through it; children
    graph.paths.Forks(tree, weights, share)  -- the nodes where it splits into ways of share
    graph.paths.Cover(tree, floor, share[, near]) -- { { nodes, gain } }, the fewest

Every result is plain Lua tables, the native work done in one call.

## Steps

1. `paths.rs`: the algorithms, with `cargo test` holding them to the
   Python tooling's cases (`test_incursion.py`).
2. `bind/paths.rs` and the Lua stub; `tests/graph_paths_test.lua`, native
   pass only; the parity, layers and index tests told of the module.
3. `wartactics.incursion`, `wartactics.classes`, `wartactics.ambush`, each
   with its tests, ported from the Python's.
4. `features/aiwar/sv_classes.lua`: computed with the rooms on the slow
   lane, kept with them (`ROOMS_VERSION`), the hiding spots' sight traced
   a slice at a time; `ns_classes_print`.
5. The overlay: classes, each team's tree over the rooms, the ambush
   markings.
6. Lanes on the spanning tree: a later plan.

## Done

Steps 1 to 4 (2026-10-30): `paths.rs` and its binding, the stub and its
native-pass tests; `wartactics.incursion` (native-pass tests),
`wartactics.classes` (the stages over the spaces in both passes, the
gradient and junctions native) and `wartactics.ambush` (both passes);
`features/aiwar/sv_classes.lua` and `ns_classes_print`. Step 5: the
rooms overlay (game_aiwar_rooms) carries each room's class, team and
gradient, each team's tree as branches, the junctions and the ambush
markings; `cl_rooms.lua` colours the rooms by class and draws the rest. A map change
loads a rebuilt `gmsv_foundation_win64.dll` (`cargo xwin build --release
--target x86_64-pc-windows-msvc`, which `server_root.py` links into the
server's `lua/bin`); no restart was needed.

## Open

- The Lua oracle of `graph.paths`, should clients ever need it.
- Saving coverage and crouch-only hiding spots on the nav mesh (issue #13).
