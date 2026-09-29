-- Round plumbing shared by tf_gamerules, team_round_timer and the control
-- point entities: the rules from foundation.rounds, the HUD timer (what TF2 keeps in
-- CBaseTeamObjectiveResource::m_iTimerToShowInHUD), setup and overtime flags,
-- the current mini-round, and the team switch.
WETSAND.RoundsLib = WETSAND.require("foundation.rounds")

local L = WETSAND.RoundsLib

-- teamplay_round_timer.cpp
local overtimeNag = CreateConVar("tf_overtime_nag", "0", FCVAR_NOTIFY, "Announcer overtime nag.")

-- Sounds to a chosen set of players, as TF2 plays them to each client's
-- local player (wetsand_pa_sound_file is received by cl_announcer.lua).
function WETSAND.SoundTo(players, name)
	if #players == 0 then return end
	net.Start("wetsand_pa_sound_file")
	net.WriteString(name)
	net.Send(players)
end

-- Every player not on the given team (spectators included), as the client's
-- "local player's team != capping team" test selects them.
function WETSAND.PlayersNotOn(team)
	local list = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply:Team() ~= team then list[#list + 1] = ply end
	end
	return list
end

-- Setup and overtime ------------------------------------------------------------------

-- CTeamplayRoundBasedRules::SetSetup: every timer entering or leaving setup sets it.
function WETSAND.SetSetup(inSetup)
	SetGlobal2Bool("wetsand_round_in_setup", inSetup)
end

function WETSAND.InSetup()
	return GetGlobal2Bool("wetsand_round_in_setup", false)
end

-- CTeamplayRoundBasedRules::SetOvertime; train watchers hear it through the
-- WetsandOvertime hook (the SDK sends them OnStartOvertime).
function WETSAND.SetOvertime(overtime)
	if GetGlobal2Bool("wetsand_round_overtime", false) == overtime then return end
	SetGlobal2Bool("wetsand_round_overtime", overtime)
	hook.Run("WetsandOvertime", overtime)
end

function WETSAND.InOvertime()
	return GetGlobal2Bool("wetsand_round_overtime", false)
end

-- The overtime nag (tf_overtime_nag): a coin flip each second.
local nextNag = 0
function WETSAND.OvertimeNag()
	if not overtimeNag:GetBool() or CurTime() <= nextNag then return end
	nextNag = CurTime() + 1
	if math.random(0, 1) > 0 then WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, "Game.Overtime") end
end

-- CTeamplayRoundBasedRules::TimerMayExpire: a pushed cart holds the clock.
function WETSAND.TimerMayExpire()
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		if not watcher:TimerMayExpire() then return false end
	end
	return true
end

-- The HUD timer -------------------------------------------------------------------------

local TIMER_KEYS = { "wetsand_timer_shown", "wetsand_timer_paused", "wetsand_timer_in_setup" }

local function ClearTimerKeys()
	for _, key in ipairs(TIMER_KEYS) do SetGlobal2Bool(key, false) end
end

-- CTeamRoundTimer::SetActiveTimer: newly (or nil) becomes the timer shown in
-- the HUD; other enabled, shown timers stop showing.
function WETSAND.SetActiveTimer(newly)
	local timers = ents.FindByClass("team_round_timer")
	local infos, newlyIndex = {}, nil
	for i, t in ipairs(timers) do
		infos[i] = { enabled = not t.disabled, show = t.showInHud == 1 }
		if t == newly then newlyIndex = i end
	end
	local chosen, hide = L.ChooseActiveTimer(infos, newlyIndex)
	for _, i in ipairs(hide) do timers[i].showInHud = 0 end
	WETSAND.HudTimer = chosen and timers[chosen] or nil
	if WETSAND.HudTimer then WETSAND.HudTimer:Publish() else ClearTimerKeys() end
end

function WETSAND.IsHudTimer(timer)
	return WETSAND.HudTimer == timer
end

-- CTeamRoundTimer::Activate for every timer, after the map (or a full reset) spawns.
function WETSAND.ActivateTimers()
	WETSAND.HudTimer = nil
	ClearTimerKeys()
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do
		if t.showInHud == 1 then WETSAND.SetActiveTimer(t) end
	end
end

-- Without tf_gamerules nothing sends RoundSpawn, so timers run from map spawn.
hook.Add("InitPostEntity", "wetsand_rounds", function()
	WETSAND.ActivateTimers()
	if WETSAND.Active() then return end
	for _, t in ipairs(ents.FindByClass("team_round_timer")) do t:RoundSpawn() end
end)

-- Control point master and mini-rounds -----------------------------------------------

-- g_hControlPointMasters[0]
function WETSAND.Master()
	return ents.FindByClass("team_control_point_master")[1] or NULL
end

function WETSAND.PlayingMiniRounds()
	local master = WETSAND.Master()
	return IsValid(master) and master:PlayingMiniRounds()
end

function WETSAND.CurrentRound()
	local master = WETSAND.Master()
	if not IsValid(master) then return NULL end
	return master:CurrentRound()
end

function WETSAND.PartialCapPointsRate()
	local master = WETSAND.Master()
	return IsValid(master) and master.partialCapRate or 0
end

-- CTeamplayRoundBasedRules::ShouldScorePerRound (score_style 0).
function WETSAND.ScorePerRound()
	local master = WETSAND.Master()
	return not (IsValid(master) and master:ScorePerCapture())
end

-- Team switch ----------------------------------------------------------------------------

-- Every RED player to BLU and every BLU player to RED (HandleSwitchTeams,
-- game_forcerespawn's ForceRespawnSwitchTeams). Scores are the caller's.
function WETSAND.SwitchTeams()
	for _, ply in ipairs(player.GetAll()) do
		local team = WETSAND.TeamOf(ply)
		if team ~= WETSAND.TEAM_UNASSIGNED then WETSAND.SetPlayerTeam(ply, WETSAND.EnemyOf(team), true) end
	end
end

function WETSAND.SwapTeamScores()
	local red, blu = team.GetScore(WETSAND.TEAM_RED), team.GetScore(WETSAND.TEAM_BLUE)
	team.SetScore(WETSAND.TEAM_RED, blu)
	team.SetScore(WETSAND.TEAM_BLUE, red)
end

-- A round notice for the HUD (teamplay_capture_blocked and the like).
util.AddNetworkString("wetsand_round_notice_show")
function WETSAND.RoundNotice(text, team)
	net.Start("wetsand_round_notice_show")
	net.WriteString(text)
	net.WriteUInt(team, 2)
	net.Broadcast()
end
