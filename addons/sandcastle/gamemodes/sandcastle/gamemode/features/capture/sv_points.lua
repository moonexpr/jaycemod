-- Part of the capture controller (sv.lua): the point set, its queries, and
-- the changes to its points carried out. Its helpers go to the other parts
-- as Points.
local Controller, Team, GAME_TEAMS, caplinear = ...
local Capture = WS.require("foundation.capture")
local Master = WS.require("foundation.capture.master")
local Rounds = WS.require("foundation.rounds")

local POINT_CLASS = "team_control_point"
local NOBODY, RED, BLUE = WS.TEAM_UNASSIGNED, WS.TEAM_RED, WS.TEAM_BLUE
local TEAM_OUTPUT = {
	[RED] = "Team1",
	[BLUE] = "Team2",
}

-- CTeamControlPoint::SetModel: the owning team's model, bodygroup 0 set to
-- the team, and the team's skin (team - 2, neutral last).
local DEFAULT_MODEL = "models/effects/cappoint_hologram.mdl"
local TEAM_BODYGROUP = 0
local POINT_SKIN = {
	[RED] = 0,
	[BLUE] = 1,
	[NOBODY] = 2,
}

-- EmitSound's volume, flags and DSP for a line (the soundscript sets the rest).
local FULL_VOLUME, NO_SOUND_FLAGS, NO_DSP = 1, 0, 0

-- The point set (FindControlPoints) --------------------------------------------------

local function IsPoint(ent)
	return IsValid(ent) and ent:GetClass() == POINT_CLASS
end

local function PointByName(name)
	local ent = WS.FindByName(name)
	if IsPoint(ent) then return ent end
	return NULL
end

-- team_previouspoint_<team>_0..2 as point entities, a slot nil when unset.
local function PreviousPoints(kv)
	local previous = {}
	for _, team in ipairs(GAME_TEAMS) do
		local slots = {}
		for n = 1, Capture.MAX_PREVIOUS_POINTS do
			local point = PointByName(kv["team_previouspoint_" .. team .. "_" .. (n - 1)])
			if IsValid(point) then slots[n] = point end
		end
		previous[team] = slots
	end
	return previous
end

-- The spec of a point, keeping the state it has in the old set while the
-- entity lives on (a mini-round without a map reset).
local function PointSpec(ent, old)
	local kv = WS.KeyValues(ent)
	local spec = {
		id = ent,
		index = tonumber(kv.point_index) or 0,
		defaultOwner = Team(kv.point_default_owner),
		startLocked = kv.point_start_locked == "1",
		group = tonumber(kv.point_group) or 0,
		warnOnCap = tonumber(kv.point_warn_on_cap) or Capture.CP_WARN.NORMAL,
		warnSound = kv.point_warn_sound,
		printName = kv.point_printname or "",
		spawnflags = tonumber(kv.spawnflags) or 0,
		previous = PreviousPoints(kv),
		sounds = {
			start = kv.point_capture_start_sound,
			stop = kv.point_capture_end_sound,
			progress = kv.point_capture_progress_sound,
			interrupted = kv.point_capture_interrupted_sound,
		},
		capSounds = {
			[NOBODY] = kv["team_capsound_" .. NOBODY],
			[RED] = kv["team_capsound_" .. RED],
			[BLUE] = kv["team_capsound_" .. BLUE],
		},
		-- the HUD's icon for each owner (Capture.ICON_DEFAULT when unset)
		icons = {
			[NOBODY] = kv["team_icon_" .. NOBODY],
			[RED] = kv["team_icon_" .. RED],
			[BLUE] = kv["team_icon_" .. BLUE],
		},
	}
	if old and old:Has(ent) then
		spec.owner = old:Owner(ent)
		spec.locked = old:Locked(ent)
	end
	return spec
end

-- A round's cpr_cp_names as point entities.
local function NamedPoints(names)
	local points = {}
	for _, name in ipairs(names) do
		for _, ent in ipairs(ents.FindByName(name)) do
			if IsPoint(ent) then points[#points + 1] = ent end
		end
	end
	return points
end

local function RoundName(ent)
	local name = ent:GetName()
	if name == "" then return "ws_round_" .. ent:EntIndex() end
	return name
end

-- FindControlPointRounds
local function RoundSpecs(self)
	local specs = {}
	for ent, r in pairs(self.roundEnts) do
		if IsValid(ent) then
			specs[#specs + 1] = {
				name = RoundName(ent),
				priority = r.priority,
				restrict = r.restrict,
				printName = r.printName,
				points = NamedPoints(r.pointNames),
				ent = ent,
			}
		end
	end
	table.sort(specs, function(a, b) return a.ent:EntIndex() < b.ent:EntIndex() end)
	return specs
end

local function ApplyPointModel(self, ent)
	local kv = WS.KeyValues(ent)
	local team = self.set:Owner(ent)
	local model = kv["team_model_" .. team]
	if not model or model == "" then model = DEFAULT_MODEL end
	if ent:GetModel() ~= model and util.IsValidModel(model) then ent:SetModel(model) end
	ent:SetBodygroup(TEAM_BODYGROUP, team)
	ent:SetSkin(POINT_SKIN[team])
	if bit.band(self.set:Spawnflags(ent), Capture.SF_HIDE_MODEL) ~= 0 then ent:SetNoDraw(true) end
end

-- Each point has a proxy (WS.Proxy, kind "point"), the box an admin
-- right-clicks for its entries (ws/sh_editors_point.lua), and the props
-- of its base name it. A payload checkpoint's is its cart's instead
-- (features/payload).
local POINT_PROXY_MINS, POINT_PROXY_MAXS = Vector(-48, -48, -8), Vector(48, 48, 64)

local function KeepPointProxy(point)
	local proxy, made = WS.Proxy(point, "point", point, POINT_PROXY_MINS, POINT_PROXY_MAXS)
	if made then WS.ProxyBodies(proxy, point:GetPos()) end
end

-- CTeamControlPointMaster::FindControlPoints and FindControlPointRounds,
-- at load and on every RoundSpawn (a map reset recreates the points).
function Controller:Rebuild()
	local old = self.set
	local specs = {}
	for _, ent in ipairs(ents.FindByClass(POINT_CLASS)) do specs[#specs + 1] = PointSpec(ent, old) end
	self.set = Capture.New({
		caplinear = caplinear:GetBool(),
		points = specs,
	})
	if self.master then self.master:SetRounds(RoundSpecs(self)) end
	for _, ent in ipairs(self.set:Ids()) do
		ApplyPointModel(self, ent)
		KeepPointProxy(ent)
	end
end

function Controller:Set()
	if not self.set then self:Rebuild() end
	return self.set
end

cvars.AddChangeCallback("tf_caplinear", function(_, _, value)
	if Controller.set then Controller.set:SetCaplinear(value ~= "0") end
end, "ws_capture")

-- What the capture order needs from the master: the round in play and the
-- team's base point (GetBaseControlPoint).
local function OrderQuery(self, team)
	local set = self:Set()
	if not self.master then
		local points = {}
		for i, id in ipairs(set:Ids()) do
			points[i] = {
				index = set:Rank(id),
				defaultOwner = set:DefaultOwner(id),
			}
		end
		return {
			playingMiniRounds = false,
			inRound = nil,
			base = Capture.BaseControlPoint(team, points),
		}
	end
	return {
		playingMiniRounds = self.master:PlayingMiniRounds(),
		inRound = self.master:InRound(),
		base = self.master:BaseControlPoint(set, team),
	}
end

-- Point queries -------------------------------------------------------------------------

function Controller:Owner(point) return self:Set():Owner(point) end
function Controller:Index(point) return self:Set():Index(point) end
function Controller:Rank(point) return self:Set():Rank(point) end

-- Every point entity in rank order.
function Controller:Points()
	return self:Set():Ids()
end

function Controller:IsInRound(point)
	return not self.master or self.master:IsInRound(point)
end

function Controller:TeamMayCapture(point, team)
	return self:Set():TeamMayCapture(point, team, OrderQuery(self, team))
end

local function AreasOf(self, point)
	local list = {}
	for ent, a in pairs(self.areas) do
		if IsValid(ent) and PointByName(a.pointName) == point then list[#list + 1] = a end
	end
	return list
end

function Controller:IsCapturing(point)
	for _, a in ipairs(AreasOf(self, point)) do
		if a.state.capturing then return true end
	end
	return false
end

function Controller:CappingTeam(point)
	for _, a in ipairs(AreasOf(self, point)) do
		if a.state.capturing then return a.state.cappingTeam end
	end
	return NOBODY
end

-- CTFGameRules::TimerMayExpire's hold: some area is capturing.
local function AnyCapturing(self)
	for ent, a in pairs(self.areas) do
		if IsValid(ent) and a.state.capturing then return true end
	end
	return false
end

-- The mini-round being played, or NULL.
local function RoundNamed(self, name)
	for ent in pairs(self.roundEnts) do
		if IsValid(ent) and RoundName(ent) == name then return ent end
	end
	return NULL
end

function Controller:CurrentRound()
	if not self.master then return NULL end
	return RoundNamed(self, self.master:Current())
end

-- The mini-round that comes first while none is chosen (Sandbox mode), or
-- NULL: its spawns are the ones set up (ws/sv_teams_spawn.lua).
function Controller:UpcomingRound()
	if not self.master then return NULL end
	return RoundNamed(self, self.master:Upcoming(self:Set()))
end

function Controller:RoundPoints(roundEnt)
	return NamedPoints(self.roundEnts[roundEnt].pointNames)
end

-- WatcherThink's bFinalPointInMap for a team that may capture the point.
function Controller:FinalPointInMap(point)
	if not self.master then return false end
	local teams = {}
	for _, team in ipairs(GAME_TEAMS) do
		if self:TeamMayCapture(point, team) then teams[#teams + 1] = team end
	end
	return self.master:FinalPoint(self:Set(), point, teams)
end

-- Point changes -------------------------------------------------------------------------

local function PublishStage(self)
	local stage, count, name = 0, 0, ""
	if self.master then stage, count, name = self.master:Stage(self:Set()) end
	SetGlobal2Int("ws_mini_round_stage", stage)
	SetGlobal2Int("ws_mini_round_count", count)
	SetGlobal2String("ws_mini_round_name", name)
end

local function FireTeamOutput(ent, prefix, team)
	ent:TriggerOutput(prefix .. TEAM_OUTPUT[team], ent)
end

-- The model's lines ({ hearer, team, sound }): everyone and team lines
-- play from the point through a recipient filter, as TF2's
-- CBroadcastRecipientFilter and CTeamRecipientFilter do; the others' lines
-- are each client's own (CLocalPlayerFilter).
local LINE_FILTER = {
	[Capture.HEAR_EVERYONE] = function(filter) filter:AddAllPlayers() end,
	[Capture.HEAR_TEAM] = function(filter, team) filter:AddRecipientsByTeam(team) end,
}

local function PlayLines(self, point, lines)
	for _, line in ipairs(lines) do
		if line.hearer == Capture.HEAR_OTHERS then
			WS.BroadcastSoundToOthers(line.team, line.sound)
		else
			local filter = RecipientFilter()
			LINE_FILTER[line.hearer](filter, line.team)
			point:EmitSound(line.sound, SNDLVL_NORM, PITCH_NORM, FULL_VOLUME, CHAN_AUTO, NO_SOUND_FLAGS, NO_DSP, filter)
		end
	end
end

-- CTeamControlPoint::HandleScoring: with score_style 1 each capture scores.
local function HandleScoring(self, point, capTeam)
	local scorePerCapture = self.master ~= nil and self.master:ScorePerCapture()
	if not scorePerCapture then return end
	team.AddScore(capTeam, 1)
end

-- CTeamControlPointMaster::FireTeamWinOutput and the round's.
local function DeclareWinner(self, winner, roundName, forceMapReset, switchTeams)
	if roundName then
		local roundEnt = self:CurrentRound()
		if IsValid(roundEnt) then roundEnt:TriggerOutput(Master.WinOutput(winner), roundEnt) end
	end
	self.rounds:SetWinningTeam(winner, Rounds.WINREASON.ALL_POINTS_CAPTURED, forceMapReset, switchTeams)
	if IsValid(self.masterEnt) then self.masterEnt:TriggerOutput(Master.WinOutput(winner), self.masterEnt) end
end

-- CTeamControlPointMaster::CheckWinConditions, KOTH's clock gate included.
function Controller:CheckWinConditions()
	if not self.master then return end
	local winner, roundName = self.master:Winner(self:Set())
	if not winner or not self.rounds:MayWinByPoints(winner) then return end
	local forceMapReset, switchTeams = self.master:WinArgs(self.set)
	DeclareWinner(self, winner, roundName, forceMapReset, switchTeams)
end

local POINT_EVENTS = {
	-- CTeamControlPoint::InternalSetOwner, then HandleScoring and the
	-- master's win check.
	owner = function(self, e)
		local point = e.id
		PlayLines(self, point, e.lines)
		-- the capture bell, everyone's own sound wherever they are
		if e.bell then WS.BroadcastSound(NOBODY, e.bell) end
		ApplyPointModel(self, point)
		if e.team == NOBODY then
			WS.FireOutput(point, "OnCapReset", point)
		else
			WS.FireOutput(point, "OnCap" .. TEAM_OUTPUT[e.team], point)
		end
		if e.sounding and e.team ~= NOBODY then
			WS.FireOutput(point, "OnOwnerChangedTo" .. TEAM_OUTPUT[e.team], point)
			WS.Events.Fire("game_teamplay_point_captured", {
				cp = self.set:Index(point),
				cpname = self.set:PrintName(point),
				team = e.team,
				cappers = e.cappers,
			})
		end
		hook.Run("WSPointCaptured", point, e.team)
		if e.scoring then HandleScoring(self, point, e.team) end
		self:CheckWinConditions()
	end,
	unlocked = function(self, e) WS.FireOutput(e.id, "OnUnlocked", e.id) end,
	unlock_time = function() end,
	round_start_owned = function(self, e)
		WS.FireOutput(e.id, "OnRoundStartOwnedBy" .. TEAM_OUTPUT[e.team], e.id)
	end,
}

local function ApplyPointEvents(self, events)
	for _, e in ipairs(events) do POINT_EVENTS[e.kind](self, e) end
end

-- CTeamControlPoint::ForceOwner
function Controller:ForceOwner(point, team)
	ApplyPointEvents(self, self:Set():SetOwner(point, team, Capture.CAUSE_FORCE))
end

function Controller:SetPointLocked(point, locked)
	ApplyPointEvents(self, self:Set():SetLocked(point, locked))
end

function Controller:SetPointUnlockTime(point, seconds)
	ApplyPointEvents(self, self:Set():SetUnlockTime(point, seconds, CurTime()))
end

-- Payload hides the points its carts' bars show.
function Controller:SetHudHidden(point, hidden)
	self.hudHidden[point] = hidden
end

-- A tf_logic_cp_timer's countdown under the point (nil: none).
function Controller:SetPointTimer(point, endTime)
	self.pointTimers[point] = endTime
end

-- team_control_point inputs (CTeamControlPoint's input table).
local POINT_INPUTS = {
	-- InputSetOwner: a sounding capture only when a player sent it.
	setowner = function(self, point, value, caller)
		local cause = IsValid(caller) and caller:IsPlayer() and Capture.CAUSE_PLAYER_INPUT or Capture.CAUSE_INPUT
		ApplyPointEvents(self, self:Set():SetOwner(point, Team(value), cause, self.rounds:PointsMayBeCaptured()))
	end,
	setlocked = function(self, point, value) self:SetPointLocked(point, (tonumber(value) or 0) > 0) end,
	setunlocktime = function(self, point, value) self:SetPointUnlockTime(point, tonumber(value) or 0) end,
	hidemodel = function(self, point) point:SetNoDraw(true) end,
	showmodel = function(self, point) point:SetNoDraw(false) end,
	roundactivate = function(self, point) ApplyPointEvents(self, self:Set():RoundActivate({ point })) end,
}

hook.Add("AcceptInput", "ws_capture_point", function(ent, input, activator, caller, value)
	if ent:GetClass() ~= POINT_CLASS then return end
	local handler = POINT_INPUTS[string.lower(input)]
	if not handler or not Controller:Set():Has(ent) then return end
	handler(Controller, ent, value, caller)
	return true
end)

return {
	PointByName = PointByName,
	RoundSpecs = RoundSpecs,
	OrderQuery = OrderQuery,
	AreasOf = AreasOf,
	AnyCapturing = AnyCapturing,
	PublishStage = PublishStage,
	FireTeamOutput = FireTeamOutput,
	PlayLines = PlayLines,
	DeclareWinner = DeclareWinner,
	ApplyPointEvents = ApplyPointEvents,
}
