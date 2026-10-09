-- The route cost of HL2's engine NPCs (the AI war's soldiers) on a TF2 nav
-- mesh: TF2's bot cost (foundation.npc.path.tfbot), minus every move their
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
local band = bit.band
local Path = require("foundation.npc.path")
local TFBot = require("foundation.npc.path.tfbot")
module(...)

-- nav.h's NavAttributeType
NAV_MESH_CROUCH = 0x00000001
NAV_MESH_JUMP = 0x00000002
local UNCROSSABLE = NAV_MESH_CROUCH + NAV_MESH_JUMP

local STEP_HEIGHT = 18
LIMITS = { stepHeight = STEP_HEIGHT, jumpHeight = STEP_HEIGHT, deathDropHeight = STEP_HEIGHT }

-- The AI war's soldiers, DrGBase NextBots now: the same body, but
-- NextBotGroundLocomotion drops as far as DrGBase's DeathDropHeight
-- (cp_steel's BLU spawn is a ledge 192 above the yard).
DRGBASE_DEATH_DROP = 200
SOLDIER_LIMITS = { stepHeight = STEP_HEIGHT, jumpHeight = STEP_HEIGHT, deathDropHeight = DRGBASE_DEATH_DROP }

function Cost(step, limits, bot)
	if step.hasFrom and band(step.attributes, UNCROSSABLE) ~= 0 then return Path.IMPASSABLE end
	return TFBot.Cost(step, limits, bot)
end
