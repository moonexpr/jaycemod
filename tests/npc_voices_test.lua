-- foundation.npc.voices: the pain and death sounds of the AI war's soldiers,
-- by the model they wear (a kit may change it: Alyx, the Combine's support
-- in the metrocops'), from HL2's own sounds, each checked to exist.
local T = dofile("tests/harness.lua")
local Voices = T.require("foundation.npc.voices")

local function Has(list, path)
	for _, p in ipairs(list) do if p == path then return true end end
	return false
end

T.test("rebels speak by their model's sex", function()
	local male = Voices.For("models/player/group03/male_04.mdl")
	T.eq(Has(male.pain, "vo/npc/male01/pain01.wav"), true, "a man's pain")
	T.eq(#male.death > 0, true, "and his death")
	local female = Voices.For("models/player/group03/female_02.mdl")
	T.eq(Has(female.pain, "vo/npc/female01/pain05.wav"), true, "a woman's pain")
	T.eq(Has(female.pain, "vo/npc/male01/pain05.wav"), false, "not a man's")
end)

T.test("Alyx, the Combine, metrocops and vortigaunts have their own", function()
	T.eq(Has(Voices.For("models/player/alyx.mdl").pain, "vo/npc/alyx/hurt04.wav"), true, "Alyx")
	T.eq(Has(Voices.For("models/player/combine_soldier.mdl").death, "npc/combine_soldier/die1.wav"), true, "a Combine soldier")
	T.eq(Has(Voices.For("models/player/combine_soldier_prisonguard.mdl").pain, "npc/combine_soldier/pain2.wav"), true, "a prison guard")
	-- the HL:A voice pack (content/sound/npc/combine_soldier) has a fourth cry HL2 lacks
	T.eq(Has(Voices.For("models/player/combine_soldier.mdl").pain, "npc/combine_soldier/pain4.wav"), true, "HL:A's fourth cry")
	T.eq(Has(Voices.For("models/player/police.mdl").death, "npc/metropolice/die3.wav"), true, "a metrocop")
	T.eq(Has(Voices.For("models/vortigaunt.mdl").pain, "npc/vort/vort_pain3.wav"), true, "a vortigaunt")
end)

T.test("model paths match whatever their case", function()
	T.eq(Voices.For("Models/Player/Alyx.mdl"), Voices.For("models/player/alyx.mdl"))
end)

-- A player in a model of no voice speaks for its side: the Combine as its
-- soldiers do, the Resistance as a rebel.
T.test("each side has a voice of its own for those whose model has none", function()
	T.eq(Voices.ForAffiliation(Voices.COMBINE), Voices.For("models/player/combine_soldier.mdl"), "the Combine's soldier")
	T.eq(Voices.ForAffiliation(Voices.REBEL), Voices.For("models/player/group03/male_04.mdl"), "a rebel")
	T.eq(Voices.ForAffiliation(Voices.COMBINE).confirm ~= nil, true, "confirmed by the flatline")
end)

T.test("a model the war does not dress its soldiers in has no voice", function()
	T.eq(Voices.For("models/player/kleiner.mdl"), nil)
end)

-- Each voice is named for the speech rules (games.ns.speech), and
-- has grunts for a light hit and a cry for a fall that hurts.
T.test("every voice has a name, grunts and a fall cry", function()
	for _, model in ipairs({ "models/player/group03/male_04.mdl", "models/player/group03/female_02.mdl", "models/player/alyx.mdl",
		"models/player/combine_soldier.mdl", "models/player/police.mdl", "models/vortigaunt.mdl" }) do
		local voice = Voices.For(model)
		T.eq(type(voice.name), "string", model .. ": a name")
		T.eq(#voice.grunt > 0, true, model .. ": grunts")
		T.eq(#voice.fall > 0, true, model .. ": a fall cry")
	end
	T.eq(Voices.For("models/player/group03/male_04.mdl").name ~= Voices.For("models/player/combine_soldier.mdl").name, true, "names differ")
end)

-- A death carries. The Combine's radio confirms it, as in HL2: Overwatch's
-- squelch and flatline beeps (npc/overwatch/radiovoice/die1-3, which are
-- the metrocops' own death sounds), after a soldier's cry; a metrocop's
-- death is that radio alone. A rebel's scream is its own signature, bigger
-- than any other sound: layered, louder, a little deeper.
T.defined(Voices.DEATH_LEVEL, "DEATH_LEVEL")
T.defined(Voices.DEATH_CONFIRM_DELAY, "DEATH_CONFIRM_DELAY")
T.defined(Voices.SCREAM_LEVEL, "SCREAM_LEVEL")
T.defined(Voices.SCREAM_LAYERS, "SCREAM_LAYERS")
T.defined(Voices.SCREAM_PITCH, "SCREAM_PITCH")

local function First() return 1 end
local function Last(n) return n end

local RADIO = { "npc/overwatch/radiovoice/die1.wav", "npc/overwatch/radiovoice/die2.wav", "npc/overwatch/radiovoice/die3.wav" }

T.test("a Combine soldier's death is a loud cry, then the radio's flatline beeps", function()
	local voice = Voices.For("models/player/combine_soldier.mdl")
	local sounds = Voices.Death(voice, First)
	T.eq(#sounds, 2, "a cry and the radio")
	T.eq(sounds[1].sound, voice.death[1], "its own cry")
	T.eq(sounds[1].level, Voices.DEATH_LEVEL, "loud")
	T.eq(sounds[1].delay, 0, "at once")
	T.eq(sounds[2].sound, RADIO[1], "Overwatch's radio, squelch and flatline")
	T.eq(sounds[2].level, Voices.DEATH_LEVEL, "as loud")
	T.eq(sounds[2].delay, Voices.DEATH_CONFIRM_DELAY, "after the cry")
	T.eq(Voices.Death(voice, Last)[2].sound, RADIO[3], "any of the three")
end)

T.test("a metrocop's death is the radio's flatline itself, nothing over it", function()
	local voice = Voices.For("models/player/police.mdl")
	local sounds = Voices.Death(voice, First)
	T.eq(#sounds, 1, "one sound")
	T.eq(sounds[1].sound, "npc/metropolice/die1.wav", "HL2's metrocop death: Overwatch's radio")
	T.eq(sounds[1].level, Voices.DEATH_LEVEL, "loud")
end)

T.test("a rebel's scream is layered, louder and deeper than any other death", function()
	for _, model in ipairs({ "models/player/group03/male_04.mdl", "models/player/group03/female_02.mdl", "models/player/alyx.mdl" }) do
		local voice = Voices.For(model)
		local sounds = Voices.Death(voice, First)
		T.eq(#sounds, Voices.SCREAM_LAYERS, model .. ": one copy a layer")
		for _, s in ipairs(sounds) do
			T.eq(s.sound, voice.death[1], model .. ": the same cry")
			T.eq(s.level, Voices.SCREAM_LEVEL, model .. ": at the scream's level")
			T.eq(s.pitch, Voices.SCREAM_PITCH, model .. ": deeper")
			T.eq(s.delay, 0, model .. ": together")
		end
	end
	T.eq(Voices.SCREAM_LAYERS >= 2, true, "layered: louder than one sound can play")
	T.eq(Voices.SCREAM_LEVEL > Voices.DEATH_LEVEL, true, "carries farther than the Combine's")
	T.eq(Voices.SCREAM_PITCH < 100, true, "below the recording's pitch")
	T.eq(Voices.DEATH_LEVEL > 75, true, "a death louder than a soldier's grunt (SNDLVL_NORM)")
end)

T.test("a death not a scream plays at the recording's own pitch", function()
	for _, s in ipairs(Voices.Death(Voices.For("models/player/combine_soldier.mdl"), First)) do T.eq(s.pitch, 100, s.sound) end
end)

-- A Combine soldier's gear rattles as it runs, as HL2's do
-- (NPC_CombineS.RunFootstepLeft/Right: gear1, 3, 5 on the left foot, 2, 4, 6
-- on the right; a metrocop's its own), but quietly: under its footsteps.
T.defined(Voices.GEAR_VOLUME, "GEAR_VOLUME")
T.defined(Voices.GEAR_LEVEL, "GEAR_LEVEL")

T.test("a Combine soldier's gear rattles on each running step, by foot", function()
	local voice = Voices.For("models/player/combine_soldier.mdl")
	local left = Voices.Gear(voice, "left", true, First)
	T.eq(left.sound, "npc/combine_soldier/gear1.wav", "the left foot's first")
	T.eq(Voices.Gear(voice, "left", true, Last).sound, "npc/combine_soldier/gear5.wav", "the left foot's last")
	T.eq(Voices.Gear(voice, "right", true, First).sound, "npc/combine_soldier/gear2.wav", "the right foot's")
	T.eq(left.volume, Voices.GEAR_VOLUME, "its volume")
	T.eq(left.level, Voices.GEAR_LEVEL, "its level")
	T.eq(left.pitch >= 95 and left.pitch <= 105, true, "HL2's pitch spread")
	T.eq(Voices.Gear(Voices.For("models/player/police.mdl"), "right", true, First).sound, "npc/metropolice/gear2.wav", "a metrocop's own")
end)

T.test("gear rattles quietly, and only at a run", function()
	local voice = Voices.For("models/player/combine_soldier.mdl")
	T.eq(Voices.Gear(voice, "left", false, First), nil, "a walk: still")
	T.eq(Voices.GEAR_VOLUME < 0.75, true, "under HL2's 0.75")
	T.eq(Voices.GEAR_LEVEL < 75, true, "carries less than a step (SNDLVL_NORM)")
	T.eq(Voices.Gear(Voices.For("models/player/group03/male_04.mdl"), "left", true, First), nil, "a rebel wears no gear")
end)

-- A hit of PAIN_SHARE of the soldier's health or more is a cry of pain; a
-- lighter one, a grunt.
T.defined(Voices.PAIN_SHARE, "PAIN_SHARE")
T.defined(Voices.FEEDBACK_COOLDOWN, "FEEDBACK_COOLDOWN")

T.test("a heavy hit is a cry of pain, a light one a grunt", function()
	T.eq(Voices.Feedback(100 * Voices.PAIN_SHARE, 100), "pain", "heavy")
	T.eq(Voices.Feedback(100 * Voices.PAIN_SHARE - 1, 100), "grunt", "light")
	T.eq(Voices.Feedback(30, 300), Voices.Feedback(10, 100), "a share of its own health")
end)

-- A voice's affiliation, which the speech rules answer by first
-- (content/scripts/responserules/<affiliation>.txt): HL2's sides.
T.test("each voice belongs to the Combine or the rebels", function()
	T.eq(type(Voices.COMBINE) == "string" and type(Voices.REBEL) == "string" and Voices.COMBINE ~= Voices.REBEL, true, "two sides")
	local function Of(model) return Voices.For(model).affiliation end
	T.eq(Of("models/player/combine_soldier.mdl"), Voices.COMBINE, "a Combine soldier")
	T.eq(Of("models/player/police.mdl"), Voices.COMBINE, "a metrocop")
	T.eq(Of("models/player/group03/male_04.mdl"), Voices.REBEL, "a rebel")
	T.eq(Of("models/player/group03/female_02.mdl"), Voices.REBEL, "a rebel woman")
	T.eq(Of("models/player/alyx.mdl"), Voices.REBEL, "Alyx")
	T.eq(Of("models/vortigaunt.mdl"), Voices.REBEL, "a vortigaunt fights with the rebels")
end)

T.finish()
