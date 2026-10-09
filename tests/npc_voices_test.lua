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

T.finish()
