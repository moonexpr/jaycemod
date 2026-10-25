-- Records the server's Lua route searches so they replay offline
-- (games.nextsoldier.route_record; .devtools/bin/route_replay.lua), through
-- server_lua.py:
--
--   server_lua.py -f .devtools/bin/record_routes.lua          defines WSRouteRecord
--   server_lua.py 'return WSRouteRecord.Start(120, true)'     record 120 s, from a round restart
--   server_lua.py 'return WSRouteRecord.Report()'             what it has so far
--   server_lua.py 'return WSRouteRecord.Save("pl_upward_war")'  data/ws_routes/<name>.dat
--
-- Each search is wrapped as it is made: a search on the mesh
-- (wetsands.navsearch, native on a server with native/wetsands) through its
-- rules, a watched one (foundation.graph.pathfinder, on the NavGraph) through
-- its graph. Every area the search found untraversable, every link its
-- crossable refused, every spawn room it read (and, on the NavGraph, every
-- estimate it took; the mesh's are its centres' distances, which a replay
-- computes alike) is written down, with the request and, once the search is
-- done, what it found. Save adds the nav mesh: each area's centre,
-- attributes and links in the order the NavGraph walks them.
WSRouteRecord = WSRouteRecord or {}
local R = WSRouteRecord

local Record = nextsoldier.route_record
local NavSearch = wetsands.navsearch
local Pathfinder = graph.pathfinder
local HL2 = WS.require("foundation.wetsands.path.hl2")
local Lanes = nextsoldier.lanes

local DIR = "ws_routes"

local restore = {}

local function Swap(tbl, key, fn)
	restore[#restore + 1] = { tbl, key, tbl[key] }
	tbl[key] = fn
end

local function Unswap()
	for i = #restore, 1, -1 do restore[i][1][restore[i][2]] = restore[i][3] end
	restore = {}
end

local function StrategyName(strategy)
	if strategy == HL2 then return "hl2" end
	if strategy == Lanes.Strategy then return "lanes" end
	return "other"
end

local function Source(req)
	if req.ignoreBlockers then return "gates" end
	if req.strategy == HL2 then return "soldier" end
	if req.strategy == Lanes.Strategy then return "lanes" end
	return "other"
end

local function CopyBot(bot)
	local penalized = {}
	for id in pairs(bot.penalized or {}) do penalized[id] = true end
	return {
		entIndex = bot.entIndex or 0,
		now = bot.now or CurTime(),
		team = bot.team or WS.TEAM_UNASSIGNED,
		route = bot.route or 0,
		miniBoss = bot.miniBoss == true,
		roundWon = bot.roundWon == true,
		winningTeam = bot.winningTeam or WS.TEAM_UNASSIGNED,
		penalized = penalized,
	}
end

-- The graph's answers written into rec as the search asks them.
local function Watch(graph, rec)
	local traversable = graph.traversable
	graph.traversable = function(area)
		local open = traversable(area)
		if not open then rec.blocked[area:GetID()] = true end
		return open
	end
	local crossable = graph.crossable
	if crossable then
		graph.crossable = function(from, to)
			local ok = crossable(from, to)
			if not ok then
				local id = from:GetID()
				rec.uncrossable[id] = rec.uncrossable[id] or {}
				rec.uncrossable[id][to:GetID()] = true
			end
			return ok
		end
	end
	local controller = graph.controller
	graph.controller = setmetatable({
		FillStep = function(_, step, ...)
			local filled = controller:FillStep(step, ...)
			if step.hasFrom and step.spawnRoomTeam ~= Record.NO_ROOM then rec.rooms[step.areaId] = step.spawnRoomTeam end
			return filled
		end,
	}, { __index = controller })
	local estimate = graph.Estimate
	graph.Estimate = function(g, id, goal)
		local value = estimate(g, id, goal)
		rec.estimates[id] = value
		return value
	end
end

-- The rules' answers written into rec as the search asks them.
local function WatchRules(rules, rec)
	local watched = {}
	if rules.traversable then
		watched.traversable = function(id)
			local open = rules.traversable(id)
			if not open then rec.blocked[id] = true end
			return open
		end
	end
	if rules.crossable then
		watched.crossable = function(from, to)
			local ok = rules.crossable(from, to)
			if not ok then
				rec.uncrossable[from] = rec.uncrossable[from] or {}
				rec.uncrossable[from][to] = true
			end
			return ok
		end
	end
	if rules.room then
		watched.room = function(id)
			local team = rules.room(id)
			if team ~= Record.NO_ROOM then rec.rooms[id] = team end
			return team
		end
	end
	return watched
end

-- The request a search was made for, as a record holds it.
local function Rec(npcs, source, strategy, limits, bot, start, goal, goalPos, maxExpanded)
	return {
		t = CurTime() - R.started,
		source = source or "other",
		team = bot.team or WS.TEAM_UNASSIGNED,
		start = start,
		goal = goal,
		goalPos = {
			x = goalPos.x,
			y = goalPos.y,
			z = goalPos.z,
		},
		strategy = StrategyName(strategy),
		generation = npcs.blockerGeneration,
		maxExpanded = maxExpanded or Pathfinder.MAX_EXPANDED,
		limits = {
			stepHeight = limits.stepHeight,
			jumpHeight = limits.jumpHeight,
			deathDropHeight = limits.deathDropHeight,
			crouches = limits.crouches == true,
		},
		bot = CopyBot(bot),
		blocked = {},
		uncrossable = {},
		rooms = {},
		estimates = {},
	}
end

function R.Start(seconds, restart)
	if R.running then return "already recording" end
	local npcs = WS.Feature("npc")
	R.searches, R.started, R.running, R.map = {}, CurTime(), true, game.GetMap()
	R.reach0 = table.Copy(npcs.reachStats or {})
	local pending
	local request = npcs.RequestRoute
	Swap(npcs, "RequestRoute", function(self, req)
		pending = Source(req)
		local r = request(self, req)
		pending = nil
		return r
	end)
	local new = Pathfinder.New
	Swap(Pathfinder, "New", function(graph, start, goal, maxExpanded)
		local rec = Rec(npcs, pending, graph.strategy, graph.limits, graph.bot or {}, start, goal, graph.goalPos, maxExpanded)
		Watch(graph, rec)
		local search = new(graph, start, goal, maxExpanded)
		R.searches[#R.searches + 1] = {
			rec = rec,
			search = search,
		}
		return search
	end)
	local newMesh = NavSearch.New
	Swap(NavSearch, "New", function(mesh, strategy, limits, bot, start, goal, goalPos, maxExpanded, told, rules)
		local rec = Rec(npcs, pending, strategy, limits, bot or {}, start, goal, goalPos, maxExpanded)
		local search = newMesh(mesh, strategy, limits, bot, start, goal, goalPos, maxExpanded, told, WatchRules(rules or {}, rec))
		R.searches[#R.searches + 1] = {
			rec = rec,
			search = search,
		}
		return search
	end)
	timer.Create("ws_route_record", seconds, 1, R.Stop)
	if restart then RunConsoleCommand("mp_round_restart") end
	return string.format("recording route searches for %d s%s", seconds, restart and ", from a round restart" or "")
end

function R.Stop()
	timer.Remove("ws_route_record")
	Unswap()
	R.running = false
	return "stopped"
end

-- The searches so far, each with its result once done.
local function Requests()
	local list = {}
	for _, entry in ipairs(R.searches or {}) do
		local rec, search = entry.rec, entry.search
		if search.status ~= Pathfinder.RUNNING then
			rec.result = {
				status = search.status,
				expanded = search.expanded,
				route = search:Route(),
			}
		end
		list[#list + 1] = rec
	end
	return list
end

-- The mesh as the NavGraph walks it: its cached neighbours where it has
-- them (ws/sv_nav.lua links seams at run time), else the engine's.
local function Areas(npcs)
	local areas = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		local id, center = area:GetID(), area:GetCenter()
		local others = {}
		local cached = npcs.neighbors and npcs.neighbors[id]
		if cached then
			for i, to in ipairs(cached) do others[i] = navmesh.GetNavAreaByID(to) end
		else
			others = area:GetAdjacentAreas()
		end
		local links = {}
		for i, other in ipairs(others) do
			links[i] = {
				to = other:GetID(),
				distance = other:GetCenter():Distance(center),
				rise = area:ComputeAdjacentConnectionHeightChange(other),
			}
		end
		areas[id] = {
			x = center.x,
			y = center.y,
			z = center.z,
			attributes = area:GetAttributes(),
			links = links,
		}
	end
	return areas
end

function R.Save(name)
	local requests = Requests()
	local bytes = Record.Write({
		map = R.map or game.GetMap(),
		areas = Areas(WS.Feature("npc")),
		requests = requests,
	})
	file.CreateDir(DIR)
	local path = DIR .. "/" .. name .. ".dat"
	local f = file.Open(path, "wb", "DATA")
	f:Write(bytes)
	f:Close()
	return string.format("data/%s: %d searches, %d bytes", path, #requests, #bytes)
end

function R.Report()
	local requests = Requests()
	local by, done = {}, 0
	for _, rec in ipairs(requests) do
		by[rec.source] = (by[rec.source] or 0) + 1
		if rec.result then done = done + 1 end
	end
	local parts = {}
	for source, n in pairs(by) do parts[#parts + 1] = source .. " " .. n end
	local reach, now = {}, WS.Feature("npc").reachStats or {}
	for k, v in pairs(now) do reach[#reach + 1] = k .. " " .. (v - ((R.reach0 or {})[k] or 0)) end
	table.sort(reach)
	return string.format("%s: %d searches (%s), %d done; reach memo: %s", R.running and "recording" or "stopped", #requests,
		table.concat(parts, ", "), done, #reach > 0 and table.concat(reach, ", ") or "off")
end
