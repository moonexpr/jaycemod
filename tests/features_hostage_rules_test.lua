-- The CS:S gamerules' rules (features.hostage.rules): what CS:S's round-end
-- inputs do to a round, and when a timed round runs out. cs_gamerules, the
-- entity, forwards to these.
local T = dofile("tests/harness.lua")
local Rules = T.require("features.hostage.rules")
local Rounds = gameplay.rounds
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local W = Rounds.WINREASON

T.test("the terrorists' win input makes RED win, the counter-terrorists' BLU", function()
	local red = Rules.Input("endround_terroristswin")
	T.eq(red.winner, RED, "terrorists")
	T.eq(red.reason, W.OPPONENTS_DEAD, "reason")
	local blue = Rules.Input("endround_counterterroristswin")
	T.eq(blue.winner, BLUE, "counter-terrorists")
end)

T.test("the hostages' inputs give each side its own reason", function()
	local rescued = Rules.Input("endround_hostagesrescued")
	T.eq(rescued.winner, BLUE, "rescued: BLU")
	T.eq(rescued.reason, W.HOSTAGES_RESCUED, "rescued: its reason")
	local kept = Rules.Input("endround_hostagesnotrescued")
	T.eq(kept.winner, RED, "not rescued: RED")
	T.eq(kept.reason, W.HOSTAGES_NOT_RESCUED, "not rescued: its reason")
end)

T.test("a draw input is no one's win", function()
	local draw = Rules.Input("endround_draw")
	T.eq(draw.winner, nil, "no winner")
	T.eq(draw.draw, true, "a draw")
end)

T.test("any other input is not the rules' to answer", function()
	T.eq(Rules.Input("roundspawn"), nil, "tf_gamerules'")
	T.eq(Rules.Input("nonsense"), nil, "unknown")
end)

T.test("a timed round runs out at its limit; an untimed one never", function()
	T.eq(Rules.Expired(0, 1e9), false, "no limit")
	T.eq(Rules.Expired(120, 119), false, "time left")
	T.eq(Rules.Expired(120, 120), true, "at the limit")
	T.eq(Rules.Expired(120, 500), true, "past it")
end)

T.finish()
