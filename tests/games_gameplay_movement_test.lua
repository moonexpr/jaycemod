-- games.gameplay.movement: TF2's player movement, the gamemode's standard,
-- and GMod's own for Sandbox; a crouch jump's reach from either.
local T = dofile("tests/harness.lua")
local Movement = gameplay.movement

-- TF2's own values, pinned: tf_gamerules.cpp's g_TFViewVectors,
-- tf_gamemovement.cpp's jump, movevars_shared.cpp's convars for a non-HL2 game.
T.test("TF2's body is TF2's", function()
	local tf2 = Movement.TF2
	T.eq(tf2.jumpSpeed, 289, "jump speed")
	T.eq(tf2.hullMin.x, -24, "hull min")
	T.eq(tf2.hullMax.x, 24, "hull max x")
	T.eq(tf2.hullMax.z, 82, "standing height")
	T.eq(tf2.duckHullMax.z, 62, "crouching height")
	T.eq(tf2.view, 72, "eye")
	T.eq(tf2.duckView, 45, "eye crouching")
	T.eq(tf2.stepHeight, 18, "step")
	T.eq(tf2.convars.sv_gravity, "800", "gravity")
	T.eq(tf2.convars.sv_friction, "4", "friction")
	T.eq(tf2.convars.sv_stopspeed, "100", "stop speed")
	T.eq(tf2.convars.sv_accelerate, "10", "accelerate")
	T.eq(tf2.convars.sv_airaccelerate, "10", "air accelerate")
end)

-- GMod's player_default and its engine's movement convars, pinned.
T.test("GMod's body is a Sandbox player's", function()
	local gmod = Movement.GMOD
	T.eq(gmod.jumpSpeed, 200, "jump power")
	T.eq(gmod.hullMax.z, 72, "standing height")
	T.eq(gmod.duckHullMax.z, 36, "crouching height")
	T.eq(gmod.convars.sv_gravity, "600", "gravity")
	T.eq(gmod.convars.sv_friction, "8", "friction")
end)

T.test("both bodies say the same things, so either can be applied", function()
	for key in pairs(Movement.TF2) do T.eq(Movement.GMOD[key] ~= nil, true, "GMod's " .. key) end
	for key in pairs(Movement.GMOD) do T.eq(Movement.TF2[key] ~= nil, true, "TF2's " .. key) end
	for name in pairs(Movement.TF2.convars) do T.eq(Movement.GMOD.convars[name] ~= nil, true, "GMod's " .. name) end
end)

-- The jump's apex (speed squared over twice the gravity) and the feet lifted
-- by the standing hull over the crouching one (FinishDuck in the air).
T.test("a TF2 crouch jump reaches 72, its bots' GetMaxJumpHeight", function()
	T.near(Movement.CrouchJump(Movement.TF2), 72, 0.5, "TF2")
	T.near(Movement.JumpReach(289, 800, 82, 62), Movement.CrouchJump(Movement.TF2), 1e-9, "from its parts")
end)

T.test("a crouch jump reaches higher on a lighter gravity, lower on a smaller jump", function()
	local sandbox = Movement.JumpReach(200, 600, 72, 36)
	T.near(sandbox, 200 * 200 / 1200 + 36, 1e-9, "GMod's player")
	T.near(Movement.CrouchJump(Movement.GMOD), sandbox, 1e-9, "GMod's body")
	T.eq(Movement.JumpReach(200, 800, 72, 36) < sandbox, true, "heavier")
	T.eq(Movement.JumpReach(150, 600, 72, 36) < sandbox, true, "a smaller jump")
end)

T.test("the TF2 layer moves as TF2, Sandbox as GMod", function()
	T.eq(Movement.For(true), Movement.TF2, "active")
	T.eq(Movement.For(false), Movement.GMOD, "Sandbox")
end)

T.finish()
