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

-- Scores ---------------------------------------------------------------------------

function Controller:Score(t)
	return team.GetScore(t)
end

function Controller:SetScore(t, score)
	team.SetScore(t, math.max(0, math.floor(score)))
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
	for _, each in ipairs(t and { t } or { RED, BLUE }) do rules:SetAdminRespawnWaveTime(each, math.max(0, seconds)) end
	return true
end

function Controller:UseMapRespawnTimes()
	local rules = Rules()
	if not rules then return false, NO_ROUNDS end
	rules:SetAdminRespawnWaveTime(RED, nil)
	rules:SetAdminRespawnWaveTime(BLUE, nil)
	return true
end

function Controller:RespawnsDisabled()
	local rules = Rules()
	return rules ~= nil and rules:RespawnsDisabled()
end

function Controller:SetRespawnsDisabled(disabled)
	local rules = Rules()
	if not rules then return false, NO_ROUNDS end
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

function Controller:CartSpeed()
	return WETSAND.CartSpeedScale()
end

function Controller:SetCartSpeed(scale)
	WETSAND.SetCartSpeedScale(scale)
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
