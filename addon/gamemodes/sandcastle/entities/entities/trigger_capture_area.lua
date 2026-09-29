-- trigger_capture_area (CTriggerAreaCapture, trigger_area_capture.cpp): the
-- volume players stand in to capture its control point. Each think it counts
-- the players inside and steps the capture (foundation/capture.lua), then
-- fires the outputs, changes ownership and tells the point and any train
-- watcher, in the order the SDK does. On payload maps it rides the cart with
-- a huge area_time_to_cap, so the capture never completes by time: the track
-- captures the point (CaptureCurrentCP) and what matters is the capper count
-- (OnNumCappersChanged/2, -1 while blocked) that moves the cart.
ENT.Type = "brush"
ENT.Base = "base_brush"

-- TF2's convars (teamplayroundbased_gamerules.cpp).
local capstyle = CreateConVar("mp_capstyle", "1", FCVAR_REPLICATED, "Sets the style of capture points used. 0 = Fixed players required to cap. 1 = More players cap faster, but longer cap times.")
local blockstyle = CreateConVar("mp_blockstyle", "1", FCVAR_REPLICATED, "Sets the style of capture point blocking used. 0 = Blocks break captures completely. 1 = Blocks only pause captures.")
local capdeteriorate = CreateConVar("mp_capdeteriorate_time", "90.0", FCVAR_REPLICATED, "Time it takes for a full capture point to deteriorate.")

local THINK_TIME = 0.1 -- AREA_THINK_TIME
local C

function ENT:KeyValue(key, value)
	local k = string.lower(key)
	self.wetsandKv = self.wetsandKv or {}
	self.wetsandKv[k] = value
	if k == "model" then self.brushModel = value end
	if string.sub(key, 1, 2) == "On" then self:StoreOutput(key, value) end
end

function ENT:Key(name, default)
	local v = (self.wetsandKv or {})[name]
	if v == nil or v == "" then return default end
	return v
end

-- team_<field>_2 and _3 as numbers.
function ENT:TeamKeys(field, default)
	return {
		[WETSAND.TEAM_RED] = tonumber(self:Key(field .. "_2", default)) or default,
		[WETSAND.TEAM_BLUE] = tonumber(self:Key(field .. "_3", default)) or default,
	}
end

function ENT:Initialize()
	C = WETSAND.PayloadCapture
	if self.brushModel then self:SetModel(self.brushModel) end
	self:SetSolid(SOLID_NONE)
	self:SetNoDraw(true)
	self.enabled = self:Key("startdisabled", "0") ~= "1"
	self.pointName = self:Key("area_cap_point")
	self.capTime = tonumber(self:Key("area_time_to_cap", 5)) or 5
	local canCap = self:TeamKeys("team_cancap", 1)
	self.canCap = { [WETSAND.TEAM_RED] = canCap[WETSAND.TEAM_RED] ~= 0, [WETSAND.TEAM_BLUE] = canCap[WETSAND.TEAM_BLUE] ~= 0 }
	-- Spawn: at least one player is always required
	self.numRequired = self:TeamKeys("team_numcap", 1)
	self.startRequired = self:TeamKeys("team_startcap", 1)
	for _, t in ipairs({ WETSAND.TEAM_RED, WETSAND.TEAM_BLUE }) do
		self.numRequired[t] = math.max(self.numRequired[t], 1)
		self.startRequired[t] = math.max(self.startRequired[t], 1)
	end
	self.spawnAdjust = self:TeamKeys("team_spawn", 0)
	self.cap = C.New(WETSAND.TEAM_UNASSIGNED)
end

function ENT:Point()
	return WETSAND.FindByName(self.pointName)
end

-- The watcher that moves the train this area rides (SetTrainWatcher).
function ENT:SetTrainWatcher(watcher)
	self.trainWatcher = watcher
end

function ENT:IsBlocked()
	return self.cap.blocked
end

function ENT:IsCapturing()
	return self.cap.capturing
end

-- Counting players ------------------------------------------------------------------------

-- CaptureThink counts a team only if the rules let it capture the point
-- (TeamMayCapturePoint). WETSAND.TeamCanCapPoint also refuses the owner and teams
-- this area never lets cap, which still count here: they defend and block.
function ENT:TeamCounts(point, team)
	return team == self.cap.owner or not self.canCap[team] or WETSAND.TeamCanCapPoint(point, team)
end

-- A disabled trigger touches nobody. Team members that are not players
-- (the AI war's soldiers) count as their team's players do.
function ENT:Counts(point)
	local counts = { [WETSAND.TEAM_RED] = 0, [WETSAND.TEAM_BLUE] = 0 }
	if not self.enabled then return counts end
	local function Add(team)
		if counts[team] and self:TeamCounts(point, team) then counts[team] = counts[team] + 1 end
	end
	for _, ply in ipairs(WETSAND.PlayersInside(self)) do Add(WETSAND.TeamOf(ply)) end
	for _, member in ipairs(WETSAND.MembersInside(self)) do Add(WETSAND.TeamNumber(member)) end
	return counts
end

function ENT:StepInput(point)
	return {
		now = CurTime(),
		pointsMayBeCaptured = not IsValid(WETSAND.Rules) or WETSAND.Rules:PointsMayBeCaptured(),
		counts = self:Counts(point),
		canCap = self.canCap,
		numRequired = self.numRequired,
		startRequired = self.startRequired,
		capTime = self.capTime,
		scales = capstyle:GetBool(),
		blockstyle = blockstyle:GetInt(),
		deteriorate = capdeteriorate:GetFloat(),
		overtime = GetGlobal2Bool("wetsand_round_overtime", false),
		teamMayCapture = function(team) return WETSAND.TeamCanCapPoint(point, team) end,
	}
end

-- Events --------------------------------------------------------------------------------

local TEAM_OUTPUT = { [WETSAND.TEAM_RED] = "Team1", [WETSAND.TEAM_BLUE] = "Team2" }

-- SetNumCappers
function ENT:SetNumCappers(n, blocked)
	self:TriggerOutput("OnNumCappersChanged", self, tostring(n))
	-- OnNumCappersChanged2 carries -1 for a blocked cart (hill decisions)
	if blocked then n = -1 end
	self:TriggerOutput("OnNumCappersChanged2", self, tostring(n))
	if IsValid(self.trainWatcher) then self.trainWatcher:SetNumTrainCappers(n, self) end
end

-- HandleRespawnTimeAdjustments, then the point changes hands.
function ENT:ChangeOwner(point, old, team)
	for _, adjust in ipairs(C.SpawnAdjustments(old, team, self.spawnAdjust)) do
		local input = adjust.team == WETSAND.TEAM_RED and "AddRedTeamRespawnWaveTime" or "AddBlueTeamRespawnWaveTime"
		WETSAND.Rules:Fire(input, tostring(adjust.seconds))
	end
	WETSAND.SetPointOwner(point, team, self)
end

local EVENTS = {
	start = function(self, point, e)
		self:TriggerOutput("OnStart" .. TEAM_OUTPUT[e.team], self)
		self:TriggerOutput("OnStartCap", self)
	end,
	capturestart = function(self, point, e) WETSAND.PointCaptureStarted(point, e.team) end,
	numcappers = function(self, point, e) self:SetNumCappers(e.n, e.blocked) end,
	-- UpdateBlocked: the point hears a block when it starts
	blocked = function(self, point, e)
		if e.value then WETSAND.PointCaptureBlocked(point, WETSAND.EnemyOf(e.capping)) end
	end,
	["break"] = function(self, point, e)
		self:TriggerOutput("OnBreak" .. TEAM_OUTPUT[e.team], self)
		self:TriggerOutput("OnBreakCap", self)
	end,
	["end"] = function(self, point, e)
		self:TriggerOutput("OnCap" .. TEAM_OUTPUT[e.team], self)
		self:TriggerOutput("OnEndCap", self)
	end,
	owner = function(self, point, e) self:ChangeOwner(point, e.old, e.team) end,
}

function ENT:Apply(point, events)
	for _, e in ipairs(events) do EVENTS[e.kind](self, point, e) end
end

-- CaptureThink
function ENT:Think()
	self:NextThink(CurTime() + THINK_TIME)
	local point = self:Point()
	if not IsValid(point) then return true end
	self.cap.owner = WETSAND.CapTeam(point)
	self.lastInput = self:StepInput(point)
	self:Apply(point, C.Step(self.cap, self.lastInput))
	return true
end

-- Capture progress for the HUD, or nil with no point or while disabled.
function ENT:HudState()
	local point = self:Point()
	if not self.enabled or not IsValid(point) or not self.lastInput then return nil end
	return {
		index = WETSAND.PointIndex(point),
		owner = WETSAND.CapTeam(point),
		capping = self.cap.cappingTeam,
		progress = C.Progress(self.cap, self.lastInput),
		blocked = self.cap.blocked,
		cappers = self.cap.touching[self.cap.cappingTeam] or 0,
	}
end

-- Inputs ------------------------------------------------------------------------------

local INPUTS = {
	-- InputSetControlPoint: break the capture of the old point first
	setcontrolpoint = function(self, value)
		local old = self:Point()
		local events = C.Break(self.cap)
		if IsValid(old) then self:Apply(old, events) end
		self.pointName = tostring(value)
		local point = self:Point()
		if IsValid(point) then self.cap.owner = WETSAND.CapTeam(point) end
	end,
	capturecurrentcp = function(self)
		local point = self:Point()
		if IsValid(point) then self:Apply(point, C.CaptureCurrent(self.cap)) end
	end,
	-- "<team> <0/1>"
	setteamcancap = function(self, value)
		local team, can = string.match(tostring(value), "(%d+)%s+(%d+)")
		team = tonumber(team)
		if self.canCap[team] ~= nil then self.canCap[team] = tonumber(can) ~= 0 end
	end,
	roundspawn = function() end,
	enable = function(self) self.enabled = true end,
	disable = function(self) self.enabled = false end,
}

function ENT:AcceptInput(name, activator, caller, value)
	local handler = INPUTS[string.lower(name)]
	if not handler then return false end
	handler(self, value)
	return true
end
