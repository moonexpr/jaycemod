-- The in-game half of the harness (.devtools/bin/ingame_tests.py). Never
-- part of the shipped addon: the harness copies this file and checks/*.lua
-- to garrysmod/data/ws_tests/harness/ as .txt and loads this one after
-- each map change with
--   lua_run RunString(file.Read("ws_tests/harness/runner.txt", "DATA"), "ws_tests/runner")
-- then starts each check with
--   lua_run WS_TESTS.Run("<check>", "<run id>")
-- A check is a chunk returning function(t): it runs as a coroutine, so it
-- may wait (t:Wait, t:WaitFor) while the server keeps ticking. Its record
-- is written to ws_tests/results/<run id>.json, which the harness polls:
--   { map, check, status = "pass" | "fail" | "skip" | "error",
--     checks = { { name, ok, detail } }, info = {}, error, seconds }
-- Arguments come from ws_tests/harness/args/<run id>.txt (JSON), so no
-- console command carries them (the console splits commands on ";").
WS_TESTS = WS_TESTS or {}
local Tests = WS_TESTS

local DATA = "ws_tests/"
local CHECKS = DATA .. "harness/checks/"
local ARGS = DATA .. "harness/args/"
local RESULTS = DATA .. "results/"
local SCRIPT_EXT = ".txt"
local THINK_HOOK = "ws_tests"
local STATION_HOOK = "ws_tests_station"
local POLL = 0.1 -- seconds between a WaitFor's tries
local STATION_INTERVAL = 0.2 -- seconds between putting stationed bots back
local BOT_JOIN_TIMEOUT = 10
local FLOOR_TRACE = 4096 -- units searched below a point for the floor
local STAND_OFFSET = 2 -- units above the floor a bot is put
local BOT_SPACING = 28 -- units between bots stationed together

Tests.running = Tests.running or {}
Tests.stations = Tests.stations or {}

local Context = {}
Context.__index = Context

local STATE_NAMES = {}
for name, value in pairs(WS.STATE) do
	if isnumber(value) then STATE_NAMES[value] = name end
end

function Tests.StateName(state)
	return STATE_NAMES[state] or tostring(state)
end

-- Waiting --------------------------------------------------------------------------

function Context:Wait(seconds)
	coroutine.yield(CurTime() + seconds)
end

-- Tries fn every POLL seconds until it returns a true value or timeout
-- seconds pass; returns that value (nil on timeout) and the seconds taken.
function Context:WaitFor(timeout, fn)
	local start = CurTime()
	while true do
		local value = fn()
		if value then return value, CurTime() - start end
		if CurTime() - start >= timeout then return nil, CurTime() - start end
		self:Wait(POLL)
	end
end

-- Recording ------------------------------------------------------------------------

function Context:Check(name, ok, detail)
	self.checks[#self.checks + 1] = {
		name = name,
		ok = ok and true or false,
		detail = detail ~= nil and tostring(detail) or "",
	}
	return ok
end

function Context:Info(key, value)
	self.info[key] = value
end

-- The check could not be decided here; why.
function Context:Skip(reason)
	self.skipped = reason
end

-- Features, without loading one the map did not ----------------------------------

function Context:Loaded(name)
	return WS.FeatureLoader.loaded[name] == true
end

function Context:Feature(name)
	if self:Loaded(name) then return WS.Feature(name) end
end

-- Bots -------------------------------------------------------------------------------

-- At least count bots, made with the console's bot command.
function Context:Bots(count)
	for _ = #player.GetBots() + 1, count do game.ConsoleCommand("bot\n") end
	self:WaitFor(BOT_JOIN_TIMEOUT, function() return #player.GetBots() >= count end)
	local bots = player.GetBots()
	local list = {}
	for i = 1, math.min(count, #bots) do list[i] = bots[i] end
	return list
end

-- Puts each bot on team through the gamemode's one team switch and brings
-- it to life now rather than at its respawn wave.
function Context:Join(bots, team)
	for _, bot in ipairs(bots) do
		WS.SetPlayerTeam(bot, team)
	end
	self:Wait(POLL)
	for _, bot in ipairs(bots) do
		if not bot:Alive() then bot:Spawn() end
	end
	return self:WaitFor(BOT_JOIN_TIMEOUT, function()
		for _, bot in ipairs(bots) do
			if not WS.IsAliveInGame(bot) then return false end
		end
		return true
	end)
end

-- The floor under a point of an entity's bounds, given in its own space.
function Tests.FloorUnder(ent, localPoint)
	local from = ent:LocalToWorld(localPoint)
	local tr = util.TraceLine({
		start = from,
		endpos = from - Vector(0, 0, FLOOR_TRACE),
		mask = MASK_PLAYERSOLID_BRUSHONLY,
	})
	return tr.HitPos + Vector(0, 0, STAND_OFFSET)
end

-- The middle of an area's bounds, in its own space.
function Tests.AreaMiddle(area)
	return (area:OBBMins() + area:OBBMaxs()) * 0.5
end

-- Keeps the bots standing on the spots spot() returns (a list, one per
-- bot, recomputed every STATION_INTERVAL, so they follow a moving area)
-- until Unstation or the check ends.
function Context:Station(bots, spots)
	Tests.stations[self.runId] = {
		bots = bots,
		spots = spots,
		next = 0,
	}
end

function Context:Unstation()
	Tests.stations[self.runId] = nil
end

-- Spots on the floor of an area: the first at its middle, the others in a
-- row along its local x axis.
function Tests.AreaSpots(area, count)
	local middle = Tests.AreaMiddle(area)
	local spots = {}
	for i = 1, count do
		local offset = (i - 1 - (count - 1) / 2) * BOT_SPACING
		spots[i] = Tests.FloorUnder(area, middle + Vector(offset, 0, 0))
	end
	return spots
end

hook.Add("Think", STATION_HOOK, function()
	local now = CurTime()
	for _, station in pairs(Tests.stations) do
		if now >= station.next then
			station.next = now + STATION_INTERVAL
			local spots = station.spots()
			for i, bot in ipairs(station.bots) do
				if IsValid(bot) and bot:Alive() and spots[i] then
					bot:SetPos(spots[i])
					bot:SetVelocity(-bot:GetVelocity())
				end
			end
		end
	end
end)

-- Points and rounds, as the checks describe them ------------------------------------

function Tests.PointName(capture, point)
	return string.format("%s [%s]", tostring(capture:Set():PrintName(point)), point:GetName())
end

function Tests.PointArea(capture, point)
	return capture:AreaEntities(point)[1]
end

-- Each point the capture controller holds: name, owner, locked, and
-- whether team may capture it now.
function Tests.DescribePoints(capture, team)
	local list = {}
	for _, point in ipairs(capture:Points()) do
		list[#list + 1] = {
			name = Tests.PointName(capture, point),
			owner = capture:Owner(point),
			locked = capture:Set():Locked(point) and true or false,
			may_capture = capture:TeamMayCapture(point, team) and true or false,
			in_round = capture:IsInRound(point) and true or false,
		}
	end
	return list
end

function Tests.Winner()
	return GetGlobal2Int("ws_round_winner", WS.TEAM_UNASSIGNED)
end

-- Running ------------------------------------------------------------------------------

local function Status(ctx, err)
	if err then return "error" end
	for _, c in ipairs(ctx.checks) do
		if not c.ok then return "fail" end
	end
	if ctx.skipped then return "skip" end
	if #ctx.checks == 0 then return "error" end
	return "pass"
end

local function Finish(ctx, err)
	Tests.stations[ctx.runId] = nil
	if ctx.skipped then ctx.info.skipped = ctx.skipped end
	local record = {
		map = game.GetMap(),
		check = ctx.name,
		status = Status(ctx, err),
		checks = ctx.checks,
		info = ctx.info,
		error = err or (#ctx.checks == 0 and not ctx.skipped and "the check recorded nothing") or nil,
		seconds = CurTime() - ctx.started,
	}
	file.CreateDir(DATA .. "results")
	file.Write(RESULTS .. ctx.runId .. ".json", util.TableToJSON(record, true))
end

local function ReadArgs(runId)
	local text = file.Read(ARGS .. runId .. SCRIPT_EXT, "DATA")
	return text and util.JSONToTable(text) or {}
end

function Tests.Run(name, runId)
	local ctx = setmetatable({
		name = name,
		runId = runId,
		args = ReadArgs(runId),
		checks = {},
		info = {},
		started = CurTime(),
	}, Context)
	local code = file.Read(CHECKS .. name .. SCRIPT_EXT, "DATA")
	if not code then return Finish(ctx, "no check named " .. name) end
	local chunk = CompileString(code, "checks/" .. name .. ".lua", false)
	if isstring(chunk) then return Finish(ctx, chunk) end
	local body = chunk()
	local co = coroutine.create(function()
		local ok, err = xpcall(body, debug.traceback, ctx)
		return ok and nil or err
	end)
	Tests.running[co] = {
		ctx = ctx,
		wake = 0,
	}
	print("ws_tests: started " .. name .. " " .. runId)
end

hook.Add("Think", THINK_HOOK, function()
	local now = CurTime()
	for co, job in pairs(Tests.running) do
		if now >= job.wake then
			local ok, value = coroutine.resume(co, job.ctx)
			if coroutine.status(co) == "dead" then
				Tests.running[co] = nil
				-- the body's xpcall returns its traceback; resume fails only on our own bug
				local err = value
				if not ok then err = "runner: " .. tostring(value) end
				Finish(job.ctx, err)
			else
				job.wake = value
			end
		end
	end
end)

-- Clears the bots between maps.
function Tests.KickBots()
	for _, bot in ipairs(player.GetBots()) do bot:Kick("ws_tests") end
end

print("ws_tests: runner ready on " .. game.GetMap())
