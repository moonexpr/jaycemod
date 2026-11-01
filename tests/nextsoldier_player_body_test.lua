-- nextsoldier.player_body: a soldier in a player's body, as TF2's
-- bots drive theirs (PlayerBody, PlayerLocomotion): where it is sent, where
-- it looks and what it shoots become the command a player's keys would
-- make, every tick.
local T = dofile("tests/harness.lua")
local Body = nextsoldier.player_body

for _, name in ipairs({ "TURN_RATE", "ARRIVE", "STUCK_SPEED", "STUCK_TIME", "CROUCH_JUMP_TIME", "FIRE_CONE", "MELEE_CONE", "USE_INTERVAL", "BACKOFF_TIME" }) do
	T.defined(Body[name], name)
end

local TICK = 0.015
local ORIGIN = { x = 0, y = 0, z = 0 }
local EAST, NORTH = { x = 1000, y = 0, z = 0 }, { x = 0, y = 1000, z = 0 }
local GUN = {
	automatic = true,
	melee = false,
	reach = 1500,
	clip = 30,
	reserve = 90,
}

local function Sense(fields)
	local sense = {
		pos = ORIGIN,
		eyePos = { x = 0, y = 0, z = 64 },
		eye = { pitch = 0, yaw = 0 },
		speed = 200,
		climb = 0,
		onGround = true,
		walk = false,
		fire = true,
		weapon = GUN,
	}
	for k, v in pairs(fields) do sense[k] = v end
	return sense
end

-- Commands for seconds of ticks, the eye following the body's own turns
-- and the clock running on; the last command.
local function Run(body, now, seconds, fields)
	local sense = Sense(fields)
	local cmd
	for i = 1, math.floor(seconds / TICK + 0.5) do
		cmd = body:Command(now + i * TICK, TICK, sense)
		sense.eye = { pitch = cmd.pitch, yaw = cmd.yaw }
	end
	return cmd, sense
end

T.test("a soldier sent somewhere moves straight at it, and stands once there", function()
	local body = Body.New()
	local cmd = body:Command(0, TICK, Sense({ target = NORTH }))
	T.near(cmd.moveYaw, 90, 1e-6, "north")
	T.eq(cmd.walk, false, "runs")
	cmd = body:Command(0, TICK, Sense({ target = NORTH, walk = true }))
	T.eq(cmd.walk, true, "walks at a walk")
	cmd = body:Command(0, TICK, Sense({ target = { x = Body.ARRIVE - 1, y = 0, z = 0 } }))
	T.eq(cmd.moveYaw, nil, "there: stands")
	cmd = body:Command(0, TICK, Sense({}))
	T.eq(cmd.moveYaw, nil, "sent nowhere: stands")
end)

T.test("it aims at its enemy whichever way it moves", function()
	local body = Body.New()
	local cmd = Run(body, 0, 1, { target = EAST, aim = NORTH, aimRadius = 16 })
	T.near(cmd.moveYaw, 0, 1e-6, "moving east")
	T.near(cmd.yaw, 90, 1e-6, "aiming north")
end)

T.test("with no enemy it faces where it is told to look, else the way it goes", function()
	local body = Body.New()
	T.near(Run(body, 0, 1, { look = NORTH }).yaw, 90, 1e-6, "standing, looking north")
	T.near(Run(body, 1, 1, { target = { x = -1000, y = 0, z = 0 } }).yaw, 180, 1e-6, "moving west, facing west")
end)

T.test("it turns no faster than its turn rate", function()
	local body = Body.New()
	local cmd = body:Command(0, TICK, Sense({ aim = { x = -1000, y = 1, z = 64 }, aimRadius = 16 }))
	T.near(math.abs(cmd.yaw), Body.TURN_RATE * TICK, 1e-6, "one tick's turn toward the enemy behind")
	T.near(cmd.pitch, 0, 1e-6, "level")
end)

T.test("it aims up and down at an enemy above or below its eyes", function()
	local body = Body.New()
	local cmd = Run(body, 0, 1, { aim = { x = 1000, y = 0, z = 64 + 1000 }, aimRadius = 16 })
	T.near(cmd.pitch, -45, 1e-6, "up is negative pitch, as Source's")
end)

T.test("it fires only once its aim is on the enemy, and not when told to hold", function()
	local body = Body.New()
	local cmd = body:Command(0, TICK, Sense({ aim = NORTH, aimRadius = 16 }))
	T.eq(cmd.attack, false, "still turning")
	cmd = Run(body, 0, 1, { aim = NORTH, aimRadius = 16 })
	T.eq(cmd.attack, true, "on target")
	cmd = Run(body, 1, 0.1, { aim = NORTH, aimRadius = 16, fire = false })
	T.eq(cmd.attack, false, "held")
end)

T.test("a semi-automatic's trigger is pressed again for each shot; an automatic's held", function()
	local semi = {
		automatic = false,
		melee = false,
		reach = 750,
		clip = 18,
		reserve = 150,
	}
	local body = Body.New()
	local sense = Sense({ aim = EAST, aimRadius = 16, weapon = semi })
	local a = body:Command(0, TICK, sense).attack
	local b = body:Command(TICK, TICK, sense).attack
	local c = body:Command(2 * TICK, TICK, sense).attack
	T.eq(a, true, "pressed")
	T.eq(b, false, "released")
	T.eq(c, true, "pressed again")
	body = Body.New()
	sense.weapon = GUN
	T.eq(body:Command(0, TICK, sense).attack and body:Command(TICK, TICK, sense).attack, true, "held")
end)

T.test("an empty gun is reloaded, not fired", function()
	local empty = {
		automatic = true,
		melee = false,
		reach = 1500,
		clip = 0,
		reserve = 90,
	}
	local cmd = Body.New():Command(0, TICK, Sense({ aim = EAST, aimRadius = 16, weapon = empty }))
	T.eq(cmd.attack, false, "no shot")
	T.eq(cmd.reload, true, "reloads")
	empty.reserve = 0
	cmd = Body.New():Command(0, TICK, Sense({ aim = EAST, aimRadius = 16, weapon = empty }))
	T.eq(cmd.reload, false, "nothing to reload with")
end)

T.test("a melee weapon strikes only within its reach", function()
	local crowbar = {
		automatic = true,
		melee = true,
		reach = 64,
		clip = -1,
		reserve = 0,
	}
	local near, far = { x = 40, y = 0, z = 64 }, { x = 200, y = 0, z = 64 }
	T.eq(Body.New():Command(0, TICK, Sense({ aim = near, aimRadius = 16, weapon = crowbar })).attack, true, "in reach")
	T.eq(Body.New():Command(0, TICK, Sense({ aim = far, aimRadius = 16, weapon = crowbar })).attack, false, "out of reach")
end)

T.test("stuck while trying to move, it crouch-jumps once, then waits to be stuck again", function()
	local body = Body.New()
	local stuck = { target = EAST, speed = 0 }
	local cmd = Run(body, 0, Body.STUCK_TIME - 0.1, stuck)
	T.eq(cmd.jump, false, "not stuck long enough")
	cmd = Run(body, Body.STUCK_TIME - 0.1, 0.1 + TICK, stuck)
	T.eq(cmd.jump, true, "jumps")
	cmd = body:Command(Body.STUCK_TIME + 2 * TICK, TICK, Sense({ target = EAST, speed = 0, onGround = false }))
	T.eq(cmd.jump, false, "the jump is let go")
	T.eq(cmd.duck, true, "ducks in the air: a crouch jump")
	cmd = body:Command(Body.STUCK_TIME + Body.CROUCH_JUMP_TIME + 0.1, TICK, Sense({ target = EAST, speed = 0 }))
	T.eq(cmd.duck, false, "stands again on landing")
	T.eq(cmd.jump, false, "and waits to be stuck again")
	T.eq(Run(Body.New(), 0, Body.STUCK_TIME + 0.1, { target = EAST }).jump, false, "a soldier on the move never jumps")
	T.eq(Run(Body.New(), 0, Body.STUCK_TIME + 0.1, { speed = 0 }).jump, false, "nor one standing by choice")
end)

T.test("it ducks where the nav mesh says crouch, and jumps once where it says jump", function()
	local body = Body.New()
	T.eq(body:Command(0, TICK, Sense({ target = EAST, crouchArea = true })).duck, true, "crouch area")
	T.eq(body:Command(TICK, TICK, Sense({ target = EAST, jumpArea = true })).jump, true, "jump area")
	T.eq(body:Command(2 * TICK, TICK, Sense({ target = EAST, jumpArea = true })).jump, false, "once, not held")
	T.eq(body:Command(3 * TICK, TICK, Sense({ target = EAST })).jump, false, "left it")
	T.eq(body:Command(4 * TICK, TICK, Sense({ target = EAST, jumpArea = true })).jump, true, "a jump area again")
end)

T.test("sent nowhere, it closes on an enemy past its weapon's chase range, backs off inside its avoid range, holds between", function()
	local ranges = { chase = 1000, avoid = 750 }
	local function Engage(x)
		return Body.New():Command(0, TICK, Sense({
			aim = { x = x, y = 0, z = 64 },
			aimRadius = 16,
			chase = ranges.chase,
			avoid = ranges.avoid,
		}))
	end
	T.near(Engage(ranges.chase + 100).moveYaw, 0, 1e-6, "closes in")
	T.near(math.abs(Engage(ranges.avoid - 100).moveYaw), 180, 1e-6, "backs off")
	T.eq(Engage((ranges.chase + ranges.avoid) / 2).moveYaw, nil, "holds")
	local sent = Body.New():Command(0, TICK, Sense({ target = NORTH, aim = { x = 5000, y = 0, z = 64 }, aimRadius = 16, chase = ranges.chase, avoid = ranges.avoid }))
	T.near(sent.moveYaw, 90, 1e-6, "sent somewhere, it goes there whatever its enemy")
	T.eq(Body.New():Command(0, TICK, Sense({ aim = { x = 5000, y = 0, z = 64 }, aimRadius = 16 })).moveYaw, nil, "no ranges: it stands")
end)

T.test("a low obstacle ahead is jumped, one at head height ducked under, a door ahead used", function()
	local low = Body.New():Command(0, TICK, Sense({ target = EAST, lowBlocked = true }))
	T.eq(low.jump, true, "jumps the low obstacle")
	local head = Body.New():Command(0, TICK, Sense({ target = EAST, headBlocked = true }))
	T.eq(head.duck, true, "ducks under the high one")
	T.eq(head.jump, false, "and does not jump into it")
	local wall = Body.New():Command(0, TICK, Sense({ target = EAST, lowBlocked = true, headBlocked = true }))
	T.eq(wall.jump or wall.duck, false, "a wall is neither: being stuck deals with it")
	T.eq(Body.New():Command(0, TICK, Sense({ lowBlocked = true })).jump, false, "standing still, nothing")
	local body = Body.New()
	local door = { x = 100, y = 0, z = 64 }
	local focused = { target = EAST, doorAhead = true, look = door, lookPriority = true }
	T.eq(body:Command(0, TICK, Sense(focused)).use, true, "uses the door while looking at it")
	T.eq(body:Command(TICK, TICK, Sense(focused)).use, false, "once, not held")
	T.eq(body:Command(Body.USE_INTERVAL - TICK, TICK, Sense(focused)).use, false, "not again while it swings")
	T.eq(body:Command(Body.USE_INTERVAL + TICK, TICK, Sense(focused)).use, true, "again when it stayed shut")
end)

T.test("door focus takes priority over an enemy until the body can use it", function()
	local body = Body.New()
	local door = { x = 0, y = 1000, z = 64 }
	local fields = {
		target = EAST,
		doorAhead = true,
		look = door,
		lookPriority = true,
		aim = EAST,
		aimRadius = 16,
	}
	local first = body:Command(0, TICK, Sense(fields))
	T.eq(first.use, false, "does not use before turning")
	T.eq(first.yaw > 0, true, "turns toward the door instead of the enemy")
	fields.eye = { pitch = 0, yaw = 90 }
	local command = body:Command(1, TICK, Sense(fields))
	T.near(command.yaw, 90, 1e-6, "looks directly at the door")
	T.eq(command.use, true, "uses once it is looking at the door")
end)

T.test("a hop its orders ask for is a jump toward its target", function()
	local body = Body.New()
	local cmd = body:Command(0, TICK, Sense({ target = EAST, hop = true }))
	T.eq(cmd.jump, true, "jumps")
	T.near(cmd.moveYaw, 0, 1e-6, "toward the target")
end)

-- Wedged: held up in the air between two slopes too steep to stand on (a
-- crevice beside arena_watchtower's logs), it cannot jump, having no
-- ground; it backs away from where it is sent for BACKOFF_TIME, then goes on.
local WEDGED = { target = EAST, onGround = false, speed = 0, climb = 0 }

T.test("held still in the air, it backs away from where it is sent", function()
	local body = Body.New()
	local cmd = Run(body, 0, Body.STUCK_TIME / 2, WEDGED)
	T.near(cmd.moveYaw, 0, 1e-6, "not yet: still toward it")
	cmd = Run(body, Body.STUCK_TIME / 2, Body.STUCK_TIME, WEDGED)
	T.near(math.abs(cmd.moveYaw), 180, 1e-6, "wedged: away")
	T.eq(cmd.jump, false, "no ground to jump from")
end)

T.test("having backed away, it goes on toward where it is sent", function()
	local body = Body.New()
	Run(body, 0, Body.STUCK_TIME * 1.5, WEDGED)
	local free = { target = EAST, onGround = true, speed = 200, climb = 0 }
	local cmd = Run(body, Body.STUCK_TIME * 1.5, Body.BACKOFF_TIME * 1.5, free)
	T.near(cmd.moveYaw, 0, 1e-6, "toward it again")
end)

T.test("falling straight down is not being wedged", function()
	local body = Body.New()
	local cmd = Run(body, 0, Body.STUCK_TIME * 2, { target = EAST, onGround = false, speed = 0, climb = -400 })
	T.near(cmd.moveYaw, 0, 1e-6, "toward it")
end)

T.finish()
