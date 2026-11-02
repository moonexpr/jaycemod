-- How a player's body moves: TF2's (the gamemode's standard, the operator's
-- rule: every player, bot and soldier moves as a TF2 player does) and
-- GMod's own (a Sandbox player's, kept for Sandbox mode, whose maps are
-- built for it). A body is { jumpSpeed, hullMin, hullMax, duckHullMin,
-- duckHullMax, view, duckView, stepHeight, convars }: the jump's upward
-- speed, the hulls standing and crouching ({ x, y, z } corners), the eyes'
-- height standing and crouching, a stair step, and the movement convars
-- (name -> value) the server runs with.
--
-- TF2's are tf_gamerules.cpp's g_TFViewVectors, tf_gamemovement.cpp's jump
-- (289, ducked or not) and movevars_shared.cpp's convars outside HL2 (gravity
-- 800, friction 4, stop speed 100); GMod's, player_default's and its engine's.
local tonumber = tonumber
module(...)

TF2 = {
	jumpSpeed = 289,
	hullMin = { x = -24, y = -24, z = 0 },
	hullMax = { x = 24, y = 24, z = 82 },
	duckHullMin = { x = -24, y = -24, z = 0 },
	duckHullMax = { x = 24, y = 24, z = 62 },
	view = 72,
	duckView = 45,
	stepHeight = 18,
	convars = { sv_gravity = "800", sv_friction = "4", sv_stopspeed = "100", sv_accelerate = "10", sv_airaccelerate = "10" },
}

GMOD = {
	jumpSpeed = 200,
	hullMin = { x = -16, y = -16, z = 0 },
	hullMax = { x = 16, y = 16, z = 72 },
	duckHullMin = { x = -16, y = -16, z = 0 },
	duckHullMax = { x = 16, y = 16, z = 36 },
	view = 64,
	duckView = 28,
	stepHeight = 18,
	convars = { sv_gravity = "600", sv_friction = "8", sv_stopspeed = "10", sv_accelerate = "10", sv_airaccelerate = "10" },
}

-- The body for the game: TF2's while its layer runs (WS.Active), else GMod's.
function For(active)
	return active and TF2 or GMOD
end

-- How high a crouch jump lifts the feet: the jump's apex (its speed squared
-- over twice the gravity) and, legs tucked in the air, the standing hull's
-- height over the crouching one's (gamemovement's FinishDuck).
function JumpReach(jumpSpeed, gravity, standHeight, duckHeight)
	return jumpSpeed * jumpSpeed / (2 * gravity) + standHeight - duckHeight
end

-- The box a walk is swept with: the body's own width (hullMin, hullMax:
-- { x, y, z } corners), from its feet to height (above the step it lifts the
-- sweep by, so stairs pass). A narrower sweep than the body passes lines its
-- shoulders catch on.
function Sweep(hullMin, hullMax, height)
	return { x = hullMin.x, y = hullMin.y, z = 0 }, { x = hullMax.x, y = hullMax.y, z = height }
end

-- A body's crouch jump at its own gravity: TF2's 72 (CTFBotLocomotion's
-- GetMaxJumpHeight), GMod's about 69.
function CrouchJump(body)
	return JumpReach(body.jumpSpeed, tonumber(body.convars.sv_gravity), body.hullMax.z, body.duckHullMax.z)
end
