-- Weighted directed graphs and the paths across them: the shortest-path tree
-- from a set of starts, paths read off it, alternative paths by the penalty
-- method, each node's ground within a reach, a tree's branch weights and
-- forks, and maximum coverage by paths along a tree. Nodes are 1..n; a step
-- goes one way at a cost.
--
-- New(count) -> a graph: g:Step(from, to, cost), g:Nodes() (#g),
--   g:Tree(starts) -> a walk: tree:Path(node), tree:Distance(node),
--   tree:Distances(), tree:Parents(), tree:Branches(floor) -> { children,
--   weight, roots }, tree:Forks(floor, share); g:Alternatives(starts, target,
--   k, detour, penalty) -> { { nodes, length } }; g:Near(reach) -> node ->
--   { nodes }; g:Cover(tree, floor, share[, reach]) -> { { nodes, gain } }.
--
-- The module is its native twin (native/foundation/src/paths.rs, bound in
-- src/bind/paths.rs): only the server runs the war that uses it, and the
-- server loads the binary. This Lua twin is a stub until clients need it.
local error = error
module(...)

-- TODO(Claude): the Lua oracle of graph.paths, the native twin's walks step
-- for step (.devtools/bin/incursion.py is their reference), when a client
-- needs it; until then it refuses, naming the native twin.
function New()
	error("graph.paths is native only (native/foundation): its Lua twin is a TODO(Claude) stub", 2)
end
