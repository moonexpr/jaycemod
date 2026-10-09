-- The editors feature's controller: what the Game Rules and Round Timer
-- editors (edit_gamerules, edit_roundtimer) read and change. The editors
-- check that the player is an admin before calling any of it. An action
-- returns true, or false and why not.
local Controller = {}

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local NO_ROUNDS = "this map has no rounds (no tf_gamerules)"
local NO_TIMER = "no round timer is showing"

local function Rules()
	return IsValid(WETSAND.Rules) and WETSAND.Rules or nil
end

-- Everyone is told what the admin changed (foundation.admin_notices). A
-- field sends a change at every step of its slider, so its notice waits
-- until the admin has left the fields alone SETTLE seconds.
local Notices = WETSAND.require("foundation.admin_notices")
local SETTLE = 3

local function Settled(key, notices)
	timer.Create("wetsand_admin_notice_" .. key, SETTLE, 1, function() WETSAND.Notify(notices) end)
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
	timer.Create("wetsand_admin_notice_score_" .. t, SETTLE, 1, function()
		local awarded = team.GetScore(t) - scoredFrom[t]
		scoredFrom[t] = nil
		if awarded > 0 then WETSAND.Notify(Notices.PointsAwarded(t, awarded, WETSAND.TeamName)) end
	end)
end

-- Respawns -------------------------------------------------------------------------

function Controller:RespawnTime(t)
	local rules = Rules()
	return rules and rules:TeamRespawnWaveTime(t) or 0
end

-- t nil sets both teams.
function Controller:SetRespawnTime(t, seconds)
	local rules = Rules()
	if not rules then return false, NO_ROUNDS end
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
	local rules = Rules()
	if not rules then return false, NO_ROUNDS end
	rules:SetAdminRespawnWaveTime(RED, nil)
	rules:SetAdminRespawnWaveTime(BLUE, nil)
	WETSAND.Notify(Notices.MapRespawnWaves())
	return true
end

function Controller:RespawnsDisabled()
	local rules = Rules()
	return rules ~= nil and rules:RespawnsDisabled()
end

function Controller:SetRespawnsDisabled(disabled)
	local rules = Rules()
	if not rules then return false, NO_ROUNDS end
	if rules:RespawnsDisabled() ~= disabled then WETSAND.Notify(Notices.RespawnsDisabled(disabled)) end
	rules:SetRespawnsDisabled(disabled)
	return true
end

-- Rounds and carts -------------------------------------------------------------------

function Controller:ResetRound()
	local rules = Rules()
	if not rules then return false, NO_ROUNDS end
	rules:RestartRound()
	return true
end

-- Every active cart goes back to its checkpoint (both on a race map), a
-- point it has just taken given back (the watcher's RetractToCheckpoint).
function Controller:RetractCarts()
	local moved, why = false, "this map has no payload cart"
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local ok, reason = watcher:RetractToCheckpoint()
		if ok then moved = true else why = reason end
	end
	if moved then return true end
	return false, why
end

-- Every active cart moves on to its next checkpoint (both on a race map).
function Controller:AdvanceCarts()
	local moved, why = false, "this map has no payload cart"
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local ok, reason = watcher:AdvanceToNextCheckpoint()
		if ok then moved = true else why = reason end
	end
	if moved then return true end
	return false, why
end

-- A map with a train watcher has the payload feature, which keeps the cart
-- speed; elsewhere the editor shows the map's own speed and changes nothing.
local MAP_CART_SPEED = 1

local function Payload()
	return ents.FindByClass("team_train_watcher")[1] and WETSAND.Feature("payload") or nil
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
	return ents.FindByClass("team_round_timer")[1] and WETSAND.Feature("rounds") or nil
end

local function Timer()
	local rounds = Rounds()
	return rounds and rounds:HudTimer() or nil
end

local function Remaining(timer)
	return WETSAND.Feature("rounds"):TimerOf(timer):TimeRemaining(CurTime())
end

function Controller:TimeLeft()
	local timer = Timer()
	return timer and Remaining(timer) or 0
end

function Controller:SetTimeLeft(seconds)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	WETSAND.Feature("rounds"):TimerInput(timer, "settime", math.max(0, seconds))
	return true
end

function Controller:Paused()
	local timer = Timer()
	return timer ~= nil and WETSAND.Feature("rounds"):TimerOf(timer):Paused()
end

function Controller:SetPaused(paused)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	if self:Paused() ~= paused then WETSAND.Notify(Notices.TimerPaused(paused)) end
	WETSAND.Feature("rounds"):TimerInput(timer, paused and "pause" or "resume")
	return true
end

-- TF2's AddTeamTime: the team is credited and the announcer says so. As in
-- TF2, time is only added while the round runs.
function Controller:AddTeamTime(t, seconds)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	if WETSAND.Active() and WETSAND.State() ~= WETSAND.STATE.RND_RUNNING then
		return false, "time can only be added while the round is running"
	end
	WETSAND.Feature("rounds"):AddTimerSeconds(timer, seconds, t)
	return true
end

-- Taking time away has no TF2 input or announcement: the timer is set.
function Controller:RemoveTime(seconds)
	local timer = Timer()
	if not timer then return false, NO_TIMER end
	WETSAND.Feature("rounds"):TimerInput(timer, "settime", math.max(0, Remaining(timer) - seconds))
	return true
end

return Controller
