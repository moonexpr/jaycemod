-- foundation.wetsands.navsearch's contract, held by both implementations:
-- the Lua one (the oracle, published by the index) and the native one
-- (native/wetsands, which a server installs over it). Every case runs
-- through each, and the two must also agree with each other.
local T = dofile("tests/harness.lua")
local Pathfinder = graph.pathfinder
local HL2 = T.require("foundation.wetsands.path.hl2")
local TFBot = T.require("foundation.wetsands.path.tfbot")
local Lanes = nextsoldier.lanes

local IMPLEMENTATIONS = {
	{ "lua", wetsands.navsearch },
	{ "native", T.native("wetsands") },
}

local RED, BLUE = 2, 3
local CELL = 100

--  1 - 2 - 3 - 4
--   \     /
--      5
local AREAS = {
	{ 1, 0, 0, { { 2, CELL }, { 5, 2 * CELL } } },
	{ 2, CELL, 0, { { 1, CELL }, { 3, CELL } } },
	{ 3, 2 * CELL, 0, { { 2, CELL }, { 4, CELL }, { 5, 2 * CELL } } },
	{ 4, 3 * CELL, 0, { { 3, CELL } } },
	{ 5, CELL, CELL, { { 1, 2 * CELL }, { 3, 2 * CELL } } },
}

local function Mesh(NavSearch, attributes)
	local mesh = NavSearch.Mesh()
	for _, a in ipairs(AREAS) do mesh:Area(a[1], a[2], a[3], 0, (attributes or {})[a[1]] or 0) end
	for _, a in ipairs(AREAS) do
		for _, link in ipairs(a[4]) do mesh:Link(a[1], link[1], link[2], 0) end
	end
	mesh:Seal()
	return mesh
end

local function Bot()
	return { entIndex = 12, now = 30, team = RED, route = TFBot.FASTEST_ROUTE, miniBoss = false, roundWon = false, winningTeam = 0, penalized = {} }
end

local GOAL = { x = 3 * CELL, y = 0, z = 0 }

local function Run(search)
	while search:Step(1) == Pathfinder.RUNNING do end
	return search
end

local function Joined(list) return table.concat(list, " ") end

local function Search(NavSearch, fields)
	fields = fields or {}
	return NavSearch.New(fields.mesh or Mesh(NavSearch), fields.strategy or HL2, fields.limits or HL2.SOLDIER_LIMITS,
		fields.bot or Bot(), fields.start or 1, fields.goal or 4, fields.goalPos or GOAL, fields.maxExpanded or Pathfinder.MAX_EXPANDED,
		fields.told, fields.rules)
end

-- Each case: name, a function of an implementation returning what it saw.
local CASES = {
	{ "walks the mesh to the goal by the cheapest way", function(N)
		local s = Run(Search(N))
		return { s.status, Joined(s:Route()), s.expanded, s.closest }
	end },
	{ "a closed area sends the route the long way round", function(N)
		local s = Run(Search(N, { told = { closed = { [2] = true } } }))
		return { s.status, Joined(s:Route()) }
	end },
	{ "an uncrossable link is closed one way only", function(N)
		local there = Run(Search(N, { told = { uncrossable = { [3] = { [4] = true } } } }))
		local back = Run(Search(N, { start = 4, goal = 1, goalPos = { x = 0, y = 0, z = 0 }, told = { uncrossable = { [3] = { [4] = true } } } }))
		return { there.status, Joined(there:Route()), back.status }
	end },
	{ "an enemy spawn room is closed until the round is won", function(N)
		local closed = Run(Search(N, { told = { rooms = { [2] = BLUE } } }))
		local bot = Bot()
		bot.roundWon, bot.winningTeam = true, RED
		local won = Run(Search(N, { bot = bot, told = { rooms = { [2] = BLUE } } }))
		return { Joined(closed:Route()), Joined(won:Route()) }
	end },
	{ "told estimates steer the search", function(N)
		local s = Run(Search(N, { told = { estimates = { [2] = 1e6 } } }))
		return { s.status, Joined(s:Route()), s.expanded }
	end },
	{ "rules are asked once an area and a link, and refuse", function(N)
		local asked, crossed = {}, 0
		local s = Run(Search(N, { rules = {
			traversable = function(id) asked[#asked + 1] = id return id ~= 3 end,
			crossable = function() crossed = crossed + 1 return true end,
		} }))
		local seen = {}
		for _, id in ipairs(asked) do seen[id] = (seen[id] or 0) + 1 end
		local once = true
		for _, n in pairs(seen) do once = once and n == 1 end
		return { s.status, Joined(s:Route()), once, crossed > 0 }
	end },
	{ "a crouch area is closed to a walker that cannot crouch", function(N)
		local mesh = Mesh(N, { [2] = HL2.NAV_MESH_CROUCH })
		local s = Run(Search(N, { mesh = mesh, limits = HL2.LIMITS }))
		return { s.status, Joined(s:Route()) }
	end },
	{ "the lanes' penalty pushes a plan off an earlier lane", function(N)
		local bot = Bot()
		bot.penalized = { [2] = true }
		local s = Run(Search(N, { strategy = Lanes.Strategy, bot = bot, goal = 3, goalPos = { x = 2 * CELL, y = 0, z = 0 } }))
		return { s.status, Joined(s:Route()) }
	end },
	{ "a search past its limit gives up with the closest route", function(N)
		local s = Run(Search(N, { maxExpanded = 1 }))
		return { s.status, s.expanded, Joined(s:Route()) }
	end },
	{ "a start that is the goal is found at once", function(N)
		local s = Search(N, { start = 2, goal = 2 })
		return { s.status, Joined(s:Route()), s:Step(1) }
	end },
	{ "a failed search knows how it reached every area", function(N)
		local s = Run(Search(N, { told = { closed = { [4] = true } } }))
		local parents = {}
		for id = 1, 5 do parents[#parents + 1] = tostring(s.parent[id]) end
		return { s.status, Joined(parents), s.start, s.goal, s.maxExpanded }
	end },
	{ "a route to an area on the way", function(N)
		local s = Run(Search(N))
		return { Joined(s:Route(3)) }
	end },
	{ "an area the mesh lacks is refused", function(N)
		local ok = pcall(Search, N, { goal = 9 })
		local mesh = Mesh(N)
		local sealed = pcall(mesh.Area, mesh, 9, 0, 0, 0, 0)
		return { ok, sealed }
	end },
}

local seen = {}
for _, case in ipairs(CASES) do
	for _, implementation in ipairs(IMPLEMENTATIONS) do
		local name, NavSearch = implementation[1], implementation[2]
		T.test(name .. ": " .. case[1], function()
			local ok, result = pcall(case[2], NavSearch)
			T.eq(ok, true, "ran: " .. tostring(result))
			seen[case[1]] = seen[case[1]] or {}
			seen[case[1]][name] = ok and table.concat((function()
				local parts = {}
				for i, v in ipairs(result) do parts[i] = tostring(v) end
				return parts
			end)(), " | ") or nil
		end)
	end
end

T.test("the two implementations agree on every case", function()
	for _, case in ipairs(CASES) do
		local both = seen[case[1]] or {}
		T.eq(both.native, both.lua, case[1])
	end
end)

T.test("the Lua implementation's answers are the expected ones", function()
	T.eq(seen["walks the mesh to the goal by the cheapest way"].lua, "found | 1 2 3 4 | 3 | 4", "straight")
	T.eq(seen["a closed area sends the route the long way round"].lua, "found | 1 5 3 4", "round")
	T.eq(seen["an uncrossable link is closed one way only"].lua, "failed | 1 2 3 | found", "one way")
	T.eq(seen["an enemy spawn room is closed until the round is won"].lua, "1 5 3 4 | 1 2 3 4", "rooms")
	T.eq(seen["rules are asked once an area and a link, and refuse"].lua, "failed | 1 2 | true | true", "rules")
	T.eq(seen["a crouch area is closed to a walker that cannot crouch"].lua, "found | 1 5 3 4", "crouch")
	T.eq(seen["the lanes' penalty pushes a plan off an earlier lane"].lua, "found | 1 5 3", "lanes")
	T.eq(seen["a start that is the goal is found at once"].lua, "found | 2 | found", "no move")
	T.eq(seen["an area the mesh lacks is refused"].lua, "false | false", "refused")
end)

T.finish()
