-- round_manager: what a score and a win tell the games and the gamemode.
local T = dofile("tests/harness.lua")

local RED = 2
local order, teamScores, hookArgs, fired
local Rounds
local now, globals = 100, {}

ROUND_WAITING, ROUND_PREPARE, ROUND_ACTIVE, ROUND_OVER = 0, 1, 2, 3
CurTime = function() return now end
local function SetGlobal(name, value) globals[name] = value end
SetGlobal2Int, SetGlobal2Float = SetGlobal, SetGlobal
GetGlobal2Float = function(name, default)
	if globals[name] == nil then return default end
	return globals[name]
end
game_events = { Fire = function(name, fields) fired[#fired + 1] = { name = name, fields = fields } end }
player = { GetAll = function() return {} end }
game = { CleanUpMap = function() end, LoadNextMap = function() end }
function coroutine.wait(seconds)
	local ends = now + seconds
	while now < ends do coroutine.yield() end
end
CreateConVar = function() return { GetInt = function() return 3 end } end
team = {
	AddScore = function(t, score)
		order[#order + 1] = "team"
		teamScores[t] = (teamScores[t] or 0) + score
	end,
	NumPlayers = function() return 1 end,
	Joinable = function() return false end,
	GetName = function() return "a team" end,
	GetScore = function() return 0 end,
}
game_manager = {
	RunActive = function(name, info)
		order[#order + 1] = "game:" .. name
		hookArgs.game = info
	end,
	Active = function() return {} end,
	Tiebreaker = function() end,
}
hook = { Run = function(name, a, b)
	order[#order + 1] = "hook:" .. name
	hookArgs.hook = { a, b }
	-- what a gamemode answers
	if name == "RoundWin" then
		hookArgs.winner = a
		Rounds.Declare(a)
	end
end }

dofile("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/game_timer.lua")
dofile("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/round_manager.lua")
Rounds = package.loaded.round_manager
local Timer = package.loaded.game_timer

local function Fresh()
	order, teamScores, hookArgs, fired = {}, {}, {}, {}
end

-- As GM:Think does, a second at a time.
local function Run(seconds)
	for _ = 1, seconds do
		now = now + 1
		Timer.Think()
		Rounds.Think(true)
	end
end

-- A new match, played up to its round.
local function InRound()
	Fresh()
	Rounds.Think(false)
	Run(7)
	T.eq(globals.SandcastleRoundState, ROUND_ACTIVE, "in the round")
end

T.test("a round that runs out of time ends with nobody winning", function()
	InRound()
	T.defined(Timer.Remaining(Timer.ROUND), "its clock")
	Run(Timer.Remaining(Timer.ROUND) - 1)
	T.eq(hookArgs.winner, nil, "not yet")
	T.eq(globals.SandcastleRoundState, ROUND_ACTIVE, "still on")
	Run(1)
	T.eq(hookArgs.winner, TF_TEAM_UNASSIGNED, "nobody")
	T.eq(globals.SandcastleRoundState, ROUND_OVER, "over")
	T.eq(next(teamScores), nil, "no score")
	T.eq(fired[1].name, "teamplay_round_win", "announced")
	T.eq(fired[1].fields.team, TF_TEAM_UNASSIGNED, "as a stalemate")
end)

T.test("a team's clock running out closes the round for it", function()
	InRound()
	Timer.Start(Timer.TeamClock(RED), 3, { outcome = { team = RED } })
	Run(4)
	T.eq(hookArgs.winner, RED, "RED")
	T.eq(teamScores[RED], 1, "scored")
	T.eq(#fired, 1, "announced once")
	T.eq(fired[1].fields.team, RED, "RED's win")
end)

T.test("a new phase stops every clock of the last one", function()
	InRound()
	Timer.Start(Timer.TeamClock(RED), 1000, { outcome = { team = RED } })
	Rounds.RoundOutcome({ team = RED })
	Run(2)
	T.eq(globals.SandcastleRoundState, ROUND_OVER, "over")
	T.eq(Timer.Running(Timer.TeamClock(RED)), false, "the team's clock")
end)

T.test("a time adjustment moves the clock of the round being played only", function()
	InRound()
	local left = Timer.Remaining(Timer.ROUND)
	Rounds.AdjustTime({ team = RED, delta = 10 })
	T.eq(Timer.Remaining(Timer.ROUND), left + 10, "in the round")
	Rounds.RoundOutcome({ team = RED })
	Run(2)
	left = Timer.Remaining(Timer.ROUND)
	Rounds.AdjustTime({ team = RED, delta = 10 })
	T.eq(Timer.Remaining(Timer.ROUND), left, "after it")
end)

T.test("a score reaches the team, then the games being played, then the gamemode", function()
	Fresh()
	local info = { team = RED, score = 1, event = "control_point_capture" }
	Rounds.AddTeamScore(info)
	T.eq(table.concat(order, ","), "team,game:TeamScored,hook:TeamScored", "in order")
	T.eq(teamScores[RED], 1, "added")
	T.eq(hookArgs.game, info, "the games told what for")
	T.eq(hookArgs.hook[1], info, "the gamemode told what for")
end)

T.test("RoundOutcome fires the gamemode's RoundWin with the team and the outcome", function()
	Fresh()
	local outcome = { team = RED, reason = 7, forceMapReset = true, switchTeams = false }
	Rounds.RoundOutcome(outcome)
	T.eq(table.concat(order, ","), "hook:RoundWin", "the hook")
	T.eq(hookArgs.hook[1], RED, "the winner")
	T.eq(hookArgs.hook[2].reason, 7, "the caller's reason")
end)

T.test("an outcome with no team is a stalemate or a tie", function()
	Fresh()
	local outcome = { reason = 7, forceMapReset = true }
	Rounds.RoundOutcome(outcome)
	T.eq(hookArgs.hook[1], TF_TEAM_UNASSIGNED, "nobody won")
	T.eq(hookArgs.hook[2], outcome, "the outcome as given")
end)

T.test("only RoundOutcome closes a round from outside", function()
	T.eq(Rounds.Win, nil, "the old name is gone")
end)

T.finish()
