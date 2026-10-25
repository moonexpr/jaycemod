-- The route cost of HL2's engine NPCs (the AI war's soldiers) on a TF2 nav
-- mesh: TF2's bot cost (foundation.wetsands.path.tfbot), minus every move their
-- body cannot make. The mesh was generated for TF2 players, who crouch and
-- jump; an engine NPC moving without an AI node graph does neither:
-- - it steps up at most StepHeight (CAI_BaseNPC::StepHeight, 18), and down
--   no further (CAI_MoveProbe::CheckStep finds no ground below a step and
--   calls the move blocked), with no jump links to take it further;
-- - it stands 72 tall (HULL_HUMAN), where a crouching TF2 player is 62, so
--   an area TF2 flags as crouch-only (NAV_MESH_CROUCH) is too low, and one
--   flagged jump-only (NAV_MESH_JUMP) cannot be crossed.
-- Its hull is narrower than a TF2 player's, so no area is too narrow.
-- Besides a step's usual fields it reads step.attributes (the area's
-- NAV_MESH_* flags).
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local band = bit.band
local Path = wetsands.path
local TFBot = require("foundation.wetsands.path.tfbot")
module(...)

-- nav.h's NavAttributeType
NAV_MESH_CROUCH = 0x00000001
NAV_MESH_JUMP = 0x00000002

local STEP_HEIGHT = 18
LIMITS = { stepHeight = STEP_HEIGHT, jumpHeight = STEP_HEIGHT, deathDropHeight = STEP_HEIGHT }

-- The AI war's soldiers, DrGBase NextBots now: the same body, but they go
-- down drops as deep as SOLDIER_DROP_HEIGHT, rappelling one deeper than a
-- safe fall (games.nextsoldier.rappel; cp_steel's BLU spawn is a ledge 192
-- above the yard, mvm_decoy's deeper), their DrGBase DeathDropHeight; the soldier
-- crouches and jumps (ws/sh_drg_soldier.lua). Its hull does not catch on a
-- low ceiling, so a crouch area only needs it to crouch; it jumps a ledge
-- lower than SOLDIER_JUMP_HEIGHT, an HL2 player's crouch jump.
SOLDIER_DROP_HEIGHT = 1000
SOLDIER_JUMP_HEIGHT = 56
SOLDIER_LIMITS = {
	stepHeight = STEP_HEIGHT,
	jumpHeight = SOLDIER_JUMP_HEIGHT,
	deathDropHeight = SOLDIER_DROP_HEIGHT,
	crouches = true,
}

-- Whether a walker within limits cannot cross an area of these NAV_MESH_*
-- attributes: a crouch area unless it crouches, a jump area unless it jumps.
local function Uncrossable(attributes, limits)
	if band(attributes, NAV_MESH_CROUCH) ~= 0 and not limits.crouches then return true end
	return band(attributes, NAV_MESH_JUMP) ~= 0 and limits.jumpHeight <= limits.stepHeight
end

-- Whether a walker in an area of these attributes must crouch there.
function MustCrouch(attributes)
	return band(attributes, NAV_MESH_CROUCH) ~= 0
end

function Cost(step, limits, bot)
	if step.hasFrom and Uncrossable(step.attributes, limits) then return Path.IMPASSABLE end
	return TFBot.Cost(step, limits, bot)
end

function Model(limits, bot)
	local model = TFBot.Model(limits, bot)
	model.attributeRule = true
	return model
end
