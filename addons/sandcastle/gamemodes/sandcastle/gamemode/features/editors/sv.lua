-- The editors feature's controller: what the Game Rules and Round Timer
-- editors (edit_gamerules, edit_roundtimer) read and change. The editors
-- check that the player is an admin before calling any of it. An action
-- returns true, or false and why not.
local Controller = {}

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local NO_ROUNDS = "this map has no rounds"
local NO_TIMER = "no round timer is showing"

-- Everyone is told what the admin changed (foundation.admin_notices). A
-- field sends a change at every step of its slider, so its notice waits
-- until the admin has left the fields alone SETTLE seconds.
local Notices = WS.require("foundation.admin_notices")
local SETTLE = 3

local function Settled(key, notices)
	timer.Create("ws_admin_notice_" .. key, SETTLE, 1, function() WS.Notify(notices) end)
end

-- Scores ---------------------------------------------------------------------------

function Controller:Score(t)
	return team.GetScore(t)
end

-- A score raised from the field is told once it has rested SETTLE seconds:
-- the points awarded since the first change (none for a score lowered).
local scoredFrom = {} -- team -> its score before the changes being settled

function Controller:SetScore(t, score)
	if scoredFrom[t] == nil then scoredFrom[t] = team.GetScore(t) end
	team.SetScore(t, math.max(0, math.floor(score)))
	timer.Create("ws_admin_notice_score_" .. t, SETTLE, 1, function()
		local awarded = team.GetScore(t) - scoredFrom[t]
		scoredFrom[t] = nil
		if awarded <= 0 then return end
		WS.Notify(Notices.PointsAwarded(t, awarded, WS.TeamName))
		WS.Events.Fire("game_points_awarded", { team = t, points = awarded })
	end)
end

-- Respawns -------------------------------------------------------------------------

function Controller:RespawnTime(t)
	return WS.Active() and WS.Rules:TeamRespawnWaveTime(t) or 0
end

-- t nil sets both teams.
function Controller:SetRespawnTime(t, seconds)
	if not WS.Active() then return false, NO_ROUNDS end
	local rules = WS.Rules
	seconds = math.max(0, seconds)
	local changed = false
	for _, each in ipairs(t and { t } or { RED, BLUE }) do
		changed = changed or rules:TeamRespawnWaveTime(each) ~= seconds
		rules:SetAdminRespawnWaveTime(each, seconds)
	end
	-- RED's, BLU's or both: one notice once the respawn fields are left alone
	if changed then Settled("respawn", Notices.RespawnTimesModified()) end
	return true
end

function Controller:UseMapRespawnTimes()
	if not WS.Active() then return false, NO_ROUNDS end
	local rules = WS.Rules
	rules:SetAdminRespawnWaveTime(RED, nil)
	rules:SetAdminRespawnWaveTime(BLUE, nil)
	WS.Notify(Notices.MapRespawnWaves())
	return true
end

function Controller:RespawnsDisabled()
	return WS.Active() and WS.Rules:RespawnsDisabled()
end

function Controller:SetRespawnsDisabled(disabled)
	if not WS.Active() then return false, NO_ROUNDS end
	local rules = WS.Rules
	if rules:RespawnsDisabled() ~= disabled then WS.Notify(Notices.RespawnsDisabled(disabled)) end
	rules:SetRespawnsDisabled(disabled)
	return true
end

-- Win conditions -------------------------------------------------------------------

-- TF2's match limits (mp_winlimit, mp_maxrounds, mp_timelimit): the rounds
-- feature makes the convars the engine lacks, so a map without rounds has none.
function Controller:WinCondition(convar)
	local cv = GetConVar(convar)
	return cv and cv:GetInt() or 0
end

function Controller:SetWinCondition(convar, value)
	local cv = GetConVar(convar)
	if not cv then return false, NO_ROUNDS end
	cv:SetInt(value)
	return true
end

-- Rounds and carts -------------------------------------------------------------------

function Controller:ResetRound()
	if not WS.Active() then return false, NO_ROUNDS end
	WS.Rules:RestartRound()
	return true
end

-- A cart (its train watcher) goes back to its last checkpoint, or on to its
-- next (ws/sh_editors_cart.lua, from the cart's right-click).
function Controller:RetractCart(watcher)
	return watcher:RetractToCheckpoint()
end

function Controller:AdvanceCart(watcher)
	return watcher:AdvanceToNextCheckpoint()
end

-- A map with a train watcher has the payload feature, which keeps the cart
-- speed; elsewhere the editor shows the map's own speed and changes nothing.
local MAP_CART_SPEED = 1

local function Payload()
	return ents.FindByClass("team_train_watcher")[1] and WS.Feature("payload") or nil
end

function Controller:CartSpeed()
	local payload = Payload()
	return payload and payload:CartSpeedScale() or MAP_CART_SPEED
end

function Controller:SetCartSpeed(scale)
	local payload = Payload()
	if payload then payload:SetCartSpeedScale(scale) end
end

-- The round timer shown in the HUD --------------------------------------------------------

-- A map with a round timer has the rounds feature, which knows the HUD timer.
local function Rounds()
	return ents.FindByClass("team_round_timer")[1] and WS.Feature("rounds") or nil
end

local function Timer()
	local rounds = Rounds()
	return rounds and rounds:HudTimer() or nil
end

local function Remaining(timer)
	return WS.Feature("rounds"):TimerOf(timer):TimeRemaining(CurTime())
end

function Controller:TimeLeft()
	local timer = Timer()
	return timer and Remaining(timer) or 0
end

function Controller:SetTimeLeft(seconds)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	WS.Feature("rounds"):TimerInput(timer, "settime", math.max(0, seconds))
	return true
end

function Controller:Paused()
	local timer = Timer()
	return timer ~= nil and WS.Feature("rounds"):TimerOf(timer):Paused()
end

function Controller:SetPaused(paused)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	if self:Paused() ~= paused then WS.Notify(Notices.TimerPaused(paused)) end
	WS.Feature("rounds"):TimerInput(timer, paused and "pause" or "resume")
	return true
end

-- TF2's AddTeamTime: the team is credited and the announcer says so. As in
-- TF2, time is only added while the round runs.
function Controller:AddTeamTime(t, seconds)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	if WS.Active() and WS.State() ~= WS.STATE.RND_RUNNING then
		return false, "time can only be added while the round is running"
	end
	WS.Feature("rounds"):AddTimerSeconds(timer, seconds, t)
	return true
end

-- A map without an objective plays untimed rounds; its round time, set
-- here, gives each round a timer of that many seconds (0: untimed again).
-- A map with an objective keeps the timers its objective set up.
function Controller:SetRoundTime(seconds)
	if not WS.Active() then return false, NO_ROUNDS end
	local rounds = WS.Feature("rounds")
	if rounds:Mode().OBJECTIVE then return false, "this map's objective times its rounds" end
	rounds:SetRoundTime(math.max(0, math.floor(seconds)))
	return true
end

-- Taking time away has no TF2 input or announcement: the timer is set.
function Controller:RemoveTime(seconds)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	WS.Feature("rounds"):TimerInput(timer, "settime", math.max(0, Remaining(timer) - seconds))
	return true
end

return Controller
