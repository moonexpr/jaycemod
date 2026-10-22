-- Searches over a graph the caller describes as neighbors(node) -> a list of
-- nodes; nodes are any values usable as table keys. Route finding is
-- foundation.npc.pathfinder's; these answer what is reachable.
--
-- Flood(starts, neighbors, admit, limit[, stop]) -> the nodes reached,
--   breadth first from starts (taken as given, each once), through nodes
--   admit(node) lets in; and whether the flood was cut: it would have
--   reached more than limit nodes, or it took up a node where stop(node)
--   answers true.
-- Components(nodes, neighbors) -> node -> the number of its connected group,
--   1 up, numbered in the order of nodes.
-- Distances(starts, edges, limit) -> node -> the cheapest walk to it from
--   the nearest start (Dijkstra), edges(node) -> a list of { node, cost }
--   (costs not negative); nodes farther than limit are left out.
local ipairs = ipairs
local Heap = require("foundation.tree.heap")
module(...)

function Flood(starts, neighbors, admit, limit, stop)
	local seen, reached, head = {}, {}, 1
	for _, node in ipairs(starts) do
		if not seen[node] then
			seen[node] = true
			reached[#reached + 1] = node
		end
	end
	while head <= #reached do
		local node = reached[head]
		head = head + 1
		if stop and stop(node) then return reached, true end
		for _, next in ipairs(neighbors(node)) do
			if not seen[next] then
				seen[next] = true
				if admit(next) then
					if #reached >= limit then return reached, true end
					reached[#reached + 1] = next
				end
			end
		end
	end
	return reached, false
end

function Components(nodes, neighbors)
	local component, count = {}, 0
	for _, node in ipairs(nodes) do
		if not component[node] then
			count = count + 1
			component[node] = count
			local stack = { node }
			while #stack > 0 do
				local n = stack[#stack]
				stack[#stack] = nil
				for _, m in ipairs(neighbors(n)) do
					if not component[m] then
						component[m] = count
						stack[#stack + 1] = m
					end
				end
			end
		end
	end
	return component
end

function Distances(starts, edges, limit)
	local dist = {}
	local queue = Heap.New(function(a, b) return a.cost < b.cost end)
	for _, node in ipairs(starts) do
		dist[node] = 0
		queue:Push({ node = node, cost = 0 })
	end
	while queue:Size() > 0 do
		local top = queue:Pop()
		if top.cost == dist[top.node] then
			for _, edge in ipairs(edges(top.node)) do
				local cost = top.cost + edge.cost
				local known = dist[edge.node]
				if cost <= limit and (known == nil or cost < known) then
					dist[edge.node] = cost
					queue:Push({ node = edge.node, cost = cost })
				end
			end
		end
	end
	return dist
end
