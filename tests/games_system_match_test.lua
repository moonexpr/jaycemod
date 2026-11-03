-- games.system.match: what the game is running, asked of the systems that
-- subscribe, each through its own transaction, so a broken one breaks nothing
-- else.
local T = dofile("tests/harness.lua")
local Match = system.match
local Transaction = transaction

local function New()
	local told = {}
	local match = Match.New(function(name, err) told[#told + 1] = { name = name, err = err } end)
	return match, told
end

T.test("a transaction commits with the subscribers that say they are running", function()
	local match = New()
	match:Subscribe("war", function() return true end)
	match:Subscribe("arena", function() return false end)
	local tx = match:Running()
	T.eq(tx:State(), Transaction.COMMITTED)
	T.eq(tx:Value().war, true, "running")
	T.eq(tx:Value().arena, nil, "not running")
end)

T.test("a system that never subscribed, as one that failed to load, is simply not running", function()
	local match, told = New()
	T.eq(match:Running():State(), Transaction.COMMITTED)
	T.eq(match:IsRunning("war"), false)
	T.eq(#told, 0, "nothing is wrong")
end)

T.test("a subscriber that breaks is not running, is reported, and leaves the others their answers", function()
	local match, told = New()
	match:Subscribe("broken", function() error("the war's table is gone", 0) end)
	match:Subscribe("war", function() return true end)
	local tx = match:Running()
	T.eq(tx:State(), Transaction.COMMITTED, "the match's own transaction stands")
	T.eq(tx:Value().broken, nil)
	T.eq(tx:Value().war, true, "the next subscriber still answers")
	T.eq(#told, 1)
	T.eq(told[1].name, "broken")
	T.eq(told[1].err, "the war's table is gone")
end)

T.test("a subscriber that goes on breaking is reported once an error", function()
	local match, told = New()
	local message = "first"
	match:Subscribe("broken", function() error(message, 0) end)
	match:Running()
	match:Running()
	T.eq(#told, 1, "the same error, asked again")
	message = "second"
	match:Running()
	T.eq(#told, 2, "another error")
end)

T.test("a subscriber that declines has no answer and no bug", function()
	local match, told = New()
	match:Subscribe("war", function() Transaction.Refuse("not ready", "still loading") end)
	T.eq(match:IsRunning("war"), false)
	T.eq(#told, 0)
end)

T.test("a name subscribed again replaces its subscriber, as a reload does", function()
	local match = New()
	match:Subscribe("war", function() return false end)
	match:Subscribe("war", function() return true end)
	T.eq(match:IsRunning("war"), true)
end)

T.finish()
