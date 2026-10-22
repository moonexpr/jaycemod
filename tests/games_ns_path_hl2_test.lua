-- games.ns.path.hl2: the route cost of HL2's engine NPCs on a TF2
-- nav mesh: TF2's bot cost, minus every move the NPC's body cannot make.
local T = dofile("tests/harness.lua")
local Path = T.require("games.ns.path")
local HL2 = T.require("games.ns.path.hl2")
local TFBot = T.require("games.ns.path.tfbot")
local Teams = T.require("games.gameplay.teams")

local BOT = {
	entIndex = 7,
	now = 12,
	team = Teams.BLUE,
	route = TFBot.FASTEST_ROUTE,
	miniBoss = false,
	roundWon = false,
	winningTeam = Teams.UNASSIGNED,
}

local function Step(overrides)
	local step = {
		hasFrom = true,
		traversable = true,
		length = 0,
		centerDistance = 100,
		heightChange = 0,
		fromCostSoFar = 40,
		areaId = 3,
		spawnRoomTeam = Teams.UNASSIGNED,
		attributes = 0,
	}
	for k, v in pairs(overrides or {}) do step[k] = v end
	return step
end

T.test("the limits are the engine NPC's: one step up or down, no more", function()
	T.eq(HL2.LIMITS.stepHeight, 18, "CAI_BaseNPC::StepHeight")
	T.eq(HL2.LIMITS.jumpHeight, HL2.LIMITS.stepHeight, "no jumping")
	T.eq(HL2.LIMITS.deathDropHeight, HL2.LIMITS.stepHeight, "no dropping past a step")
end)

-- The AI war's soldiers are DrGBase NextBots now (NextBotGroundLocomotion):
-- an HL2 body that crouches and jumps (ws/sh_drg_soldier.lua) and drops as
-- far as DrGBase's DeathDropHeight, as off cp_steel's BLU spawn ledge (192).
T.defined(HL2.SOLDIER_JUMP_HEIGHT, "SOLDIER_JUMP_HEIGHT")
T.defined(HL2.SOLDIER_DROP_HEIGHT, "SOLDIER_DROP_HEIGHT")

T.test("the soldiers' limits: a step up, a jump, and a drop of up to SOLDIER_DROP_HEIGHT, rappelled past a safe fall", function()
	local limits = HL2.SOLDIER_LIMITS
	T.eq(limits.stepHeight, 18, "a step")
	T.eq(limits.jumpHeight, HL2.SOLDIER_JUMP_HEIGHT, "a jump")
	T.eq(limits.deathDropHeight, HL2.SOLDIER_DROP_HEIGHT, "as deep as it goes")
	T.eq(HL2.Cost(Step({ heightChange = -192 }), limits, BOT) ~= Path.IMPASSABLE, true, "off cp_steel's ledge")
	T.eq(HL2.Cost(Step({ heightChange = -400 }), limits, BOT) ~= Path.IMPASSABLE, true, "a deadly fall, rappelled")
	T.eq(HL2.Cost(Step({ heightChange = -(HL2.SOLDIER_DROP_HEIGHT + 1) }), limits, BOT), Path.IMPASSABLE, "deeper than it goes")
	T.eq(HL2.Cost(Step({ heightChange = limits.jumpHeight - 1 }), limits, BOT) ~= Path.IMPASSABLE, true, "a ledge it jumps")
	T.eq(HL2.Cost(Step({ heightChange = limits.jumpHeight }), limits, BOT), Path.IMPASSABLE, "a ledge past its jump")
end)

T.test("a soldier crouches and jumps through the areas a TF2 player would", function()
	local limits = HL2.SOLDIER_LIMITS
	local flat = HL2.Cost(Step(), limits, BOT)
	T.eq(HL2.Cost(Step({ attributes = HL2.NAV_MESH_CROUCH }), limits, BOT), flat, "crouch")
	T.eq(HL2.Cost(Step({ attributes = HL2.NAV_MESH_JUMP }), limits, BOT), flat, "jump")
end)

T.test("a soldier must crouch in an area a TF2 player crouches through", function()
	T.eq(HL2.MustCrouch(HL2.NAV_MESH_CROUCH), true, "crouch")
	T.eq(HL2.MustCrouch(HL2.NAV_MESH_CROUCH + 0x1000), true, "crouch, on stairs")
	T.eq(HL2.MustCrouch(HL2.NAV_MESH_JUMP), false, "jump")
	T.eq(HL2.MustCrouch(0), false, "open ground")
end)

T.test("flat ground costs what it costs a TF2 bot", function()
	T.eq(HL2.Cost(Step(), HL2.LIMITS, BOT), TFBot.Cost(Step(), HL2.LIMITS, BOT), "same")
	T.eq(HL2.Cost(Step({ hasFrom = false, attributes = HL2.NAV_MESH_CROUCH }), HL2.LIMITS, BOT), 0, "the first area is free")
end)

T.test("a climb or drop of a step height or more is a dead end", function()
	T.eq(HL2.Cost(Step({ heightChange = 17 }), HL2.LIMITS, BOT), 140, "a step up")
	T.eq(HL2.Cost(Step({ heightChange = 18 }), HL2.LIMITS, BOT), Path.IMPASSABLE, "a ledge up")
	T.eq(HL2.Cost(Step({ heightChange = -18 }), HL2.LIMITS, BOT), 140, "a step down")
	T.eq(HL2.Cost(Step({ heightChange = -19 }), HL2.LIMITS, BOT), Path.IMPASSABLE, "a ledge down")
end)

T.test("areas a TF2 player must crouch or jump through are dead ends", function()
	T.eq(HL2.Cost(Step({ attributes = HL2.NAV_MESH_CROUCH }), HL2.LIMITS, BOT), Path.IMPASSABLE, "crouch")
	T.eq(HL2.Cost(Step({ attributes = HL2.NAV_MESH_JUMP }), HL2.LIMITS, BOT), Path.IMPASSABLE, "jump")
	T.eq(HL2.Cost(Step({ attributes = 0x1000 }), HL2.LIMITS, BOT), 140, "stairs are fine")
end)

T.finish()
