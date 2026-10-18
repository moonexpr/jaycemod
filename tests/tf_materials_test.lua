-- ws.tf_materials: which of a TF2 material's textures to set, and from
-- where, when HL2's files of the same names hide TF2's (GMod searches HL2's
-- content first).
local T = dofile("tests/harness.lua")
local Materials = T.require("ws.tf_materials")
local SoundPaths = T.require("ws.sound_paths")

local function Set(list)
	local set = {}
	for _, v in ipairs(list) do set[v] = true end
	return function(v) return set[v] == true end
end

T.test("a texture name is TF2's form: lower case, forward slashes, no extension", function()
	T.eq(Materials.TextureName("Concrete\\ConcreteWall002C.vtf"), "concrete/concretewall002c", "normalised")
	T.eq(Materials.TextureName("metal/grate"), "metal/grate", "already")
end)

T.test("a map's patched material names the material it includes", function()
	T.eq(Materials.Included({ include = "materials/concrete/concretewall002c.vmt" }), "concrete/concretewall002c", "the base")
	T.eq(Materials.Included({ ["$basetexture"] = "x" }), nil, "no patch")
end)

T.test("a hidden texture plays from its relocated copy; TF2's own names as they are", function()
	local params = { ["$basetexture"] = "Metal/Grate011a", ["$bumpmap"] = "metal/grate011a_normal", ["$surfaceprop"] = "metal", ["$envmap"] = "env_cubemap" }
	local plan = Materials.Plan(params, false, Set({ "metal/grate011a" }))
	T.eq(plan.textures["$basetexture"], "sandcastle/tf/metal/grate011a", "relocated")
	T.eq(plan.textures["$bumpmap"], nil, "TF2's own file, under a TF2 material HL2 does not hide: left")
	T.eq(plan.textures["$surfaceprop"], nil, "not a texture")
	T.eq(plan.textures["$envmap"], nil, "the map's cubemap stays")
	T.eq(#plan.copies, 1, "one file to copy")
	T.eq(plan.copies[1], "metal/grate011a", "the hidden one")
end)

T.test("a material HL2 hides sets every texture TF2's names, relocated where hidden", function()
	local params = { ["$basetexture"] = "concrete/wall_tf", ["$detail"] = "overlays/detail" }
	local plan = Materials.Plan(params, true, Set({ "overlays/detail" }))
	T.eq(plan.textures["$basetexture"], "concrete/wall_tf", "TF2's name, which HL2 lacks")
	T.eq(plan.textures["$detail"], SoundPaths.RELOCATED .. "overlays/detail", "relocated")
end)

T.test("a material with nothing hidden needs nothing", function()
	local plan = Materials.Plan({ ["$basetexture"] = "tf/only" }, false, Set({}))
	T.eq(next(plan.textures), nil, "no texture to set")
	T.eq(#plan.copies, 0, "no copy")
end)

-- 2fort's windows: HL2's glass/glasswindow002a is opaque, TF2's translucent
-- with its own envmap tint; drawing TF2's texture by HL2's flags draws black.
T.test("a material HL2 hides takes TF2's flags and values too", function()
	local params = { ["$basetexture"] = "glass/glasswindow002a", ["$translucent"] = 1, ["$envmapcontrast"] = 0.5,
		["$envmaptint"] = "[ .1 .1 .1]", ["$surfaceprop"] = "glass" }
	local plan = Materials.Plan(params, true, Set({}))
	T.eq(plan.flags, Materials.FLAGS["$translucent"], "translucent, and no other managed flag")
	T.eq(plan.values["$envmapcontrast"], 0.5, "a number")
	T.eq(plan.values["$envmaptint"][1], 0.1, "a vector's x")
	T.eq(plan.values["$envmaptint"][3], 0.1, "a vector's z")
	T.eq(plan.values["$surfaceprop"], nil, "not a drawing value")
	local opaque = Materials.Plan({ ["$basetexture"] = "x" }, true, Set({}))
	T.eq(opaque.flags, 0, "TF2's opaque: every managed flag cleared")
	T.eq(Materials.Plan({ ["$translucent"] = 1 }, false, Set({})).flags, nil, "TF2's own material: left alone")
end)

T.test("a material's flags keep those TF2's are not about", function()
	local translucent, nocull = Materials.FLAGS["$translucent"], Materials.FLAGS["$nocull"]
	local OTHER = 2 ^ 30 -- a flag no material file sets
	T.eq(Materials.Flags(nocull + OTHER, translucent), translucent + OTHER, "nocull dropped, translucent set, the other kept")
end)

T.finish()
