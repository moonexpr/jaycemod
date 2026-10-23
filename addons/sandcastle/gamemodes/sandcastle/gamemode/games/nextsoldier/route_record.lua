-- Route searches as the server ran them, recorded so they replay offline
-- (under plain LuaJIT) with the same solver (games.npc.astar)
-- and cost strategy (games.nextsoldier.path.*): what the npc controller's
-- NavGraph (features/npc/sv_routes.lua) answered is written down, so a
-- replay asks the same questions of the record instead of the engine.
-- .devtools/bin/record_routes.lua records on the server;
-- .devtools/bin/route_replay.lua replays.
--
-- A record is { map, areas, requests }:
--   areas[id] = { x, y, z (its centre), attributes (NAV_MESH_*), links }
--     links = { to, distance (centre to centre, as the engine measures),
--     rise (ComputeAdjacentConnectionHeightChange) } in GetAdjacentAreas'
--     order: the NavGraph's neighbours
--   requests = { t, source, team, start, goal (area ids), goalPos, strategy
--     (a name), generation (the blocker count), maxExpanded, limits, bot,
--     blocked (id -> true: areas the live search found untraversable),
--     uncrossable (from -> to -> true), rooms (id -> spawn room team, those
--     not NO_ROOM), estimates (id -> the estimate the live search took),
--     result ({ status, expanded, route }, nil for a search unfinished) }
-- The live search asked about the areas it reached; a replay that reaches
-- others (another solver) finds them open, in no spawn room, estimated from
-- their centres.
--
--   Write(record) -> bytes, Read(bytes) -> record (refuses another format)
--   Graph(record, request, strategy) -> the solver's graph port over it
--   Replay(record, request, strategies) -> { status, expanded, route,
--     search (the solver's, done) }, strategies: name -> strategy
--     (Cost(step, limits, bot))
--   Matches(result, replayed) -> whether both searches did the same
local Buffer = require("foundation.file.buffer")
local Geometry = require("foundation.math.geometry")
local Pathfinder = require("foundation.graph.pathfinder")
local AStar = require("games.npc.astar")
local Path = require("games.nextsoldier.path")
local error, format, ipairs, pairs, pcall, setmetatable, tonumber, tostring = error, string.format, ipairs, pairs, pcall, setmetatable, tonumber, tostring
module(...)

FORMAT, VERSION = "ws_route_record", 1

-- TEAM_UNASSIGNED: an area in no spawn room.
NO_ROOM = 0

local TRUE, FALSE = 1, 0

-- Writing ----------------------------------------------------------------------------

-- A double, exactly: time, which a single would round.
local function WriteNumber(w, x) w:String(format("%.17g", x)) end

local function WriteBool(w, b) w:Byte(b and TRUE or FALSE) end

local function WritePoint(w, p)
	w:Float32(p.x)
	w:Float32(p.y)
	w:Float32(p.z)
end

local function Count(map)
	local n = 0
	for _ in pairs(map) do n = n + 1 end
	return n
end

local function WriteIds(w, set)
	w:Varint(Count(set))
	for id in pairs(set) do w:Varint(id) end
end

local function WriteArea(w, id, area)
	w:Varint(id)
	WritePoint(w, area)
	w:Varint(area.attributes)
	w:Varint(#area.links)
	for _, link in ipairs(area.links) do
		w:Varint(link.to)
		w:Float32(link.distance)
		w:Float32(link.rise)
	end
end

local function WriteBot(w, bot)
	w:Varint(bot.entIndex)
	WriteNumber(w, bot.now)
	w:Varint(bot.team)
	w:Varint(bot.route)
	WriteBool(w, bot.miniBoss)
	WriteBool(w, bot.roundWon)
	w:Varint(bot.winningTeam)
	WriteIds(w, bot.penalized or {})
end

local function WriteRequest(w, r)
	WriteNumber(w, r.t)
	w:String(r.source)
	w:Varint(r.team)
	w:Varint(r.start)
	w:Varint(r.goal)
	WritePoint(w, r.goalPos)
	w:String(r.strategy)
	w:Varint(r.generation)
	w:Varint(r.maxExpanded)
	w:Float32(r.limits.stepHeight)
	w:Float32(r.limits.jumpHeight)
	w:Float32(r.limits.deathDropHeight)
	WriteBool(w, r.limits.crouches)
	WriteBot(w, r.bot)
	WriteIds(w, r.blocked)
	local pairsOut = {}
	for from, tos in pairs(r.uncrossable) do
		for to in pairs(tos) do pairsOut[#pairsOut + 1] = { from, to } end
	end
	w:Varint(#pairsOut)
	for _, p in ipairs(pairsOut) do
		w:Varint(p[1])
		w:Varint(p[2])
	end
	w:Varint(Count(r.rooms))
	for id, team in pairs(r.rooms) do
		w:Varint(id)
		w:Varint(team)
	end
	w:Varint(Count(r.estimates))
	for id, value in pairs(r.estimates) do
		w:Varint(id)
		w:Float32(value)
	end
	WriteBool(w, r.result ~= nil)
	if r.result then
		w:String(r.result.status)
		w:Varint(r.result.expanded)
		w:Varint(#r.result.route)
		for _, id in ipairs(r.result.route) do w:Varint(id) end
	end
end

function Write(record)
	local w = Buffer.Writer()
	w:String(FORMAT)
	w:Varint(VERSION)
	w:String(record.map)
	w:Varint(Count(record.areas))
	for id, area in pairs(record.areas) do WriteArea(w, id, area) end
	w:Varint(#record.requests)
	for _, r in ipairs(record.requests) do WriteRequest(w, r) end
	return w:Bytes()
end

-- Reading ----------------------------------------------------------------------------

local function ReadNumber(r) return tonumber(r:String()) end

local function ReadBool(r) return r:Byte() == TRUE end

local function ReadPoint(r)
	return {
		x = r:Float32(),
		y = r:Float32(),
		z = r:Float32(),
	}
end

local function ReadIds(r)
	local set = {}
	for _ = 1, r:Varint() do set[r:Varint()] = true end
	return set
end

local function ReadArea(r)
	local id = r:Varint()
	local area = ReadPoint(r)
	area.attributes = r:Varint()
	area.links = {}
	for i = 1, r:Varint() do
		area.links[i] = {
			to = r:Varint(),
			distance = r:Float32(),
			rise = r:Float32(),
		}
	end
	return id, area
end

local function ReadBot(r)
	return {
		entIndex = r:Varint(),
		now = ReadNumber(r),
		team = r:Varint(),
		route = r:Varint(),
		miniBoss = ReadBool(r),
		roundWon = ReadBool(r),
		winningTeam = r:Varint(),
		penalized = ReadIds(r),
	}
end

local function ReadRequest(r)
	local q = {
		t = ReadNumber(r),
		source = r:String(),
		team = r:Varint(),
		start = r:Varint(),
		goal = r:Varint(),
		goalPos = ReadPoint(r),
		strategy = r:String(),
		generation = r:Varint(),
		maxExpanded = r:Varint(),
	}
	q.limits = {
		stepHeight = r:Float32(),
		jumpHeight = r:Float32(),
		deathDropHeight = r:Float32(),
		crouches = ReadBool(r),
	}
	q.bot = ReadBot(r)
	q.blocked = ReadIds(r)
	q.uncrossable = {}
	for _ = 1, r:Varint() do
		local from, to = r:Varint(), r:Varint()
		q.uncrossable[from] = q.uncrossable[from] or {}
		q.uncrossable[from][to] = true
	end
	q.rooms = {}
	for _ = 1, r:Varint() do q.rooms[r:Varint()] = r:Varint() end
	q.estimates = {}
	for _ = 1, r:Varint() do q.estimates[r:Varint()] = r:Float32() end
	if ReadBool(r) then
		q.result = {
			status = r:String(),
			expanded = r:Varint(),
			route = {},
		}
		for i = 1, r:Varint() do q.result.route[i] = r:Varint() end
	end
	return q
end

function Read(bytes)
	local r = Buffer.Reader(bytes)
	local ok, header = pcall(r.String, r)
	if not ok or header ~= FORMAT then error("not a route record", 2) end
	local version = r:Varint()
	if version ~= VERSION then error("a route record of version " .. tostring(version) .. ", not " .. VERSION, 2) end
	local record = {
		map = r:String(),
		areas = {},
		requests = {},
	}
	for _ = 1, r:Varint() do
		local id, area = ReadArea(r)
		record.areas[id] = area
	end
	for i = 1, r:Varint() do record.requests[i] = ReadRequest(r) end
	return record
end

-- Replaying ----------------------------------------------------------------------------

-- Each area's neighbours and links by their far end, derived once per mesh.
local derived = setmetatable({}, { __mode = "k" })

local function Derived(areas)
	local d = derived[areas]
	if d then return d end
	d = {
		neighbors = {},
		linkTo = {},
	}
	for id, area in pairs(areas) do
		local ids, byTo = {}, {}
		for i, link in ipairs(area.links) do
			ids[i] = link.to
			byTo[link.to] = link
		end
		d.neighbors[id], d.linkTo[id] = ids, byTo
	end
	derived[areas] = d
	return d
end

local ReplayGraph = {}
ReplayGraph.__index = ReplayGraph

-- The step a strategy prices, as the controller's FillStep fills it for the
-- Lua search (no ladders: an engine NPC climbs none).
function ReplayGraph:Cost(from, to, costSoFar)
	local request = self.request
	local refused = request.uncrossable[from]
	if refused and refused[to] then return Path.IMPASSABLE end
	local link, step = self.linkTo[from][to], self.step
	step.hasFrom = true
	step.traversable = not request.blocked[to]
	step.ladderLength = nil
	step.length = link.distance
	step.centerDistance = link.distance
	step.heightChange = link.rise
	step.fromCostSoFar = costSoFar
	step.areaId = to
	step.spawnRoomTeam = request.rooms[to] or NO_ROOM
	step.attributes = self.areas[to].attributes
	return self.strategy.Cost(step, request.limits, request.bot)
end

function ReplayGraph:Neighbors(id)
	return self.neighbors[id]
end

function ReplayGraph:Estimate(id)
	return self.request.estimates[id] or Geometry.Distance(self.areas[id], self.request.goalPos)
end

function Graph(record, request, strategy)
	local d = Derived(record.areas)
	return setmetatable({
		areas = record.areas,
		neighbors = d.neighbors,
		linkTo = d.linkTo,
		request = request,
		strategy = strategy,
		step = {},
	}, ReplayGraph)
end

function Replay(record, request, strategies)
	local strategy = strategies[request.strategy]
	if not strategy then error("no strategy " .. tostring(request.strategy) .. " to replay with", 2) end
	local search = AStar.New(Graph(record, request, strategy), request.start, request.goal, request.maxExpanded)
	while search:Step(search.maxExpanded + 1) == Pathfinder.RUNNING do end
	return {
		status = search.status,
		expanded = search.expanded,
		route = search:Route(),
		search = search,
	}
end

function Matches(result, replayed)
	if result.status ~= replayed.status or result.expanded ~= replayed.expanded or #result.route ~= #replayed.route then return false end
	for i, id in ipairs(result.route) do
		if replayed.route[i] ~= id then return false end
	end
	return true
end
