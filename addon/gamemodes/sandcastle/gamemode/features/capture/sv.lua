-- The capture feature's controller. It owns the map's PointSet (every
-- team_control_point), the Master (team_control_point_master and its
-- team_control_point_rounds) and an Area model per trigger_capture_area;
-- feeds them the players standing in the areas, the map's inputs and the
-- round's phases; and carries out what they answer: outputs, point models,
-- capture sounds, announcer lines, scoring, and round wins through the
-- rounds controller. It publishes the point HUD (wetsand_point_*) and each
-- player's capture panel (NW2 wetsand_capture_point/_reason), and is the
-- rounds controller's objective port.
--
-- team_control_point is GMod's own inert engine class, so its keyvalues are
-- recorded by sv_world and its inputs taken here through AcceptInput.
local Capture = WETSAND.require("foundation.capture")
local Area = WETSAND.require("foundation.capture.area")
local Master = WETSAND.require("foundation.capture.master")
local Rounds = WETSAND.require("foundation.rounds")

local POINT_CLASS = "team_control_point"
local NOBODY, RED, BLUE = WETSAND.TEAM_UNASSIGNED, WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local GAME_TEAMS = { RED, BLUE }
local TEAM_OUTPUT = {
	[RED] = "Team1",
	[BLUE] = "Team2",
}
local WAVE_TIME_INPUT = {
	[RED] = "AddRedTeamRespawnWaveTime",
	[BLUE] = "AddBlueTeamRespawnWaveTime",
}

-- TF2's convars (tf_gamerules.cpp, teamplayroundbased_gamerules.cpp).
local caplinear = CreateConVar("tf_caplinear", "1", FCVAR_REPLICATED, "If set to 1, teams must capture control points linearly.")
local capstyle = CreateConVar("mp_capstyle", "1", FCVAR_REPLICATED, "Sets the style of capture points used. 0 = Fixed players required to cap. 1 = More players cap faster, but longer cap times.")
local blockstyle = CreateConVar("mp_blockstyle", "1", FCVAR_REPLICATED, "Sets the style of capture point blocking used. 0 = Blocks break captures completely. 1 = Blocks only pause captures.")
local capdeteriorate = CreateConVar("mp_capdeteriorate_time", "90.0", FCVAR_REPLICATED, "Time it takes for a full capture point to deteriorate.")

local UNLOCK_THINK_TIME = 0.1 -- CONTROL_POINT_UNLOCK_THINK
local MASTER_THINK_TIME = 0.2 -- CPMThink
local PUBLISH_INTERVAL = 0.1 -- the HUD's 10 Hz

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

local NO_POINT_STOOD_ON = 0 -- wetsand_capture_point: ranks are published 1-based

local Controller = {
	AREA_THINK_TIME = 0.1, -- AREA_THINK_TIME: each trigger_capture_area thinks this often
	rounds = WETSAND.Feature("rounds"),
	set = nil,
	masterEnt = NULL,
	master = nil,
	roundEnts = {},
	areas = {},
	hudHidden = {},
	pointTimers = {},
	cpTimers = {}, -- tf_logic_cp_timer entity -> { model, pointName, point }
	loops = {},
	nextUnlock = 0,
	nextMasterThink = 0,
	nextPublish = 0,
}

local function Team(value)
	return tonumber(value) or NOBODY
end

-- The point set (FindControlPoints) --------------------------------------------------

local function IsPoint(ent)
	return IsValid(ent) and ent:GetClass() == POINT_CLASS
end

local function PointByName(name)
	local ent = WETSAND.FindByName(name)
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
	local kv = WETSAND.KeyValues(ent)
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
	if name == "" then return "wetsand_round_" .. ent:EntIndex() end
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
	local kv = WETSAND.KeyValues(ent)
	local team = self.set:Owner(ent)
	local model = kv["team_model_" .. team]
	if not model or model == "" then model = DEFAULT_MODEL end
	if ent:GetModel() ~= model and util.IsValidModel(model) then ent:SetModel(model) end
	ent:SetBodygroup(TEAM_BODYGROUP, team)
	ent:SetSkin(POINT_SKIN[team])
	if bit.band(self.set:Spawnflags(ent), Capture.SF_HIDE_MODEL) ~= 0 then ent:SetNoDraw(true) end
end

-- Each point has a proxy (WETSAND.Proxy, kind "point"), the box an admin
-- right-clicks for its entries (wetsand/sh_editors_point.lua), and the props
-- of its base name it. A payload checkpoint's is its cart's instead
-- (features/payload).
local POINT_PROXY_MINS, POINT_PROXY_MAXS = Vector(-48, -48, -8), Vector(48, 48, 64)

local function KeepPointProxy(point)
	local proxy, made = WETSAND.Proxy(point, "point", point, POINT_PROXY_MINS, POINT_PROXY_MAXS)
	if made then WETSAND.ProxyBodies(proxy, point:GetPos()) end
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
end, "wetsand_capture")

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
-- NULL: its spawns are the ones set up (wetsand/sv_teams_spawn.lua).
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
	SetGlobal2Int("wetsand_mini_round_stage", stage)
	SetGlobal2Int("wetsand_mini_round_count", count)
	SetGlobal2String("wetsand_mini_round_name", name)
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
			WETSAND.BroadcastSoundToOthers(line.team, line.sound)
		else
			local filter = RecipientFilter()
			LINE_FILTER[line.hearer](filter, line.team)
			point:EmitSound(line.sound, SNDLVL_NORM, PITCH_NORM, FULL_VOLUME, CHAN_AUTO, NO_SOUND_FLAGS, NO_DSP, filter)
		end
	end
end

-- CTeamControlPoint::HandleScoring: with score_style 1 each capture scores,
-- with the scored chime unless it wins the game (to everyone on payload
-- maps, to the team elsewhere: the mode's SCORE_CHIME_TO_ALL).
local function HandleScoring(self, point, capTeam)
	local scorePerCapture = self.master ~= nil and self.master:ScorePerCapture()
	if not scorePerCapture then return end
	team.AddScore(capTeam, 1)
	local wouldWin = self.master:WouldNewOwnerWin(self.set, point, capTeam)
	local chime = Capture.ScoredChime(scorePerCapture, wouldWin, self.rounds:Mode().SCORE_CHIME_TO_ALL, capTeam)
	if chime then PlayLines(self, point, { chime }) end
end

-- CTeamControlPointMaster::FireTeamWinOutput and the round's.
local function DeclareWinner(self, winner, roundName, forceMapReset, switchTeams)
	if roundName then
		local roundEnt = self:CurrentRound()
		if IsValid(roundEnt) then FireTeamOutput(roundEnt, "OnWonByTeam", winner) end
	end
	self.rounds:SetWinningTeam(winner, Rounds.WINREASON.ALL_POINTS_CAPTURED, forceMapReset, switchTeams)
	if IsValid(self.masterEnt) then FireTeamOutput(self.masterEnt, "OnWonByTeam", winner) end
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
		ApplyPointModel(self, point)
		if e.team == NOBODY then
			WETSAND.FireOutput(point, "OnCapReset", point)
		else
			WETSAND.FireOutput(point, "OnCap" .. TEAM_OUTPUT[e.team], point)
		end
		if e.sounding and e.team ~= NOBODY then
			WETSAND.FireOutput(point, "OnOwnerChangedTo" .. TEAM_OUTPUT[e.team], point)
			WETSAND.Events.Fire("teamplay_point_captured", {
				cp = self.set:Index(point),
				cpname = self.set:PrintName(point),
				team = e.team,
			})
		end
		hook.Run("WetsandPointCaptured", point, e.team)
		if e.scoring then HandleScoring(self, point, e.team) end
		self:CheckWinConditions()
	end,
	unlocked = function(self, e) WETSAND.FireOutput(e.id, "OnUnlocked", e.id) end,
	unlock_time = function() end,
	round_start_owned = function(self, e)
		WETSAND.FireOutput(e.id, "OnRoundStartOwnedBy" .. TEAM_OUTPUT[e.team], e.id)
	end,
}

local function ApplyPointEvents(self, events)
	for _, e in ipairs(events) do POINT_EVENTS[e.kind](self, e) end
end

-- CTeamControlPoint::ForceOwner
function Controller:ForceOwner(point, team)
	ApplyPointEvents(self, self:Set():SetOwner(point, team, Capture.CAUSE_FORCE))
end

-- A capture for team as a player's SetOwner input makes it (an admin's Set
-- Team, wetsand/sh_editors_point.lua): its capture sound, the map's outputs
-- (OnOwnerChangedTo..., OnCap...), scoring and the win check. Returns true,
-- or false and why not.
function Controller:CapturePoint(point, team)
	if self:Owner(point) == team then return false, "the point is already " .. WETSAND.TeamName[team] .. "'s" end
	local events = self:Set():SetOwner(point, team, Capture.CAUSE_PLAYER_INPUT, self.rounds:PointsMayBeCaptured())
	if #events == 0 then return false, "points cannot be captured now" end
	ApplyPointEvents(self, events)
	return true
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

hook.Add("AcceptInput", "wetsand_capture_point", function(ent, input, activator, caller, value)
	if ent:GetClass() ~= POINT_CLASS then return end
	local handler = POINT_INPUTS[string.lower(input)]
	if not handler or not Controller:Set():Has(ent) then return end
	handler(Controller, ent, value, caller)
	return true
end)

-- Round phases --------------------------------------------------------------------------

-- InputRoundSpawn: the master finds its points and rounds again.
function Controller:RoundSpawn()
	self:Rebuild()
	PublishStage(self)
end

-- InputRoundActivate: every point (outputs, locks), then the master, which
-- chooses the mini-round and registers it with the gamerules.
function Controller:RoundActivate()
	local set = self:Set()
	ApplyPointEvents(self, set:RoundActivate())
	if self.master then
		local name, firstAfterRestart = self.master:RoundActivate(set, self.rounds:History(), math.random)
		if name then
			self.rounds:AddPlayedRound(name)
			if firstAfterRestart then self.rounds:SetFirstRoundPlayed(name) end
			local roundEnt = self:CurrentRound()
			roundEnt:TriggerOutput("OnStart", roundEnt)
			hook.Run("WetsandMiniRoundStart", roundEnt)
		end
	end
	PublishStage(self)
end

-- CTFGameRules::PreviousRoundEnd: the mini-round's OnEnd.
function Controller:PreviousRoundEnd()
	if not self.master then return end
	local roundEnt = self:CurrentRound()
	self.master:EndRound()
	if IsValid(roundEnt) then roundEnt:TriggerOutput("OnEnd", roundEnt) end
end

-- The master ---------------------------------------------------------------------------

-- InternalSetWinner: team 0 is a stalemate.
local function SetWinner(self, team)
	local args = self.master:SetWinnerArgs(team, self:Set())
	if args.stalemate then
		self.rounds:SetStalemate(Rounds.STALEMATE.TIMER, args.forceMapReset, false)
		return
	end
	DeclareWinner(self, team, nil, args.forceMapReset, args.switchTeams)
end

-- InputSetWinnerAndForceCaps: the winner takes every point in play.
local function SetWinnerAndForceCaps(self, team)
	for _, point in ipairs(self.master:ForcedCaps(self:Set())) do self:ForceOwner(point, team) end
	SetWinner(self, team)
end

-- The rounds controller's objective port (Rounds.OBJECTIVE_METHODS).
local Objective = {}

function Objective:PlayingMiniRounds() return Controller.master:PlayingMiniRounds() end
function Objective:NumPlayable() return Controller.master:NumPlayable(Controller:Set()) end
function Objective:PlayAllRounds() return Controller.master:PlayAllRounds() end
function Objective:RoundsRemaining(team) return Controller.master:RoundsRemaining(team, Controller:Set()) end
function Objective:ScorePerRound() return not Controller.master:ScorePerCapture() end
function Objective:SuddenDeathWin(team) SetWinnerAndForceCaps(Controller, team) end

-- g_hControlPointMasters[0]: the first master bound is the one in charge.
function Controller:BindMaster(ent, kv)
	if IsValid(self.masterEnt) and self.masterEnt ~= ent then return end
	self.masterEnt = ent
	self.master = Master.New({
		restrict = Team(kv.cpm_restrict_team_cap_win),
		switchTeams = kv.switch_teams == "1",
		scoreStyle = tonumber(kv.score_style) or Master.SCORE_PER_ROUND,
		playAllRounds = kv.play_all_rounds == "1",
		partialCapRate = tonumber(kv.partial_cap_points_rate) or 0,
		capLayout = kv.caplayout or "",
		disabled = kv.startdisabled == "1",
		rounds = RoundSpecs(self),
	})
	self.rounds:SetObjective(Objective)
end

-- A map reset removes the master before its replacement binds.
function Controller:UnbindMaster(ent)
	if ent ~= self.masterEnt then return end
	self.masterEnt = NULL
	self.master = nil
	self.rounds:SetObjective(Rounds.NO_OBJECTIVE)
end

local MASTER_INPUTS = {
	enable = function(self) self.master:Enable() end,
	disable = function(self) self.master:Disable() end,
	setwinner = function(self, value) SetWinner(self, Team(value)) end,
	setwinnerandforcecaps = function(self, value) SetWinnerAndForceCaps(self, Team(value)) end,
	roundspawn = function(self) self:RoundSpawn() end,
	roundactivate = function(self) self:RoundActivate() end,
	setcaplayout = function(self, value) self.master:SetCapLayout(tostring(value)) end,
	-- The HUD's icons are drawn in rows, not at custom positions.
	setcaplayoutcustompositionx = function() end,
	setcaplayoutcustompositiony = function() end,
}

-- Whether the master took the input.
function Controller:MasterInput(ent, name, value)
	local handler = MASTER_INPUTS[name]
	if not handler or ent ~= self.masterEnt then return false end
	handler(self, value)
	return true
end

-- team_control_point_round: cpr_cp_names, cpr_priority,
-- cpr_restrict_team_cap_win, cpr_printname.
function Controller:BindRound(ent, kv)
	self.roundEnts[ent] = {
		pointNames = string.Explode("%s+", string.Trim(kv.cpr_cp_names or ""), true),
		priority = tonumber(kv.cpr_priority) or 0,
		restrict = Team(kv.cpr_restrict_team_cap_win),
		printName = kv.cpr_printname or "",
	}
	if self.master then self.master:SetRounds(RoundSpecs(self)) end
end

function Controller:UnbindRound(ent)
	self.roundEnts[ent] = nil
end

-- Enable and Disable are accepted but not consulted (IsPlayable ignores
-- StartDisabled, as in the SDK); the point list is found by name on use.
local ROUND_INPUTS = {
	enable = function() end,
	disable = function() end,
	roundspawn = function() end,
}

function Controller:RoundInput(ent, name, value)
	local handler = ROUND_INPUTS[name]
	if not handler then return false end
	handler(self, ent, value)
	return true
end

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
	}
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
	for _, ply in ipairs(WETSAND.PlayersInside(a.ent)) do Add(WETSAND.TeamOf(ply)) end
	for _, member in ipairs(WETSAND.MembersInside(a.ent)) do Add(WETSAND.TeamNumber(member)) end
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
	hook.Run("WetsandPointCaptureStarted", point, team)
end

-- CTeamControlPoint::CaptureBlocked: the clients show the HUD's "defended"
-- notice (for points with a print name).
local function CaptureBlocked(self, point, team)
	WETSAND.Events.Fire("teamplay_capture_blocked", {
		cp = self.set:Index(point),
		cpname = self.set:PrintName(point),
		team = team,
	})
	hook.Run("WetsandPointCaptureBlocked", point, team)
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
	end,
	capturestart = function(self, a, point, e) CaptureStarted(self, point, e.team) end,
	numcappers = function(self, a, point, e) SetNumCappers(a, e.n, e.blocked) end,
	-- UpdateBlocked: the point hears a block when it starts
	blocked = function(self, a, point, e)
		if e.value then CaptureBlocked(self, point, WETSAND.EnemyOf(e.capping)) end
	end,
	["break"] = function(self, a, point, e)
		FireTeamOutput(a.ent, "OnBreak", e.team)
		a.ent:TriggerOutput("OnBreakCap", a.ent)
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

-- The HUD --------------------------------------------------------------------------------

-- The first enabled area on the point, with the state the HUD shows.
local function HudArea(self, point)
	for _, a in ipairs(AreasOf(self, point)) do
		if a.enabled then
			return {
				capping = a.state.cappingTeam,
				teamInZone = a.state.teamInZone,
				touching = a.state.touching,
				blocked = a.state.blocked,
				progress = a.lastInput and Area.Progress(a.state, a.lastInput) or 0,
				numRequired = a.numRequired,
				canCap = a.canCap,
				scales = capstyle:GetBool(),
			}
		end
	end
	return nil
end

local function Key(rank, field)
	return "wetsand_point_" .. rank .. "_" .. field
end

local function PublishPoint(rank, hud)
	SetGlobal2Int(Key(rank, "owner"), hud.owner)
	SetGlobal2Bool(Key(rank, "locked"), hud.locked)
	SetGlobal2Float(Key(rank, "unlock_time"), hud.unlockTime)
	SetGlobal2Int(Key(rank, "capping"), hud.capping)
	SetGlobal2Float(Key(rank, "progress"), hud.progress)
	SetGlobal2Int(Key(rank, "cappers"), hud.cappers)
	SetGlobal2Int(Key(rank, "required"), hud.required)
	SetGlobal2Bool(Key(rank, "blocked"), hud.blocked)
	SetGlobal2Bool(Key(rank, "red_can_cap"), hud.redCanCap)
	SetGlobal2Bool(Key(rank, "blue_can_cap"), hud.blueCanCap)
	SetGlobal2Bool(Key(rank, "in_round"), hud.inRound)
	SetGlobal2Bool(Key(rank, "hidden"), hud.hidden)
	SetGlobal2String(Key(rank, "name"), hud.name)
	SetGlobal2Float(Key(rank, "timer_end"), hud.timerEnd)
end

-- Every point with what the HUD shows of it, in rank order: { point, rank
-- (0-based), hud (PointSet:HudPoint) }. What a player may know of the
-- points, so the AI war reads its capture state here.
function Controller:HudPoints()
	local set = self:Set()
	local q = OrderQuery(self, RED)
	local bases = {
		[RED] = q.base,
		[BLUE] = OrderQuery(self, BLUE).base,
	}
	local list = {}
	for _, point in ipairs(set:Ids()) do
		list[#list + 1] = {
			point = point,
			rank = set:Rank(point),
			hud = set:HudPoint(point, {
				area = HudArea(self, point),
				playingMiniRounds = q.playingMiniRounds,
				inRound = q.inRound,
				bases = bases,
				hidden = self.hudHidden[point] == true,
				timerEnd = self.pointTimers[point] or 0,
			}),
		}
	end
	return list
end

-- The point's enabled trigger_capture_area entities.
function Controller:AreaEntities(point)
	local list = {}
	for ent, a in pairs(self.areas) do
		if IsValid(ent) and a.enabled and PointByName(a.pointName) == point then list[#list + 1] = ent end
	end
	return list
end

local function PublishPoints(self)
	local set = self:Set()
	for _, entry in ipairs(self:HudPoints()) do PublishPoint(entry.rank + 1, entry.hud) end
	SetGlobal2Int("wetsand_point_count", set:Count())
	SetGlobal2String("wetsand_point_layout", self.master and self.master:CapLayout() or "")
end

-- The capture panel of each player standing in an area (C_TFPlayer's
-- control point, CControlPointProgressBar::UpdateBarText).
local function PublishPanels(self)
	local standing = {}
	for ent, a in pairs(self.areas) do
		local point = IsValid(ent) and a.enabled and AreaPoint(self, a) or NULL
		if IsValid(point) then
			for _, ply in ipairs(WETSAND.PlayersInside(ent)) do
				local team = WETSAND.TeamOf(ply)
				if team ~= NOBODY then
					local q = OrderQuery(self, team)
					q.pointsMayBeCaptured = self.rounds:PointsMayBeCaptured()
					q.blocked = a.state.blocked
					q.capping = a.state.cappingTeam
					q.cappers = a.state.touching[team]
					q.required = capstyle:GetBool() and 0 or a.numRequired[team]
					q.pauseOnBlock = blockstyle:GetInt() == Area.BLOCKSTYLE_PAUSE
					q.canCap = a.canCap
					standing[ply] = {
						rank = self.set:Rank(point) + 1,
						reason = self.set:CannotCapReason(point, team, q),
						-- what the panel pins to: the cart an area rides, else the point
						anchor = IsValid(ent:GetParent()) and ent:GetParent() or point,
					}
				end
			end
		end
	end
	for _, ply in ipairs(player.GetAll()) do
		local s = standing[ply]
		ply:SetNW2Int("wetsand_capture_point", s and s.rank or NO_POINT_STOOD_ON)
		ply:SetNW2Int("wetsand_capture_reason", s and s.reason or Capture.REASON_NONE)
		ply:SetNW2Entity("wetsand_capture_anchor", s and s.anchor or NULL)
	end
end

-- Timed unlocks, the master's think and the HUD, on one clock.
hook.Add("Think", "wetsand_capture", function()
	local self = Controller
	local now = CurTime()
	if now >= self.nextUnlock then
		self.nextUnlock = now + UNLOCK_THINK_TIME
		ApplyPointEvents(self, self:Set():Tick(now, self.rounds:State() == WETSAND.STATE.RND_RUNNING))
	end
	if now >= self.nextMasterThink then
		self.nextMasterThink = now + MASTER_THINK_TIME
		if self.master and self.master:Active() and self.rounds:PointsMayBeCaptured() then self:CheckWinConditions() end
	end
	if now >= self.nextPublish and WETSAND.Active() then
		self.nextPublish = now + PUBLISH_INTERVAL
		PublishPoints(self)
		PublishPanels(self)
	end
end)

-- Wiring into the round -------------------------------------------------------------------

Controller.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_CAPTURE, function() Controller:RoundSpawn() end)
Controller.rounds:AddRoundListener(Rounds.PHASE_ACTIVATE, Rounds.LISTEN_CAPTURE, function() Controller:RoundActivate() end)
Controller.rounds:AddRoundListener(Rounds.PHASE_ROUND_END, Rounds.LISTEN_CAPTURE, function() Controller:PreviousRoundEnd() end)
Controller.rounds:AddTimerHold("capture", function() return AnyCapturing(Controller) end, true)

-- A cleanup recreates every point, and not every cleanup is a round's (an
-- admin's game.CleanUpMap has no RoundSpawn): the set follows the new ones.
hook.Add("PostCleanupMap", "wetsand_capture", function() Controller:Rebuild() end)

-- tf_logic_cp_timer (CCPTimerLogic) -------------------------------------------------------
-- Loaded with the first timer: its model, its round-spawn listener and its
-- hold on the round timer.

local POINT_TIMER_MODEL = "foundation.capture.point_timer"
local POINT_TIMER_HOLD = "cp_timer"
local POINT_TIMER_MISSING = "%s failed to find control point named '%s'"

-- The model's events, by kind: the entity's output and the HUD's countdown
-- (ObjectiveResource()->SetCPTimerTime).
local function PointTimerEvents(PointTimer)
	return {
		[PointTimer.START] = function(self, ent, point, e)
			ent:TriggerOutput("OnCountdownStart", ent)
			self:SetPointTimer(point, e.endTime)
		end,
		[PointTimer.END] = function(self, ent, point)
			ent:TriggerOutput("OnCountdownEnd", ent)
			self:SetPointTimer(point, nil)
		end,
	}
end

-- CCPTimerLogic::InputRoundSpawn: the point again, since a map reset
-- recreates the points.
local function FindTimerPoint(ent, t)
	if t.pointName == "" then return end
	t.point = PointByName(t.pointName)
	if not IsValid(t.point) then print(string.format(POINT_TIMER_MISSING, ent:GetClass(), t.pointName)) end
end

local function PointTimersRoundSpawn()
	for ent, t in pairs(Controller.cpTimers) do
		if IsValid(ent) then FindTimerPoint(ent, t) end
	end
end

-- CTFGameRules::TimerMayExpire over m_CPTimerEnts.
local function PointTimersHold()
	for ent, t in pairs(Controller.cpTimers) do
		if IsValid(ent) and IsValid(t.point) and not t.model:MayExpire(Controller:TeamMayCapture(t.point, t.model:Team())) then
			return true
		end
	end
	return false
end

-- kv = { controlpoint, timer_length, team_number }.
function Controller:BindPointTimer(ent, kv)
	local PointTimer = WETSAND.require(POINT_TIMER_MODEL)
	self.pointTimerEvents = self.pointTimerEvents or PointTimerEvents(PointTimer)
	self.pointTimerThinkTime = PointTimer.THINK_INTERVAL
	self.cpTimers[ent] = {
		model = PointTimer.New({
			length = tonumber(kv.timer_length),
			team = tonumber(kv.team_number),
		}),
		pointName = kv.controlpoint or "",
		point = NULL,
	}
	self.rounds:AddRoundListener(Rounds.PHASE_SPAWN, Rounds.LISTEN_LOGIC, PointTimersRoundSpawn)
	self.rounds:AddTimerHold(POINT_TIMER_HOLD, PointTimersHold)
end

function Controller:UnbindPointTimer(ent)
	self.cpTimers[ent] = nil
end

-- CCPTimerLogic::Think, only while the timer has its point; returns when
-- the entity thinks next.
function Controller:PointTimerThink(ent)
	local t = self.cpTimers[ent]
	local now = CurTime()
	if IsValid(t.point) then
		local events = t.model:Think(now, {
			teamMayCapture = self:TeamMayCapture(t.point, t.model:Team()),
			capping = self:CappingTeam(t.point) ~= NOBODY,
			roundWon = self.rounds:State() == WETSAND.STATE.TEAM_WIN,
		})
		for _, e in ipairs(events) do self.pointTimerEvents[e.kind](self, ent, t.point, e) end
	end
	return now + self.pointTimerThinkTime
end

-- The timer's inputs, lower-cased: only RoundSpawn.
function Controller:PointTimerInput(ent, name)
	if name ~= "roundspawn" then return false end
	FindTimerPoint(ent, self.cpTimers[ent])
	return true
end

return Controller
