-- foundation.npc.path.hl2: the route cost of HL2's engine NPCs on a TF2
-- nav mesh: TF2's bot cost, minus every move the NPC's body cannot make.
local T = dofile("tests/harness.lua")
local Path = T.require("foundation.npc.path")
local HL2 = T.require("foundation.npc.path.hl2")
local TFBot = T.require("foundation.npc.path.tfbot")
local Teams = T.require("foundation.teams")

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
