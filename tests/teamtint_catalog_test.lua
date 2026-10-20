-- teamtint_catalog (addons/teamtint): which of a body's materials a team
-- is painted on, by material path; and how each is themed, from the
-- material's own facts (its shader, a tint mask, a baked team texture).
local T = dofile("tests/harness.lua")
local Catalog = T.require("teamtint_catalog")

-- Paths ----------------------------------------------------------------------

T.test("a path is normalized: case, slashes, the materials/ folder and the extension", function()
	T.eq(Catalog.Normalize("Materials\\Models\\Combine_Soldier\\CombineSoldierSheet.vmt"),
		"models/combine_soldier/combinesoldiersheet", "as a VMT on disk")
	T.eq(Catalog.Normalize("models/police/metrocop_sheet"), "models/police/metrocop_sheet", "already plain")
end)

-- Classes ------------------------------------------------------------------------

T.test("armour and clothing take the team, under either the NPC's or the player model's folder", function()
	T.eq(Catalog.Classify("models/combine_soldier/combinesoldiersheet").class, "armor", "the Combine's sheet")
	T.eq(Catalog.Classify("models/player/combine_soldier/combinesoldiersheet").class, "armor", "a player model's copy")
	T.eq(Catalog.Classify("models/police/metrocop_sheet").class, "armor", "a metrocop")
	T.eq(Catalog.Classify("models/humans/male/group03/citizen_sheet").class, "cloth", "a rebel's clothes")
	T.eq(Catalog.Classify("models/barney/barneybody").class, "cloth", "Barney")
	T.eq(Catalog.Classify("models/vortigaunt/vortigaunt_base").class, "hide", "a vortigaunt")
end)

T.test("faces, eyes and teeth match before the folder's rule", function()
	T.eq(Catalog.Classify("models/humans/male/group01/joe_facemap").class, "skin", "a face")
	T.eq(Catalog.Classify("models/alyx/alyx_faceandhair").class, "skin", "Alyx's face")
	T.eq(Catalog.Classify("models/combine_soldier/eyeball_l").class, "eyes", "an eye")
	T.eq(Catalog.Classify("models/humans/male/group01/mouth").class, "teeth", "a mouth")
end)

T.test("a material in no rule's folder is no catalog's", function()
	T.eq(Catalog.Classify("models/props_c17/oildrum001"), nil, "a prop")
	T.eq(Catalog.Classify(""), nil, "nothing")
end)

T.test("every class a rule names is a class, and every class says whether it takes a team", function()
	for _, list in ipairs({ Catalog.FOLDERS, Catalog.PARTS }) do
		for _, rule in ipairs(list) do
			T.eq(type(Catalog.CLASSES[rule.class]), "table", rule.pattern)
		end
	end
	for name, class in pairs(Catalog.CLASSES) do
		T.eq(type(class.tint), "boolean", name)
	end
end)

-- Strategies ----------------------------------------------------------------------

local VLG = "VertexLitGeneric"

T.test("a team colour goes on through the tint mask when the material has one", function()
	T.eq(Catalog.Strategy("cloth", { shader = VLG, tintMask = true }), Catalog.PROXY, "a rebel's clothes")
	T.eq(Catalog.Strategy("cloth", { shader = VLG, tintMask = true, baked = true }), Catalog.PROXY,
		"the mask is preferred: it needs no texture")
end)

T.test("without a mask the team texture is baked, else the material only takes the shading", function()
	T.eq(Catalog.Strategy("armor", { shader = VLG, baked = true }), Catalog.BAKED, "baked")
	T.eq(Catalog.Strategy("armor", { shader = VLG }), Catalog.SHADE, "not baked yet")
end)

T.test("skin takes the shading but never the team; eyes and teeth are left alone", function()
	T.eq(Catalog.Strategy("skin", { shader = VLG, tintMask = true }), Catalog.SHADE, "a face")
	T.eq(Catalog.Strategy("eyes", { shader = VLG }), Catalog.NONE, "eyes")
	T.eq(Catalog.Strategy("teeth", { shader = VLG }), Catalog.NONE, "teeth")
end)

T.test("only VertexLitGeneric is themed, whatever its build's suffix", function()
	T.eq(Catalog.Strategy("armor", { shader = "VertexLitGeneric_DX9" }), Catalog.SHADE, "the DX9 build")
	T.eq(Catalog.Strategy("eyes", { shader = "EyeRefract" }), Catalog.NONE, "eyes' own shader")
	T.eq(Catalog.Strategy("armor", { shader = "UnlitGeneric", baked = true }), Catalog.NONE, "unlit")
end)

-- Baked textures ----------------------------------------------------------------

T.test("a baked team texture sits under teamtint/<team>/ at its base texture's path", function()
	T.eq(Catalog.BakedTexture("red", "Models/Combine_Soldier/CombineSoldierSheet"),
		"teamtint/red/models/combine_soldier/combinesoldiersheet", "RED")
	T.eq(Catalog.BakedTexture("blu", "models/police/metrocop_sheet"), "teamtint/blu/models/police/metrocop_sheet", "BLU")
	T.eq(Catalog.BakedTexture("original", "models/police/metrocop_sheet"), nil, "no team, no texture")
end)

T.finish()
