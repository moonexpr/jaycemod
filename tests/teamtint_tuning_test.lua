-- teamtint_tuning (addons/teamtint): the knobs an artist turns (TF2's
-- shading terms, the team colours), stored for all classes or one, their
-- VertexLitGeneric parameters, the debug views, and the VMT an export writes.
local T = dofile("tests/harness.lua")
local Tuning = T.require("teamtint_tuning")

local function Param(name)
	for _, p in ipairs(Tuning.SCHEMA) do
		if p.name == name then return p end
	end
end

-- Schema ---------------------------------------------------------------------

T.test("every knob has a kind, a default of that kind, and numbers within its range", function()
	local names = {}
	for _, p in ipairs(Tuning.SCHEMA) do
		T.eq(names[p.name], nil, "one " .. p.name)
		names[p.name] = true
		T.eq(Tuning.Clamp(p.name, p.default) ~= nil, true, p.name .. "'s default is its kind")
		T.eq(Tuning.Format(p.name, Tuning.Clamp(p.name, p.default)), Tuning.Format(p.name, p.default), p.name .. " in range")
	end
	T.defined(Param("phong_boost").default, "phong_boost")
	T.defined(Param("rim_exponent").default, "rim_exponent")
end)

T.test("a knob's text, as a convar holds it, parses to its kind and formats back", function()
	T.eq(Tuning.Parse("phong_boost", "1.5"), 1.5, "a number")
	T.eq(Tuning.Parse("rim", "1"), 1, "a flag")
	local fresnel = Tuning.Parse("fresnel", "0.3 1 8")
	T.eq(#fresnel, 3, "a vector")
	T.eq(Tuning.Format("fresnel", fresnel), "0.3 1 8", "formats back")
	T.eq(Tuning.Format("red_color", Tuning.Parse("red_color", "184 56 59")), "184 56 59", "a colour")
	T.eq(Tuning.Parse("lightwarp", "teamtint/lightwarp"), "teamtint/lightwarp", "a texture")
end)

T.test("text that is not the knob's kind parses to nothing", function()
	T.eq(Tuning.Parse("phong_boost", "loud"), nil, "a word for a number")
	T.eq(Tuning.Parse("fresnel", "1 2"), nil, "two of three")
	T.eq(Tuning.Parse("nonsense", "1"), nil, "no such knob")
end)

T.test("values are kept within their knob's range", function()
	local p = Param("phong_boost")
	T.eq(Tuning.Clamp("phong_boost", p.max + 100), p.max, "above")
	T.eq(Tuning.Clamp("phong_boost", p.min - 100), p.min, "below")
	T.eq(Tuning.Clamp("rim", 0.7), 1, "a flag rounds")
	local c = Tuning.Clamp("red_color", { 300, -5, 59.4 })
	T.eq(c[1], 255, "a channel above")
	T.eq(c[2], 0, "a channel below")
	T.eq(c[3], 59, "channels are whole")
end)

-- Scopes -----------------------------------------------------------------------

T.test("a value set for all classes is every class's until a class has its own", function()
	local t = Tuning.Defaults()
	Tuning.Set(t, Tuning.ALL, "rim_boost", 3)
	T.eq(Tuning.Get(t, "armor", "rim_boost"), 3, "armour takes all's")
	Tuning.Set(t, "armor", "rim_boost", 5)
	T.eq(Tuning.Get(t, "armor", "rim_boost"), 5, "armour's own")
	T.eq(Tuning.Get(t, "cloth", "rim_boost"), 3, "cloth still all's")
	Tuning.Clear(t, "armor")
	T.eq(Tuning.Get(t, "armor", "rim_boost"), 3, "cleared, armour takes all's again")
end)

T.test("the team colours are the same for every class", function()
	local t = Tuning.Defaults()
	Tuning.Set(t, "armor", "red_color", { 200, 0, 0 })
	T.eq(Tuning.Get(t, "cloth", "red_color")[1], 200, "set from a class, held for all")
end)

T.test("a tuning survives its plain-table form, dropping what it does not know", function()
	local t = Tuning.Defaults()
	Tuning.Set(t, "armor", "phong_exponent", 40)
	local data = Tuning.Encode(t)
	data.base.mystery = 1
	data.classes.armor.rim_boost = "loud"
	local back = Tuning.Decode(data)
	T.eq(Tuning.Get(back, "armor", "phong_exponent"), 40, "kept")
	T.eq(back.base.mystery, nil, "an unknown knob dropped")
	T.eq(Tuning.Get(back, "armor", "rim_boost"), Param("rim_boost").default, "a bad value dropped")
	T.eq(Tuning.Get(Tuning.Decode(nil), "armor", "rim"), Param("rim").default, "nothing decodes to the defaults")
end)

-- Material parameters -----------------------------------------------------------

local function Context(fields)
	local ctx = { team = "red", strategy = "shade", base = "models/x/sheet", tintMask = false, hasExponent = false, view = 0 }
	for k, v in pairs(fields or {}) do ctx[k] = v end
	return ctx
end

local function Params(fields)
	local t = Tuning.Defaults()
	return Tuning.MaterialParams(Tuning.Resolved(t, "armor"), Context(fields)), t
end

T.test("every themed material takes TF2's terms: phong, the warp, the rim", function()
	local p = Params()
	T.eq(p["$phong"], 1, "phong")
	T.eq(p["$rimlight"], Param("rim").default, "rim light")
	T.eq(p["$lightwarptexture"], Param("lightwarp").default, "the warp")
	T.eq(#p["$phongfresnelranges"], 3, "fresnel ranges")
	T.eq(p["$basetexture"], "models/x/sheet", "its own base")
end)

T.test("the tint mask takes the team's colour, times the gain", function()
	local p = Params({ strategy = "proxy", tintMask = true })
	local red = Param("red_color").default
	T.near(p["$color2"][1], red[1] / 255 * Param("tint_gain").default, 1e-9, "red")
	T.eq(p["$blendtintbybasealpha"], 1, "through the mask")
	T.eq(Params({ strategy = "proxy", tintMask = true, team = "original" })["$color2"][1], 1, "no team: untinted")
end)

T.test("a baked material wears its team's texture, untinted", function()
	local p = Params({ strategy = "baked", baked = "teamtint/red/models/x/sheet" })
	T.eq(p["$basetexture"], "teamtint/red/models/x/sheet", "baked")
	T.eq(p["$color2"][1], 1, "no tint on top")
end)

T.test("the phong exponent is the knob's unless the material has its own texture, which the rim mask needs", function()
	T.defined(Params()["$phongexponent"], "the knob's")
	T.eq(Params()["$rimmask"], nil, "no exponent texture, no rim mask")
	local own = Params({ hasExponent = true })
	T.eq(own["$phongexponent"], nil, "the texture's")
	T.eq(own["$rimmask"], Param("rim_mask").default, "the rim mask")
end)

T.test("the views isolate a term", function()
	T.eq(Params({ view = Tuning.VIEW_TINT_OFF, strategy = "baked", baked = "teamtint/red/x" })["$basetexture"], "models/x/sheet",
		"tint off: its own base")
	T.eq(Params({ view = Tuning.VIEW_LIGHTING })["$basetexture"], Tuning.WHITE, "lighting: white albedo")
	T.eq(Params({ view = Tuning.VIEW_SPECULAR })["$basetexture"], Tuning.BLACK, "spec and rim: black albedo")
	local silhouette = Params({ view = Tuning.VIEW_SILHOUETTE, strategy = "proxy", tintMask = true })
	T.eq(silhouette["$blendtintbybasealpha"], 0, "silhouette: the whole body")
	T.near(silhouette["$color2"][1], Param("red_color").default[1] / 255, 1e-9, "flat team colour")
	T.eq(Tuning.ViewFlags(Tuning.VIEW_ALBEDO).fullbright, true, "albedo is unlit")
	T.eq(Tuning.ViewFlags(Tuning.VIEW_VALUE).greyscale, true, "value is grey")
	T.eq(Tuning.ViewFlags(Tuning.VIEW_NORMAL).fullbright, false, "normal is lit")
end)

T.test("every view sets the same keys, so leaving one restores what it changed", function()
	local function Keys(p)
		local list = {}
		for k in pairs(p) do list[#list + 1] = k end
		table.sort(list)
		return table.concat(list, " ")
	end
	local normal = Keys(Params())
	for view = 0, #Tuning.VIEWS - 1 do
		T.eq(Keys(Params({ view = view })), normal, Tuning.VIEWS[view + 1])
	end
end)

-- Export --------------------------------------------------------------------------

T.test("a VMT is written with its keys in order and its values as KeyValues", function()
	local text = Tuning.VmtText("VertexLitGeneric", {
		["$phong"] = 1,
		["$basetexture"] = "models/x/sheet",
		["$phongfresnelranges"] = { 0.3, 1, 8 },
		["$rimlightboost"] = 2.25,
	})
	T.eq(text, table.concat({
		'"VertexLitGeneric"',
		"{",
		'\t"$basetexture" "models/x/sheet"',
		'\t"$phong" "1"',
		'\t"$phongfresnelranges" "[0.3 1 8]"',
		'\t"$rimlightboost" "2.25"',
		"}",
		"",
	}, "\n"), "the text")
end)

T.finish()
