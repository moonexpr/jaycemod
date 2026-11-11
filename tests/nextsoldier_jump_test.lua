-- nextsoldier.body.jump: the activity a body's jump plays, by what it holds and
-- what its model has: a TF2 model, a GMod player model and an HL2 NPC's name them
-- differently, and each has only its own.
local T = dofile ("tests/harness.lua")
local Jump = nextsoldier.body.jump

-- As the models answer on the server (SelectWeightedSequence).
local function Model (...)
	local has = {}
	for _, name in ipairs ({ ... }) do has [name] = true end
	return function (name) return has [name] == true end
end

local TF2 = Model (
	"ACT_MP_JUMP_START_PRIMARY", "ACT_MP_JUMP_FLOAT_PRIMARY", "ACT_MP_JUMP_LAND_PRIMARY",
	"ACT_MP_JUMP_START_SECONDARY", "ACT_MP_JUMP_FLOAT_SECONDARY", "ACT_MP_JUMP_LAND_SECONDARY",
	"ACT_MP_JUMP_START_MELEE", "ACT_MP_JUMP_FLOAT_MELEE", "ACT_MP_JUMP_LAND_MELEE")
local GMOD = Model (
	"ACT_HL2MP_JUMP_AR2", "ACT_HL2MP_JUMP_SMG1", "ACT_HL2MP_JUMP_PISTOL", "ACT_HL2MP_JUMP_SHOTGUN",
	"ACT_HL2MP_JUMP_SLAM", "ACT_HL2MP_JUMP_MELEE", "ACT_LAND")
local NPC = Model ("ACT_JUMP", "ACT_GLIDE", "ACT_LAND")

T.test ("a TF2 model plays the jump of the slot its weapon is held as, each phase its own", function ()
	T.eq (Jump.Pick ("ar2", Jump.START, TF2),    "ACT_MP_JUMP_START_PRIMARY")
	T.eq (Jump.Pick ("ar2", Jump.FLOAT, TF2),    "ACT_MP_JUMP_FLOAT_PRIMARY")
	T.eq (Jump.Pick ("ar2", Jump.LAND, TF2),     "ACT_MP_JUMP_LAND_PRIMARY")
	T.eq (Jump.Pick ("pistol", Jump.FLOAT, TF2), "ACT_MP_JUMP_FLOAT_SECONDARY")
	T.eq (Jump.Pick ("melee", Jump.FLOAT, TF2),  "ACT_MP_JUMP_FLOAT_MELEE")
end)

T.test ("a TF2 model holding nothing it has a slot for jumps as with its primary", function ()
	T.eq (Jump.Pick ("normal", Jump.FLOAT, TF2),       "ACT_MP_JUMP_FLOAT_PRIMARY")
	T.eq (Jump.Pick ("no such hold", Jump.FLOAT, TF2), "ACT_MP_JUMP_FLOAT_PRIMARY")
end)

T.test ("a GMod player model plays its hold type's jump all the way up, and lands as any", function ()
	T.eq (Jump.Pick ("ar2", Jump.FLOAT, GMOD), "ACT_HL2MP_JUMP_AR2")
	T.eq (Jump.Pick ("ar2", Jump.START, GMOD), "ACT_HL2MP_JUMP_AR2")
	T.eq (Jump.Pick ("smg", Jump.FLOAT, GMOD), "ACT_HL2MP_JUMP_SMG1", "named as its other acts name it")
	T.eq (Jump.Pick ("pistol", Jump.FLOAT, GMOD), "ACT_HL2MP_JUMP_PISTOL")
	T.eq (Jump.Pick ("ar2", Jump.LAND, GMOD),     "ACT_LAND")
end)

T.test ("a GMod player model with empty hands jumps as GMod's own players do", function ()
	T.eq (Jump.Pick ("normal", Jump.FLOAT, GMOD),       "ACT_HL2MP_JUMP_SLAM")
	T.eq (Jump.Pick ("no such hold", Jump.FLOAT, GMOD), "ACT_HL2MP_JUMP_SLAM")
end)

T.test ("an HL2 NPC's model jumps, glides and lands whatever it holds", function ()
	T.eq (Jump.Pick ("ar2", Jump.START, NPC), "ACT_JUMP")
	T.eq (Jump.Pick ("ar2", Jump.FLOAT, NPC), "ACT_GLIDE")
	T.eq (Jump.Pick ("ar2", Jump.LAND, NPC),  "ACT_LAND")
end)

T.test ("a model with no jump has none picked, and keeps its usual animation", function ()
	T.eq (Jump.Pick ("ar2", Jump.FLOAT, Model ()), nil)
end)

T.finish ()
