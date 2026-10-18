-- Part of the capture controller (sv.lua): the capture areas, their
-- captures and their inputs.
local Controller, GAME_TEAMS, capstyle, blockstyle, capdeteriorate, Points = ...
local Capture = WS.require("foundation.capture")
local Area = WS.require("foundation.capture.area")
local PointByName, AreasOf = Points.PointByName, Points.AreasOf
local PlayLines, FireTeamOutput, ApplyPointEvents = Points.PlayLines, Points.FireTeamOutput, Points.ApplyPointEvents

local NOBODY, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE
local WAVE_TIME_INPUT = {
	[RED] = "AddRedTeamRespawnWaveTime",
	[BLUE] = "AddBlueTeamRespawnWaveTime",
}

-- Capture areas -------------------------------------------------------------------------

-- team_<field>_2 and _3 as numbers.
local function TeamKeys(kv, field, default)
	return {
		[RED] = tonumber(kv[field .. "_2"]) or default,
		[BLUE] = tonumber(kv[field .. "_3"]) or default,
	}
end

-- CTriggerAreaCapture's keyvalues; at least one player is always required.
function Controller:BindArea(ent, kv)
	local canCap = TeamKeys(kv, "team_cancap", 1)
	local numRequired = TeamKeys(kv, "team_numcap", 1)
	local startRequired = TeamKeys(kv, "team_startcap", 1)
	for _, team in ipairs(GAME_TEAMS) do
		numRequired[team] = math.max(numRequired[team], 1)
		startRequired[team] = math.max(startRequired[team], 1)
	end
	self.areas[ent] = {
		ent = ent,
		enabled = kv.startdisabled ~= "1",
		pointName = kv.area_cap_point or "",
		capTime = tonumber(kv.area_time_to_cap) or 5,
		canCap = {
			[RED] = canCap[RED] ~= 0,
			[BLUE] = canCap[BLUE] ~= 0,
		},
		numRequired = numRequired,
		startRequired = startRequired,
		spawnAdjust = TeamKeys(kv, "team_spawn", 0),
		state = Area.New(NOBODY),
		watcher = NULL,
		lastInput = nil,
		-- trigger_timer_door's door_name: the door the capture opens
		doorName = kv.door_name or "",
	}
end

-- CTriggerTimerDoor: a capture opens its door as it starts and closes it
-- if it breaks (mvm_mannhattan's gates).
local function DoorInput(a, input)
	if a.doorName == "" then return end
	local door = WS.FindByName(a.doorName)
	if IsValid(door) then door:Fire(input) end
end

function Controller:UnbindArea(ent)
	local a = self.areas[ent]
	if not a then return end
	local point = PointByName(a.pointName)
	if IsValid(point) and self.loops[point] then self.loops[point]:Stop() end
	self.areas[ent] = nil
end

-- The train watcher whose cart this area rides (SetTrainWatcher).
function Controller:SetAreaWatcher(ent, watcher)
	self.areas[ent].watcher = watcher
end

function Controller:AreaBlocked(ent)
	return self.areas[ent].state.blocked
end

function Controller:AreaCapturing(ent)
	return self.areas[ent].state.capturing
end

-- CaptureThink counts a team only if the rules let it capture the point.
-- The owner, and teams this area never lets cap, still count: they defend
-- and block.
local function TeamCounts(self, a, point, team)
	return team == a.state.owner or not a.canCap[team] or self:TeamMayCapture(point, team)
end

-- A disabled trigger touches nobody. Team members that are not players
-- (the AI war's soldiers) count as their team's players do.
local function Counts(self, a, point)
	local counts = {
		[RED] = 0,
		[BLUE] = 0,
	}
	if not a.enabled then return counts end
	local function Add(team)
		if counts[team] and TeamCounts(self, a, point, team) then counts[team] = counts[team] + 1 end
	end
	for _, ply in ipairs(WS.PlayersInside(a.ent)) do Add(WS.TeamOf(ply)) end
	for _, member in ipairs(WS.MembersInside(a.ent)) do Add(WS.TeamNumber(member)) end
	return counts
end

local function StepInput(self, a, point)
	return {
		now = CurTime(),
		pointsMayBeCaptured = self.rounds:PointsMayBeCaptured(),
		counts = Counts(self, a, point),
		canCap = a.canCap,
		numRequired = a.numRequired,
		startRequired = a.startRequired,
		capTime = a.capTime,
		scales = capstyle:GetBool(),
		blockstyle = blockstyle:GetInt(),
		deteriorate = capdeteriorate:GetFloat(),
		overtime = self.rounds:InOvertime(),
		teamMayCapture = function(team) return self:TeamMayCapture(point, team) end,
	}
end

-- The point's looping and one-shot capture sounds, from the point (the
-- loop to the players near it, CPASFilter).
local function PlayPointSounds(self, point, e)
	local sounds = Area.PointSounds(e, self.set:Spawnflags(point), self.set:Sounds(point))
	if sounds.stopLoop and self.loops[point] then
		self.loops[point]:Stop()
		self.loops[point] = nil
	end
	if sounds.play then point:EmitSound(sounds.play) end
	if sounds.loop then
		self.loops[point] = CreateSound(point, sounds.loop)
		self.loops[point]:Play()
	end
end

-- CTeamControlPoint::CaptureStart, with what the clients do on it (the
-- contested line, or the final-cap warning).
local function CaptureStarted(self, point, team)
	PlayLines(self, point, self.set:CaptureStarted(point, team, CurTime()))
	hook.Run("WSPointCaptureStarted", point, team)
end

-- CTeamControlPoint::CaptureBlocked: the clients show the HUD's "defended"
-- notice (for points with a print name).
local function CaptureBlocked(self, point, team)
	WS.Events.Fire("game_teamplay_capture_blocked", {
		cp = self.set:Index(point),
		cpname = self.set:PrintName(point),
		team = team,
	})
	hook.Run("WSPointCaptureBlocked", point, team)
end

-- SetNumCappers: OnNumCappersChanged2 carries -1 for a blocked cart.
local function SetNumCappers(a, n, blocked)
	a.ent:TriggerOutput("OnNumCappersChanged", a.ent, tostring(n))
	if blocked then n = Area.CAPPERS_BLOCKED end
	a.ent:TriggerOutput("OnNumCappersChanged2", a.ent, tostring(n))
	if IsValid(a.watcher) then a.watcher:SetNumTrainCappers(n, a.ent) end
end

-- EndCapture after its outputs: HandleRespawnTimeAdjustments,
-- PlaySpecialCapSounds, then the point's SetOwner.
local function CaptureEnded(self, a, point, e)
	for _, adjust in ipairs(Area.SpawnAdjustments(e.old, e.team, a.spawnAdjust)) do
		self.rounds:ProxyInput(WAVE_TIME_INPUT[adjust.team], tostring(adjust.seconds))
	end
	local set = self.set
	local wouldWin = self.master ~= nil and self.master:WouldNewOwnerWin(set, point, e.team)
	local scorePerRound = not (self.master and self.master:ScorePerCapture())
	self.rounds:CapSounds(e.team, wouldWin, scorePerRound)
	ApplyPointEvents(self, set:SetOwner(point, e.team, Capture.CAUSE_CAPTURE, self.rounds:PointsMayBeCaptured()))
end

local AREA_EVENTS = {
	start = function(self, a, point, e)
		FireTeamOutput(a.ent, "OnStart", e.team)
		a.ent:TriggerOutput("OnStartCap", a.ent)
		DoorInput(a, "Open")
	end,
	capturestart = function(self, a, point, e) CaptureStarted(self, point, e.team) end,
	numcappers = function(self, a, point, e) SetNumCappers(a, e.n, e.blocked) end,
	-- UpdateBlocked: the point hears a block when it starts
	blocked = function(self, a, point, e)
		if e.value then CaptureBlocked(self, point, WS.EnemyOf(e.capping)) end
	end,
	["break"] = function(self, a, point, e)
		FireTeamOutput(a.ent, "OnBreak", e.team)
		a.ent:TriggerOutput("OnBreakCap", a.ent)
		DoorInput(a, "Close")
	end,
	["end"] = function(self, a, point, e)
		FireTeamOutput(a.ent, "OnCap", e.team)
		a.ent:TriggerOutput("OnEndCap", a.ent)
	end,
	owner = function(self, a, point, e) CaptureEnded(self, a, point, e) end,
}

local function ApplyAreaEvents(self, a, point, events)
	for _, e in ipairs(events) do
		PlayPointSounds(self, point, e)
		AREA_EVENTS[e.kind](self, a, point, e)
	end
end

-- An admin's capture for team (Set Team, ws/sh_editors_point.lua), as
-- a finished capture on its area: the area's OnCap and OnEndCap outputs,
-- which the map's logic hangs on (cp_steel's relays open the next point's
-- doors), the respawn adjustments, the capture sounds, the point's outputs,
-- scoring and the win check. A point no area captures is set as a player's
-- SetOwner input would. Returns true, or false and why not.
function Controller:CapturePoint(point, team)
	if self:Owner(point) == team then return false, "the point is already " .. WS.TeamName[team] .. "'s" end
	if not self.rounds:PointsMayBeCaptured() then return false, "points cannot be captured now" end
	local a = AreasOf(self, point)[1]
	if a then
		ApplyAreaEvents(self, a, point, Area.CaptureFor(a.state, team))
	else
		ApplyPointEvents(self, self:Set():SetOwner(point, team, Capture.CAUSE_PLAYER_INPUT, true))
	end
	return true
end

-- The area's point, when it is one of the set's.
local function AreaPoint(self, a)
	local point = PointByName(a.pointName)
	if IsValid(point) and self:Set():Has(point) then return point end
	return NULL
end

-- CaptureThink
function Controller:AreaThink(ent)
	local a = self.areas[ent]
	local point = AreaPoint(self, a)
	if not IsValid(point) then return end
	a.state.owner = self.set:Owner(point)
	a.lastInput = StepInput(self, a, point)
	ApplyAreaEvents(self, a, point, Area.Step(a.state, a.lastInput))
end

local AREA_INPUTS = {
	-- InputSetControlPoint: break the capture of the old point first
	setcontrolpoint = function(self, a, value)
		local old = AreaPoint(self, a)
		local events = Area.Break(a.state)
		if IsValid(old) then ApplyAreaEvents(self, a, old, events) end
		a.pointName = tostring(value)
		local point = AreaPoint(self, a)
		if IsValid(point) then a.state.owner = self.set:Owner(point) end
	end,
	capturecurrentcp = function(self, a)
		local point = AreaPoint(self, a)
		if IsValid(point) then ApplyAreaEvents(self, a, point, Area.CaptureCurrent(a.state)) end
	end,
	-- "<team> <0/1>"
	setteamcancap = function(self, a, value)
		local team, can = string.match(tostring(value), "(%d+)%s+(%d+)")
		team = tonumber(team)
		if a.canCap[team] ~= nil then a.canCap[team] = tonumber(can) ~= 0 end
	end,
	roundspawn = function() end,
	enable = function(self, a) a.enabled = true end,
	disable = function(self, a) a.enabled = false end,
}

-- Whether the area took the input.
function Controller:AreaInput(ent, name, value)
	local handler = AREA_INPUTS[name]
	if not handler then return false end
	handler(self, self.areas[ent], value)
	return true
end

return AreaPoint
