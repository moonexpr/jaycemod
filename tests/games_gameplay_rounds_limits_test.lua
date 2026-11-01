-- Round limits (games.gameplay.rounds.limits): mp_fraglimit and
-- mp_creditlimit win a round for the first team to reach them, counted
-- from the round's start: its frags (kills of the enemy), and the money it
-- has earned (not what it held to begin with). Frags decide before money; a
-- tie at a limit is a stalemate (games.gameplay.rounds breaks it with sudden
-- death, or ends the match drawn).
local T = dofile("tests/harness.lua")
local Limits = T.require("games.gameplay.rounds.limits")
local Rounds = gameplay.rounds
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local W = Rounds.WINREASON

local function Tally(redFrags, blueFrags, redEarned, blueEarned)
	local t = Limits.Tally.New()
	for _ = 1, redFrags do t:Frag(RED) end
	for _ = 1, blueFrags do t:Frag(BLUE) end
	t:Earn(RED, redEarned or 0)
	t:Earn(BLUE, blueEarned or 0)
	return t
end

T.test("a tally counts each team's frags and earnings from zero, and starts over with the round", function()
	local t = Tally(3, 1, 500, 0)
	T.eq(t:Frags(RED), 3, "RED's frags")
	T.eq(t:Frags(BLUE), 1, "BLU's")
	T.eq(t:Earned(RED), 500, "RED's earnings")
	t:Reset()
	T.eq(t:Frags(RED) + t:Earned(RED), 0, "a new round")
end)

T.test("the first team to the frag limit wins", function()
	local o = Limits.Outcome({ frags = 5, cash = 0 }, Tally(5, 4))
	T.eq(o.team, RED, "RED")
	T.eq(o.reason, W.FRAGLIMIT, "by frags")
	T.eq(Limits.Outcome({ frags = 5, cash = 0 }, Tally(4, 4)), nil, "nobody there yet")
end)

T.test("the first team to the cash limit wins, on money earned", function()
	local o = Limits.Outcome({ frags = 0, cash = 1000 }, Tally(0, 0, 200, 1000))
	T.eq(o.team, BLUE, "BLU")
	T.eq(o.reason, W.CASHLIMIT, "by money")
end)

T.test("frags decide before money", function()
	local o = Limits.Outcome({ frags = 5, cash = 1000 }, Tally(0, 5, 1000, 0))
	T.eq(o.team, BLUE, "BLU's frags over RED's money")
	T.eq(o.reason, W.FRAGLIMIT, "by frags")
end)

T.test("both teams at a limit together: the higher count wins, a tie is a stalemate", function()
	local o = Limits.Outcome({ frags = 5, cash = 0 }, Tally(6, 5))
	T.eq(o.team, RED, "the higher")
	local tie = Limits.Outcome({ frags = 5, cash = 0 }, Tally(5, 5))
	T.eq(tie.tie, true, "a tie")
	T.eq(tie.reason, W.FRAGLIMIT, "at the frag limit")
end)

T.test("a limit of 0 is off", function()
	T.eq(Limits.Outcome({ frags = 0, cash = 0 }, Tally(100, 0, 99999, 0)), nil, "nothing decides")
end)

T.test("only a mode without an objective plays to the round limits; an objective's modes have them at 0", function()
	local on = Limits.Of(Rounds.Mode, 30, 10000)
	T.eq(on.frags == 30 and on.cash == 10000, true, "no objective: the convars")
	local OBJECTIVE_MODES = {
		control_points = "features.rounds.control_points",
		koth = "features.koth.model",
		arena = "features.arena.round",
		payload = "features.payload.round",
	}
	for _, name in ipairs({ "control_points", "koth", "arena", "payload" }) do
		local off = Limits.Of(T.require(OBJECTIVE_MODES[name]).Mode, 30, 10000)
		T.eq(off.frags == 0 and off.cash == 0, true, name .. ": off")
	end
end)

-- The announcer's cues (Tally:Calls): first blood, and a team close to winning.

local function Kinds(calls)
	local list = {}
	for i, c in ipairs(calls) do list[i] = c.kind .. " " .. c.team .. (c.reason and (" " .. c.reason) or "") end
	return table.concat(list, ", ")
end

T.test("the round's first frag is first blood, once, while the frag limit is on", function()
	local limits = { frags = 10, cash = 0 }
	local t = Limits.Tally.New()
	t:Frag(BLUE)
	T.eq(Kinds(t:Calls(limits)), "first_blood " .. BLUE, "first blood")
	t:Frag(RED)
	T.eq(Kinds(t:Calls(limits)), "", "once")
	local off = Limits.Tally.New()
	off:Frag(RED)
	T.eq(Kinds(off:Calls({ frags = 0, cash = 0 })), "", "no frag limit, no first blood")
end)

T.test("a team at CLOSE_SHARE of a limit is close to winning, once a round", function()
	local limits = { frags = 10, cash = 1000 }
	local t = Limits.Tally.New()
	t:Frag(RED)
	t:Calls(limits)
	local close = math.ceil(10 * Limits.CLOSE_SHARE)
	for _ = 2, close - 1 do t:Frag(RED) end
	T.eq(Kinds(t:Calls(limits)), "", "not yet")
	t:Frag(RED)
	T.eq(Kinds(t:Calls(limits)), "close " .. RED .. " " .. W.FRAGLIMIT, "close by frags")
	t:Frag(RED)
	T.eq(Kinds(t:Calls(limits)), "", "once")
	t:Earn(BLUE, 1000)
	T.eq(Kinds(t:Calls(limits)), "close " .. BLUE .. " " .. W.CASHLIMIT, "close by money")
	t:Reset()
	for _ = 1, close do t:Frag(RED) end
	T.eq(Kinds(t:Calls(limits)), "first_blood " .. RED .. ", close " .. RED .. " " .. W.FRAGLIMIT, "a new round calls again")
end)

-- The HUD (Limits.Panels): one Player Destruction panel per limit that is on.

T.test("a panel per limit on, the frag limit's first (lowest on screen), each team's fill and number", function()
	local panels = Limits.Panels({ frags = 30, cash = 10000 }, { [RED] = 15, [BLUE] = 45 }, { [RED] = 2500, [BLUE] = 0 })
	T.eq(#panels, 2, "both limits on")
	local frags, cash = panels[1], panels[2]
	T.eq(frags.reason, W.FRAGLIMIT, "frags first")
	T.eq(frags.label, "Playing to: 30", "TF2's #TF_PlayingTo")
	T.eq(frags.fills[RED], 0.5, "RED halfway")
	T.eq(frags.fills[BLUE], 1, "BLU past it, full")
	T.eq(frags.values[BLUE], "45", "BLU's frags")
	T.eq(cash.reason, W.CASHLIMIT, "then money")
	T.eq(cash.label, "Playing to: $10,000", "in money")
	T.eq(cash.values[RED], "$2,500", "RED's earnings")
	T.eq(cash.fills[RED], 0.25, "a quarter")
end)

T.test("no panel for a limit that is off", function()
	T.eq(#Limits.Panels({ frags = 0, cash = 0 }, { [RED] = 1, [BLUE] = 1 }, { [RED] = 0, [BLUE] = 0 }), 0, "none")
	local only = Limits.Panels({ frags = 0, cash = 500 }, { [RED] = 0, [BLUE] = 0 }, { [RED] = 0, [BLUE] = 0 })
	T.eq(#only == 1 and only[1].reason, W.CASHLIMIT, "money alone")
end)

-- The match's win conditions: TF2's casual ones for the map's kind
-- (tf_match_description_casual.cpp picks a server_casual_*_win_conditions.cfg).

local function Map(facts)
	local map = { mvm = false, payload = false, ctf = false, multipleTrains = false, miniRounds = false, stages = 0, switchTeams = false,
		controlPoints = false, scorePerCapture = false }
	for k, v in pairs(facts) do map[k] = v end
	return map
end

local C = Limits.WIN_CONDITIONS

T.test("TF2's casual win conditions, as its cfgs set them", function()
	T.eq(C.ROUNDS.winlimit, 2, "server_casual_rounds_win_conditions: first to two")
	T.eq(C.ROUNDS.maxrounds, 0, "no round limit")
	T.eq(C.STOPWATCH.maxrounds, 2, "server_casual_stopwatch_win_conditions: two rounds")
	T.eq(C.STOPWATCH.winlimit, 0, "no win limit")
	T.eq(C.MAX_ROUNDS.maxrounds, 1, "server_casual_max_rounds_win_conditions: one round")
	T.eq(C.MAX_ROUNDS.winlimit, 0, "no win limit")
end)

T.test("a symmetric map is won by the first team to the win limit", function()
	T.eq(Limits.WinConditions(Map({})), C.ROUNDS, "no objective or KOTH")
	T.eq(Limits.WinConditions(Map({ payload = true, multipleTrains = true })), C.ROUNDS, "a one-stage payload race")
end)

T.test("an attack/defend map plays stopwatch", function()
	T.eq(Limits.WinConditions(Map({ payload = true })), C.STOPWATCH, "payload")
	T.eq(Limits.WinConditions(Map({ payload = true, miniRounds = true, stages = 3 })), C.STOPWATCH, "multi-stage payload")
	T.eq(Limits.WinConditions(Map({ miniRounds = true, stages = 3 })), C.STOPWATCH, "control points in stages")
	T.eq(Limits.WinConditions(Map({ switchTeams = true })), C.STOPWATCH, "control points that switch teams on a win")
end)

-- A hostage map's rounds are won by rescue or by killing, never by a count
-- of wins ending the match early: it plays ten rounds, whoever wins them.
T.test("a hostage map plays ten rounds, with no win limit", function()
	local conditions = Limits.WinConditions(Map({ hostage = true }))
	T.eq(conditions, C.HOSTAGE, "hostage")
	T.eq(C.HOSTAGE.winlimit, 0, "no win limit")
	T.eq(C.HOSTAGE.maxrounds, 10, "ten rounds")
	T.eq(Limits.WinConditions(Map({ hostage = true, payload = true })), C.HOSTAGE, "whatever else it carries")
end)

-- A bomb defusal map's are won by the bomb or by killing, the same way.
T.test("a defuse map plays ten rounds, with no win limit", function()
	T.eq(Limits.WinConditions(Map({ defuse = true })), C.HOSTAGE, "as a hostage map's")
	T.eq(Limits.WinConditions(Map({ defuse = true, control_points = true })), C.HOSTAGE, "though its sites are points")
end)

T.test("a multi-stage payload race and CTF play one round", function()
	T.eq(Limits.WinConditions(Map({ payload = true, multipleTrains = true, miniRounds = true, stages = 3 })), C.MAX_ROUNDS, "race in stages")
	T.eq(Limits.WinConditions(Map({ ctf = true })), C.MAX_ROUNDS, "CTF")
	T.eq(Limits.WinConditions(Map({ payload = true, multipleTrains = true, miniRounds = true, stages = 1 })), C.ROUNDS, "a race of one stage is symmetric")
end)

-- A capture is a point on a control-point map's score (score_style 1, as
-- cp_egypt_final's), so a win limit ends the match a few captures in,
-- before its later stages: control-point maps play to no win limit.
T.test("control-point maps, and any map scoring each capture, play to no win limit", function()
	local symmetric = Limits.WinConditions(Map({ controlPoints = true }))
	T.eq(symmetric.winlimit, 0, "symmetric control points: no win limit")
	T.eq(symmetric.maxrounds, 0, "nor a round limit: the time limit ends it")
	T.eq(Limits.WinConditions(Map({ controlPoints = true, miniRounds = true, stages = 3 })), C.STOPWATCH,
		"in stages: stopwatch, which has none either")
	T.eq(Limits.WinConditions(Map({ scorePerCapture = true })).winlimit, 0, "a score per capture")
end)

T.test("Mann vs. Machine has no casual win conditions", function()
	T.eq(Limits.WinConditions(Map({ mvm = true, ctf = true })), nil, "its waves decide")
end)

T.finish()
