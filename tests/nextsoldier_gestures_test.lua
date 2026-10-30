-- nextsoldier.gestures: what a soldier's body says without words: the
-- gesture an occasion plays (by act name), how fast, how long before that
-- occasion moves it again, the celebration a squad wiped out earns, the
-- roll or throw of a grenade, and the canned death a crit plays.
local T = dofile("tests/harness.lua")
local Gestures = nextsoldier.gestures

local OCCASIONS = { Gestures.AGREE, Gestures.CELEBRATE, Gestures.GREET, Gestures.GRENADE_ROLL,
	Gestures.GRENADE_THROW, Gestures.SIGNAL_FORWARD, Gestures.SIGNAL_GROUP, Gestures.SIGNAL_HALT }

local function First(low) return low end
local function Last(_, high) return high end

T.test("the tuning is defined", function()
	T.defined(Gestures.FAST, "FAST")
	T.defined(Gestures.MODERATE_COOLDOWN, "MODERATE_COOLDOWN")
	T.defined(Gestures.LONG_COOLDOWN, "LONG_COOLDOWN")
	T.defined(Gestures.SQUAD_KILLS, "SQUAD_KILLS")
	T.defined(Gestures.DOWNTIME, "DOWNTIME")
	T.defined(Gestures.ROLL_RANGE, "ROLL_RANGE")
end)

T.test("every occasion plays a GMod player-model act by name", function()
	for _, occasion in ipairs(OCCASIONS) do
		local gesture = Gestures.GESTURES[occasion]
		T.eq(#gesture.acts > 0, true, occasion .. " has acts")
		for _, act in ipairs(gesture.acts) do T.eq(act:match("^ACT_") ~= nil, true, occasion .. ": " .. act) end
	end
end)

T.test("the occasions play at twice the speed, but for the halt", function()
	for _, occasion in ipairs(OCCASIONS) do
		local expected = occasion == Gestures.SIGNAL_HALT and 1 or Gestures.FAST
		T.eq(Gestures.GESTURES[occasion].rate, expected, occasion)
	end
	T.eq(Gestures.FAST, 2, "twice the speed")
end)

T.test("agreeing and celebrating cool down moderately, greeting longer, grenades and signals not at all", function()
	T.eq(Gestures.GESTURES[Gestures.AGREE].cooldown, Gestures.MODERATE_COOLDOWN)
	T.eq(Gestures.GESTURES[Gestures.CELEBRATE].cooldown, Gestures.MODERATE_COOLDOWN)
	T.eq(Gestures.GESTURES[Gestures.GREET].cooldown, Gestures.LONG_COOLDOWN)
	T.eq(Gestures.LONG_COOLDOWN > Gestures.MODERATE_COOLDOWN, true, "greeting cools down longer")
	for _, occasion in ipairs({ Gestures.GRENADE_ROLL, Gestures.GRENADE_THROW, Gestures.SIGNAL_FORWARD,
		Gestures.SIGNAL_GROUP, Gestures.SIGNAL_HALT }) do
		T.eq(Gestures.GESTURES[occasion].cooldown, 0, occasion)
	end
end)

T.test("an occasion's act is drawn from its acts by the random source", function()
	local acts = Gestures.GESTURES[Gestures.CELEBRATE].acts
	T.eq(Gestures.Memory():Play(Gestures.CELEBRATE, 0, First), acts[1])
	T.eq(Gestures.Memory():Play(Gestures.CELEBRATE, 0, Last), acts[#acts])
	local act, rate = Gestures.Memory():Play(Gestures.AGREE, 0, First)
	T.eq(act, "ACT_GMOD_GESTURE_AGREE")
	T.eq(rate, Gestures.FAST)
end)

T.test("an occasion does not move a soldier again until it cools down; others still do", function()
	local memory = Gestures.Memory()
	T.eq(memory:Play(Gestures.AGREE, 10, First) ~= nil, true, "first agree")
	T.eq(memory:Play(Gestures.AGREE, 10 + Gestures.MODERATE_COOLDOWN - 0.1, First), nil, "cooling down")
	T.eq(memory:Play(Gestures.GREET, 11, First) ~= nil, true, "another occasion is its own")
	T.eq(memory:Play(Gestures.AGREE, 10 + Gestures.MODERATE_COOLDOWN, First) ~= nil, true, "cooled down")
end)

T.test("each soldier's memory is its own", function()
	local a, b = Gestures.Memory(), Gestures.Memory()
	a:Play(Gestures.GREET, 0, First)
	T.eq(b:Play(Gestures.GREET, 0, First) ~= nil, true)
end)

T.test("grenades and signals play every time", function()
	local memory = Gestures.Memory()
	for _ = 1, 3 do
		T.eq(memory:Play(Gestures.GRENADE_THROW, 5, First), "ACT_GMOD_GESTURE_ITEM_THROW")
		T.eq(memory:Play(Gestures.SIGNAL_HALT, 5, First), "ACT_SIGNAL_HALT")
	end
end)

T.test("a taunt is played standing still; a gesture on the move", function()
	T.eq(Gestures.Still("ACT_GMOD_TAUNT_MUSCLE"), true)
	T.eq(Gestures.Still("ACT_GMOD_TAUNT_DANCE"), true)
	T.eq(Gestures.Still("ACT_GMOD_GESTURE_AGREE"), false)
	T.eq(Gestures.Still("ACT_SIGNAL_FORWARD"), false)
end)

T.test("an unknown occasion is our bug", function()
	T.eq(pcall(Gestures.Memory().Play, Gestures.Memory(), "shrug", 0, First), false)
end)

T.test("a grenade near is rolled, one farther thrown", function()
	T.eq(Gestures.Throw(Gestures.ROLL_RANGE), Gestures.GRENADE_ROLL, "at the roll range")
	T.eq(Gestures.Throw(Gestures.ROLL_RANGE + 1), Gestures.GRENADE_THROW)
	T.eq(Gestures.GESTURES[Gestures.GRENADE_ROLL].acts[1], "ACT_GMOD_GESTURE_ITEM_DROP")
end)

-- A squad wiped out: SQUAD_KILLS kills in one fight, then DOWNTIME of calm.
local function Kills(memory, count, from)
	for i = 1, count do memory:Killed(from + i) end
	return from + count
end

T.test("a soldier that wiped out a squad celebrates once calm DOWNTIME after its last kill", function()
	local memory = Gestures.Memory()
	local last = Kills(memory, Gestures.SQUAD_KILLS, 0)
	T.eq(memory:Calm(last + Gestures.DOWNTIME - 0.1), false, "not calm long enough")
	T.eq(memory:Calm(last + Gestures.DOWNTIME), true, "calm: celebrates")
	T.eq(memory:Calm(last + Gestures.DOWNTIME + 1), false, "once")
end)

T.test("fewer kills than a squad earn nothing, and the fight's count ends with the calm", function()
	local memory = Gestures.Memory()
	local last = Kills(memory, Gestures.SQUAD_KILLS - 1, 0)
	T.eq(memory:Calm(last + Gestures.DOWNTIME), false, "too few")
	last = Kills(memory, 1, last + Gestures.DOWNTIME + 10)
	T.eq(memory:Calm(last + Gestures.DOWNTIME), false, "the last fight's kills do not carry over")
end)

T.test("a kill while the soldier is calming down keeps the fight going", function()
	local memory = Gestures.Memory()
	local last = Kills(memory, Gestures.SQUAD_KILLS - 1, 0)
	T.eq(memory:Calm(last + 1), false)
	last = Kills(memory, 1, last + 2)
	T.eq(memory:Calm(last + Gestures.DOWNTIME), true, "the kills add up")
end)

T.test("a crit plays one of the player model's four canned deaths; any other death none", function()
	T.eq(#Gestures.DEATHS, 4)
	for i, name in ipairs(Gestures.DEATHS) do T.eq(name, string.format("death_%02d", i)) end
	T.eq(Gestures.Death(true, First), "death_01")
	T.eq(Gestures.Death(true, Last), "death_04")
	T.eq(Gestures.Death(false, First), nil)
end)

T.finish()
