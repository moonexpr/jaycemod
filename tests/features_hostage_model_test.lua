-- The hostage rescue rules (features.hostage.model): CS:S's hostage rescue
-- as a value. Hostages are held, follow a rescuer, are rescued at a zone or
-- are killed; the rescuers win once none is left unresolved and at least half
-- were rescued, and otherwise the round runs on to the other side's win by
-- time or elimination.
local T = dofile("tests/harness.lua")
local Hostage = T.require("features.hostage.model")

local function Refused(fn, ...)
	local ok, err = pcall(fn, ...)
	if ok then error("expected a refusal", 2) end
	return tostring(err)
end

local function Round(n)
	local ids = {}
	for i = 1, n do ids[i] = "h" .. i end
	return Hostage.New(ids)
end

T.test("a round starts with every hostage held and no outcome", function()
	local round = Round(4)
	T.eq(round:Total(), 4, "total")
	T.eq(round:Unresolved(), 4, "unresolved")
	T.eq(round:Rescued(), 0, "rescued")
	T.eq(round:Killed(), 0, "killed")
	T.eq(round:StateOf("h1"), Hostage.HELD, "state")
	T.eq(round:Outcome(), nil, "outcome")
end)

T.test("a round needs hostages, each named once", function()
	Refused(Hostage.New, {})
	Refused(Hostage.New, { "a", "a" })
	Refused(Hostage.New, { "a", 7 })
end)

T.test("a held hostage follows whoever uses it, and is rescued from following", function()
	local round = Round(1):Follow("h1", "ann")
	T.eq(round:StateOf("h1"), Hostage.FOLLOWING, "following")
	T.eq(round:RescuerOf("h1"), "ann", "its rescuer")
	round = round:Rescue("h1")
	T.eq(round:StateOf("h1"), Hostage.RESCUED, "rescued")
	T.eq(round:RescuerOf("h1"), nil, "no rescuer once rescued")
end)

T.test("a value never changes: each move returns a new round", function()
	local before = Round(2)
	local after = before:Follow("h1", "ann")
	T.eq(before:StateOf("h1"), Hostage.HELD, "the old round")
	T.eq(after:StateOf("h1"), Hostage.FOLLOWING, "the new round")
end)

T.test("only a held hostage can be taken, only a following one rescued or let go", function()
	local following = Round(2):Follow("h1", "ann")
	Refused(following.Follow, following, "h1", "bob")
	local held = Round(2)
	Refused(held.Rescue, held, "h1")
	Refused(held.Release, held, "h1")
	local done = following:Rescue("h1")
	Refused(done.Follow, done, "h1", "bob")
	Refused(done.Rescue, done, "h1")
end)

T.test("an unknown hostage is the caller's mistake", function()
	local round = Round(1)
	Refused(round.Follow, round, "nobody", "ann")
	Refused(round.Kill, round, "nobody")
	Refused(round.StateOf, round, "nobody")
end)

T.test("a rescuer who dies or leaves drops every hostage following them", function()
	local round = Round(3):Follow("h1", "ann"):Follow("h2", "ann"):Follow("h3", "bob")
	round = round:ReleaseFrom("ann")
	T.eq(round:StateOf("h1"), Hostage.HELD, "h1")
	T.eq(round:StateOf("h2"), Hostage.HELD, "h2")
	T.eq(round:StateOf("h3"), Hostage.FOLLOWING, "bob keeps h3")
	T.eq(round:ReleaseFrom("nobody"):Unresolved(), 3, "releasing a stranger changes nothing")
end)

T.test("a hostage can be killed held or following, once", function()
	local round = Round(2):Follow("h1", "ann")
	round = round:Kill("h1"):Kill("h2")
	T.eq(round:Killed(), 2, "killed")
	T.eq(round:Unresolved(), 0, "unresolved")
	Refused(round.Kill, round, "h1")
	Refused(round.Follow, round, "h1", "ann")
end)

T.test("the rescuers win when none is unresolved and half or more were rescued", function()
	local round = Round(4)
	for _, id in ipairs({ "h1", "h2" }) do round = round:Follow(id, "ann"):Rescue(id) end
	T.eq(round:Outcome(), nil, "two are still unresolved")
	round = round:Kill("h3"):Kill("h4")
	T.eq(round:Outcome(), Hostage.RESCUED, "two of four is half")
end)

T.test("fewer than half rescued leaves the round running", function()
	local round = Round(4):Follow("h1", "ann"):Rescue("h1"):Kill("h2"):Kill("h3"):Kill("h4")
	T.eq(round:Unresolved(), 0, "nothing left to resolve")
	T.eq(round:Outcome(), nil, "one of four is not enough")
end)

T.test("a hostage still held keeps the round running however many were rescued", function()
	local round = Round(3):Follow("h1", "ann"):Rescue("h1"):Follow("h2", "ann"):Rescue("h2")
	T.eq(round:Outcome(), nil, "h3 is still held")
end)

T.finish()
