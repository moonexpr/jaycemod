-- games.nextsoldier.rappel: a soldier going down a drop it would land from
-- faster than a safe fall (games.nextsoldier.noise's MAX_SAFE_FALL_SPEED)
-- rappels: it comes down no faster than RAPPEL_SPEED.
local T = dofile("tests/harness.lua")
local Rappel = nextsoldier.rappel
local Noise = nextsoldier.noise

local GRAVITY = 600

T.test("a short drop is fallen as it is", function()
	T.eq(Rappel.Descent(0, 100, GRAVITY), 0, "off a ledge 100 up: no rappel")
	T.eq(Rappel.Descent(200, 50, GRAVITY), 200, "falling, near the floor: as it falls")
end)

T.test("a drop it would land from faster than a safe fall is rappelled at RAPPEL_SPEED", function()
	local deadly = Noise.MAX_SAFE_FALL_SPEED ^ 2 / (2 * GRAVITY) + 1
	T.eq(Rappel.Descent(Rappel.RAPPEL_SPEED * 2, deadly, GRAVITY), Rappel.RAPPEL_SPEED, "held to the rappel's speed")
	T.eq(Rappel.Descent(Rappel.RAPPEL_SPEED / 2, deadly, GRAVITY), Rappel.RAPPEL_SPEED / 2, "slower already: kept")
	T.eq(Rappel.Descent(400, 200, GRAVITY), Rappel.RAPPEL_SPEED, "fast already, with far to go: braked")
end)

T.test("once rappelling, it keeps to RAPPEL_SPEED down to the floor", function()
	local deadly = Noise.MAX_SAFE_FALL_SPEED ^ 2 / (2 * GRAVITY) + 1
	local speed, rappelling = Rappel.Descent(Rappel.RAPPEL_SPEED * 2, deadly, GRAVITY, false)
	T.eq(rappelling, true, "it starts")
	speed, rappelling = Rappel.Descent(Rappel.RAPPEL_SPEED + 10, 20, GRAVITY, rappelling)
	T.eq(speed, Rappel.RAPPEL_SPEED, "held near the floor too")
	T.eq(rappelling, true, "still")
	local _, falling = Rappel.Descent(200, 50, GRAVITY, false)
	T.eq(falling, false, "a short fall is no rappel")
end)

T.test("a rappel lands softly: RAPPEL_SPEED is no hard landing", function()
	T.eq(Rappel.RAPPEL_SPEED < Noise.MIN_BOUNCE_SPEED, true, "quieter than a bounce")
end)

T.test("Rappels tells a drop deeper than a safe fall", function()
	local safe = Noise.MAX_SAFE_FALL_SPEED ^ 2 / (2 * GRAVITY)
	T.eq(Rappel.Rappels(safe - 1, GRAVITY), false, "within a safe fall")
	T.eq(Rappel.Rappels(safe + 1, GRAVITY), true, "past it")
end)

T.test("the tuning is defined", function()
	T.defined(Rappel.RAPPEL_SPEED, "RAPPEL_SPEED")
end)

T.finish()
