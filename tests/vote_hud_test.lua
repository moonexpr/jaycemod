-- ws.vote_hud: the running vote and its result as cooler-hud v2.6 lays
-- them out (votehud.res) and CHudVote fills them (hud_vote.cpp): the
-- header naming who called it, the issue, a row an option (TF2's yes/no
-- instructions, or "F1. <option>" on a vote of choices), the player's cast
-- lit, the yes/no counts beside the vote bar, and the passed or failed
-- panel.
local T = dofile("tests/harness.lua")
local VoteHud = T.require("ws.vote_hud")
local Vote = T.require("games.gameplay.vote")

local NOW = 100

local function State(over)
	local state = {
		running = true,
		caller = "alice",
		question = "Change the map to cp_dustbowl?",
		ends = NOW + 12,
		yes = 3,
		no = 1,
		quorum = 3,
		mine = true,
		cast = Vote.BALLOT_NONE,
		options = {},
		counts = {},
	}
	for k, v in pairs(over or {}) do state[k] = v end
	return state
end

T.test("the header names who called the vote, the server when nobody did", function()
	T.eq(VoteHud.Active(State(), NOW).header, "alice wants to call a vote:", "a player's")
	T.eq(VoteHud.Active(State({ caller = "" }), NOW).header, "Server wants to call a vote:", "the server's")
end)

T.test("the issue is the vote's question", function()
	T.eq(VoteHud.Active(State(), NOW).issue, "Change the map to cp_dustbowl?", "issue")
end)

T.test("the clock counts the whole seconds left, never below zero", function()
	T.eq(VoteHud.Active(State({ ends = NOW + 11.2 }), NOW).clock, "0:12", "rounded up")
	T.eq(VoteHud.Active(State({ ends = NOW + 75 }), NOW).clock, "1:15", "minutes")
	T.eq(VoteHud.Active(State({ ends = NOW - 3 }), NOW).clock, "0:00", "ended")
end)

T.test("a yes/no vote: TF2's instructions on two rows, each casting its ballot", function()
	local card = VoteHud.Active(State(), NOW)
	T.eq(card.yesNo, true, "yes/no")
	T.eq(#card.rows, 2, "two rows")
	T.eq(card.rows[1].text, "Press F1 to vote YES", "yes row")
	T.eq(card.rows[2].text, "Press F2 to vote NO", "no row")
	T.eq(card.rows[1].cast.yes, true, "the first row casts yes")
	T.eq(card.rows[2].cast.yes, false, "the second casts no")
	T.eq(card.rows[1].cast.choice, 0, "no choice on a yes/no vote")
	T.eq(card.rows[1].lit or card.rows[2].lit, false, "nothing lit before a cast")
end)

T.test("a yes/no vote's counts go beside the vote bar's boxes", function()
	local card = VoteHud.Active(State(), NOW)
	T.eq(card.yes, "3", "Option1CountLabel")
	T.eq(card.no, "1", "Option2CountLabel")
	T.eq(card.rows[1].count, nil, "not in the rows")
end)

T.test("the player's cast is lit", function()
	local yes = VoteHud.Active(State({ cast = Vote.BALLOT_YES }), NOW)
	T.eq(yes.rows[1].lit, true, "yes lit")
	T.eq(yes.rows[2].lit, false, "no unlit")
	local no = VoteHud.Active(State({ cast = Vote.BALLOT_NO }), NOW)
	T.eq(no.rows[1].lit, false, "yes unlit")
	T.eq(no.rows[2].lit, true, "no lit")
end)

T.test("a player who may not vote is shown the ballots, without keys or clicks", function()
	local card = VoteHud.Active(State({ mine = false }), NOW)
	T.eq(card.rows[1].text, "Yes", "yes")
	T.eq(card.rows[2].text, "No", "no")
	T.eq(card.rows[1].cast, nil, "the yes row casts nothing")
	T.eq(card.rows[2].cast, nil, "nor the no row")
end)

local MAPS = { "cp_dustbowl", "pl_badwater", "koth_harvest" }

T.test("a vote of choices: a row an option, keyed F1 on, each picking it, with its count", function()
	local card = VoteHud.Active(State({ options = MAPS, counts = { 2, 0, 1 }, cast = 3 }), NOW)
	T.eq(card.yesNo, false, "no vote bar")
	T.eq(#card.rows, 3, "a row an option")
	T.eq(card.rows[1].text, "F1. cp_dustbowl", "CHudVote's F1. prefix")
	T.eq(card.rows[3].text, "F3. koth_harvest", "in order")
	T.eq(card.rows[2].cast.yes, false, "a pick is no yes")
	T.eq(card.rows[2].cast.choice, 2, "the second row picks the second")
	T.eq(card.rows[1].count, "2", "its count")
	T.eq(card.rows[3].lit, true, "the player's pick lit")
	T.eq(card.rows[1].lit, false, "the rest unlit")
end)

T.test("an option past the bound keys has no key, but still takes a click", function()
	local options = { "a", "b", "c", "d", "e" }
	local card = VoteHud.Active(State({ options = options, counts = { 0, 0, 0, 0, 0 } }), NOW)
	T.eq(card.rows[4].text, "F4. d", "F4 is bound")
	T.eq(card.rows[5].text, "e", "nothing binds a fifth")
	T.eq(card.rows[5].cast.choice, 5, "clicked, it picks the fifth")
end)

T.test("a player who may not vote sees the options without keys or clicks", function()
	local card = VoteHud.Active(State({ mine = false, options = MAPS, counts = { 0, 0, 0 } }), NOW)
	T.eq(card.rows[1].text, "cp_dustbowl", "no key")
	T.eq(card.rows[1].cast, nil, "no click")
end)

T.test("the panel is votehud.res's height for up to five rows, and grows for more", function()
	local function Tall(n)
		local options, counts = {}, {}
		for i = 1, n do options[i], counts[i] = "map" .. i, 0 end
		return VoteHud.Active(State({ options = options, counts = counts }), NOW).tall
	end
	T.eq(VoteHud.Active(State(), NOW).tall, VoteHud.ACTIVE_TALL, "yes/no")
	T.eq(Tall(3), VoteHud.ACTIVE_TALL, "three choices")
	T.eq(Tall(5), VoteHud.ACTIVE_TALL, "five, as many as LabelOption1..5")
	T.eq(Tall(6), VoteHud.ACTIVE_TALL + VoteHud.OPTION_TALL, "a sixth row grows it a row")
end)

T.test("each row sits a row under the last, from LabelOption1", function()
	T.eq(VoteHud.RowY(1), VoteHud.OPTION_Y, "the first")
	T.eq(VoteHud.RowY(3), VoteHud.OPTION_Y + 2 * VoteHud.OPTION_TALL, "the third")
end)

T.test("a passed vote: the yes icon, Vote Passed and the result", function()
	local panel = VoteHud.Result({ passed = true, text = "Changing the map to cp_dustbowl" })
	T.eq(panel.icon, VoteHud.YES_ICON, "PassedIcon")
	T.eq(panel.title, "Vote Passed", "#GameUI_vote_passed")
	T.eq(panel.passed, true, "drawn as passed")
	T.eq(panel.text, "Changing the map to cp_dustbowl", "PassedResult")
end)

T.test("a failed vote: the no icon, Vote Failed and why", function()
	local panel = VoteHud.Result({ passed = false, text = Vote.FAILED_QUORUM })
	T.eq(panel.icon, VoteHud.NO_ICON, "FailedIcon")
	T.eq(panel.title, "Vote Failed", "#GameUI_vote_failed")
	T.eq(panel.passed, false, "drawn as failed")
	T.eq(panel.text, Vote.FAILED_QUORUM, "FailedReason")
end)

T.test("the result fades out over its last moments", function()
	T.eq(VoteHud.ResultAlpha(NOW, NOW + VoteHud.RESULT_SECONDS), 1, "whole at first")
	T.eq(VoteHud.ResultAlpha(NOW, NOW + VoteHud.RESULT_FADE / 2), 0.5, "half way through the fade")
	T.eq(VoteHud.ResultAlpha(NOW, NOW - 1), 0, "gone")
end)

T.finish()
