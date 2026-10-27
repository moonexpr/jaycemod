-- The pain and death sounds of the AI war's soldiers, by the model they
-- wear (a kit may change it: Alyx the hero, the Combine's support in the
-- metrocops' model), from HL2's own sounds, every one found in the game's
-- files. The soldier plays a hit's grunt or cry (Feedback), a hurtful
-- fall's cry and its death (Death: loud, then confirmed) itself
-- (ws/sh_drg_soldier.lua, ws/sv_voices.lua), as players wearing these
-- models do. A voice is { name, affiliation (what the speech
-- rules call it and its side: nextsoldier.speech), grunt, pain, death,
-- fall = { path... }, confirm = { path... } (a death's signature after its
-- cry, one of them; or nil), gear = { left, right = { path... } } (what
-- rattles as its wearer runs; or nil) }.
local format, ipairs, lower, match = string.format, ipairs, string.lower, string.match
module(...)

local function Numbered(pattern, numbers)
	local list = {}
	for i, n in ipairs(numbers) do list[i] = format(pattern, n) end
	return list
end

-- A rebel's sharpest cries of pain stand for its death: HL2's citizens have
-- no death lines of their own.
-- HL2's sides, a voice's affiliation: the speech rules answer by it first
-- (addons/responserules: scripts/responserules/<affiliation>.txt), so a
-- model of either side fits whichever team it fights for.
COMBINE, REBEL = "combine", "rebel"

-- A human's fall that hurts is the HL2 player's.
local FALL = { "player/pl_fallpain1.wav", "player/pl_fallpain3.wav" }

local MALE = {
	name = "male",
	affiliation = REBEL,
	grunt = Numbered("vo/npc/male01/pain0%d.wav", { 1, 2, 3 }),
	pain = Numbered("vo/npc/male01/pain0%d.wav", { 1, 2, 3, 4, 5, 6 }),
	death = Numbered("vo/npc/male01/pain0%d.wav", { 7, 8, 9 }),
	fall = FALL,
}
local FEMALE = {
	name = "female",
	affiliation = REBEL,
	grunt = Numbered("vo/npc/female01/pain0%d.wav", { 1, 2, 3 }),
	pain = Numbered("vo/npc/female01/pain0%d.wav", { 1, 2, 3, 4, 5, 6 }),
	death = Numbered("vo/npc/female01/pain0%d.wav", { 7, 8, 9 }),
	fall = FALL,
}
local ALYX = {
	name = "alyx",
	affiliation = REBEL,
	grunt = Numbered("vo/npc/alyx/hurt0%d.wav", { 4, 5 }),
	pain = Numbered("vo/npc/alyx/hurt0%d.wav", { 4, 5, 6, 8 }),
	death = { "vo/npc/alyx/uggh01.wav", "vo/npc/alyx/uggh02.wav", "vo/npc/alyx/gasp02.wav", "vo/npc/alyx/gasp03.wav" },
	fall = FALL,
}
-- HL2's Combine radio as its wearer dies: Overwatch's squelch and flatline
-- beeps, about three seconds (the metrocops' own death sounds, die1-3, are
-- the same recordings).
local RADIO = Numbered("npc/overwatch/radiovoice/die%d.wav", { 1, 2, 3 })

-- The Combine soldiers speak with Half-Life: Alyx's unused soldier voice
-- (the gamemode's content/sound/npc/combine_soldier, shadowing HL2's files
-- of the same names; credits.txt), which has a fourth cry.
-- The Combine's and the metrocops' cries are all short: a grunt is any. A
-- metrocop's death is the radio's flatline itself (HL2's), so nothing
-- confirms it.
local COMBINE_SOLDIER = {
	name = "combine",
	affiliation = COMBINE,
	grunt = Numbered("npc/combine_soldier/pain%d.wav", { 1, 2, 3, 4 }),
	pain = Numbered("npc/combine_soldier/pain%d.wav", { 1, 2, 3, 4 }),
	death = Numbered("npc/combine_soldier/die%d.wav", { 1, 2, 3 }),
	fall = Numbered("npc/combine_soldier/pain%d.wav", { 1, 2, 3, 4 }),
	confirm = RADIO,
	gear = { left = Numbered("npc/combine_soldier/gear%d.wav", { 1, 3, 5 }), right = Numbered("npc/combine_soldier/gear%d.wav", { 2, 4, 6 }) },
}
local METROCOP = {
	name = "metrocop",
	affiliation = COMBINE,
	grunt = Numbered("npc/metropolice/pain%d.wav", { 1, 2, 3, 4 }),
	pain = Numbered("npc/metropolice/pain%d.wav", { 1, 2, 3, 4 }),
	death = Numbered("npc/metropolice/die%d.wav", { 1, 2, 3, 4 }),
	fall = Numbered("npc/metropolice/pain%d.wav", { 1, 2, 3, 4 }),
	gear = { left = Numbered("npc/metropolice/gear%d.wav", { 1, 3, 5 }), right = Numbered("npc/metropolice/gear%d.wav", { 2, 4, 6 }) },
}
-- HL2's vortigaunt has one cry of pain, and no death line.
local VORTIGAUNT = {
	name = "vortigaunt",
	affiliation = REBEL,
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
	{ "^models/player/combine_", COMBINE_SOLDIER },
	{ "^models/player/police", METROCOP },
	{ "^models/vortigaunt", VORTIGAUNT },
}

-- A hit of this share of a soldier's most health or more is a cry of pain,
-- a lighter one a grunt; a soldier makes neither again for FEEDBACK_COOLDOWN.
PAIN_SHARE = 0.25
FEEDBACK_COOLDOWN = 0.5

-- A death carries across the fight (a TF2 death scream's SNDLVL_95), louder
-- than a grunt's SNDLVL_NORM; its confirmation follows once the cry is over
-- (the Combine's run to a second). A rebel's scream is bigger: its cry
-- played SCREAM_LAYERS times at once (no one sound plays louder than its
-- recording), carried farther, and a little deeper (pitch, 100 the
-- recording's).
DEATH_LEVEL = 95
DEATH_CONFIRM_DELAY = 1
SCREAM_LEVEL = 105
SCREAM_LAYERS = 2
SCREAM_PITCH = 92

-- What a death of voice plays: { sound, level, pitch, delay (seconds) }s,
-- its cry first (random(n): 1..n picks it; a rebel's, layered), then its
-- confirmation, if it has one.
function Death(voice, random)
	local cry = voice.death[random(#voice.death)]
	if voice.affiliation == REBEL then
		local sounds = {}
		for i = 1, SCREAM_LAYERS do sounds[i] = { sound = cry, level = SCREAM_LEVEL, pitch = SCREAM_PITCH, delay = 0 } end
		return sounds
	end
	local sounds = { { sound = cry, level = DEATH_LEVEL, pitch = 100, delay = 0 } }
	if voice.confirm then
		sounds[2] = { sound = voice.confirm[random(#voice.confirm)], level = DEATH_LEVEL, pitch = 100, delay = DEATH_CONFIRM_DELAY }
	end
	return sounds
end

-- A Combine soldier's gear rattles with each running step, as HL2's
-- (NPC_CombineS.RunFootstepLeft/Right, NPC_MetroPolice's: by foot, pitch 95
-- to 105), but quietly: GEAR_VOLUME of the recording against HL2's 0.75, at
-- GEAR_LEVEL, carrying less than the step itself (SNDLVL_NORM).
GEAR_VOLUME = 0.25
GEAR_LEVEL = 60
local GEAR_PITCH_LOW, GEAR_PITCH_SPREAD = 94, 11

-- What a running step of foot ("left" or "right") rattles, { sound, volume,
-- level, pitch } (random(n): 1..n picks the sound, then the pitch), or nil:
-- a walk, or a voice with no gear.
function Gear(voice, foot, running, random)
	if not (running and voice.gear) then return nil end
	local sounds = voice.gear[foot]
	return { sound = sounds[random(#sounds)], volume = GEAR_VOLUME, level = GEAR_LEVEL, pitch = GEAR_PITCH_LOW + random(GEAR_PITCH_SPREAD) }
end

-- Which of its voice's lists a hit of damage on a soldier of maxHealth
-- plays: "pain" or "grunt".
function Feedback(damage, maxHealth)
	return damage >= maxHealth * PAIN_SHARE and "pain" or "grunt"
end

-- The voice a side speaks with where a model gives none (a player in a
-- model of no voice): the Combine's soldier, a rebel.
local BY_AFFILIATION = {
	[COMBINE] = COMBINE_SOLDIER,
	[REBEL] = MALE,
}

function ForAffiliation(affiliation)
	return BY_AFFILIATION[affiliation]
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
