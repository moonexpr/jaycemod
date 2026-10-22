-- Replays recorded route searches (.devtools/bin/record_routes.lua) under
-- plain LuaJIT, with the gamemode's own solver and cost strategies
-- (foundation.npc.route_record), and reports what they cost and whether
-- each replay did exactly what the live search did.
--
--   luajit .devtools/bin/route_replay.lua RECORD.dat [--repeat N]
--
-- Run from the repo root. --repeat replays every search N times for steadier
-- timings (default 1). Exits 1 when any finished search replays differently.
local T = dofile("tests/harness.lua")
local Record = T.require("foundation.npc.route_record")
local Pathfinder = T.require("foundation.core.pathfinder")

local STRATEGIES = {
	hl2 = T.require("foundation.npc.path.hl2"),
	lanes = T.require("foundation.aiwar.lanes").Strategy,
}

local MICROSECONDS = 1e6
local SHOWN_MISMATCHES = 5

local function Args(argv)
	local args = { repeats = 1 }
	local i = 1
	while argv[i] do
		if argv[i] == "--repeat" then
			args.repeats = assert(tonumber(argv[i + 1]), "--repeat takes a count")
			i = i + 2
		else
			args.path = argv[i]
			i = i + 1
		end
	end
	assert(args.path, "usage: luajit .devtools/bin/route_replay.lua RECORD.dat [--repeat N]")
	return args
end

local function Load(path)
	local f = assert(io.open(path, "rb"))
	local bytes = f:read("*a")
	f:close()
	return Record.Read(bytes)
end

local function Main(argv)
	local args = Args(argv)
	local record = Load(args.path)
	local areas, links = 0, 0
	for _, area in pairs(record.areas) do
		areas = areas + 1
		links = links + #area.links
	end
	print(string.format("%s: %d areas, %d links, %d searches", record.map, areas, links, #record.requests))
	local by, order, mismatches, matched, replayed, skipped = {}, {}, {}, 0, 0, 0
	local seconds, expansions = 0, 0
	for i, request in ipairs(record.requests) do
		if not request.result or not STRATEGIES[request.strategy] then
			skipped = skipped + 1
		else
			local g = by[request.source]
			if not g then
				g = { n = 0, live = 0, notFound = 0 }
				by[request.source] = g
				order[#order + 1] = request.source
			end
			local started, result = os.clock(), nil
			for _ = 1, args.repeats do result = Record.Replay(record, request, STRATEGIES) end
			seconds = seconds + (os.clock() - started) / args.repeats
			expansions = expansions + result.expanded
			g.n, g.live = g.n + 1, g.live + request.result.expanded
			if request.result.status ~= Pathfinder.FOUND then g.notFound = g.notFound + 1 end
			replayed = replayed + 1
			if Record.Matches(request.result, result) then
				matched = matched + 1
			else
				mismatches[#mismatches + 1] = { i = i, request = request, result = result }
			end
		end
	end
	table.sort(order)
	for _, source in ipairs(order) do
		local g = by[source]
		print(string.format("  %-8s %4d searches, %7d expansions, %d not found", source, g.n, g.live, g.notFound))
	end
	print(string.format("replayed %d (skipped %d: unfinished or no strategy); %d of %d match the live search", replayed, skipped, matched, replayed))
	if expansions > 0 then
		print(string.format("offline: %.3f s, %.2f us an expansion", seconds, seconds * MICROSECONDS / expansions))
	end
	for k = 1, math.min(#mismatches, SHOWN_MISMATCHES) do
		local m = mismatches[k]
		local live, again = m.request.result, m.result
		print(string.format("  mismatch #%d %s %d->%d: live %s %d expanded, %d areas; replay %s %d expanded, %d areas",
			m.i, m.request.source, m.request.start, m.request.goal, live.status, live.expanded, #live.route, again.status, again.expanded, #again.route))
	end
	return #mismatches == 0
end

os.exit(Main(arg) and 0 or 1)
