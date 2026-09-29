-- team_control_point. GMod's engine already has a class by this name, which
-- wins over a Lua entity of the same name, and it is inert: it shows its model
-- but keeps none of TF2's state. So the TF2 behaviour lives here, beside each
-- engine control point: its keyvalues and outputs are recorded as the map sets
-- them (sv_world.lua), its inputs are taken through AcceptInput, and its outputs
-- are fired from the recording. Behaviour follows CTeamControlPoint
-- (team_control_point.cpp) and CTFGameRules::TeamMayCapturePoint.

-- team_control_point.h spawnflags
local SF_HIDE_MODEL = 2
local DEFAULT_MODEL = "models/effects/cappoint_hologram.mdl"
local DEFAULT_WARN_SOUND = "ControlPoint.CaptureWarn"
-- The client's spam guard on the final-cap warning (C_BaseTeamObjectiveResource::ClientThink).
local WARN_INTERVAL = 5
local MAX_PREVIOUS_POINTS = 3

-- TF2's convar (tf_gamerules.cpp).
local caplinear = CreateConVar("tf_caplinear", "1", FCVAR_REPLICATED, "If set to 1, teams must capture control points linearly.")

local function State(ent)
	local kv = WETSAND.KeyValues(ent)
	if kv.owner == nil then
		kv.owner = tonumber(kv.point_default_owner) or WETSAND.TEAM_UNASSIGNED
		kv.locked = kv.point_start_locked == "1"
	end
	return kv
end

-- CTeamControlPoint::SetModel: the owning team's model, bodygroup 0 set to the
-- team, and the team's skin (team - 2, neutral last).
local TEAM_BODYGROUP = 0
local POINT_SKIN = { [WETSAND.TEAM_RED] = 0, [WETSAND.TEAM_BLUE] = 1, [WETSAND.TEAM_UNASSIGNED] = 2 }

function WETSAND.ApplyPointModel(ent)
	local s = State(ent)
	local team = s.owner
	local model = s["team_model_" .. team]
	if not model or model == "" then model = DEFAULT_MODEL end
	if ent:GetModel() ~= model and util.IsValidModel(model) then ent:SetModel(model) end
	ent:SetBodygroup(TEAM_BODYGROUP, team)
	ent:SetSkin(POINT_SKIN[team])
	if bit.band(tonumber(s.spawnflags) or 0, SF_HIDE_MODEL) ~= 0 then ent:SetNoDraw(true) end
end

function WETSAND.CapTeam(ent)
	return State(ent).owner
end

function WETSAND.PointLocked(ent)
	return State(ent).locked
end

-- The map's point_index. TF2 renumbers points 0..n-1 in this order
-- (CTeamControlPointMaster::FindControlPoints); WETSAND.PointRank gives that number.
function WETSAND.PointIndex(ent)
	return tonumber(State(ent).point_index) or 0
end

function WETSAND.PointGroup(ent)
	return tonumber(State(ent).point_group) or 0
end

function WETSAND.PointDefaultOwner(ent)
	return tonumber(State(ent).point_default_owner) or WETSAND.TEAM_UNASSIGNED
end

-- Every control point, ordered by index, with each one's rank.
function WETSAND.ControlPoints()
	local points = ents.FindByClass("team_control_point")
	local indices = {}
	for i, p in ipairs(points) do indices[i] = WETSAND.PointIndex(p) end
	local ranks = WETSAND.RoundsLib.Ranks(indices)
	local ordered, rankOf = {}, {}
	for i, p in ipairs(points) do
		ordered[ranks[i] + 1] = p
		rankOf[p] = ranks[i]
	end
	return ordered, rankOf
end

function WETSAND.PointRank(ent)
	local _, rankOf = WETSAND.ControlPoints()
	return rankOf[ent]
end

-- Owner changes ---------------------------------------------------------------------

local function CheckMasters()
	for _, master in ipairs(ents.FindByClass("team_control_point_master")) do
		if master:IsActive() then master:CheckWinConditions() end
	end
end

-- CTeamControlPoint::InternalSetOwner. makeSound marks a true capture by
-- players: the team's cap sound, OnOwnerChangedToTeam, the capture notice.
local function InternalSetOwner(ent, team, makeSound, activator)
	local s = State(ent)
	s.owner = team
	if makeSound then
		local sound = s["team_capsound_" .. team]
		if sound and sound ~= "" then ent:EmitSound(sound) end
	end
	WETSAND.ApplyPointModel(ent)
	activator = activator or ent
	if team == WETSAND.TEAM_UNASSIGNED then
		WETSAND.FireOutput(ent, "OnCapReset", activator)
	else
		WETSAND.FireOutput(ent, team == WETSAND.TEAM_RED and "OnCapTeam1" or "OnCapTeam2", activator)
	end
	if makeSound and team ~= WETSAND.TEAM_UNASSIGNED then
		WETSAND.FireOutput(ent, team == WETSAND.TEAM_RED and "OnOwnerChangedToTeam1" or "OnOwnerChangedToTeam2", activator)
		WETSAND.Announce(WETSAND.TeamName[team] .. " captured point " .. WETSAND.PointIndex(ent), team)
	end
	hook.Run("WetsandPointCaptured", ent, team)
	CheckMasters()
end

-- CTeamControlPoint::HandleScoring: with score_style 1 each capture scores a
-- point, with the scored chime unless the capture wins the game (everyone
-- hears it on payload maps, only the team elsewhere).
local function HandleScoring(ent, capTeam)
	if WETSAND.ScorePerRound() or capTeam == WETSAND.TEAM_UNASSIGNED then return end
	team.AddScore(capTeam, 1)
	local master = WETSAND.Master()
	if not IsValid(master) or master:WouldNewOwnerWin(ent, capTeam) then return end
	local escort = #ents.FindByClass("team_train_watcher") > 0
	WETSAND.BroadcastSound(escort and WETSAND.TEAM_UNASSIGNED or capTeam, "Hud.EndRoundScored")
end

local function PointsMayBeCaptured()
	return not IsValid(WETSAND.Rules) or WETSAND.Rules:PointsMayBeCaptured()
end

-- CTeamControlPoint::SetOwner: a capture by players (a capture area).
function WETSAND.SetPointOwner(ent, team, activator)
	if not PointsMayBeCaptured() then return end
	HandleScoring(ent, team)
	InternalSetOwner(ent, team, true, activator)
end

-- CTeamControlPoint::ForceOwner: set by the game, no capture.
function WETSAND.ForcePointOwner(ent, team)
	InternalSetOwner(ent, team, false)
end

-- Locks ----------------------------------------------------------------------------------

-- CTeamControlPoint::InternalSetLocked: OnUnlocked fires whenever the point
-- is set unlocked, including at round start for a point that was never locked.
local function SetLocked(ent, locked)
	local s = State(ent)
	s.locked = locked
	if not locked then
		s.unlockAt = nil
		WETSAND.FireOutput(ent, "OnUnlocked", ent)
	end
end

local function SetUnlockTime(ent, seconds)
	if seconds <= 0 then
		SetLocked(ent, false)
		return
	end
	State(ent).unlockAt = CurTime() + seconds
end

-- CTeamControlPoint::UnlockThink: the timed unlock waits for the round to run.
timer.Create("wetsand_control_point_unlock", 0.1, 0, function()
	if WETSAND.Active() and WETSAND.State() ~= WETSAND.STATE.RND_RUNNING then return end
	for _, ent in ipairs(ents.FindByClass("team_control_point")) do
		local at = WETSAND.KeyValues(ent).unlockAt
		if at and at < CurTime() then SetLocked(ent, false) end
	end
end)

-- CTeamControlPoint::InputRoundActivate, sent at every round start.
function WETSAND.PointRoundActivate(ent)
	local team = WETSAND.CapTeam(ent)
	if team == WETSAND.TEAM_RED then WETSAND.FireOutput(ent, "OnRoundStartOwnedByTeam1", ent) end
	if team == WETSAND.TEAM_BLUE then WETSAND.FireOutput(ent, "OnRoundStartOwnedByTeam2", ent) end
	WETSAND.ApplyPointModel(ent)
	SetLocked(ent, WETSAND.PointLocked(ent))
end

-- Who may capture ---------------------------------------------------------------------------

-- team_previouspoint_<team>_<n>, as ranks; -1 where unset or unknown.
local function PreviousPoints(ent, team, rankOf)
	local s = State(ent)
	local previous = {}
	for n = 0, MAX_PREVIOUS_POINTS - 1 do
		local point = WETSAND.FindByName(s["team_previouspoint_" .. team .. "_" .. n])
		previous[n + 1] = IsValid(point) and rankOf[point] or -1
	end
	return previous
end

-- CTFGameRules::TeamMayCapturePoint, plus the capture area's own tests: the
-- team does not own the point, and with mini-rounds the point is in play.
function WETSAND.TeamCanCapPoint(point, team)
	if team ~= WETSAND.TEAM_RED and team ~= WETSAND.TEAM_BLUE then return false end
	if WETSAND.CapTeam(point) == team then return false end
	local master = WETSAND.Master()
	local mini = IsValid(master) and master:PlayingMiniRounds()
	if mini and not master:IsInRound(point) then return false end

	local ordered, rankOf = WETSAND.ControlPoints()
	local owners, bases = {}, {}
	for rank, p in ipairs(ordered) do
		owners[rank - 1] = WETSAND.CapTeam(p)
		bases[rank] = { index = rank - 1, defaultOwner = WETSAND.PointDefaultOwner(p) }
	end
	return WETSAND.RoundsLib.TeamMayCapturePoint({
		caplinear = caplinear:GetBool(),
		index = rankOf[point],
		team = team,
		locked = WETSAND.PointLocked(point),
		previous = PreviousPoints(point, team, rankOf),
		playingMiniRounds = mini,
		owners = owners,
		count = #ordered,
		base = WETSAND.RoundsLib.BaseControlPoint(team, bases),
	})
end

-- A team started capturing (CTeamControlPoint::CaptureStart, with what the
-- client does on it: C_TFObjectiveResource::SetCappingTeam's "our point is
-- being contested", or the final-cap warning for point_warn_on_cap 1).
function WETSAND.PointCaptureStarted(point, team)
	local s = State(point)
	local warn = tonumber(s.point_warn_on_cap) or WETSAND.RoundsLib.CP_WARN.NORMAL
	if warn == WETSAND.RoundsLib.CP_WARN.NORMAL and team ~= WETSAND.TEAM_UNASSIGNED then
		local line = s.owner ~= WETSAND.TEAM_UNASSIGNED and "Announcer.ControlPointContested" or "Announcer.ControlPointContested_Neutral"
		WETSAND.SoundTo(WETSAND.PlayersNotOn(team), line)
	elseif warn == WETSAND.RoundsLib.CP_WARN.FINALCAP and CurTime() > (s.lastWarn or -math.huge) + WARN_INTERVAL then
		s.lastWarn = CurTime()
		local sound = s.point_warn_sound
		if not sound or sound == "" then sound = DEFAULT_WARN_SOUND end
		WETSAND.SoundTo(WETSAND.PlayersNotOn(team), sound)
	end
	hook.Run("WetsandPointCaptureStarted", point, team)
end

-- The team that blocked a capture (CTeamControlPoint::CaptureBlocked): the
-- HUD's "defended" notice, only for points with a print name.
function WETSAND.PointCaptureBlocked(point, team)
	local name = State(point).point_printname
	if name and name ~= "" then
		WETSAND.RoundNotice(WETSAND.TeamName[team] .. " defended " .. name, team)
	end
	hook.Run("WetsandPointCaptureBlocked", point, team)
end

-- Inputs ------------------------------------------------------------------------------------

local INPUTS = {
	-- CTeamControlPoint::InputSetOwner: a sounding capture only when a player sent it.
	setowner = function(ent, value, activator, caller)
		local team = tonumber(value) or WETSAND.TEAM_UNASSIGNED
		if WETSAND.CapTeam(ent) == team or not PointsMayBeCaptured() then return end
		HandleScoring(ent, team)
		InternalSetOwner(ent, team, IsValid(caller) and caller:IsPlayer(), activator)
	end,
	setlocked = function(ent, value) SetLocked(ent, (tonumber(value) or 0) > 0) end,
	setunlocktime = function(ent, value) SetUnlockTime(ent, tonumber(value) or 0) end,
	hidemodel = function(ent) ent:SetNoDraw(true) end,
	showmodel = function(ent) ent:SetNoDraw(false) end,
	roundactivate = function(ent) WETSAND.PointRoundActivate(ent) end,
}

hook.Add("AcceptInput", "wetsand_control_point", function(ent, input, activator, caller, value)
	if ent:GetClass() ~= "team_control_point" then return end
	local handler = INPUTS[string.lower(input)]
	if not handler then return end
	handler(ent, value, activator, caller)
	return true
end)

-- Show each point in its owner's colours as soon as the map (or a round reset)
-- has spawned, not only once the round goes active.
local function ApplyAll()
	for _, ent in ipairs(ents.FindByClass("team_control_point")) do
		WETSAND.ApplyPointModel(ent)
	end
end
hook.Add("InitPostEntity", "wetsand_control_point", ApplyAll)
hook.Add("PostCleanupMap", "wetsand_control_point", ApplyAll)
