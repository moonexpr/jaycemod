-- Replays recorded route searches (.devtools/bin/record_routes.lua) under
-- plain LuaJIT, with the gamemode's own solver and cost strategies
-- (games.nextsoldier.route_record), and reports what they cost and whether
-- each replay did exactly what the live search did.
--
--   luajit .devtools/bin/route_replay.lua RECORD.dat [--repeat N] [--reach TERM]
--
-- Run from the repo root. --repeat replays every search N times for steadier
-- timings (default 1). --reach plays the searches in order through a reach
-- memo (games.nextsoldier.reach_memo) of that term: which would have been
-- answered without a search, the expansions saved, whether each answer is
-- the route the live search then found, and any it would have got wrong (a
-- goal it called out of reach that the live search reached). Exits 1 when
-- any finished search replays differently.
local T = dofile("tests/harness.lua")
local Record = T.require("games.nextsoldier.route_record")
local Pathfinder = T.require("foundation.graph.pathfinder")
local ReachMemo = T.require("games.nextsoldier.reach_memo")

local STRATEGIES = {
	hl2 = T.require("games.nextsoldier.path.hl2"),
	lanes = T.require("games.nextsoldier.lanes").Strategy,
}

local MICROSECONDS = 1e6
local SHOWN_MISMATCHES = 5
local REACH_KEYS = 32

-- Lane legs route around links a soldier cannot cross (WS.NavLinkCrossable);
-- the record keeps the refusals, not the rule, so this stands for it.
local CROSSABLE_BY_SOURCE = { lanes = { "WS.NavLinkCrossable" } }

local function Args(argv)
	local args = { repeats = 1 }
	local i = 1
	while argv[i] do
		if argv[i] == "--repeat" then
			args.repeats = assert(tonumber(argv[i + 1]), "--repeat takes a count")
			i = i + 2
		elseif argv[i] == "--reach" then
			args.reach = assert(tonumber(argv[i + 1]), "--reach takes a term in seconds")
			i = i + 2
		else
			args.path = argv[i]
			i = i + 1
		end
	end
	assert(args.path, "usage: luajit .devtools/bin/route_replay.lua RECORD.dat [--repeat N] [--reach TERM]")
	return args
end

local function Load(path)
	local f = assert(io.open(path, "rb"))
	local bytes = f:read("*a")
	f:close()
	return Record.Read(bytes)
end

-- One limits table for each set of values, as the server shares one.
local function Interned(cache, limits)
	local key = string.format("%g:%g:%g:%s", limits.stepHeight, limits.jumpHeight, limits.deathDropHeight, tostring(limits.crouches))
	cache[key] = cache[key] or limits
	return cache[key]
end

local function SameRoute(a, b)
	if #a ~= #b then return false end
	for i, id in ipairs(a) do
		if b[i] ~= id then return false end
	end
	return true
end

-- The searches in order through a reach memo: each failed search that ran
-- out of areas teaches its region, and a later one is checked against the
-- regions as the server would, with what that later search was told. The
-- record has no blocker log, so every change of generation counts as one
-- the edges' check catches (no change to the mesh's links). A request sent
-- to a region's nearest area is replayed so, to count what that costs.
local function Reach(record, term)
	local clock = { now = 0 }
	function clock:Now() return self.now end
	local memo = ReachMemo.New({
		clock = clock,
		term = term,
		capacity = REACH_KEYS,
	})
	local limitsOf, by, order = {}, {}, {}
	local function Center(id) return record.areas[id] end
	for _, request in ipairs(record.requests) do
		local result, strategy = request.result, STRATEGIES[request.strategy]
		if result and strategy then
			clock.now = request.t
			local g = by[request.source]
			if not g then
				g = { n = 0, expanded = 0, answered = 0, exact = 0, retargeted = 0, wrong = 0, saved = 0 }
				by[request.source] = g
				order[#order + 1] = request.source
			end
			g.n, g.expanded = g.n + 1, g.expanded + result.expanded
			local key = memo:Key({
				strategy = strategy,
				limits = Interned(limitsOf, request.limits),
				bot = request.bot,
				ignoreBlockers = request.source == "gates",
				crossable = CROSSABLE_BY_SOURCE[request.source],
			})
			local blocked, uncrossable = request.blocked, request.uncrossable
			local region = memo:Unreachable(key, request.start, request.goal, function(id) return not blocked[id] end, function(from, to)
				return not (uncrossable[from] and uncrossable[from][to])
			end, request.generation, function() return true end)
			if region then
				if result.status == Pathfinder.FOUND then g.wrong = g.wrong + 1 end
				if region.start == request.start then
					g.answered, g.saved = g.answered + 1, g.saved + result.expanded
					if SameRoute(region:RouteTo(region:Nearest(request.goalPos, Center)), result.route) then g.exact = g.exact + 1 end
				else
					local nearest = region:Nearest(request.goalPos, Center)
					local nearer = setmetatable({ goal = nearest, goalPos = Center(nearest), estimates = {} }, { __index = request })
					g.retargeted = g.retargeted + 1
					g.saved = g.saved + result.expanded - Record.Replay(record, nearer, STRATEGIES).expanded
				end
			elseif result.status == Pathfinder.FAILED and result.expanded < request.maxExpanded then
				local search = Record.Replay(record, request, STRATEGIES).search
				memo:Learn(key, ReachMemo.Region(request.start, search.parent, blocked, uncrossable), request.generation)
			end
		end
	end
	table.sort(order)
	print(string.format("reach memo, %g s:", term))
	for _, source in ipairs(order) do
		local g = by[source]
		print(string.format("  %-8s %4d searches: %4d answered without a search (%d the route the search found), %d sent to a nearer goal, %d wrong; %7d of %7d expansions saved",
			source, g.n, g.answered, g.exact, g.retargeted, g.wrong, g.saved, g.expanded))
	end
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
	if args.reach then Reach(record, args.reach) end
	return #mismatches == 0
end

os.exit(Main(arg) and 0 or 1)
