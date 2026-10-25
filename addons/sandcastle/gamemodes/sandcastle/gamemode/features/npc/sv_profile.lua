-- Part of the npc controller (sv.lua): path profiling, the path searches
-- watched for the nbdebug feature, and the bench, with their commands.
-- Pairs with profile.lua.
local Controller, NavGraph = ...
local Profile = WS.require("features.npc.profile")

-------------------------------------------------------------------------------
-- Path profiling: whether the NextBots' path search is worth moving off the
-- main thread (a binary module), measured before anything is built.

local PROFILE_WINDOW_DEFAULT, PROFILE_WINDOW_MAX = 30, 600
local BENCH_DEFAULT, BENCH_MAX = 200, 5000

function Controller:PathProfile()
	return self.pathProfile
end

-- Runs compute(), a Path:Compute through bot's cost function, with a probe
-- on that function (and its costs to `recorder`, if given). Returns what
-- compute returned, the seconds it took, and the probe.
local function Probed(bot, recorder, compute)
	local probe = {
		costCalls = 0,
		costSeconds = 0,
		recorder = recorder,
	}
	bot.pathProbe = probe
	local started = SysTime()
	local found = compute()
	local seconds = SysTime() - started
	bot.pathProbe = nil
	return found, seconds, probe
end

local function RecordProfile(profile, label, found, seconds, probe)
	profile:Record({
		label = label,
		seconds = seconds,
		costCalls = probe.costCalls,
		costSeconds = probe.costSeconds,
		found = found,
	})
end

-- Records in the profile how long compute() took and how much of that was
-- the cost callback.
function Controller:MeasureCompute(profile, label, bot, compute)
	local found, seconds, probe = Probed(bot, nil, compute)
	RecordProfile(profile, label, found, seconds, probe)
	return found
end

-------------------------------------------------------------------------------
-- Watching path searches for the nbdebug feature (features.nbdebug.model).
-- Only the NPCs it asks for are watched; for them each search is timed and,
-- with watch.costs, every cost it asked for is recorded, and when it is done
-- a features.nbdebug.model path report goes out as the hook
-- WSNpcPathComputed(ent, report). Nothing else changes for them.

local PATH_COMPUTED_HOOK = "WSNpcPathComputed"
local ENGINE_DEFAULT_COST = "the engine's default cost"
local MICROSECONDS = 1e6

-- watch: { costs }, or nil to stop watching.
function Controller:WatchPaths(entIndex, watch)
	self.pathWatch[entIndex] = watch
end

function Controller:PathWatch(ent)
	return self.pathWatch[ent:EntIndex()]
end

-- A watched NextBot's Path:Compute (ws_nextbot's FollowPath). An open
-- path profile records it too.
function Controller:ObserveCompute(watch, bot, path, goal, compute)
	local Debug = WS.require("features.nbdebug.model")
	local recorder = watch.costs and bot.pathCost and Debug.NewCostRecorder() or nil
	local start = bot:GetPos()
	local found, seconds, probe = Probed(bot, recorder, compute)
	if self.pathProfile then RecordProfile(self.pathProfile, bot.Variant, found, seconds, probe) end
	local points, areaIds, lastArea = {}, {}, nil
	for i, segment in ipairs(path:GetAllSegments()) do
		points[i] = {
			pos = segment.pos,
			move = Debug.MoveOfSegment(segment.type),
		}
		if IsValid(segment.area) then
			lastArea = segment.area
			areaIds[#areaIds + 1] = lastArea:GetID()
		end
	end
	local variant = WS.require(bot.Variant)
	hook.Run(PATH_COMPUTED_HOOK, bot, Debug.NewPathReport({
		source = Debug.SOURCE_ENGINE,
		strategy = bot.pathCost and variant.PATH or ENGINE_DEFAULT_COST,
		start = start,
		goal = goal,
		limits = variant.LOCOMOTION,
		found = found,
		points = points,
		areaIds = areaIds,
		totalCost = lastArea and lastArea:GetCostSoFar() or nil,
		microseconds = seconds * MICROSECONDS,
		nodesExpanded = recorder and recorder:Expanded() or nil,
		explored = recorder and recorder:Explored() or nil,
		computedAt = CurTime(),
	}))
	return found
end

local function RecordedCost(graph, fromId, toId, costSoFar)
	local cost = NavGraph.Cost(graph, fromId, toId, costSoFar)
	graph.recorder:Record(toId, fromId, cost)
	return cost
end

-- A watched NPC's route search (RequestRoute): with watch.costs its graph
-- records every cost. Returns what ThinkSearches keeps of it.
function Controller:ObserveRoute(graph, request, start, watch)
	if watch.costs then
		graph.recorder = WS.require("features.nbdebug.model").NewCostRecorder()
		graph.recorder:Record(start:GetID(), nil, 0)
		graph.Cost = RecordedCost
	end
	return {
		index = request.bot.entIndex,
		request = request,
		recorder = graph.recorder,
		seconds = 0,
	}
end

-- A watched route search is done: its report, with the waypoints the NPC
-- will be given (RouteWaypoints), all on the ground.
function Controller:PublishRoute(running, areas, found)
	local Debug = WS.require("features.nbdebug.model")
	local observed, search = running.observed, running.search
	local ent, request = Entity(observed.index), observed.request
	if not IsValid(ent) then return end
	local route = search:Route()
	local points = {}
	for i, pos in ipairs(self:RouteWaypoints(areas, request.to, found, request.from)) do
		points[i] = {
			pos = pos,
			move = Debug.MOVE_GROUND,
		}
	end
	local recorder = observed.recorder
	hook.Run(PATH_COMPUTED_HOOK, ent, Debug.NewPathReport({
		source = Debug.SOURCE_ROUTE,
		strategy = request.strategy._NAME,
		start = request.from,
		goal = request.to,
		limits = request.limits,
		found = found,
		points = points,
		areaIds = route,
		totalCost = search:CostSoFar(route[#route]),
		microseconds = observed.seconds * MICROSECONDS,
		nodesExpanded = search.expanded,
		explored = recorder and recorder:Explored() or nil,
		computedAt = CurTime(),
	}))
end

-- Every live NextBot of this gamemode that searches with a Lua cost.
local function PathingBots()
	local bots = {}
	for ent in pairs(Controller.npcs) do
		if IsValid(ent) and ent.pathCost then bots[#bots + 1] = ent end
	end
	table.sort(bots, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return bots
end

-- One goal, computed with the engine's own cost and then with the bot's
-- Lua cost, on paths of their own so the bot's path is left alone.
function Controller:BenchGoal(profile, bot, goal)
	local enginePath = Path("Follow")
	self:MeasureCompute(profile, Profile.BENCH_ENGINE_LABEL, bot, function() return enginePath:Compute(bot, goal) end)
	local luaPath = Path("Follow")
	self:MeasureCompute(profile, bot.Variant, bot, function() return luaPath:Compute(bot, goal, bot.pathCost) end)
end

local function Tell(ply, lines)
	for _, line in ipairs(lines) do
		print(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	end
end

local function Admin(ply)
	return WS.Can(ply, system.permissions.NEXTSOLDIER) == true
end

concommand.Add("ws_path_profile", function(ply, _, args)
	if not Admin(ply) then return end
	if Controller.pathProfile then
		Tell(ply, { "path profile: a window is already open" })
		return
	end
	local seconds = math.Clamp(tonumber(args[1]) or PROFILE_WINDOW_DEFAULT, 1, PROFILE_WINDOW_MAX)
	Controller.pathProfile = Profile.New(SysTime())
	Tell(ply, { string.format("path profile: measuring every path compute for %d s", seconds) })
	timer.Simple(seconds, function()
		local profile = Controller.pathProfile
		Controller.pathProfile = nil
		Tell(ply, Profile.Format(profile:Report(SysTime()), engine.TickInterval()))
	end)
end, nil, "Measure the NextBots' path computes during play for N seconds (default 30) and print whether offloading them would pay")

-- The bench stalls the server for its whole run, on purpose.
concommand.Add("ws_path_bench", function(ply, _, args)
	if not Admin(ply) then return end
	local bots, areas = PathingBots(), navmesh.GetAllNavAreas()
	if #bots == 0 then
		Tell(ply, { "path bench: no NextBot with a path cost is alive; spawn one first" })
		return
	end
	if #areas == 0 then
		Tell(ply, { "path bench: this map has no navigation mesh" })
		return
	end
	local count = math.Clamp(tonumber(args[1]) or BENCH_DEFAULT, 1, BENCH_MAX)
	local profile = Profile.New(SysTime(), true)
	for i = 1, count do
		local bot = bots[(i - 1) % #bots + 1]
		Controller:BenchGoal(profile, bot, areas[math.random(#areas)]:GetCenter())
	end
	Tell(ply, Profile.Format(profile:Report(SysTime()), engine.TickInterval()))
end, nil, "Compute N paths (default 200) from the live NextBots to random nav areas, under the engine's cost and their Lua cost, and print the timings")
