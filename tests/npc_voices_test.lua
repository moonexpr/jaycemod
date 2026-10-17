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
	T.eq(Has(Voices.For("models/player/police.mdl").death, "npc/metropolice/die3.wav"), true, "a metrocop")
	T.eq(Has(Voices.For("models/vortigaunt.mdl").pain, "npc/vort/vort_pain3.wav"), true, "a vortigaunt")
end)

T.test("model paths match whatever their case", function()
	T.eq(Voices.For("Models/Player/Alyx.mdl"), Voices.For("models/player/alyx.mdl"))
end)

T.test("a model the war does not dress its soldiers in has no voice", function()
	T.eq(Voices.For("models/player/kleiner.mdl"), nil)
end)

-- Each voice is named for the speech rules (foundation.aiwar.speech), and
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

-- A hit of PAIN_SHARE of the soldier's health or more is a cry of pain; a
-- lighter one, a grunt.
T.defined(Voices.PAIN_SHARE, "PAIN_SHARE")
T.defined(Voices.FEEDBACK_COOLDOWN, "FEEDBACK_COOLDOWN")

T.test("a heavy hit is a cry of pain, a light one a grunt", function()
	T.eq(Voices.Feedback(100 * Voices.PAIN_SHARE, 100), "pain", "heavy")
	T.eq(Voices.Feedback(100 * Voices.PAIN_SHARE - 1, 100), "grunt", "light")
	T.eq(Voices.Feedback(30, 300), Voices.Feedback(10, 100), "a share of its own health")
end)

T.finish()
