-- The gameplay feature's controller: the Gameplay Settings' switches.
-- Stopping the game puts the map in non-gameplay mode, which plays like
-- Sandbox (tf_gamerules' Halt: no rounds, timers paused, spawn doors and
-- forcefields open). A new game is announced and counted down from
-- COUNTDOWN with the announcer's round-start lines; then the scores are
-- cleared, the round system restarts from scratch (as a map's first round:
-- RestartRound's full reset) and everyone is made a spectator with the
-- team menu open until they choose a team. An action returns true, or
-- false and why not.
local Controller = {
	counting = false,
}

local COUNTDOWN = 5
local TIMER = "wetsand_new_game"

local function Rules()
	return IsValid(WETSAND.Rules) and WETSAND.Rules or nil
end

local function Center(text)
	for _, ply in ipairs(player.GetAll()) do ply:PrintMessage(HUD_PRINTCENTER, text) end
end

function Controller:Stop()
	local rules = Rules()
	if not rules then return false, "this map has no TF2 rounds (no tf_gamerules)" end
	if rules:Halted() then return false, "the game is already stopped" end
	timer.Remove(TIMER)
	self.counting = false
	rules:Halt()
	WETSAND.Announce("The game has been stopped. Free play until a new game starts.")
	return true
end

function Controller:StartNewGame()
	local rules = Rules()
	if not rules then return false, "this map has no TF2 rounds (no tf_gamerules)" end
	if self.counting then return false, "a new game is already counting down" end
	self.counting = true
	WETSAND.Announce("A new game is starting!")
	local left = COUNTDOWN
	local function Tick()
		if left > 0 then
			Center("New game in " .. left)
			WETSAND.BroadcastSound(WETSAND.TEAM_UNASSIGNED, "Announcer.RoundBegins" .. left .. "Seconds")
			left = left - 1
			return
		end
		timer.Remove(TIMER)
		self.counting = false
		self:Begin()
	end
	Tick()
	timer.Create(TIMER, 1, COUNTDOWN, Tick)
	return true
end

-- The countdown's end: a clean slate, everyone choosing a team.
function Controller:Begin()
	local rules = Rules()
	if not rules then return end
	team.SetScore(WETSAND.TEAM_RED, 0)
	team.SetScore(WETSAND.TEAM_BLUE, 0)
	rules:Unhalt()
	rules:RestartRound()
	for _, ply in ipairs(player.GetAll()) do
		WETSAND.SetPlayerTeam(ply, WETSAND.TEAM_SPECTATOR, true)
		WETSAND.ShowTeamMenu(ply)
	end
	Center("Choose a team!")
end

function Controller:Status()
	local rules = Rules()
	if not rules then return "no TF2 rounds on this map" end
	if self.counting then return "a new game is counting down" end
	return rules:Halted() and "stopped (free play)" or "running"
end

return Controller
