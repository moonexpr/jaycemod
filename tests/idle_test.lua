-- foundation.idle: an empty server's countdown to being idle, called off by
-- a player joining.
local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_actor.lua")
local Idle = T.require("foundation.idle")

local DELAY = 300
local STEP = 1

local function Watch()
	local clock = Fake.Clock(0)
	return Idle.New(clock, DELAY), clock
end

T.test("a server empty for the delay goes idle, once", function()
	local watch, clock = Watch()
	T.eq(watch:Update(0), nil, "emptied: the countdown starts")
	T.eq(watch:IsIdle(), false, "not idle yet")
	clock:Advance(DELAY)
	T.eq(watch:Update(0), nil, "at the delay: still counting")
	clock:Advance(STEP)
	T.eq(watch:Update(0), Idle.IDLE, "past it: idle")
	T.eq(watch:IsIdle(), true, "idle")
	clock:Advance(DELAY * 2)
	T.eq(watch:Update(0), nil, "idle is said once")
end)

T.test("a player joining calls the countdown off; the next emptying counts afresh", function()
	local watch, clock = Watch()
	watch:Update(0)
	clock:Advance(DELAY - STEP)
	T.eq(watch:Update(1), nil, "a player joins before the delay")
	clock:Advance(STEP * 2)
	T.eq(watch:Update(1), nil, "with a player, never idle")
	T.eq(watch:Update(0), nil, "empty again: counting from now")
	clock:Advance(DELAY - STEP)
	T.eq(watch:Update(0), nil, "not the old countdown's end")
	clock:Advance(STEP * 2)
	T.eq(watch:Update(0), Idle.IDLE, "the new one's")
end)

T.test("a player joining an idle server makes it active, and it can go idle again", function()
	local watch, clock = Watch()
	watch:Update(0)
	clock:Advance(DELAY + STEP)
	watch:Update(0)
	T.eq(watch:Update(2), Idle.ACTIVE, "players joined: active")
	T.eq(watch:IsIdle(), false, "no longer idle")
	T.eq(watch:Update(2), nil, "active is said once")
	watch:Update(0)
	clock:Advance(DELAY + STEP)
	T.eq(watch:Update(0), Idle.IDLE, "idle again")
end)

T.test("a server with players never idles", function()
	local watch, clock = Watch()
	for _ = 1, 3 do
		clock:Advance(DELAY)
		T.eq(watch:Update(1), nil, "busy")
	end
	T.eq(watch:IsIdle(), false, "not idle")
end)

T.finish()
