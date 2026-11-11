-- nextsoldier.behavior.Responder: a brain with no chart, answering the yes-or-no
-- queries as it is set, as a soldier's brain is asked (sh_war_soldier's Ask).
local T = dofile ("tests/harness.lua")
local Behavior = nextsoldier.behavior
local StateChart = generator.state_chart
local YES, NO, UNDEFINED = StateChart.ANSWER_YES, StateChart.ANSWER_NO, StateChart.ANSWER_UNDEFINED

T.test ("every yes-or-no query is one a soldier asks", function ()
	local asked = {}
	for _, name in ipairs (Behavior.QUERIES) do asked [name] = true end
	T.eq (#Behavior.YES_NO_QUERIES > 0, true)
	for _, name in ipairs (Behavior.YES_NO_QUERIES) do T.eq (asked [name], true, name) end
end)

T.test ("a responder answers no until it is set", function ()
	local responder = Behavior.Responder ()
	for _, name in ipairs (Behavior.YES_NO_QUERIES) do
		T.eq (responder:Query (name), NO, name)
		T.eq (responder:Answers (name), false, name)
	end
end)

T.test ("a responder answers as it is set, each query apart", function ()
	local responder = Behavior.Responder ()
	responder:Set ("ShouldHurry", true)
	T.eq (responder:Query ("ShouldHurry"), YES)
	T.eq (responder:Answers ("ShouldHurry"), true)
	T.eq (responder:Query ("ShouldRetreat"), NO, "another query")
	responder:Set ("ShouldHurry", false)
	T.eq (responder:Query ("ShouldHurry"), NO, "set back")
end)

T.test ("a responder takes the query's arguments as a soldier asks it", function ()
	local responder = Behavior.Responder ()
	responder:Set ("ShouldAttack", true)
	T.eq (responder:Query ("ShouldAttack", {}), YES)
end)

T.test ("what is no yes-or-no question stays undefined", function ()
	T.eq (Behavior.Responder ():Query ("SelectMoreDangerousThreat", {}, {}), UNDEFINED)
end)

T.test ("a responder refuses a query no soldier asks", function ()
	local responder = Behavior.Responder ()
	local ok, err = pcall (responder.Set, responder, "ShouldDance", true)
	T.eq (ok, false)
	T.eq (tostring (err):find ("ShouldDance", 1, true) ~= nil, true, "names it")
end)

T.test ("a responder hears a soldier's events and does nothing", function ()
	T.eq (Behavior.Responder ():Event ("OnInjured", {}), nil)
end)

T.finish ()
