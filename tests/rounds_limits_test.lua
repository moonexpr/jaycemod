-- Round limits (foundation.rounds.limits): mp_round_fraglimit and
-- mp_round_cashlimit win a round for the first team to reach them, counted
-- from the round's start: its frags (kills of the enemy), and the money it
-- has earned (not what it held to begin with). Frags decide before money; a
-- tie at a limit is a stalemate (foundation.rounds breaks it with sudden
-- death, or ends the match drawn).
local T = dofile("tests/harness.lua")
local Limits = T.require("foundation.rounds.limits")
local Rounds = T.require("foundation.rounds")
local Teams = T.require("foundation.teams")

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
		control_points = "foundation.rounds.control_points",
		koth = "features.koth.model",
		arena = "foundation.rounds.arena",
		payload = "foundation.rounds.payload",
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

T.finish()
