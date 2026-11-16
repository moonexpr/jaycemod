-- round_manager: what a score and a win tell the games and the gamemode.
local T = dofile ("tests/harness.lua")

local RED = 2
local order, teamScores, hookArgs, fired
local Rounds
local now, globals = 100, {}

ROUND_WAITING, ROUND_PREPARE, ROUND_ACTIVE, ROUND_OVER = 0, 1, 2, 3
CurTime = function () return now end
local function SetGlobal (name, value) globals [name] = value end
SetGlobal2Int, SetGlobal2Float = SetGlobal, SetGlobal
GetGlobal2Float = function (name, default)
	if globals [name] == nil then return default end
	return globals [name]
end
game_events = { Fire = function (name, fields) fired [#fired + 1] = { name = name, fields = fields } end }
player = { GetAll = function () return {} end }
game = { CleanUpMap = function () end, LoadNextMap = function () end }
function coroutine.wait (seconds)
	local ends = now + seconds
	while now < ends do coroutine.yield () end
end
-- each convar made, by name: its default, flags, help and range
local convars = {}
CreateConVar = function (name, default, flags, help, min, max)
	convars [name] = { default = default, min = min, max = max }
	return { GetInt = function () return 3 end }
end
team =
{
	AddScore = function (t, score)
		order [#order + 1] = "team"
		teamScores [t] = (teamScores [t] or 0) + score
	end,
	NumPlayers = function () return 1 end,
	Joinable = function () return false end,
	GetName = function () return "a team" end,
	GetScore = function () return 0 end
}
game_manager =
{
	RunActive = function (name, info)
		order [#order + 1] = "game:" .. name
		hookArgs.game = info
	end,
	Active = function () return {} end,
	Tiebreaker = function () end
}
hook = { Run = function (name, a, b)
	order [#order + 1] = "hook:" .. name
	hookArgs.hook = { a, b }
	-- what a gamemode answers
	if name == "RoundWin" then
		hookArgs.winner = a
		Rounds.Declare (a)
	end
end }

dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/game_timer.lua")
dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/round_manager.lua")
Rounds = package.loaded.round_manager
local Timer = package.loaded.game_timer

local function Fresh ()
	order, teamScores, hookArgs, fired = {}, {}, {}, {}
end

-- As GM:Think does, a second at a time.
local function Run (seconds)
	for _ = 1, seconds do
		now = now + 1
		Timer.Think ()
		Rounds.Think (true)
	end
end

-- A new match, played up to its round.
local function InRound ()
	Fresh ()
	Rounds.Think (false)
	Run (7)
	T.eq (Rounds.State (), ROUND_ACTIVE, "in the round")
end

-- Gameplay's win conditions set mp_winlimit to 0 for a map whose captures score (an attack/defend
-- map's stopwatch): a win limit there would end the match a capture in.
T.test ("mp_winlimit may be 0, no limit: a team's wins then never take the match", function ()
	T.eq (convars.mp_winlimit.min,  0,     "0 allowed")
	T.eq (Rounds.TakesMatch (5, 0), false, "no limit")
	T.eq (Rounds.TakesMatch (3, 3), true,  "the limit reached")
	T.eq (Rounds.TakesMatch (2, 3), false, "short of it")
end)

T.test ("a round that runs out of time ends with nobody winning", function ()
	InRound ()
	T.defined (Timer.Remaining (Timer.ROUND), "its clock")
	Run (Timer.Remaining (Timer.ROUND) - 1)
	T.eq (hookArgs.winner, nil,          "not yet")
	T.eq (Rounds.State (), ROUND_ACTIVE, "still on")
	Run (1)
	T.eq (hookArgs.winner,       TF_TEAM_UNASSIGNED,   "nobody")
	T.eq (Rounds.State (),       ROUND_OVER,           "over")
	T.eq (next (teamScores),     nil,                  "no score")
	T.eq (fired [1].name,        "teamplay_round_win", "announced")
	T.eq (fired [1].fields.team, TF_TEAM_UNASSIGNED,   "as a stalemate")
end)

T.test ("a team's clock running out closes the round for it", function ()
	InRound ()
	Timer.Start (Timer.TeamClock (RED), 3, { outcome = { team = RED } })
	Run (4)
	T.eq (hookArgs.winner,       RED, "RED")
	T.eq (teamScores [RED],      1,   "scored")
	T.eq (#fired,                1,   "announced once")
	T.eq (fired [1].fields.team, RED, "RED's win")
end)

T.test ("a new phase stops every clock of the last one", function ()
	InRound ()
	Timer.Start (Timer.TeamClock (RED), 1000, { outcome = { team = RED } })
	Rounds.RoundOutcome ({ team = RED })
	Run (2)
	T.eq (Rounds.State (),                       ROUND_OVER, "over")
	T.eq (Timer.Running (Timer.TeamClock (RED)), false,      "the team's clock")
end)

T.test ("a time adjustment moves the clock of the round being played only", function ()
	InRound ()
	local left = Timer.Remaining (Timer.ROUND)
	Rounds.AdjustTime ({ team = RED, delta = 10 })
	T.eq (Timer.Remaining (Timer.ROUND), left + 10, "in the round")
	Rounds.RoundOutcome ({ team = RED })
	Run (2)
	left = Timer.Remaining (Timer.ROUND)
	Rounds.AdjustTime ({ team = RED, delta = 10 })
	T.eq (Timer.Remaining (Timer.ROUND), left, "after it")
end)

T.test ("a score reaches the team, then the games being played, then the gamemode", function ()
	Fresh ()
	local info = { team = RED, score = 1, event = "control_point_capture" }
	Rounds.AddTeamScore (info)
	T.eq (table.concat (order, ","), "team,game:TeamScored,hook:TeamScored", "in order")
	T.eq (teamScores [RED],          1,                                      "added")
	T.eq (hookArgs.game,             info,                                   "the games told what for")
	T.eq (hookArgs.hook [1],         info,                                   "the gamemode told what for")
end)

T.test ("RoundOutcome fires the gamemode's RoundWin with the team and the outcome", function ()
	Fresh ()
	local outcome = { team = RED, reason = 7, forceMapReset = true, switchTeams = false }
	Rounds.RoundOutcome (outcome)
	T.eq (table.concat (order, ","), "hook:RoundWin", "the hook")
	T.eq (hookArgs.hook [1],         RED,             "the winner")
	T.eq (hookArgs.hook [2].reason,  7,               "the caller's reason")
end)

T.test ("an outcome with no team is a stalemate or a tie", function ()
	Fresh ()
	local outcome = { reason = 7, forceMapReset = true }
	Rounds.RoundOutcome (outcome)
	T.eq (hookArgs.hook [1], TF_TEAM_UNASSIGNED, "nobody won")
	T.eq (hookArgs.hook [2], outcome,            "the outcome as given")
end)

T.test ("only RoundOutcome closes a round from outside", function ()
	T.eq (Rounds.Win, nil, "the old name is gone")
end)

-- The match's phases, told as they come ------------------------------------------------

local BLUE = 3
local events, limits, ready, scores
do
	local Base = hook.Run
	hook.Run = function (name, a, b)
		if name == "MatchEvent" then
			events [#events + 1] = b and a .. ":" .. b or a
			return
		end
		if name == "MatchLimits" then return limits end
		return Base (name, a, b)
	end
	team.NumPlayers = function () return ready and 1 or 0 end
	team.GetScore = function (t) return scores [t] or 0 end
	local AddScore = team.AddScore
	team.AddScore = function (t, score)
		scores [t] = (scores [t] or 0) + score
		AddScore (t, score)
	end
end

-- A match from nothing, with these limits.
local function NewMatch (matchLimits)
	Fresh ()
	events, limits, ready, scores = {}, matchLimits, true, {}
	game_manager.Tiebreaker = function () end
	Rounds.Think (false)
end

local function Told ()
	local told = table.concat (events, " ")
	events = {}
	return told
end

T.test ("how a match is over: a team's wins, the rounds played, or the lead, whichever comes first", function ()
	local Over = Rounds.MatchOver
	T.eq (Over (1, 0, 1, {}),           false, "no limits: never")
	T.eq (Over (2, 1, 3, { wins = 3 }), false, "short of the wins")
	local over, winner = Over (3, 1, 4, { wins = 3 })
	T.eq (over,   true, "the wins reached")
	T.eq (winner, RED,  "by RED")
	over, winner = Over (1, 3, 4, { difference = 2 })
	T.eq (over,   true, "the lead reached")
	T.eq (winner, BLUE, "by BLU")
	over, winner = Over (2, 2, 4, { rounds = 4 })
	T.eq (over,                                                     true,  "the rounds played")
	T.eq (winner,                                                   nil,   "level: nobody's match")
	T.eq (Over (2, 2, 3, { rounds = 4, wins = 0, difference = 0 }), false, "0 is no limit")
end)

T.test ("a match waits for its teams, sets up, starts once, and tells each round", function ()
	NewMatch ({ wins = 2 })
	ready = false
	Run (2)
	T.eq (Told (), "PreStart", "waiting for players")
	ready = true
	Run (1)
	T.eq (Told (), "PreEnd SetupStart", "the teams are there: setting up")
	Run (6)
	T.eq (Told (), "SetupEnd GameStart RoundStart", "the game starts with its first round")
	Rounds.RoundOutcome ({ team = RED })
	Run (1)
	T.eq (Told (), "RoundEnd", "the round is over, the match is not")
	Run (20)
	T.eq (Told (), "SetupStart SetupEnd RoundStart", "the next round: the game does not start twice")
	Rounds.RoundOutcome ({ team = RED })
	Run (9)
	T.eq (Told (), "RoundEnd WinTeam:" .. RED .. " GameDone", "RED takes the match, and the game is done")
end)

T.test ("a round nobody wins goes to the tie breaker a map can play", function ()
	NewMatch ({ rounds = 1 })
	local bonus
	game_manager.Tiebreaker = function () return "game_sudden_death" end
	game_manager.SetBonus = function (name) bonus = name end
	Run (7)
	Told ()
	Run (Timer.Remaining (Timer.ROUND) + 1)
	T.eq (Told (), "RoundEnd TieBreakStart SetupStart", "the tie breaker begins")
	T.eq (bonus,   "game_sudden_death",                 "the map's")
	Run (6)
	T.eq (Told (), "SetupEnd RoundStart", "its round")
	Rounds.RoundOutcome ({ team = BLUE })
	Run (9)
	T.eq (Told (), "RoundEnd TieBreakEnd WinTeam:" .. BLUE .. " GameDone", "settled, and with it the match")
	T.eq (bonus,   nil,                                                    "the tie breaker over")
end)

T.test ("a match that runs out of rounds level is done with no winner", function ()
	NewMatch ({ rounds = 1 })
	Run (7)
	Told ()
	Run (Timer.Remaining (Timer.ROUND) + 8)
	T.eq (Told (), "RoundEnd GameDone", "done, nobody's")
end)

T.test ("with no limits told, the match goes by mp_winlimit", function ()
	NewMatch (nil)
	Run (7)
	Rounds.RoundOutcome ({ team = RED })
	Run (8)
	T.eq (Told (), "SetupStart SetupEnd GameStart RoundStart RoundEnd", "one win of three: the match goes on")
end)

T.finish ()
