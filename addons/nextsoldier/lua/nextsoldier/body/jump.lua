-- The activity a body's jump plays, by what it holds and what its model has. The
-- families of model name theirs differently and have only their own: a TF2 model
-- ACT_MP_JUMP_<PHASE>_<SLOT>, by weapon slot and phase; a GMod player model
-- ACT_HL2MP_JUMP_<HOLD>, by hold type, one for going up and coming down, and no
-- plain one (empty hands jump as a SLAM's holder, as GMod's players do); an HL2
-- NPC's ACT_JUMP and ACT_GLIDE. So no model is named here: what a model has decides.
--
-- Candidates(hold, phase) -> the activities' names, best first.
-- Pick(hold, phase, has) -> the first has(name) answers true of, or nil: this
--   model has no jump.
local ipairs = ipairs
local upper = string.upper
module("nextsoldier.body.jump")

START, FLOAT, LAND = "START", "FLOAT", "LAND"

local PRIMARY, SECONDARY, MELEE = "PRIMARY", "SECONDARY", "MELEE"

-- A hold type's TF2 weapon slot; what is not here jumps as with a primary.
local SLOTS = {
	pistol = SECONDARY, revolver = SECONDARY, duel = SECONDARY,
	melee = MELEE, melee2 = MELEE, knife = MELEE, fist = MELEE, grenade = MELEE, slam = MELEE,
}

-- A hold type's name in a GMod player model's acts, where it is not its own.
local GMOD_HOLDS = { smg = "SMG1" }

local NPC_ACTS = { [START] = "ACT_JUMP", [FLOAT] = "ACT_GLIDE", [LAND] = "ACT_LAND" }

function Candidates(hold, phase)
	local slot = SLOTS[hold] or PRIMARY
	local names = { "ACT_MP_JUMP_" .. phase .. "_" .. slot }
	if slot ~= PRIMARY then names[#names + 1] = "ACT_MP_JUMP_" .. phase .. "_" .. PRIMARY end
	if phase ~= LAND then
		names[#names + 1] = "ACT_HL2MP_JUMP_" .. (GMOD_HOLDS[hold] or upper(hold))
		names[#names + 1] = "ACT_HL2MP_JUMP_SLAM"
	end
	names[#names + 1] = NPC_ACTS[phase]
	return names
end

function Pick(hold, phase, has)
	for _, name in ipairs(Candidates(hold, phase)) do
		if has(name) then return name end
	end
	return nil
end
