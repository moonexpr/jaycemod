-- nextsoldier.locomotion: a soldier falls as a player falls, but a drop it
-- would land from at a speed that kills a player (nextsoldier.body.noise's
-- FATAL_FALL_SPEED) it rappels: it comes down no faster than RAPPEL_SPEED.
local T = dofile("tests/harness.lua")
local Locomotion = nextsoldier.locomotion
local Noise = nextsoldier.body.noise

local GRAVITY = 600

T.test("a short drop is fallen as it is", function()
	T.eq(Locomotion.RappelDescent(0, 100, GRAVITY), 0, "off a ledge 100 up: no rappel")
	T.eq(Locomotion.RappelDescent(200, 50, GRAVITY), 200, "falling, near the floor: as it falls")
end)

T.test("a drop a player survives is fallen as a player falls it, however hard the landing", function()
	local hard = Noise.MAX_SAFE_FALL_SPEED ^ 2 / (2 * GRAVITY) + 1
	local speed, rappelling = Locomotion.RappelDescent(Noise.MAX_SAFE_FALL_SPEED, hard, GRAVITY)
	T.eq(speed, Noise.MAX_SAFE_FALL_SPEED, "past a safe fall, unbraked")
	T.eq(rappelling, false)
	T.eq(Locomotion.Rappels(hard, GRAVITY), false, "no rappel")
end)

T.test("a drop that would kill a player is rappelled at RAPPEL_SPEED", function()
	local deadly = Noise.FATAL_FALL_SPEED ^ 2 / (2 * GRAVITY) + 1
	T.eq(Locomotion.RappelDescent(Locomotion.RAPPEL_SPEED * 2, deadly, GRAVITY), Locomotion.RAPPEL_SPEED, "held to the rappel's speed")
	T.eq(Locomotion.RappelDescent(Locomotion.RAPPEL_SPEED / 2, deadly, GRAVITY), Locomotion.RAPPEL_SPEED / 2, "slower already: kept")
	T.eq(Locomotion.RappelDescent(800, 200, GRAVITY), Locomotion.RAPPEL_SPEED, "fast already, with far to go: braked")
end)

T.test("once rappelling, it keeps to RAPPEL_SPEED down to the floor", function()
	local deadly = Noise.FATAL_FALL_SPEED ^ 2 / (2 * GRAVITY) + 1
	local speed, rappelling = Locomotion.RappelDescent(Locomotion.RAPPEL_SPEED * 2, deadly, GRAVITY, false)
	T.eq(rappelling, true, "it starts")
	speed, rappelling = Locomotion.RappelDescent(Locomotion.RAPPEL_SPEED + 10, 20, GRAVITY, rappelling)
	T.eq(speed, Locomotion.RAPPEL_SPEED, "held near the floor too")
	T.eq(rappelling, true, "still")
	local _, falling = Locomotion.RappelDescent(200, 50, GRAVITY, false)
	T.eq(falling, false, "a short fall is no rappel")
end)

T.test("a rappel lands softly: RAPPEL_SPEED is no hard landing", function()
	T.eq(Locomotion.RAPPEL_SPEED < Noise.MIN_BOUNCE_SPEED, true, "quieter than a bounce")
end)

T.test("Rappels tells a drop that would kill a player", function()
	local safe = Noise.FATAL_FALL_SPEED ^ 2 / (2 * GRAVITY)
	T.eq(Locomotion.Rappels(safe - 1, GRAVITY), false, "one it survives")
	T.eq(Locomotion.Rappels(safe + 1, GRAVITY), true, "past it")
end)

T.test("the tuning is defined", function()
	T.defined(Locomotion.RAPPEL_SPEED, "RAPPEL_SPEED")
end)

T.test("a rappel's rope is tied where the soldier left the ground", function()
	local anchor = Locomotion.RappelAnchor({ x = 90, y = 0, z = -400 }, { x = 0, y = 0, z = 100 }, 72)
	T.eq(anchor.x, 0, "over the ledge")
	T.eq(anchor.y, 0)
	T.eq(anchor.z > 100, true, "above its surface")
end)

T.test("a soldier that never stood goes down a rope from a body's height above it", function()
	local anchor = Locomotion.RappelAnchor({ x = 90, y = 5, z = -400 }, nil, 72)
	T.eq(anchor.x, 90)
	T.eq(anchor.y, 5)
	T.eq(anchor.z, -328)
end)

T.test("a rappel's sounds are there to play", function()
	for _, name in ipairs({ "clip", "run", "land" }) do
		T.eq(#Noise.RAPPEL_SOUNDS[name] > 0, true, name)
	end
	T.defined(Noise.RAPPEL_RUN_EVERY, "RAPPEL_RUN_EVERY")
end)

T.finish()
