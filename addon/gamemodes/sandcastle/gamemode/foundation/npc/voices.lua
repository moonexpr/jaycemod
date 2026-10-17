-- The pain and death sounds of the AI war's soldiers, by the model they
-- wear (a kit may change it: Alyx the hero, the Combine's support in the
-- metrocops' model), from HL2's own sounds, every one found in the game's
-- files. DrGBase plays the deaths (its nextbots' OnDeathSounds); the soldier
-- plays a hit's grunt or cry (Feedback) and a hurtful fall's cry itself
-- (ws/sh_drg_soldier.lua). A voice is { name (what the speech rules call
-- it: foundation.aiwar.speech), grunt, pain, death, fall = { path... } }.
local format, ipairs, lower, match = string.format, ipairs, string.lower, string.match
module(...)

local function Numbered(pattern, numbers)
	local list = {}
	for i, n in ipairs(numbers) do list[i] = format(pattern, n) end
	return list
end

-- A rebel's sharpest cries of pain stand for its death: HL2's citizens have
-- no death lines of their own.
-- A human's fall that hurts is the HL2 player's.
local FALL = { "player/pl_fallpain1.wav", "player/pl_fallpain3.wav" }

local MALE = {
	name = "male",
	grunt = Numbered("vo/npc/male01/pain0%d.wav", { 1, 2, 3 }),
	pain = Numbered("vo/npc/male01/pain0%d.wav", { 1, 2, 3, 4, 5, 6 }),
	death = Numbered("vo/npc/male01/pain0%d.wav", { 7, 8, 9 }),
	fall = FALL,
}
local FEMALE = {
	name = "female",
	grunt = Numbered("vo/npc/female01/pain0%d.wav", { 1, 2, 3 }),
	pain = Numbered("vo/npc/female01/pain0%d.wav", { 1, 2, 3, 4, 5, 6 }),
	death = Numbered("vo/npc/female01/pain0%d.wav", { 7, 8, 9 }),
	fall = FALL,
}
local ALYX = {
	name = "alyx",
	grunt = Numbered("vo/npc/alyx/hurt0%d.wav", { 4, 5 }),
	pain = Numbered("vo/npc/alyx/hurt0%d.wav", { 4, 5, 6, 8 }),
	death = { "vo/npc/alyx/uggh01.wav", "vo/npc/alyx/uggh02.wav", "vo/npc/alyx/gasp02.wav", "vo/npc/alyx/gasp03.wav" },
	fall = FALL,
}
-- The Combine's and the metrocops' cries are all short: a grunt is any.
local COMBINE = {
	name = "combine",
	grunt = Numbered("npc/combine_soldier/pain%d.wav", { 1, 2, 3 }),
	pain = Numbered("npc/combine_soldier/pain%d.wav", { 1, 2, 3 }),
	death = Numbered("npc/combine_soldier/die%d.wav", { 1, 2, 3 }),
	fall = Numbered("npc/combine_soldier/pain%d.wav", { 1, 2, 3 }),
}
local METROCOP = {
	name = "metrocop",
	grunt = Numbered("npc/metropolice/pain%d.wav", { 1, 2, 3, 4 }),
	pain = Numbered("npc/metropolice/pain%d.wav", { 1, 2, 3, 4 }),
	death = Numbered("npc/metropolice/die%d.wav", { 1, 2, 3, 4 }),
	fall = Numbered("npc/metropolice/pain%d.wav", { 1, 2, 3, 4 }),
}
-- HL2's vortigaunt has one cry of pain, and no death line.
local VORTIGAUNT = {
	name = "vortigaunt",
	grunt = { "npc/vort/vort_pain3.wav" },
	pain = { "npc/vort/vort_pain3.wav" },
	death = { "npc/vort/vort_pain3.wav" },
	fall = { "npc/vort/vort_pain3.wav" },
}

-- Model path patterns, in order, to their voice.
local BY_MODEL = {
	{ "^models/player/group0%d/male_", MALE },
	{ "^models/player/group0%d/female_", FEMALE },
	{ "^models/player/alyx%.mdl$", ALYX },
	{ "^models/player/combine_", COMBINE },
	{ "^models/player/police", METROCOP },
	{ "^models/vortigaunt", VORTIGAUNT },
}

-- A hit of this share of a soldier's most health or more is a cry of pain,
-- a lighter one a grunt; a soldier makes neither again for FEEDBACK_COOLDOWN.
PAIN_SHARE = 0.25
FEEDBACK_COOLDOWN = 0.5

-- Which of its voice's lists a hit of damage on a soldier of maxHealth
-- plays: "pain" or "grunt".
function Feedback(damage, maxHealth)
	return damage >= maxHealth * PAIN_SHARE and "pain" or "grunt"
end

-- The voice of a soldier wearing model, or nil for a model the war does not
-- dress its soldiers in.
function For(model)
	local path = lower(model)
	for _, entry in ipairs(BY_MODEL) do
		if match(path, entry[1]) then return entry[2] end
	end
	return nil
end
