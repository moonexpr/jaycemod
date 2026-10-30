-- The Round model (games.gameplay.rounds) driven through whole rounds, as the
-- gamerules state machine (teamplayroundbased_gamerules.cpp, tf_gamerules.cpp)
-- plays them. Each scenario asserts the effect list in order.
local T = dofile("tests/harness.lua")
local FakeObjective = dofile("tests/fake_objective.lua")
local Rounds = gameplay.rounds
local CPMode = T.require("features.rounds.control_points").Mode
local State = T.require("games.gameplay.rounds.state")
local Teams = gameplay.teams
local Spawns = system.spawn_manager

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
	deathmatch = function(e) return "deathmatch" end,
	stalemate_winner = function(e) return "stalemate_winner " .. e.team end,
	restart_seconds = function(e) return "restart_seconds " .. e.seconds .. (e.announce and (" " .. e.announce) or "") end,
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
	"hook WSRoundActive",
}

-- A round from PREGAME to RND_RUNNING at T0 + 1 + PREROUND_SECONDS.
-- mode: the round's (default the base mode: a map without an objective).
local function Running(settings, world, mode)
	local round = Rounds.New(Settings(settings))
	if mode then round:SetMode(mode) end
	round:Think(T0, world or World())
	round:Think(T0 + 1 + Rounds.PREROUND_SECONDS, world or World())
	T.eq(round:State(), State.RND_RUNNING, "running")
	return round
end

T.test("pregame waits for players, then a fresh map's first round sets up without a cleanup", function()
	-- a pre-round of 3 s (mp_enableroundwaittime 3), long enough to watch it
	local wait = Rounds.PREROUND_SECONDS * 3
	local round = Rounds.New(Settings({ enableRoundWaitTime = 3 }))
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
	T.eq(round:PreroundEnd(), T0 + 0.5 + wait, "the pre-round lasts PREROUND_SECONDS times mp_enableroundwaittime")

	Expect(round:Think(T0 + 1.5, World()), {
		"respawn_team " .. RED,
		"respawn_team " .. BLUE,
		"output Team1PlayersChanged 1",
		"output Team2PlayersChanged 1",
	}, "the pre-round respawns the dead at once; the team counts are reported once a second")

	local done = {}
	for _, line in ipairs(TO_RUNNING) do done[#done + 1] = line end
	Expect(round:Think(T0 + 0.5 + wait, World()), done, "the pre-round ends")
	T.eq(round:State(), State.RND_RUNNING, "running")
	T.eq(round:PointsMayBeCaptured(), true, "points may be captured")
end)

T.test("a full-round win scores, switches teams and resets the map after the bonus time", function()
	local round = Running()
	local objective = FakeObjective.Objective()
	local now = T0 + 20
	local win = round:SetWinningTeam(now, RED, W.DEFEND_UNTIL_TIME_LIMIT, true, true, false, objective)
	T.eq(win[4].args[2], W.DEFEND_UNTIL_TIME_LIMIT, "the hook says why (the AI war swaps sides on a defense)")
	Expect(win, {
		"score " .. RED .. " 1",
		"publish_win " .. RED,
		"state TEAM_WIN",
		"hook WSRoundWin " .. RED,
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

-- Bug: on pl_goldrush stage 2 began among stage 1's corpses and blood.
T.test("a mini-round win keeps the map, clears the last stage's gore and scores nothing", function()
	local round = Running()
	local now = T0 + 20
	Expect(round:SetWinningTeam(now, BLUE, W.ALL_POINTS_CAPTURED, false, false, false, FakeObjective.Objective()), {
		"publish_win " .. BLUE,
		"state TEAM_WIN",
		"hook WSRoundWin " .. BLUE,
		"win_song " .. BLUE,
		"output OnWonByTeam2",
	}, "the win")
	Expect(round:Think(now + 15, World()), {
		"previous_round_end",
		"state PREROUND",
		"balance_teams",
		"clear_gore",
		"round_spawn",
		"round_activate",
		"respawn_all",
		"output OnStateEnterPreRound",
		"doors_lock",
	}, "the next mini-round")
end)

-- A stalemate is the game's default end: with no sudden death to break it
-- (mp_stalemate_enable off) the match ends drawn. Nobody is humiliated:
-- everyone plays on in bonus time, unfrozen, until the level changes.
T.test("a stalemate without sudden death ends the match drawn, in bonus time until the level changes", function()
	local round = Running({ chattime = 10 })
	local now = T0 + 20
	local effects = round:SetStalemate(now, SM.TIMER, true, false)
	Expect(effects, {
		"intermission " .. Rounds.STALEMATE_GAME_OVER,
		"state GAME_OVER",
	}, "game over")
	T.eq(effects[1].winner, Rounds.NOBODY_WON, "nobody won the match")
	local note = now + Rounds.MATCH_WIN_EXTRA
	local ends = note + 10
	T.eq(effects[1]["until"], ends, "bonus time lasts the extra and mp_chattime")
	Expect(round:Think(note, World()), { "next_map" }, "the next map announced, nobody frozen")
	Expect(round:Think(ends, World()), { "changelevel" }, "the level changes")
end)

local SUDDEN_DEATH = {
	"sudden_death " .. SM.TIMER,
	"state STALEMATE",
	"respawn_all",
	"bonus_freeze",
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

-- Sudden death's own bonus round ends in a win, or at its timeout in a tie
-- both teams score; both teams dead at once is no tie-breaker, so another
-- sudden death follows.
T.test("sudden death's timer out is a tie: both teams take the point, and the next round follows", function()
	local round = Running({ stalemateEnable = true })
	round:SetStalemate(T0 + 20, SM.TIMER, true, false)
	Expect(round:Think(T0 + 21, World({
		stalemateTimerLeft = 0,
		timerMayExpire = false,
	})), {}, "a capture holds the stalemate timer")
	Expect(round:Think(T0 + 22, World({ stalemateTimerLeft = 0 })), {
		"sudden_death_over",
		"score " .. RED .. " 1",
		"score " .. BLUE .. " 1",
		"publish_win " .. NOBODY,
		"restore_timers",
		"state TEAM_WIN",
		"hook WSRoundWin " .. NOBODY,
		"win_song " .. NOBODY,
	}, "the timer runs out")
	round:Think(T0 + 40, World())
	T.eq(round:State(), State.PREROUND, "the next round")
end)

T.test("sudden death with everyone dead at once is no tie-breaker: another sudden death follows", function()
	local round = Running({ stalemateEnable = true })
	round:SetStalemate(T0 + 20, SM.TIMER, true, false)
	Expect(round:Think(T0 + 21, World({
		teams = {
			[RED] = Team(1, 0),
			[BLUE] = Team(1, 0),
		},
	})), {
		"sudden_death " .. SM.BOTH_DEAD,
		"restore_timers",
		"state STALEMATE",
		"respawn_all",
		"bonus_freeze",
		"hide_timers",
		"stalemate_timer 240",
	}, "everyone dead")
	T.eq(round:InSuddenDeath(), true, "sudden death again")
end)

T.test("a forced sudden death keeps breaking ties whatever mp_stalemate_enable says", function()
	local round = Running({ stalemateEnable = false })
	round:SuddenDeath(T0 + 20, SM.ADMIN)
	local effects = round:Think(T0 + 21, World({ teams = { [RED] = Team(1, 0), [BLUE] = Team(1, 0) } }))
	T.eq(Describe(effects):find("sudden_death " .. SM.BOTH_DEAD, 1, true) ~= nil, true, "another: " .. Describe(effects))
	T.eq(round:State(), State.STALEMATE, "still sudden death")
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
	T.defined(Rounds.MATCH_WIN_EXTRA, "Rounds.MATCH_WIN_EXTRA")
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
	T.eq(round:RespawnStatus(RED, T0 + 25, 8), Spawns.SUDDEN_DEATH, "said: no respawning in sudden death")
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

-- The maplist (mp_maplist_enabled): the installed maps the gamemode's map
-- filter (sandcastle.txt's "maps", patterns joined by |) matches, in name
-- order; the rotation goes to the one after this map, round to the first.
T.test("the maplist is the installed maps the gamemode's filter matches, in order", function()
	local installed = { "pl_upward", "gm_construct", "koth_viaduct", "cp_steel", "background01", "plr_hightower" }
	local maps = Rounds.MapsMatching(installed, "^pl_|^plr_|^cp_|^koth_")
	T.eq(table.concat(maps, " "), "cp_steel koth_viaduct pl_upward plr_hightower", "matched, sorted")
	T.eq(#Rounds.MapsMatching(installed, ""), 0, "no filter, no maps")
end)

T.test("the maplist's next map follows this one, round to the first", function()
	local maps = { "cp_steel", "koth_viaduct", "pl_upward" }
	T.eq(Rounds.MaplistNext(maps, "cp_steel"), "koth_viaduct", "the one after")
	T.eq(Rounds.MaplistNext(maps, "pl_upward"), "cp_steel", "round to the first")
	-- a map off the list (gm_construct) goes on to the list's next in name order
	T.eq(Rounds.MaplistNext(maps, "gm_construct"), "koth_viaduct", "where it would sit")
	T.eq(Rounds.MaplistNext(maps, "zz_last"), "cp_steel", "past the end, the first")
	T.eq(Rounds.MaplistNext({}, "cp_steel"), "", "an empty list: none")
	T.eq(Rounds.MaplistNext({ "cp_steel" }, "cp_steel"), "cp_steel", "a list of one: itself")
end)

-- The next-map vote (mp_vote_nextmap_enabled), called once the match is one
-- round from its end or over, whichever comes first: a team one win from
-- mp_winlimit, one round left of mp_maxrounds, mp_timelimit's last
-- MAP_VOTE_TIME_LEFT seconds (TF2's), or the game over.
T.defined(Rounds.MAP_VOTE_TIME_LEFT, "MAP_VOTE_TIME_LEFT")

local function Facts(overrides)
	local facts = {
		winlimit = 0,
		maxrounds = 0,
		timelimit = 0,
		roundsPlayed = 0,
		timeLeft = 0,
		scores = { 0, 0 },
		over = false,
	}
	for k, v in pairs(overrides or {}) do facts[k] = v end
	return facts
end

T.test("the next-map vote is due one round from the match's end, or at it", function()
	T.eq(Rounds.MapVoteDue(Facts()), false, "no limit, still playing")
	T.eq(Rounds.MapVoteDue(Facts({ winlimit = 3, scores = { 1, 1 } })), false, "two wins short")
	T.eq(Rounds.MapVoteDue(Facts({ winlimit = 3, scores = { 1, 2 } })), true, "a team one win short")
	T.eq(Rounds.MapVoteDue(Facts({ maxrounds = 5, roundsPlayed = 3 })), false, "two rounds left")
	T.eq(Rounds.MapVoteDue(Facts({ maxrounds = 5, roundsPlayed = 4 })), true, "the last round")
	T.eq(Rounds.MapVoteDue(Facts({ timelimit = 30, timeLeft = Rounds.MAP_VOTE_TIME_LEFT + 1 })), false, "time to go")
	T.eq(Rounds.MapVoteDue(Facts({ timelimit = 30, timeLeft = Rounds.MAP_VOTE_TIME_LEFT })), true, "the last minutes")
	T.eq(Rounds.MapVoteDue(Facts({ timeLeft = 0 })), false, "no time limit: time left means nothing")
	T.eq(Rounds.MapVoteDue(Facts({ over = true })), true, "the match is over")
end)

-- Its choices, from the maplist: MAP_VOTE_SAME of the current map's mode
-- (the filter's pattern it matches) and MAP_VOTE_OTHER of another's, never
-- the current map, each once; a short pool fills from what is left.
T.defined(Rounds.MAP_VOTE_SAME, "MAP_VOTE_SAME")
T.defined(Rounds.MAP_VOTE_OTHER, "MAP_VOTE_OTHER")

local FILTER = "^pl_|^cp_|^koth_"
local function First(n) return 1 end

local function ModeCount(choices, prefix)
	local n = 0
	for _, map in ipairs(choices) do if map:sub(1, #prefix) == prefix then n = n + 1 end end
	return n
end

T.test("the vote offers maps of this mode and of another", function()
	local maps = { "cp_steel", "koth_viaduct", "pl_badwater", "pl_goldrush", "pl_upward" }
	local choices = Rounds.MapVoteChoices(maps, "pl_upward", FILTER, First)
	T.eq(#choices, Rounds.MAP_VOTE_SAME + Rounds.MAP_VOTE_OTHER, "how many")
	T.eq(ModeCount(choices, "pl_"), Rounds.MAP_VOTE_SAME, "this mode's")
	T.eq(#choices - ModeCount(choices, "pl_"), Rounds.MAP_VOTE_OTHER, "another's")
	for _, map in ipairs(choices) do T.eq(map ~= "pl_upward", true, "not this map") end
end)

T.test("a mode with too few maps leaves the rest to the others", function()
	local choices = Rounds.MapVoteChoices({ "cp_steel", "cp_gorge", "pl_upward", "pl_badwater" }, "pl_upward", FILTER, First)
	T.eq(#choices, Rounds.MAP_VOTE_SAME + Rounds.MAP_VOTE_OTHER, "still a full vote")
	T.eq(ModeCount(choices, "pl_"), 1, "the one other payload map")
	local seen = {}
	for _, map in ipairs(choices) do
		T.eq(seen[map], nil, map .. " once")
		seen[map] = true
	end
end)

T.test("a map off the filter, or a pool of one, still gives what there is", function()
	T.eq(#Rounds.MapVoteChoices({ "cp_steel", "pl_upward" }, "gm_construct", FILTER, First), 2, "both, from other modes")
	T.eq(#Rounds.MapVoteChoices({ "pl_upward" }, "pl_upward", FILTER, First), 0, "nothing but this map")
end)

-- An empty server's next map: one without a nav mesh, so the idle server
-- builds it one (ws/sv_nav.lua).
T.test("an empty server's next map is one without a nav mesh, at random, never this one", function()
	local maps = { "cp_steel", "koth_viaduct", "pl_badwater", "pl_goldrush", "pl_upward" }
	local navs = { cp_steel = true, pl_badwater = true }
	local function HasNav(map) return navs[map] == true end
	local drawn
	local map = Rounds.IdleNextMap(maps, "pl_goldrush", HasNav, function(n) drawn = n return 2 end)
	T.eq(drawn, 2, "drawn from the maps without one, not this map")
	T.eq(map, "pl_upward", "the one drawn")
	T.eq(Rounds.IdleNextMap(maps, "pl_upward", function() return true end, First), nil, "every map has one: none")
	T.eq(Rounds.IdleNextMap({ "pl_upward" }, "pl_upward", function() return false end, First), nil, "only this map: none")
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
	local round = Running(settings, nil, CPMode)
	local over = TIMELIMIT_MINUTES * MINUTE
	Expect(round:Think(over, World()), WAVES, "without the input the round goes on")
	round:SetStalemateOnTimelimit(true)
	local tied = round:Think(over + 1, World())
	T.eq(Describe(tied), table.concat({
		"sudden_death " .. SM.SERVER_TIMELIMIT,
		"state STALEMATE",
		"respawn_all",
		"bonus_freeze",
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
		"hook WSRoundWin " .. BLUE,
		"win_song " .. BLUE,
		"output OnWonByTeam2",
	}, "BLU leads; the time limit win adds no score")
end)

-- The mode decides who wins at the time limit (CTF by captures,
-- features/flag/model.lua); the base mode by the teams' scores.
-- mp_match_end_at_timelimit: the time limit ends the round on any map; a
-- tie with sudden death off is the stalemate's bonus time for all.
T.test("at the time limit a tie with no sudden death is the stalemate's bonus time", function()
	local round = Running({ timelimit = TIMELIMIT_MINUTES, matchEndAtTimelimit = true, stalemateEnable = false })
	local effects = round:Think(TIMELIMIT_MINUTES * MINUTE, World())
	local over
	for _, e in ipairs(effects) do
		if e.kind == "intermission" then over = e end
	end
	T.eq(over ~= nil, true, "the match is over")
	T.eq(over.reason, Rounds.TIMELIMIT_GAME_OVER, "the game ran out of time")
	T.eq(Rounds.TIMELIMIT_GAME_OVER, "Game ran out of time.", "the operator's words")
	T.eq(round:State(), State.GAME_OVER, "bonus time, then the next map")
end)

-- Deathmatch (mp_deathmatch_enable) breaks a tied match: a round of frags
-- alone (mp_round_fraglimit), with respawns and no objective, whose winner
-- wins the match. Sudden death stays for a stalemated round.
local function Effect(effects, kind)
	for _, e in ipairs(effects) do
		if e.kind == kind then return e end
	end
	return nil
end

T.test("a tie at the time limit is a deathmatch round whose winner wins the match", function()
	local round = Running({ timelimit = TIMELIMIT_MINUTES, matchEndAtTimelimit = true, deathmatchEnable = true })
	local over = TIMELIMIT_MINUTES * MINUTE
	local effects = round:Think(over, World())
	T.eq(Effect(effects, "deathmatch") ~= nil, true, "deathmatch")
	T.eq(Effect(effects, "intermission"), nil, "the match goes on")
	T.eq(round:InDeathmatch(), true, "in it")
	T.eq(round:Mode().NAME, Rounds.DEATHMATCH, "frags alone decide it")
	T.eq(round:Mode().OBJECTIVE, false, "no objective")
	T.eq(round:Mode().HUD, Rounds.HUD_DEATHMATCH, "its own HUD: no objective panel")
	round:Think(over + 1, World())
	round:Think(over + Rounds.BONUS_FREEZE_SECONDS, World())
	T.eq(round:State(), State.RND_RUNNING, "fought, with respawns")
	T.eq(round:PointsMayBeCaptured(over + 2), false, "no point is captured in it")
	T.eq(Effect(round:Think(over + 5, World()), "deathmatch"), nil, "the spent time limit starts no second one")
	local won = round:LimitReached(over + 10, { team = BLUE, reason = W.FRAGLIMIT }, FakeObjective.Objective())
	local intermission = Effect(won, "intermission")
	T.eq(intermission ~= nil and intermission.winner, BLUE, "BLU wins the match")
	T.eq(intermission.reason, Rounds.DEATHMATCH_MATCH_WIN, "by the deathmatch")
end)

-- The deathmatch is a bonus round timed as sudden death is: the map's
-- timers hide and a stalemate timer of mp_stalemate_timelimit shows; run
-- out with no team at the frag limit, the match ends a stalemate.
T.test("a deathmatch runs on its stalemate timer; run out, the match is a stalemate", function()
	local round = Running({ timelimit = TIMELIMIT_MINUTES, matchEndAtTimelimit = true, deathmatchEnable = true })
	local over = TIMELIMIT_MINUTES * MINUTE
	round:Think(over, World())
	local fought = round:Think(over + Rounds.BONUS_FREEZE_SECONDS, World())
	T.eq(round:State(), State.RND_RUNNING, "fought")
	T.eq(Effect(fought, "hide_timers") ~= nil, true, "the map's timers hide: " .. Describe(fought))
	local timer = Effect(fought, "stalemate_timer")
	T.eq(timer ~= nil and timer.seconds, 240, "its own timer, mp_stalemate_timelimit long")
	local left = over + Rounds.BONUS_FREEZE_SECONDS + 1
	T.eq(Effect(round:Think(left, World({ stalemateTimerLeft = 10 })), "intermission"), nil, "time left: fought on")
	local paused = round:Think(left + 1, World({ stalemateTimerLeft = 0, timerMayExpire = false }))
	T.eq(Effect(paused, "intermission"), nil, "a timer that may not expire keeps it going")
	local done = round:Think(left + 2, World({ stalemateTimerLeft = 0 }))
	local intermission = Effect(done, "intermission")
	T.eq(intermission ~= nil and intermission.winner, Rounds.NOBODY_WON, "nobody won: " .. Describe(done))
	T.eq(intermission.reason, Rounds.STALEMATE_GAME_OVER, "a stalemate")
	T.eq(round:State(), State.GAME_OVER, "the match is over")
end)

T.test("a round that is no deathmatch keeps the map's timers and has no stalemate timer", function()
	local round = Rounds.New(Settings())
	round:Think(T0, World())
	local fought = round:Think(T0 + 1 + Rounds.PREROUND_SECONDS, World())
	T.eq(Effect(fought, "stalemate_timer"), nil, "no stalemate timer")
	T.eq(Effect(fought, "hide_timers"), nil, "the map's timers stay")
	T.eq(Effect(round:Think(T0 + 10, World({ stalemateTimerLeft = 0 })), "intermission"), nil, "nothing ends it")
end)

T.test("a tied match at the win limit is a deathmatch round too; without deathmatch, sudden death", function()
	local tied = { scores = { [RED] = 2, [BLUE] = 2 } }
	local round = Running({ maxrounds = 4, deathmatchEnable = true })
	round.roundsPlayed = 4
	local effects = round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, true, FakeObjective.Objective())
	-- the tie is taken up as the next round runs, as sudden death's is
	local function Through(r)
		local all = {}
		for _, t in ipairs({ T0 + 40, T0 + 40 + Rounds.PREROUND_SECONDS, T0 + 42 }) do
			for _, e in ipairs(r:Think(t, World(tied))) do all[#all + 1] = e end
		end
		return all
	end
	effects = Through(round)
	T.eq(Effect(effects, "deathmatch") ~= nil, true, "deathmatch: " .. Describe(effects))
	T.eq(round:InDeathmatch(), true, "in it")
	local old = Running({ maxrounds = 4, deathmatchEnable = false })
	old.roundsPlayed = 4
	old:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, true, FakeObjective.Objective())
	local oldEffects = Through(old)
	T.eq(Effect(oldEffects, "deathmatch"), nil, "no deathmatch without it")
	T.eq(Effect(oldEffects, "sudden_death") ~= nil, true, "sudden death instead")
end)

T.test("a tied match at a round limit goes to its deathmatch on a map with time left", function()
	local round = Running({ maxrounds = 1, deathmatchEnable = true, timelimit = TIMELIMIT_MINUTES })
	round:SetWinningTeam(T0 + 20, NOBODY, W.STALEMATE, true, false, false, FakeObjective.Objective())
	local back = T0 + 20 + Settings().bonusRoundTime + 1
	round:Think(back, World())
	round:Think(back + Rounds.PREROUND_SECONDS, World())
	round:Think(back + Rounds.PREROUND_SECONDS + 0.1, World())
	T.eq(round:InDeathmatch(), true)
end)

-- The bonus rounds, deathmatch and sudden death, open with a freeze of
-- BONUS_FREEZE_SECONDS in place of setup, so everyone reads the rules:
-- deathmatch's pre-round lasts it and its map's setup ends at once.
T.test("deathmatch has no setup: a pre-round of BONUS_FREEZE_SECONDS, everyone frozen", function()
	T.eq(Rounds.BONUS_FREEZE_SECONDS, 3, "three seconds")
	local round = Running({ timelimit = TIMELIMIT_MINUTES, matchEndAtTimelimit = true, deathmatchEnable = true })
	local over = TIMELIMIT_MINUTES * MINUTE
	local effects = round:Think(over, World())
	local freeze = Effect(effects, "bonus_freeze")
	T.eq(freeze ~= nil, true, "frozen: " .. Describe(effects))
	T.eq(freeze.ends, over + Rounds.BONUS_FREEZE_SECONDS, "for the freeze")
	local spawned, skipped
	for i, e in ipairs(effects) do
		if e.kind == "round_spawn" then spawned = i end
		if e.kind == "skip_setup" then skipped = i end
	end
	T.eq(skipped ~= nil and spawned ~= nil and skipped > spawned, true, "the map's setup ends once its timers start it: " .. Describe(effects))
	round:Think(over + Rounds.BONUS_FREEZE_SECONDS - 0.5, World())
	T.eq(round:State(), State.PREROUND, "still frozen")
	round:Think(over + Rounds.BONUS_FREEZE_SECONDS, World())
	T.eq(round:State(), State.RND_RUNNING, "then fought")
end)

T.test("a round after the deathmatch has its own pre-round and setup again", function()
	local round = Running()
	local effects = round:Think(T0 + 1, World())
	T.eq(Effect(effects, "bonus_freeze"), nil, "no freeze in a plain round")
	T.eq(Effect(effects, "skip_setup"), nil, "nor its setup skipped")
end)

T.test("sudden death opens frozen for BONUS_FREEZE_SECONDS", function()
	local round = Running({ winlimit = 3 })
	local called = round:SuddenDeathForMatch(T0 + 20)
	local freeze = Effect(called, "bonus_freeze")
	T.eq(freeze ~= nil, true, "frozen: " .. Describe(called))
	T.eq(freeze.ends, T0 + 20 + Rounds.BONUS_FREEZE_SECONDS, "for the freeze")
end)

T.test("the time limit's winner and reason are the mode's", function()
	T.eq(select(2, Rounds.Mode:TimelimitWin({ scores = { [RED] = 1, [BLUE] = 3 } })), W.TIMELIMIT, "the base: most points")
	local Decided = Rounds.Mode:Extend("decided")
	Decided.PRIORITY = 10 -- over the base mode
	function Decided:TimelimitWin() return RED, W.MOST_CAPTURES end
	local round = Running({ timelimit = TIMELIMIT_MINUTES, stalemateEnable = true }, nil, Decided)
	round:SetStalemateOnTimelimit(true)
	local publish
	for _, e in ipairs(round:Think(TIMELIMIT_MINUTES * MINUTE, World())) do
		if e.kind == "publish_win" then publish = e end
	end
	T.eq(publish.winner, RED, "the mode's winner")
	T.eq(publish.reason, W.MOST_CAPTURES, "the mode's reason")
end)

-- mp_round_restart (and the reset vote, the editors, a new game): a round
-- with players on its teams ends as a stalemate, an actual round end with
-- its win panel and stalemate song, then a fresh round on a reset map; with
-- nobody playing (a new game, everyone unassigned, or NPCs alone) it goes
-- back to PREGAME, silently.
local WITH_PLAYERS, NOBODY_PLAYING = true, false


T.test("a restart of a round with players ends it as a stalemate, then a fresh round on a reset map", function()
	local round = Running()
	local now = T0 + 30
	local ended = round:RestartRound(now, WITH_PLAYERS)
	T.eq(round:State(), State.TEAM_WIN, "the round ended")
	T.eq(Has(ended, "publish_win " .. Teams.UNASSIGNED), true, "the stalemate's win panel: " .. Describe(ended))
	T.eq(Has(ended, "win_song " .. Teams.UNASSIGNED), true, "the stalemate song and line")
	T.eq(Has(ended, "score"), false, "nobody scores")
	local fresh = round:Think(now + Settings().bonusRoundTime + 1, World())
	T.eq(round:State(), State.PREROUND, "a fresh round")
	T.eq(Has(fresh, "cleanup"), true, "on a reset map: " .. Describe(fresh))
end)

T.test("a restart with nobody playing goes back to PREGAME, silently", function()
	local round = Running()
	Expect(round:RestartRound(T0 + 30, NOBODY_PLAYING), { "state PREGAME" }, "no round end, no sound")
end)

T.test("a restart outside a round in play is silent, players or not", function()
	local round = Rounds.New(Settings())
	Expect(round:RestartRound(T0, WITH_PLAYERS), { "state PREGAME" }, "from PREGAME")
	local won = Running()
	won:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	Expect(won:RestartRound(T0 + 21, WITH_PLAYERS), { "state PREGAME" }, "while the winners celebrate")
end)

-- mp_restartround, mp_restartgame and mp_restartgame_immediate
-- (CTeamplayRoundBasedRules::CheckRestartRound), as the world reads them:
-- RestartRequest(restartround, restartgame, immediate).
T.test("mp_restartround is read first, mp_restartgame when it is 0, and only a game restart resets the map", function()
	T.eq(Rounds.RestartRequest(0, 0, false), nil, "nothing asked")
	local round = Rounds.RestartRequest(5, 0, false)
	T.eq(round.seconds, 5)
	T.eq(round.fullReset, false, "the round alone: a mini-round restarts on the map as it is")
	T.eq(round.line, Rounds.RESTART_ROUND, "announced")
	local game = Rounds.RestartRequest(0, 3, false)
	T.eq(game.seconds, 3)
	T.eq(game.fullReset, true)
	T.eq(game.line, Rounds.RESTART_GAME)
	local both = Rounds.RestartRequest(4, 9, false)
	T.eq(both.seconds, 4, "mp_restartround's delay")
	T.eq(both.fullReset, true, "mp_restartgame's reset")
	T.eq(both.line, Rounds.RESTART_GAME)
end)

T.test("mp_restartgame_immediate restarts the game now; delays are held to RESTART_DELAY_MAX", function()
	local now = Rounds.RestartRequest(0, 0, true)
	T.eq(now.seconds, 0)
	T.eq(now.fullReset, true)
	T.eq(Rounds.RestartRequest(0, Rounds.RESTART_DELAY_MAX + 1, false).seconds, Rounds.RESTART_DELAY_MAX)
	T.eq(Rounds.RestartRequest(-1, 5, false), nil, "a negative mp_restartround asks nothing, as TF2 reads it")
end)

-- The first Think a second after Running()'s last: its periodic checks run.
local PERIODIC_AT = T0 + 1 + Rounds.PREROUND_SECONDS + Rounds.PERIODIC_INTERVAL + 0.5

local function Restarting(seconds, fullReset, line)
	return World({ restart = { seconds = seconds, fullReset = fullReset, line = line } })
end

T.test("a restart asked is told once, its convars spent, and comes after its delay", function()
	local round = Running()
	local told = round:Think(PERIODIC_AT, Restarting(5, false, Rounds.RESTART_ROUND))
	T.eq(Has(told, "restart_seconds 5 " .. Rounds.RESTART_ROUND), true, Describe(told))
	T.eq(Has(round:Think(PERIODIC_AT + 4.9, World()), "reset_scores"), false, "the round runs on")
	T.eq(round:State(), State.RND_RUNNING)
	round:Think(PERIODIC_AT + 5, World())
	T.eq(round:State(), State.PREROUND, "restarted")
end)

T.test("a round restart resets the scores, the rounds played and the map's time, and keeps the map", function()
	local round = Running({ timelimit = TIMELIMIT_MINUTES, maxrounds = 5 })
	round:SetWinningTeam(T0 + 10, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	local back = T0 + 10 + Settings().bonusRoundTime + 1
	round:Think(back, World())
	round:Think(back + 1 + Rounds.PREROUND_SECONDS, World())
	T.eq(round:Limits(back).roundsPlayed, 1, "a round played")
	local at = back + 10
	round:Think(at, Restarting(0, false, Rounds.RESTART_ROUND))
	local restart = round:Think(at + Rounds.PERIODIC_INTERVAL + 0.5, World())
	local now = at + Rounds.PERIODIC_INTERVAL + 0.5
	T.eq(Has(restart, "reset_scores"), true, Describe(restart))
	T.eq(Has(restart, "cleanup"), false, "the map kept")
	T.eq(Has(restart, "clear_gore"), true)
	T.eq(round:Limits(now).roundsPlayed, 0)
	T.eq(round:Limits(now).timeLeft, TIMELIMIT_MINUTES * MINUTE)
	T.eq(round:State(), State.PREROUND)
end)

T.test("a game restart resets the map too", function()
	local round = Running()
	round:Think(PERIODIC_AT, Restarting(0, true, Rounds.RESTART_GAME))
	local restart = round:Think(PERIODIC_AT + 0.1, World())
	T.eq(Has(restart, "reset_scores"), true, Describe(restart))
	T.eq(Has(restart, "cleanup"), true, "a full reset")
end)

T.test("a game restart is announced only as a team switch, or a scramble, due", function()
	local quiet = Running():Think(PERIODIC_AT, Restarting(3, true, Rounds.RESTART_GAME))
	T.eq(Has(quiet, "restart_seconds 3"), true, Describe(quiet))
	T.eq(Has(quiet, "restart_seconds 3 "), false, "nothing to say")
	local scrambling = Running()
	scrambling:ScheduleScramble()
	local told = scrambling:Think(PERIODIC_AT, Restarting(3, true, Rounds.RESTART_GAME))
	T.eq(Has(told, "scramble_due"), true, "the scramble told again: " .. Describe(told))
end)

T.test("a restart due waits for a running round", function()
	local round = Running()
	round:SetWinningTeam(T0 + 10, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	round:Think(T0 + 11, Restarting(0, true, Rounds.RESTART_GAME))
	T.eq(Has(round:Think(T0 + 12, World()), "reset_scores"), false, "the winners celebrate")
	local back = T0 + 10 + Settings().bonusRoundTime + 1
	round:Think(back, World())
	round:Think(back + 1 + Rounds.PREROUND_SECONDS, World())
	T.eq(round:State(), State.RND_RUNNING)
	T.eq(Has(round:Think(back + 1.1 + Rounds.PREROUND_SECONDS, World()), "reset_scores"), true, "the next round running restarts")
end)

T.test("a restart due is forgotten by mp_round_restart and by a halt", function()
	local restarted = Running()
	restarted:Think(PERIODIC_AT, Restarting(5, true, Rounds.RESTART_GAME))
	restarted:RestartRound(PERIODIC_AT + 1, NOBODY_PLAYING)
	restarted:Think(PERIODIC_AT + 2, World())
	restarted:Think(PERIODIC_AT + 3 + Rounds.PREROUND_SECONDS, World())
	T.eq(Has(restarted:Think(PERIODIC_AT + 6, World()), "reset_scores"), false)
	local halted = Running()
	halted:Think(PERIODIC_AT, Restarting(5, true, Rounds.RESTART_GAME))
	halted:Halt(PERIODIC_AT + 1)
	halted:Unhalt()
	T.eq(Has(halted:Think(PERIODIC_AT + 6, World()), "reset_scores"), false)
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
	Expect(round:RestartRound(now + 7, NOBODY_PLAYING), { "state PREGAME" }, "a restart")
	local effects = round:Think(now + 8, World())
	T.eq(Describe({ effects[1], effects[2], effects[3] }), "state PREROUND, balance_teams, cleanup", "a full reset")
end)

-- A new game readies in two steps the gamemode's countdown times: the
-- halted map cleaned up, then the first pre-round, held to its end.
T.test("a new game cleans the halted map up, then holds its pre-round until the countdown ends", function()
	local round = Running()
	local now = T0 + 20
	round:Halt(now)
	Expect(round:CleanUp(), { "cleanup" }, "the map cleaned up")
	T.eq(round:Halted(), true, "still halted")
	local finish = now + 13
	local effects = round:BeginGame(now + 3, finish, World())
	T.eq(round:Halted(), false, "unhalted")
	Expect(effects, PREROUND_FULL_FRESH, "a full reset, not cleaned up again")
	T.eq(effects[1].preroundEnd, finish, "held until the countdown ends")
	round:Think(finish - 0.1, World())
	T.eq(round:State(), State.PREROUND, "held")
	round:Think(finish, World())
	T.eq(round:State(), State.RND_RUNNING, "the round runs as it ends")
end)

T.test("a new game begun without a cleanup cleans up in its pre-round", function()
	local round = Running()
	round:Halt(T0 + 20)
	local effects = round:BeginGame(T0 + 21, T0 + 30, World())
	T.eq(Describe({ effects[1], effects[2], effects[3] }), "state PREROUND, balance_teams, cleanup", "a full reset with a cleanup")
end)

T.test("a new game's pre-round is the next one's usual length", function()
	local round = Running()
	round:Halt(T0 + 20)
	round:BeginGame(T0 + 21, T0 + 30, World())
	round:Think(T0 + 30, World())
	round:SetWinningTeam(T0 + 31, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	local next = T0 + 31 + Settings().bonusRoundTime
	round:Think(next, World())
	T.eq(round:State(), State.PREROUND, "the next pre-round")
	round:Think(next + Rounds.PREROUND_SECONDS, World())
	T.eq(round:State(), State.RND_RUNNING, "lasts PREROUND_SECONDS")
end)

-- A map loaded in Sandbox mode has run: halting ended its setup and fired
-- the timer's OnSetupFinished, which on a race map disables the timer
-- itself (plr_hightower_event's plr_timer). The first game must reset it.
T.test("the first game after a map loaded in Sandbox mode cleans the map up", function()
	local round = Rounds.New(Settings())
	round:Halt(T0)
	round:Unhalt()
	round:RestartRound(T0 + 1, NOBODY_PLAYING)
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
	Expect(round:RestartRound(now + 5, NOBODY_PLAYING), {}, "no restart until unhalted")
	Expect(round:Think(now + 60, World({
		scores = {
			[RED] = 9,
			[BLUE] = 9,
		},
	})), {}, "no game over")
	T.eq(round:State(), State.BETWEEN_RNDS, "between rounds throughout")
	T.eq(round:PointsMayBeCaptured(), false, "no captures")
	round:Unhalt()
	Expect(round:RestartRound(now + 61, NOBODY_PLAYING), { "state PREGAME" }, "Gameplay mode restarts the rounds")
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

T.test("a map without an objective respawns at once, unless an admin or the map sets a wave", function()
	local round = Running()
	T.eq(round:TeamWaveTime(RED), 0, "no wave")
	round:SetAdminWaveTime(RED, 5)
	T.eq(round:TeamWaveTime(RED), 5, "the admin's")
end)

T.test("respawn waves scale with the team, and admins and maps set them", function()
	local round = Running(nil, nil, CPMode)
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

-- The controller checks the waves each round think, a little after one
-- falls due: the next is a wave after the one due, not after the late
-- check, or the waves drift and the respawn time shown is not the wave
-- that brings the player back.
local THINK = 0.1

T.test("waves keep their length however late the think checks them", function()
	local round = Running(nil, nil, CPMode)
	round:SetTeamWaveTime(RED, 2)
	local now = T0 + 20
	T.eq(round:WaveDue(RED, now, 8), true, "the first wave")
	T.eq(round:WaveDue(RED, now + 2 + THINK, 8), true, "the next, checked late")
	T.eq(round:WaveDue(RED, now + 4 - THINK / 2, 8), false, "the one after is due at now + 4")
	T.eq(round:WaveDue(RED, now + 4, 8), true, "at now + 4, not now + 4.1")
end)

T.test("the respawn time shown is the wave that brings the player back", function()
	local round = Running(nil, nil, CPMode)
	round:SetTeamWaveTime(RED, 2)
	local now = T0 + 20
	round:WaveDue(RED, now, 8)
	local death = now + 0.35
	local shown = round:RespawnAt(RED, death, 8)
	local t = now
	while true do
		t = t + THINK
		if round:WaveDue(RED, t, 8) and round:MayRespawn(RED, death, t) then break end
	end
	T.near(t, shown, THINK, "back on the wave shown")
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

T.test("setup respawns at once, and sudden death or an admin stops respawns", function()
	local round = Running()
	local now = T0 + 20
	round:SetSetup(true)
	T.eq(round:MayRespawn(RED, now, now), true, "setup: no wait of their own")
	T.eq(round:NextRespawn(RED, now, 8), now, "the first quick wave")
	T.eq(round:PointsMayBeCaptured(), false, "setup")
	round:SetSetup(false)
	T.eq(round:SetRespawnsDisabled(true), false, "disabling reschedules nobody")
	T.eq(round:RespawnAt(RED, now, 8), 0, "no respawn")
	T.eq(round:RespawnStatus(RED, now, 8), Spawns.NEXT_ROUND, "said: wait for the next round")
	T.eq(round:SetRespawnsDisabled(false), true, "the dead are rescheduled")
	local status, at = round:RespawnStatus(RED, now, 8)
	T.eq(status, Spawns.WAVE, "said: a wave")
	T.eq(at, round:RespawnAt(RED, now, 8), "at the respawn time shown")
	Expect(round:Think(now + 1, World()), WAVES, "waves")
	round:SetRespawnsDisabled(true)
	Expect(round:Think(now + 40, World()), {}, "the waves come, but nobody respawns")
end)

-- Sandcastle's pre-round and setup bring the dead back with the next of
-- their quick waves, a QUICK_WAVE apart, with no death animation to wait
-- out, whatever the team's wave.
T.test("the pre-round and setup respawn the dead with a wave every QUICK_WAVE", function()
	local preround = Rounds.New(Settings({ respawnWaveTime = 20 }))
	preround:Think(T0, World())
	T.eq(preround:State(), State.PREROUND, "the pre-round")
	T.eq(preround:MayRespawn(RED, T0 + 0.5, T0 + 0.5), true, "pre-round: no wait of their own")
	Expect(preround:Think(T0 + 0.5, World()), WAVES, "a quick wave")
	local round = Running({ respawnWaveTime = 20 })
	local now = T0 + 20
	round:SetSetup(true)
	T.eq(round:MayRespawn(RED, now, now, true), true, "switched teams: no wait either")
	Expect(round:Think(now, World()), WAVES, "a wave now")
	Expect(round:Think(now + Rounds.QUICK_WAVE / 2, World()), {}, "none between")
	T.eq(round:RespawnAt(RED, now + 0.1, 8), now + Rounds.QUICK_WAVE, "the respawn time shown: the next quick wave")
	Expect(round:Think(now + Rounds.QUICK_WAVE, World()), WAVES, "the next")
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

-- CTFGameRules::HandleTimeLimitChange: a new mp_timelimit mid-match resets
-- the time limit timer to the time left, or removes it when the limit no
-- longer makes one.
T.test("a changed time limit resets the time limit timer to the time left, or removes it", function()
	local world = World({ mapHasActiveTimer = false })
	local round = Running({ timelimit = 10, matchEndAtTimelimit = true }, world)
	local now = T0 + 60
	local function Limit(minutes)
		round:SetLimits({ winlimit = 0, maxrounds = 0, timelimit = minutes })
	end
	Limit(TIMELIMIT_MINUTES)
	local effects = round:TimeLimitTimer(now, world)
	T.eq(Describe(effects), "time_limit_timer " .. (TIMELIMIT_MINUTES * MINUTE - now), "the new time left")
	Limit(0)
	T.eq(Describe(round:TimeLimitTimer(now, world)), "remove_time_limit_timer", "no limit: no timer")
	Limit(1)
	T.eq(Describe(round:TimeLimitTimer(now, world)), "remove_time_limit_timer", "a limit already spent: no timer")
	Limit(TIMELIMIT_MINUTES)
	T.eq(Describe(round:TimeLimitTimer(now, World({ mapHasActiveTimer = true }))), "remove_time_limit_timer",
		"the map's own timer shows instead")
	local kept = Running({ timelimit = 10 }, world)
	kept:SetLimits({ winlimit = 0, maxrounds = 0, timelimit = TIMELIMIT_MINUTES })
	T.eq(Describe(kept:TimeLimitTimer(now, world)), "remove_time_limit_timer", "a limit that ends no round makes none")
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
		"intermission " .. Rounds.STALEMATE_GAME_OVER,
		"state GAME_OVER",
	}, "team 0 is a stalemate: without sudden death, the match ends drawn")
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
	local Timer = T.require("games.gameplay.rounds.timer")
	local ControlPoints = T.require("features.rounds.control_points")
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
		"hook WSRoundWin " .. RED,
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

-- mp_forcewin (teamplayroundbased_gamerules.cpp): a team wins the round,
-- team 0 is a stalemate, and with no team the first player's team wins.
T.test("mp_forcewin takes TF2's team numbers, the teams' names, or sudden death", function()
	T.eq(Rounds.ForceWinTarget({ "2" }), RED)
	T.eq(Rounds.ForceWinTarget({ "3" }), BLUE)
	T.eq(Rounds.ForceWinTarget({ "0" }), NOBODY, "team 0: a stalemate")
	T.eq(Rounds.ForceWinTarget({ "red" }), RED)
	T.eq(Rounds.ForceWinTarget({ "BLUE" }), BLUE)
	T.eq(Rounds.ForceWinTarget({ "blu" }), BLUE)
	T.eq(Rounds.ForceWinTarget({ "sudden" }), Rounds.FORCE_SUDDEN_DEATH)
	T.eq(Rounds.ForceWinTarget({ tostring(Teams.SPECTATOR) }), nil, "spectators win nothing")
	T.eq(Rounds.ForceWinTarget({ "green" }), nil, "anything else is refused")
	T.eq(Rounds.ForceWinTarget({ "2", "3" }), nil, "one team at most")
end)

T.test("mp_forcewin with no team gives the round to the first player's team", function()
	T.eq(Rounds.ForceWinTarget({}, BLUE), BLUE)
	T.eq(Rounds.ForceWinTarget({}, NOBODY), NOBODY, "an unassigned first player: a stalemate")
	local target, why = Rounds.ForceWinTarget({}, nil)
	T.eq(target, nil, "no player, no default team")
	T.eq(why, Rounds.FORCE_WIN_NO_DEFAULT, "and why")
end)

T.test("mp_forcewin's win is all points captured, scored as the map scores a round", function()
	local round = Running()
	local effects = round:ForceWin(T0 + 20, RED, FakeObjective.Objective({ scorePerRound = false }))
	T.eq(Has(effects, "score"), false, "points come from captures: no round point, as TF2's AddScore")
	T.eq(round:State(), State.TEAM_WIN)
	T.eq(effects[1].reason, W.ALL_POINTS_CAPTURED, "why: " .. Describe(effects))
	local scored = Running():ForceWin(T0 + 20, BLUE, FakeObjective.Objective())
	Expect({ scored[1] }, { "score " .. BLUE .. " 1" }, "a map scoring by rounds")
end)

T.test("mp_forcewin 0 ends the round a stalemate, nobody scoring", function()
	local round = Running()
	local effects = round:ForceWin(T0 + 20, NOBODY, FakeObjective.Objective())
	T.eq(round:State(), State.TEAM_WIN)
	T.eq(effects[1].reason, W.STALEMATE)
	T.eq(Has(effects, "publish_win " .. NOBODY), true, Describe(effects))
	T.eq(Has(effects, "score"), false)
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

T.test("mp_scrambleteams_auto: a full round won to a lead of the win difference scrambles the next round's teams", function()
	local round = Running({ scrambleAuto = true, scrambleWinDifference = 2 })
	round:Think(T0 + 1, World({ scores = { [RED] = 1, [BLUE] = 0 } }))
	local win = round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, true, false, FakeObjective.Objective())
	T.eq(Has(win, "scramble_due"), true, "announced with the win: " .. Describe(win))
	local restart = round:Think(T0 + 35, World({ scores = { [RED] = 2, [BLUE] = 0 } }))
	T.eq(Has(restart, "scramble_teams"), true, "the next round scrambled: " .. Describe(restart))
	T.eq(Has(restart, "switch_teams"), false, "in place of the switch")
end)

T.test("no scramble without mp_scrambleteams_auto, under the win difference, or on a mini-round", function()
	local off = Running({ scrambleAuto = false, scrambleWinDifference = 2 })
	off:Think(T0 + 1, World({ scores = { [RED] = 1, [BLUE] = 0 } }))
	T.eq(Has(off:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective()), "scramble_due"), false, "off")
	local close = Running({ scrambleAuto = true, scrambleWinDifference = 2 })
	T.eq(Has(close:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective()), "scramble_due"), false, "a lead of 1")
	local mini = Running({ scrambleAuto = true, scrambleWinDifference = 1 })
	T.eq(Has(mini:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, false, false, false, FakeObjective.Objective()), "scramble_due"), false, "a mini-round")
end)

T.test("a passed scramble vote scrambles the next round's teams, as TF2's does", function()
	local round = Running({ scrambleAuto = false, scrambleWinDifference = 2 })
	T.eq(round:ScramblePending(), false)
	local now = round:ScheduleScramble()
	T.eq(Has(now, "scramble_due"), true, "told at once: " .. Describe(now))
	T.eq(round:ScramblePending(), true, "a second vote is refused while it waits")
	round:SetWinningTeam(T0 + 20, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	local restart = round:Think(T0 + 35, World({ scores = { [RED] = 1, [BLUE] = 0 } }))
	T.eq(Has(restart, "scramble_teams"), true, "the next round scrambled: " .. Describe(restart))
	T.eq(round:ScramblePending(), false, "done")
end)

local function Intermission(effects)
	for _, e in ipairs(effects) do
		if e.kind == "intermission" then return e end
	end
end

T.test("an admin forcing the match's winner ends the match won by that team, whatever the score", function()
	local round = Running({ winlimit = 3 })
	local effects = round:ForceMatchWin(T0 + 20, BLUE)
	local over = Intermission(effects)
	T.eq(over ~= nil, true, "the match is over: " .. Describe(effects))
	T.eq(over.winner, BLUE)
	T.eq(over.reason, Rounds.ADMIN_MATCH_WIN)
	T.eq(#round:ForceMatchWin(T0 + 21, RED), 0, "an ended match is not ended again")
end)

T.test("a sudden death called to decide the match ends it, won by the round's winner", function()
	local round = Running({ winlimit = 3 })
	local called = round:SuddenDeathForMatch(T0 + 20)
	T.eq(Has(called, "sudden_death"), true, "sudden death: " .. Describe(called))
	local won = round:SetWinningTeam(T0 + 30, RED, W.OPPONENTS_DEAD, true, false, false, FakeObjective.Objective())
	local over = Intermission(won)
	T.eq(over ~= nil, true, "the match is over: " .. Describe(won))
	T.eq(over.winner, RED)
end)

-- The match ended early, by the gamerules' own judgement, with their
-- evaluation of the game's progress (gameplay.standing): it ends as a round
-- completed, won by the team it puts ahead, and that win decides the match;
-- a genuine tie goes to a sudden death whose winner decides it.
T.test("ended early, the leader wins the round and with it the match", function()
	local round = Running({ winlimit = 3 })
	local effects = round:EndEarly(T0 + 20, RED, FakeObjective.Objective())
	local over = Intermission(effects)
	T.eq(over ~= nil, true, "the match is over: " .. Describe(effects))
	T.eq(over.winner, RED, "won by the leader")
	T.eq(over.reason, Rounds.ENDED_EARLY_WIN, "ended early")
	T.eq(#round:EndEarly(T0 + 21, BLUE, FakeObjective.Objective()), 0, "an ended match is not closed again")
end)

T.test("ended early on a tie, a sudden death decides the match", function()
	local round = Running({ winlimit = 3 })
	local called = round:EndEarly(T0 + 20, nil, FakeObjective.Objective())
	T.eq(Has(called, "sudden_death"), true, "sudden death: " .. Describe(called))
	local won = round:SetWinningTeam(T0 + 30, BLUE, W.OPPONENTS_DEAD, true, false, false, FakeObjective.Objective())
	local over = Intermission(won)
	T.eq(over ~= nil, true, "the match is over: " .. Describe(won))
	T.eq(over.winner, BLUE, "the survivors win it")
	T.eq(over.reason, Rounds.ENDED_EARLY_WIN, "ended early")
end)

T.test("ended early on a tie with no round under way, the match ends drawn", function()
	local round = Rounds.New(Settings({ winlimit = 3 }))
	T.eq(round:State(), State.PREGAME, "waiting for players: no round to hold a sudden death")
	local effects = round:EndEarly(T0, nil, FakeObjective.Objective())
	local over = Intermission(effects)
	T.eq(over ~= nil, true, "the match is over: " .. Describe(effects))
	T.eq(over.winner, Rounds.NOBODY_WON, "drawn")
end)

T.test("a plain sudden death, or a restart, leaves the match to its limits", function()
	local round = Running({ winlimit = 3 })
	round:SuddenDeathForMatch(T0 + 20)
	round:RestartRound(T0 + 21, NOBODY_PLAYING)
	local plain = Running({ winlimit = 3 })
	plain:SuddenDeath(T0 + 20, Rounds.STALEMATE.ADMIN)
	T.eq(Intermission(plain:SetWinningTeam(T0 + 30, RED, W.OPPONENTS_DEAD, true, false, false, FakeObjective.Objective())), nil)
end)

T.test("a win handed out with WINREASON.NONE scores a point where points come from captures, and can win the match", function()
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

-- Round limits (games.gameplay.rounds.limits): an outcome the controller found.

T.test("a team at a round limit wins the round and its point, even where points come from captures", function()
	local round = Running()
	local effects = round:LimitReached(T0 + 20, { team = RED, reason = W.FRAGLIMIT }, FakeObjective.Objective({ scorePerRound = false }))
	Expect({ effects[1], effects[2] }, { "score " .. RED .. " 1", "publish_win " .. RED }, "RED wins by frags")
	T.eq(effects[2].reason, W.FRAGLIMIT, "the reason")
	T.eq(round:State(), State.TEAM_WIN, "the round won")
end)

T.test("both teams tied at a round limit is a stalemate: sudden death, or the match ends drawn", function()
	local sudden = Running({ stalemateEnable = true })
	sudden:LimitReached(T0 + 20, { tie = true, reason = W.FRAGLIMIT }, FakeObjective.Objective())
	T.eq(sudden:InSuddenDeath(), true, "sudden death")
	local drawn = Running()
	drawn:LimitReached(T0 + 20, { tie = true, reason = W.CASHLIMIT }, FakeObjective.Objective())
	T.eq(drawn:State(), State.GAME_OVER, "the match ends drawn")
end)

T.test("kills and earnings count toward the limits only in a round being fought", function()
	local round = Running()
	T.eq(round:LimitsCount(), true, "running")
	round:SetSetup(true)
	T.eq(round:LimitsCount(), false, "setup")
	local sudden = Running({ stalemateEnable = true })
	sudden:SetStalemate(T0 + 20, SM.TIMER, true, false)
	T.eq(sudden:LimitsCount(), false, "sudden death")
	local won = Running()
	won:SetWinningTeam(T0 + 20, BLUE, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	T.eq(won:LimitsCount(), false, "the bonus round")
	T.eq(Rounds.New(Settings()):LimitsCount(), false, "before the game")
end)

T.test("a round limit decides only a round being fought: not in setup, sudden death or between rounds", function()
	local setup = Running()
	setup:SetSetup(true)
	T.eq(#setup:LimitReached(T0 + 20, { team = RED, reason = W.FRAGLIMIT }, FakeObjective.Objective()), 0, "setup")
	local sudden = Running({ stalemateEnable = true })
	sudden:SetStalemate(T0 + 20, SM.TIMER, true, false)
	T.eq(#sudden:LimitReached(T0 + 21, { team = RED, reason = W.FRAGLIMIT }, FakeObjective.Objective()), 0, "sudden death")
	local won = Running()
	won:SetWinningTeam(T0 + 20, BLUE, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())
	T.eq(#won:LimitReached(T0 + 21, { team = RED, reason = W.FRAGLIMIT }, FakeObjective.Objective()), 0, "the round already won")
end)

T.finish()
