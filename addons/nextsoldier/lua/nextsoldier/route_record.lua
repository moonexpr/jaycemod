-- Route searches as the server ran them, recorded so they replay offline
-- (under plain LuaJIT) with the same solver (foundation.graph.pathfinder)
-- and cost strategy (foundation.wetsands.path.*): what the npc controller's
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
--   Mesh(record, NavSearch) -> the record's mesh for a navsearch
--     implementation (wetsands.navsearch, or the native one), built once
--   Replay(record, request, strategies[, NavSearch]) -> { status, expanded,
--     route, search (done) }: the search through NavSearch (default the Lua
--     wetsands.navsearch), strategies: name -> strategy (Cost(step, limits,
--     bot), and Model(limits, bot) for the native one)
--   Matches(result, replayed) -> whether both searches did the same
local Buffer = file.buffer
local Pathfinder = graph.pathfinder
local LuaNavSearch = wetsands.navsearch
local error, format, ipairs, pairs, pcall, setmetatable, sort, tonumber, tostring = error, string.format, ipairs, pairs, pcall, setmetatable, table.sort, tonumber, tostring
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

-- Each record's mesh, built once for each navsearch implementation.
local meshes = setmetatable({}, { __mode = "k" })

function Mesh(record, NavSearch)
	local built = meshes[record]
	if not built then
		built = {}
		meshes[record] = built
	end
	if built[NavSearch] then return built[NavSearch] end
	local ids = {}
	for id in pairs(record.areas) do ids[#ids + 1] = id end
	sort(ids)
	local mesh = NavSearch.Mesh()
	for _, id in ipairs(ids) do
		local area = record.areas[id]
		mesh:Area(id, area.x, area.y, area.z, area.attributes)
	end
	for _, id in ipairs(ids) do
		for _, link in ipairs(record.areas[id].links) do mesh:Link(id, link.to, link.distance, link.rise) end
	end
	mesh:Seal()
	built[NavSearch] = mesh
	return mesh
end

-- What the live search was told and found, as navsearch's told.
local function Told(request)
	return {
		closed = request.blocked,
		uncrossable = request.uncrossable,
		rooms = request.rooms,
		estimates = request.estimates,
	}
end

function Replay(record, request, strategies, NavSearch)
	NavSearch = NavSearch or LuaNavSearch
	local strategy = strategies[request.strategy]
	if not strategy then error("no strategy " .. tostring(request.strategy) .. " to replay with", 2) end
	local search = NavSearch.New(Mesh(record, NavSearch), strategy, request.limits, request.bot, request.start,
		request.goal, request.goalPos, request.maxExpanded, Told(request))
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
