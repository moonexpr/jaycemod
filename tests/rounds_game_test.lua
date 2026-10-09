-- The Round model (foundation.rounds) driven through whole rounds, as the
-- gamerules state machine (teamplayroundbased_gamerules.cpp, tf_gamerules.cpp)
-- plays them. Each scenario asserts the effect list in order.
local T = dofile("tests/harness.lua")
local FakeObjective = dofile("tests/fake_objective.lua")
local Rounds = T.require("foundation.rounds")
local State = T.require("foundation.rounds.state")
local Teams = T.require("foundation.teams")

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local W, SM = Rounds.WINREASON, Rounds.STALEMATE
local MINUTE = 60
local TIMELIMIT_MINUTES = 30
local T0 = 100

local STATE_NAME = {}
for name, value in pairs(State) do
	if type(value) == "number" then STATE_NAME[value] = name end
end

local function Settings(over)
	local s = {
		respawnWaveTime = 10,
		bonusRoundTime = 15,
		enableRoundWaitTime = 1,
		stalemateEnable = false,
		stalemateTimelimit = 240,
		winlimit = 0,
		maxrounds = 0,
		timelimit = 0,
		matchEndAtTimelimit = false,
		chattime = 10,
		mapResetTime = 0,
	}
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local function Team(players, alive)
	return {
		players = players,
		alive = alive,
	}
end

local function World(over)
	local w = {
		havePlayers = true,
		teams = {
			[RED] = Team(1, 1),
			[BLUE] = Team(1, 1),
		},
		scores = {
			[RED] = 0,
			[BLUE] = 0,
		},
		stalemateTimerLeft = nil,
		timerMayExpire = true,
		mapHasActiveTimer = true,
		objective = FakeObjective.Objective(),
	}
	for k, v in pairs(over or {}) do w[k] = v end
	return w
end

-- One effect as a short line, so a whole list compares as one string.
local DESCRIBE = {
	state = function(e) return "state " .. STATE_NAME[e.to] end,
	output = function(e) return "output " .. e.name .. (e.value and (" " .. e.value) or "") end,
	hook = function(e) return "hook " .. e.name .. (e.args[1] and (" " .. e.args[1]) or "") end,
	score = function(e) return "score " .. e.team .. " " .. e.points end,
	publish_win = function(e) return "publish_win " .. e.winner end,
	win_song = function(e) return "win_song " .. e.winner end,
	respawn_team = function(e) return "respawn_team " .. e.team end,
	time_limit_timer = function(e) return "time_limit_timer " .. e.seconds end,
	stalemate_timer = function(e) return "stalemate_timer " .. e.seconds end,
	sudden_death = function(e) return "sudden_death " .. e.reason end,
	stalemate_winner = function(e) return "stalemate_winner " .. e.team end,
	intermission = function(e) return "intermission " .. e.reason end,
	overtime = function(e) return "overtime " .. tostring(e.value) end,
}

local function Describe(effects)
	local lines = {}
	for i, e in ipairs(effects) do
		local describe = DESCRIBE[e.kind]
		lines[i] = describe and describe(e) or e.kind
	end
	return table.concat(lines, ", ")
end

local function Expect(effects, expected, what)
	T.eq(Describe(effects), table.concat(expected, ", "), what)
end

local PREROUND_FULL_FRESH = {
	"state PREROUND",
	"balance_teams",
	"activate_timers",
	"round_spawn",
	"round_activate",
	"new_round_outputs",
	"respawn_all",
	"output OnStateEnterPreRound",
	"doors_lock",
}

local WAVES = {
	"respawn_team " .. RED,
	"respawn_team " .. BLUE,
}

local TO_RUNNING = {
	"output OnStateExitPreRound",
	"doors_unlock",
	"state RND_RUNNING",
	"output OnStateEnterRoundRunning",
	"hook WetsandRoundActive",
}

-- A round from PREGAME to RND_RUNNING at T0 + 1 + PREROUND_SECONDS.
local function Running(settings, world)
	local round = Rounds.New(Settings(settings))
	round:Think(T0, world or World())
	round:Think(T0 + 1 + Rounds.PREROUND_SECONDS, world or World())
	T.eq(round:State(), State.RND_RUNNING, "running")
	return round
end

T.test("pregame waits for players, then a fresh map's first round sets up without a cleanup", function()
	local round = Rounds.New(Settings())
	T.eq(round:State(), State.PREGAME, "a new round waits in PREGAME")
	Expect(round:Think(T0, World({
		havePlayers = false,
		teams = {
			[RED] = Team(0, 0),
			[BLUE] = Team(0, 0),
		},
	})), {}, "nobody: no change")
	T.eq(round:State(), State.PREGAME, "still PREGAME")

	Expect(round:Think(T0 + 0.5, World()), PREROUND_FULL_FRESH, "players arrive")
	T.eq(round:State(), State.PREROUND, "pre-round")
	T.eq(round:PreroundEnd(), T0 + 0.5 + Rounds.PREROUND_SECONDS, "the pre-round lasts 3 s")

	Expect(round:Think(T0 + 1.5, World()), {
		"respawn_team " .. RED,
		"respawn_team " .. BLUE,
		"output Team1PlayersChanged 1",
		"output Team2PlayersChanged 1",
	}, "the pre-round respawns the dead at once; the team counts are reported once a second")

	local done = {}
	for _, line in ipairs(TO_RUNNING) do done[#done + 1] = line end
	Expect(round:Think(T0 + 0.5 + Rounds.PREROUND_SECONDS, World()), done, "the pre-round ends")
	T.eq(round:State(), State.RND_RUNNING, "running")
	T.eq(round:PointsMayBeCaptured(), true, "points may be captured")
end)

T.test("a full-round win scores, switches teams and resets the map after the bonus time", function()
	local round = Running()
	local objective = FakeObjective.Objective()
	local now = T0 + 20
	Expect(round:SetWinningTeam(now, RED, W.DEFEND_UNTIL_TIME_LIMIT, true, true, false, objective), {
		"score " .. RED .. " 1",
		"publish_win " .. RED,
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. RED,
		"win_song " .. RED,
		"output OnWonByTeam1",
	}, "the win")
	T.eq(round:PointsMayBeCaptured(), false, "no captures after a win")
	Expect(round:SetWinningTeam(now, BLUE, W.ALL_POINTS_CAPTURED, true, false, false, objective), {}, "a second win is ignored")

	Expect(round:Think(now + 14, World()), {}, "the bonus time runs")
	Expect(round:Think(now + 15, World()), {
		"previous_round_end",
		"state PREROUND",
		"balance_teams",
		"cleanup",
		"activate_timers",
		"round_spawn",
		"round_activate",
		"new_round_outputs",
		"switch_teams",
		"respawn_all",
		"output OnStateEnterPreRound",
		"doors_lock",
	}, "the next round")
end)

T.test("a mini-round win keeps the map and scores nothing", function()
	local round = Running()
	local now = T0 + 20
	Expect(round:SetWinningTeam(now, BLUE, W.ALL_POINTS_CAPTURED, false, false, false, FakeObjective.Objective()), {
		"publish_win " .. BLUE,
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. BLUE,
		"win_song " .. BLUE,
		"output OnWonByTeam2",
	}, "the win")
	Expect(round:Think(now + 15, World()), {
		"previous_round_end",
		"state PREROUND",
		"balance_teams",
		"round_spawn",
		"round_activate",
		"respawn_all",
		"output OnStateEnterPreRound",
		"doors_lock",
	}, "the next mini-round")
end)

T.test("a stalemate without mp_stalemate_enable is a drawn round", function()
	local round = Running()
	Expect(round:SetStalemate(T0 + 20, SM.TIMER, true, false), {
		"publish_win " .. NOBODY,
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. NOBODY,
		"win_song " .. NOBODY,
	}, "a draw")
end)

local SUDDEN_DEATH = {
	"sudden_death " .. SM.TIMER,
	"state STALEMATE",
	"respawn_all",
	"hide_timers",
	"stalemate_timer 240",
}

T.test("sudden death: one team dead hands the round to the survivors", function()
	local round = Running({ stalemateEnable = true })
	Expect(round:SetStalemate(T0 + 20, SM.TIMER, false, false), SUDDEN_DEATH, "sudden death")
	T.eq(round:PointsMayBeCaptured(), true, "points may still be captured")
	Expect(round:SetStalemate(T0 + 21, SM.TIMER, false, false), {}, "already in sudden death")
	Expect(round:Think(T0 + 22, World()), {}, "both teams alive")
	local effects = round:Think(T0 + 23, World({
		teams = {
			[RED] = Team(2, 0),
			[BLUE] = Team(2, 1),
		},
	}))
	-- sudden death over: the survivors rewarded and the dead back, to enjoy the
	-- victory or the humiliation
	Expect(effects, { "sudden_death_over", "stalemate_winner " .. BLUE }, "RED dead")
	T.eq(effects[2].forceMapReset, false, "the stalemate's map reset")
end)

T.test("sudden death: everyone dead, or its timer out when it may expire, is a stalemate win", function()
	local round = Running({ stalemateEnable = true })
	round:SetStalemate(T0 + 20, SM.TIMER, true, false)
	Expect(round:Think(T0 + 21, World({
		stalemateTimerLeft = 0,
		timerMayExpire = false,
	})), {}, "a capture holds the stalemate timer")
	Expect(round:Think(T0 + 22, World({ stalemateTimerLeft = 0 })), {
		"sudden_death_over",
		"publish_win " .. NOBODY,
		"restore_timers",
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. NOBODY,
		"win_song " .. NOBODY,
	}, "the timer runs out")

	local dead = Running({ stalemateEnable = true })
	dead:SetStalemate(T0 + 20, SM.TIMER, true, false)
	Expect(dead:Think(T0 + 21, World({
		teams = {
			[RED] = Team(1, 0),
			[BLUE] = Team(1, 0),
		},
	})), {
		"sudden_death_over",
		"publish_win " .. NOBODY,
		"restore_timers",
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. NOBODY,
		"win_song " .. NOBODY,
	}, "everyone dead")
end)

T.test("the win limit ends the game in an intermission, then the level changes", function()
	local round = Running({ winlimit = 2 })
	local now = T0 + 20
	round:SetWinningTeam(now, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	local effects = round:Think(now + 15, World({
		scores = {
			[RED] = 2,
			[BLUE] = 0,
		},
	}))
	Expect(effects, {
		"intermission Reached Win Limit",
		"state GAME_OVER",
	}, "game over")
	-- MATCH_WIN_EXTRA of fighting to the match's music, then mp_chattime frozen
	local won = now + 15
	local frozen = won + Rounds.MATCH_WIN_EXTRA
	local ends = frozen + 10
	T.eq(effects[1]["until"], ends, "the intermission lasts the extra and mp_chattime")
	T.eq(Rounds.MATCH_WIN_EXTRA, 60)
	T.eq(effects[1].winner, RED, "RED won the match")
	Expect(round:Think(frozen - 1, World()), {}, "the fight to the music")
	Expect(round:Think(frozen, World()), { "freeze" }, "everyone frozen for mp_chattime")
	Expect(round:Think(frozen + 1, World()), {}, "frozen once")
	Expect(round:Think(ends, World()), { "changelevel" }, "the level changes")
	Expect(round:Think(ends + 1, World()), {}, "once")
end)

-- RED leads, so the match has a winner (a tie goes to sudden death).
local RED_LEADS = { [RED] = 1, [BLUE] = 0 }

local function Has(effects, text)
	return Describe(effects):find(text, 1, true) ~= nil
end

T.test("mp_maxrounds counts full rounds: the round that reaches it ends the match", function()
	local round = Running({ maxrounds = 1 })
	local effects = round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	T.eq(Has(effects, "intermission Reached Round Limit"), true, Describe(effects))
	T.eq(round:State(), State.GAME_OVER)
end)

-- The win that ends the match takes the round win's place: the point is
-- scored, but no round win music or bonus round comes first.
T.test("a round win that reaches the win limit is the match win at once", function()
	local round = Running({ winlimit = 2 })
	round:Think(T0 + 1, World({ scores = { [RED] = 1, [BLUE] = 0 } }))
	local effects = round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	T.eq(Has(effects, "score"), true, "the point is scored: " .. Describe(effects))
	T.eq(Has(effects, "intermission Reached Win Limit"), true, "the match is won")
	T.eq(Has(effects, "win_song"), false, "no round win music")
	T.eq(Has(effects, "state TEAM_WIN"), false, "no bonus round")
	T.eq(effects[#effects].kind ~= nil, true)
	T.eq(round:State(), State.GAME_OVER)
end)

T.test("a round win that would tie the match is a round win, and sudden death follows", function()
	local round = Running({ maxrounds = 1 })
	round:Think(T0 + 1, World({ scores = { [RED] = 0, [BLUE] = 1 } }))
	local effects = round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	T.eq(Has(effects, "win_song"), true, Describe(effects))
	T.eq(round:State(), State.TEAM_WIN)
end)

-- A match that ends tied is not over: it goes to sudden death (even with
-- mp_stalemate_enable off). Ended at a round's end, the next round is
-- played as sudden death; ended mid-round, that round becomes one.
local TIED = { scores = { [RED] = 1, [BLUE] = 1 } }

T.test("a match that ends tied at a round's end plays the next round as sudden death", function()
	local round = Running({ maxrounds = 1, stalemateEnable = false })
	round:Think(T0 + 1, World({ scores = { [RED] = 0, [BLUE] = 1 } })) -- RED's point ties it
	round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	local seen = {}
	for t = 35, 80 do
		local text = Describe(round:Think(T0 + t, World(TIED)))
		if text ~= "" then seen[#seen + 1] = text end
	end
	local all = table.concat(seen, ", ")
	T.eq(all:find("intermission", 1, true), nil, "no game over: " .. all)
	T.eq(all:find("sudden_death " .. SM.MATCH_TIED, 1, true) ~= nil, true, "sudden death: " .. all)
	T.eq(round:State(), State.STALEMATE, "in sudden death")
end)

T.test("a match tied mid-round turns that round into sudden death", function()
	local round = Running({ winlimit = 2, stalemateEnable = false })
	local text = ""
	for t = 21, 25 do text = text .. Describe(round:Think(T0 + t, World({ scores = { [RED] = 2, [BLUE] = 2 } }))) end
	T.eq(text:find("sudden_death " .. SM.MATCH_TIED, 1, true) ~= nil, true, text)
	T.eq(text:find("intermission", 1, true), nil, "no game over")
	T.eq(round:State(), State.STALEMATE)
end)

T.test("the match winner is the team with the higher score; a tie, nobody", function()
	T.eq(Rounds.MatchWinner({ [RED] = 3, [BLUE] = 1 }), RED)
	T.eq(Rounds.MatchWinner({ [RED] = 0, [BLUE] = 2 }), BLUE)
	T.eq(Rounds.MatchWinner({ [RED] = 2, [BLUE] = 2 }), Rounds.NOBODY_WON)
	T.eq(Rounds.MatchWinner({}), Rounds.NOBODY_WON, "no scores")
end)

-- The level after the match: TF2's nextlevel when set, else GMod's map
-- cycle (game.GetMapNext), else the map again; never a map not installed.
T.test("the next level is nextlevel, else the map cycle's next, else this map again", function()
	local function Installed(list)
		local set = {}
		for _, m in ipairs(list) do set[m] = true end
		return function(map) return set[map] == true end
	end
	local exists = Installed({ "pl_upward", "cp_steel", "pl_swiftwater_final1" })
	T.eq(Rounds.NextMap("cp_steel", "pl_upward", "pl_swiftwater_final1", exists), "cp_steel", "nextlevel first")
	T.eq(Rounds.NextMap("", "pl_upward", "pl_swiftwater_final1", exists), "pl_upward", "then the cycle")
	T.eq(Rounds.NextMap("", "", "pl_swiftwater_final1", exists), "pl_swiftwater_final1", "then this map")
	T.eq(Rounds.NextMap("koth_gone", "cp_gone", "pl_swiftwater_final1", exists), "pl_swiftwater_final1", "never a map not installed")
end)

T.test("the time limit waits for mini-rounds that must all be played", function()
	local now = TIMELIMIT_MINUTES * MINUTE + 1
	local objective = FakeObjective.Objective({
		playingMiniRounds = true,
		playAllRounds = true,
		numPlayable = 1,
	})
	local round = Running({ timelimit = TIMELIMIT_MINUTES })
	round:SetWinningTeam(now, BLUE, W.ALL_POINTS_CAPTURED, false, false, false, objective)
	local effects = round:Think(now + 15, World({ objective = objective, scores = RED_LEADS }))
	T.eq(effects[1].kind, "previous_round_end", "a mini-round left: the game goes on")

	local last = Running({ timelimit = TIMELIMIT_MINUTES })
	objective.numPlayable = 0
	last:SetWinningTeam(now, BLUE, W.ALL_POINTS_CAPTURED, false, false, false, objective)
	Expect(last:Think(now + 15, World({ objective = objective, scores = RED_LEADS })), {
		"intermission Reached Time Limit",
		"state GAME_OVER",
	}, "none left")
end)

T.test("with SetStalemateOnTimelimit the time limit ends the round: the leader wins, a tie is sudden death", function()
	local settings = {
		timelimit = TIMELIMIT_MINUTES,
		stalemateEnable = true,
	}
	local round = Running(settings)
	local over = TIMELIMIT_MINUTES * MINUTE
	Expect(round:Think(over, World()), WAVES, "without the input the round goes on")
	round:SetStalemateOnTimelimit(true)
	local tied = round:Think(over + 1, World())
	T.eq(Describe(tied), table.concat({
		"sudden_death " .. SM.SERVER_TIMELIMIT,
		"state STALEMATE",
		"respawn_all",
		"hide_timers",
		"stalemate_timer 240",
	}, ", "), "a tie")

	local leader = Running(settings)
	leader:SetStalemateOnTimelimit(true)
	Expect(leader:Think(over, World({
		scores = {
			[RED] = 1,
			[BLUE] = 3,
		},
	})), {
		"respawn_team " .. RED,
		"respawn_team " .. BLUE,
		"publish_win " .. BLUE,
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. BLUE,
		"win_song " .. BLUE,
		"output OnWonByTeam2",
	}, "BLU leads; the time limit win adds no score")
end)

T.test("Halt waits between rounds until a new game", function()
	local round = Running()
	local now = T0 + 20
	Expect(round:Halt(now), {
		"state BETWEEN_RNDS",
		"output OnStateEnterBetweenRounds",
		"doors_unlock",
	}, "halted")
	T.eq(round:Halted(), true, "halted")
	Expect(round:Think(now + 5, World()), {}, "nothing thinks")
	Expect(round:Halt(now + 6), {}, "already between rounds")
	round:Unhalt()
	T.eq(round:Halted(), false, "unhalted")
	Expect(round:RestartRound(now + 7), { "state PREGAME" }, "a restart")
	local effects = round:Think(now + 8, World())
	T.eq(Describe({ effects[1], effects[2], effects[3] }), "state PREROUND, balance_teams, cleanup", "a full reset")
end)

-- A map loaded in Sandbox mode has run: halting ended its setup and fired
-- the timer's OnSetupFinished, which on a race map disables the timer
-- itself (plr_hightower_event's plr_timer). The first game must reset it.
T.test("the first game after a map loaded in Sandbox mode cleans the map up", function()
	local round = Rounds.New(Settings())
	round:Halt(T0)
	round:Unhalt()
	round:RestartRound(T0 + 1)
	local effects = round:Think(T0 + 2, World())
	T.eq(Describe({ effects[1], effects[2], effects[3] }), "state PREROUND, balance_teams, cleanup", "a full reset with a cleanup")
end)

T.test("a halted round (Sandbox mode) stays between rounds whatever happens", function()
	local objective = FakeObjective.Objective()
	local round = Rounds.New(Settings({ stalemateEnable = true }))
	local now = T0
	Expect(round:Halt(now), {
		"state BETWEEN_RNDS",
		"output OnStateEnterBetweenRounds",
		"doors_unlock",
	}, "halted from PREGAME")
	Expect(round:Think(now + 1, World()), {}, "players join: no pre-round")
	Expect(round:SetWinningTeam(now + 2, RED, W.ALL_POINTS_CAPTURED, true, false, false, objective), {},
		"capturing every point wins nothing")
	Expect(round:GameRoundWin(now + 3, {
		team = BLUE,
		reason = W.DEFEND_UNTIL_TIME_LIMIT,
		forceMapReset = true,
		switchTeams = false,
	}, objective), {}, "the timer's OnFinished to game_round_win wins nothing")
	Expect(round:SetStalemate(now + 4, SM.TIMER, true, false), {}, "no sudden death")
	Expect(round:RestartRound(now + 5), {}, "no restart until unhalted")
	Expect(round:Think(now + 60, World({
		scores = {
			[RED] = 9,
			[BLUE] = 9,
		},
	})), {}, "no game over")
	T.eq(round:State(), State.BETWEEN_RNDS, "between rounds throughout")
	T.eq(round:PointsMayBeCaptured(), false, "no captures")
	round:Unhalt()
	Expect(round:RestartRound(now + 61), { "state PREGAME" }, "Gameplay mode restarts the rounds")
end)

T.test("a halt during the intermission unfreezes everyone", function()
	local round = Running({ maxrounds = 1 })
	round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	round:Think(T0 + 35, World({ scores = RED_LEADS }))
	Expect(round:Halt(T0 + 36), {
		"unfreeze",
		"state BETWEEN_RNDS",
		"output OnStateEnterBetweenRounds",
		"doors_unlock",
	}, "out of the intermission")
	Expect(round:Think(T0 + 60, World()), {}, "no level change")
end)

T.test("a running round with no players goes back to PREGAME for a full reset", function()
	local round = Running()
	Expect(round:Think(T0 + 20, World({ havePlayers = false })), { "state PREGAME" }, "everyone left")
end)

T.test("a capture holds the timer 0.1 s past its end; other holds only while held", function()
	local round = Rounds.New(Settings())
	local free = {
		capturing = false,
		other = false,
	}
	local capturing = {
		capturing = true,
		other = false,
	}
	local held = {
		capturing = false,
		other = true,
	}
	T.eq(round:TimerMayExpire(T0, free), true, "nothing holds")
	T.eq(round:TimerMayExpire(T0, capturing), false, "a capture")
	T.eq(round:TimerMayExpire(T0 + 0.05, free), false, "the buffer")
	T.eq(round:TimerMayExpire(T0 + Rounds.CAP_IN_PROGRESS_BUFFER, free), false, "to its end")
	T.eq(round:TimerMayExpire(T0 + 0.11, free), true, "then free")
	T.eq(round:TimerMayExpire(T0 + 1, held), false, "a cp timer or a cart")
	T.eq(round:TimerMayExpire(T0 + 1, free), true, "free at once")
end)

T.test("respawn waves scale with the team, and admins and maps set them", function()
	local round = Running()
	local now = T0 + 20
	T.eq(round:TeamWaveTime(RED), 10, "mp_respawnwavetime")
	round:SetTeamWaveTime(RED, 6)
	T.eq(round:TeamWaveTime(RED), 6, "the map's")
	round:SetAdminWaveTime(RED, 2)
	T.eq(round:TeamWaveTime(RED), 2, "the admin's")
	round:SetAdminWaveTime(RED, nil)
	T.eq(round:TeamWaveTime(RED), 6, "back to the map's")
	round:AddTeamWaveTime(BLUE, -6)
	T.eq(round:TeamWaveTime(BLUE), 4, "added to mp_respawnwavetime")

	T.eq(round:WaveMaxLength(RED, 8, true), 6, "a full team waits the whole wave")
	T.eq(round:WaveMaxLength(RED, 1, true), 5, "one player: a quarter, but never under 5 s")
	round:SetTeamWaveTime(RED, 20)
	T.eq(round:WaveMaxLength(RED, 1, true), 5, "a quarter of 20")
	T.eq(round:WaveMaxLength(RED, 1, false), 20, "unscaled")

	T.eq(round:WaveDue(RED, now, 8), true, "the first wave is due at once")
	T.eq(round:WaveDue(RED, now + 1, 8), false, "the next is a wave later")
	T.eq(round:WaveDue(RED, now + 20, 8), true, "a wave later")
	-- died at now + 21: may spawn at now + 21 + 6.4 + 20, on a wave boundary
	T.eq(round:NextRespawn(RED, now + 21, 8), now + 60, "the wave after the death animation and a wave")
	T.eq(round:MayRespawn(RED, now + 21, now + 47), false, "too soon")
	T.eq(round:MayRespawn(RED, now + 21, now + 48), true, "after the animation and a wave")
	T.eq(round:RespawnAt(RED, now + 21, 8), now + 60, "the respawn time shown")
end)

-- A player who switches teams dies at once and comes back with the new
-- team's next wave, not a whole wave after: only the death animation must
-- pass first (switched).
T.test("a player who switched teams comes back with the new team's next wave", function()
	local round = Running()
	local now = T0 + 20
	round:SetTeamWaveTime(RED, 20)
	T.eq(round:WaveDue(RED, now, 8), true, "a wave now, the next at now + 20")
	T.eq(round:NextRespawn(RED, now + 1, 8, true), now + 20, "switched at now + 1: the next wave")
	T.eq(round:RespawnAt(RED, now + 1, 8, true), now + 20, "the respawn time shown")
	T.eq(round:MayRespawn(RED, now + 1, now + 20, true), true, "spawns with it")
	T.eq(round:MayRespawn(RED, now + 1, now + 7, true), false, "not before the death animation")
	T.eq(round:NextRespawn(RED, now + 1, 8, false), now + 40, "killed instead: a whole wave after")
	T.eq(round:NextRespawn(RED, now + 18, 8, true), now + 40, "switched as the wave comes: the one after the animation")
end)

T.test("setup respawns quickly, and sudden death or an admin stops respawns", function()
	local round = Running()
	local now = T0 + 20
	round:SetSetup(true)
	T.eq(round:MayRespawn(RED, now, now + Rounds.DEATH_ANIM_LENGTH), true, "setup: just the death animation")
	T.eq(round:NextRespawn(RED, now, 8), now + Rounds.DEATH_ANIM_LENGTH, "no wave in setup")
	T.eq(round:PointsMayBeCaptured(), false, "setup")
	round:SetSetup(false)
	T.eq(round:SetRespawnsDisabled(true), false, "disabling reschedules nobody")
	T.eq(round:RespawnAt(RED, now, 8), 0, "no respawn")
	T.eq(round:SetRespawnsDisabled(false), true, "the dead are rescheduled")
	Expect(round:Think(now + 1, World()), WAVES, "waves")
	round:SetRespawnsDisabled(true)
	Expect(round:Think(now + 40, World()), {}, "the waves come, but nobody respawns")
end)

T.test("the map's wave times go back to the first value set at each round", function()
	local round = Running()
	round:SetTeamWaveTime(BLUE, 8)
	round:AddTeamWaveTime(BLUE, -6)
	T.eq(round:TeamWaveTime(BLUE), 2, "added")
	round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	round:Think(T0 + 35, World())
	T.eq(round:TeamWaveTime(BLUE), 8, "the first value")
end)

T.test("a mode that makes no time limit timer suppresses it", function()
	local settings = {
		timelimit = TIMELIMIT_MINUTES,
		matchEndAtTimelimit = true,
	}
	local world = World({ mapHasActiveTimer = false })
	local round = Rounds.New(Settings(settings))
	local effects = round:Think(T0, world)
	T.eq(effects[4].kind, "time_limit_timer", "a timer for the limit")
	T.eq(effects[4].seconds, TIMELIMIT_MINUTES * MINUTE - T0, "the time left")

	local clockless = Rounds.Mode:Extend("clockless")
	clockless.PRIORITY = 1
	clockless.CREATES_TIME_LIMIT_TIMER = false
	local none = Rounds.New(Settings(settings))
	none:SetMode(clockless)
	local expected = {}
	for _, line in ipairs(PREROUND_FULL_FRESH) do expected[#expected + 1] = line end
	expected[#expected + 1] = "output Team1PlayersChanged 1"
	expected[#expected + 1] = "output Team2PlayersChanged 1"
	Expect(none:Think(T0, world), expected, "no time limit timer")
end)

T.test("setup and overtime report changes", function()
	local round = Rounds.New(Settings())
	T.eq(round:SetSetup(true), true, "into setup")
	T.eq(round:SetSetup(true), false, "no change")
	T.eq(round:InSetup(), true, "in setup")
	T.eq(round:SetOvertime(true), true, "into overtime")
	T.eq(round:InOvertime(), true, "overtime")
	T.eq(round:SetOvertime(true), false, "no change")
end)

T.test("a new round ends overtime", function()
	local round = Running()
	round:SetOvertime(true)
	round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	local effects = round:Think(T0 + 35, World())
	T.eq(Describe(effects), table.concat({
		"previous_round_end",
		"state PREROUND",
		"balance_teams",
		"cleanup",
		"activate_timers",
		"overtime false",
		"round_spawn",
		"round_activate",
		"new_round_outputs",
		"respawn_all",
		"output OnStateEnterPreRound",
		"doors_lock",
	}, ", "), "overtime off")
	T.eq(round:InOvertime(), false, "no overtime")
end)

T.test("game_round_win: a team wins, team 0 is a stalemate, and only a full reset switches", function()
	local objective = FakeObjective.Objective()
	local round = Running()
	local effects = round:GameRoundWin(T0 + 20, {
		team = RED,
		reason = W.DEFEND_UNTIL_TIME_LIMIT,
		forceMapReset = false,
		switchTeams = true,
	}, objective)
	T.eq(effects[1].kind, "publish_win", "a win")
	T.eq(effects[1].fullRound, false, "a mini-round")
	round:Think(T0 + 35, World())
	T.eq(round:State(), State.PREROUND, "next round")

	local draw = Running()
	Expect(draw:GameRoundWin(T0 + 20, {
		team = NOBODY,
		reason = W.DEFEND_UNTIL_TIME_LIMIT,
		forceMapReset = true,
		switchTeams = false,
	}, objective), {
		"publish_win " .. NOBODY,
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. NOBODY,
		"win_song " .. NOBODY,
	}, "team 0 is a stalemate")
end)

T.test("the played rounds are remembered, two deep, and forgotten at a full reset", function()
	local round = Running()
	round:AddPlayedRound("round_a")
	round:AddPlayedRound("round_b")
	round:AddPlayedRound("round_c")
	round:SetFirstRoundPlayed("round_a")
	local history = round:History()
	T.eq(history.previous[1], "round_c", "latest")
	T.eq(history.previous[2], "round_b", "before")
	T.eq(history.previous[3], nil, "two deep")
	T.eq(history.first, "round_a", "first")
	round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	round:Think(T0 + 35, World())
	T.eq(round:History().previous[1], nil, "a full reset forgets")
	T.eq(round:History().first, "round_a", "but not the first")
end)

T.test("the round reports the team counts once a second", function()
	local round = Running()
	Expect(round:Think(T0 + 10, World({
		teams = {
			[RED] = Team(3, 3),
			[BLUE] = Team(1, 1),
		},
	})), {
		"respawn_team " .. RED,
		"respawn_team " .. BLUE,
		"output Team1PlayersChanged 3",
	}, "RED changed")
end)

T.test("halted players respawn after a pause", function()
	T.eq(Rounds.HaltedRespawnDue(T0, T0 + Rounds.HALT_RESPAWN - 0.1), false, "too soon")
	T.eq(Rounds.HaltedRespawnDue(T0, T0 + Rounds.HALT_RESPAWN), true, "due")
end)

-- An attack/defend round, as on cp_gorge: the Round and the map's timer
-- (60 s setup, 270 s, max 600) driven together, as the rounds controller
-- drives them. A capture in progress holds the timer at zero; when it
-- breaks, OnFinished goes to a game_round_win for RED.
T.test("an A/D round: setup, time added by a capture, overtime while capping, then the defenders win", function()
	local Timer = T.require("foundation.rounds.timer")
	local ControlPoints = T.require("foundation.rounds.control_points")
	local objective = FakeObjective.Objective()
	local round = Rounds.New(Settings())
	round:SetMode(ControlPoints.Mode)
	local timer = Timer.New({
		length = 270,
		maxLength = 600,
		setupLength = 60,
		startPaused = false,
		showInHud = true,
		autoCountdown = true,
		resetTime = false,
		startDisabled = false,
		now = 0,
	})
	local outputs = {}
	local capturing = false
	local function Holds()
		return {
			capturing = capturing,
			other = false,
		}
	end
	local function Carry(events)
		for _, e in ipairs(events) do
			if e.kind == "setup" then round:SetSetup(e.value) end
			if e.kind == "overtime" then round:SetOvertime(e.value) end
			if e.kind == "output" then outputs[#outputs + 1] = e.name end
		end
	end
	local function Tick(now)
		Carry(timer:Think(now, {
			mayExpire = round:TimerMayExpire(now, Holds()),
			roundWon = round:State() == State.TEAM_WIN,
			overtime = round:InOvertime(),
			nagEnabled = false,
			random = function() return 0 end,
		}))
	end

	for _, e in ipairs(round:Think(T0, World())) do
		if e.kind == "round_spawn" then Carry(timer:RoundSpawn(T0)) end
	end
	round:Think(T0 + Rounds.PREROUND_SECONDS, World())
	T.eq(round:State(), State.RND_RUNNING, "running")
	T.eq(round:InSetup(), true, "setup")
	T.eq(round:PointsMayBeCaptured(), false, "no captures in setup")

	Tick(T0 + 60)
	T.eq(round:InSetup(), false, "setup over")
	T.eq(round:PointsMayBeCaptured(), true, "points open")
	T.eq(outputs[#outputs - 1], "OnSetupFinished", "the gates open")

	local events, added = timer:AddSeconds(T0 + 100, 480, BLUE, {
		roundRunningOrWon = round:State() == State.RND_RUNNING,
		isHud = true,
		roundWon = false,
		inStalemate = false,
		announces = round:Mode().ANNOUNCES_TIME_ADDED,
	})
	T.eq(added, 600 - 230, "a capture adds up to max_length")
	T.eq(events[2].kind, "time_added", "announced")

	-- 600 s left from T0 + 100; the marks do not fire at zero, the end comes first
	local zero = T0 + 100 + 600
	capturing = true
	Tick(zero)
	T.eq(round:InOvertime(), true, "overtime while BLU caps")
	Tick(zero + 5)
	T.eq(outputs[#outputs] ~= "OnFinished", true, "held")
	capturing = false
	Tick(zero + 5.05)
	T.eq(outputs[#outputs] ~= "OnFinished", true, "the 0.1 s buffer")
	Tick(zero + 5.2)
	T.eq(outputs[#outputs], "OnFinished", "the timer runs out")
	Expect(round:GameRoundWin(zero + 5.2, {
		team = RED,
		reason = W.DEFEND_UNTIL_TIME_LIMIT,
		forceMapReset = true,
		switchTeams = true,
	}, objective), {
		"score " .. RED .. " 1",
		"publish_win " .. RED,
		"state TEAM_WIN",
		"hook WetsandRoundWin " .. RED,
		"win_song " .. RED,
		"output OnWonByTeam1",
	}, "RED defended")
	Tick(zero + 6)
	T.eq(timer:Paused(), true, "the won round stops the clock")
end)

T.test("Configure takes new convar values", function()
	local round = Running()
	round:Configure({ bonusRoundTime = 5 })
	round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	T.eq(round:Think(T0 + 25, World())[1].kind, "previous_round_end", "a 5 s bonus")
end)

-- mp_forcewin: a team wins the round, or the round goes to sudden death.
T.test("mp_forcewin takes red, blue or sudden death, by name or number", function()
	T.eq(Rounds.ForceWinTarget("red"), RED)
	T.eq(Rounds.ForceWinTarget("2"), RED)
	T.eq(Rounds.ForceWinTarget("BLUE"), BLUE)
	T.eq(Rounds.ForceWinTarget("blu"), BLUE)
	T.eq(Rounds.ForceWinTarget("3"), BLUE)
	T.eq(Rounds.ForceWinTarget("sudden"), Rounds.FORCE_SUDDEN_DEATH)
	T.eq(Rounds.ForceWinTarget("0"), Rounds.FORCE_SUDDEN_DEATH)
	T.eq(Rounds.ForceWinTarget("green"), nil, "anything else is refused")
	T.eq(Rounds.ForceWinTarget(""), nil)
end)

T.test("a forced sudden death starts whatever mp_stalemate_enable says, called by the Administrator", function()
	local round = Running({ stalemateEnable = false })
	local effects = round:SuddenDeath(T0 + 20, SM.ADMIN)
	Expect({ effects[1] }, { "sudden_death " .. SM.ADMIN })
	T.eq(round:State(), State.STALEMATE)
end)

T.test("sudden death's survivors are rewarded with TF2's full overheal", function()
	T.eq(Rounds.SurvivorHealth(100, 40), 150, "half again its most")
	T.eq(Rounds.SurvivorHealth(125, 200), 200, "never less than it has")
	T.eq(Rounds.SurvivorHealth(175, 10), 262, "rounded down")
end)

T.test("mp_forcewin's win scores a point where points come from captures, and can win the match", function()
	local round = Running({ winlimit = 1 })
	local effects = round:SetWinningTeam(T0 + 20, BLUE, W.NONE, true, false, false,
		FakeObjective.Objective({ scorePerRound = false }))
	Expect({ effects[1] }, { "score " .. BLUE .. " 1" }, "the point")
	T.eq(Has(effects, "intermission Reached Win Limit"), true, "the match won: " .. Describe(effects))
end)

T.test("the survivors of sudden death win a point, even where points come from captures", function()
	local round = Running({ stalemateEnable = false })
	round:SuddenDeath(T0 + 20, SM.ADMIN)
	local effects = round:Think(T0 + 21, World({ teams = { [RED] = Team(2, 1), [BLUE] = Team(2, 0) } }))
	Expect({ effects[2] }, { "stalemate_winner " .. RED }, "BLU dead")
	local win = round:SetWinningTeam(T0 + 21, RED, W.OPPONENTS_DEAD, effects[2].forceMapReset, false, false,
		FakeObjective.Objective({ scorePerRound = false }))
	Expect({ win[1] }, { "score " .. RED .. " 1" })
end)

T.finish()
