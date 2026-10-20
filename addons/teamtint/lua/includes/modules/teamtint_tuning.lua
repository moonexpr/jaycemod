-- The knobs an artist turns to tune the team look, and what they become on
-- a material. The look is TF2's character shading (Mitchell, Francke, Eng,
-- "Illustrative Rendering in Team Fortress 2", NPAR 2007), which
-- VertexLitGeneric's phong path implements: the half Lambert term through
-- an artist's warp texture (Equation 1, $lightwarptexture), Phong
-- highlights with a Fresnel term, and broad rim lobes masked by Fresnel plus
-- the ambient rim from above (Equation 2: $phong*, $rimlight*). The team's
-- colour goes on through a tint mask ($color2) or a baked texture.
--
-- A tuning holds each knob for all classes (base) and, where an artist set
-- it, for one class of material (teamtint_catalog's classes); the team
-- colours are the same for every class. MaterialParams turns a class's
-- knobs into VertexLitGeneric parameters for one material and one debug
-- view; VmtText writes them as a VMT. GMod's require("teamtint_tuning")
-- loads it.
local floor, format, ipairs, pairs, sort, tonumber, type = math.floor, string.format, ipairs, pairs, table.sort, tonumber, type
local concat = table.concat
module("teamtint_tuning")

ALL = "all"

-- The knobs, in the panel's order. kind: number, flag (0 or 1), vector (three
-- numbers), color (three channels 0..255), texture (a path). shared: the
-- same for every class.
SCHEMA = {
	-- TF2's team colours (its Team Spirit paint)
	{ name = "red_color", kind = "color", default = { 184, 56, 59 }, shared = true, label = "RED colour" },
	{ name = "blu_color", kind = "color", default = { 88, 133, 162 }, shared = true, label = "BLU colour" },
	-- the team colour through a tint mask; above 1 lifts dark cloth
	{ name = "tint_gain", kind = "number", min = 0, max = 4, default = 1, label = "Tint gain" },
	-- Equation 1: w(), the diffuse warp
	{ name = "lightwarp", kind = "texture", default = "teamtint/lightwarp", label = "Light warp" },
	-- Equation 2, left: k_s, k_spec, f_s
	{ name = "phong_boost", kind = "number", min = 0, max = 20, default = 1, label = "Phong boost" },
	{ name = "phong_exponent", kind = "number", min = 1, max = 150, default = 20, label = "Phong exponent" },
	{ name = "fresnel", kind = "vector", min = 0, max = 10, default = { 0.3, 1, 8 }, label = "Fresnel ranges" },
	-- Equation 2: the rim lobes and the ambient rim (k_rim, their boost, k_r)
	{ name = "rim", kind = "flag", default = 1, label = "Rim light" },
	{ name = "rim_exponent", kind = "number", min = 0.1, max = 20, default = 4, label = "Rim exponent" },
	{ name = "rim_boost", kind = "number", min = 0, max = 10, default = 2, label = "Rim boost" },
	{ name = "rim_mask", kind = "flag", default = 1, label = "Rim mask" },
}

local BY_NAME = {}
for _, p in ipairs(SCHEMA) do BY_NAME[p.name] = p end

-- The debug views (teamtint_view), each isolating a term of the look.
VIEWS = { "normal", "albedo", "tint off", "lighting", "spec + rim", "value", "silhouette" }
VIEW_NORMAL = 0
VIEW_ALBEDO = 1 -- unlit: is the team colour in the texture right?
VIEW_TINT_OFF = 2 -- the shading without the team colour
VIEW_LIGHTING = 3 -- white albedo: the warp and the ambient cube alone (the paper's Fig. 6d)
VIEW_SPECULAR = 4 -- black albedo: the view-dependent terms alone (Fig. 6h)
VIEW_VALUE = 5 -- greyscale: the team read must survive in value, not only hue
VIEW_SILHOUETTE = 6 -- flat team colour, unlit: the read at a distance

-- The flat textures the views paint with (the bake tool makes them).
WHITE = "teamtint/white"
BLACK = "teamtint/black"

local function Clamp1(p, v)
	if p.min and v < p.min then return p.min end
	if p.max and v > p.max then return p.max end
	return v
end

local function Round(v) return floor(v + 0.5) end

-- value kept to its knob's kind and range, or nil if it is not of the kind.
function Clamp(name, value)
	local p = BY_NAME[name]
	if not p then return nil end
	if p.kind == "number" then
		return type(value) == "number" and Clamp1(p, value) or nil
	elseif p.kind == "flag" then
		return type(value) == "number" and (Round(value) ~= 0 and 1 or 0) or nil
	elseif p.kind == "texture" then
		return type(value) == "string" and value or nil
	end
	if type(value) ~= "table" or #value ~= 3 then return nil end
	local out = {}
	for i = 1, 3 do
		local v = value[i]
		if type(v) ~= "number" then return nil end
		if p.kind == "color" then
			v = Round(v)
			out[i] = v < 0 and 0 or (v > 255 and 255 or v)
		else
			out[i] = Clamp1(p, v)
		end
	end
	return out
end

-- A knob's value from text (a convar's), or nil.
function Parse(name, text)
	local p = BY_NAME[name]
	if not p or type(text) ~= "string" then return nil end
	if p.kind == "texture" then return Clamp(name, text) end
	if p.kind == "number" or p.kind == "flag" then return Clamp(name, tonumber(text)) end
	local values = {}
	for word in text:gmatch("%S+") do values[#values + 1] = tonumber(word) end
	return Clamp(name, values)
end

local function Number(v)
	local text = format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
	if text == "-0" then return "0" end
	return text
end

-- A knob's value as text, the inverse of Parse.
function Format(name, value)
	local p = BY_NAME[name]
	if p.kind == "texture" then return value end
	if type(value) ~= "table" then return Number(value) end
	local words = {}
	for i = 1, 3 do words[i] = Number(value[i]) end
	return concat(words, " ")
end

local function Copy(v)
	if type(v) ~= "table" then return v end
	return { v[1], v[2], v[3] }
end

-- A tuning of the defaults: { base = name -> value, classes = class -> name -> value }.
function Defaults()
	local base = {}
	for _, p in ipairs(SCHEMA) do base[p.name] = Copy(p.default) end
	return { base = base, classes = {} }
end

-- Sets name for scope (ALL or a class); a shared knob is set for all.
function Set(tuning, scope, name, value)
	local p = BY_NAME[name]
	value = Clamp(name, value)
	if not p or value == nil then return end
	if scope == ALL or p.shared then
		tuning.base[name] = value
	else
		tuning.classes[scope] = tuning.classes[scope] or {}
		tuning.classes[scope][name] = value
	end
end

-- Drops a class's own values: it takes all's again.
function Clear(tuning, scope)
	if scope == ALL then
		local fresh = Defaults()
		tuning.base = fresh.base
	else
		tuning.classes[scope] = nil
	end
end

function Get(tuning, class, name)
	local own = tuning.classes[class]
	if own and own[name] ~= nil then return own[name] end
	return tuning.base[name]
end

-- Every knob's value for class.
function Resolved(tuning, class)
	local out = {}
	for _, p in ipairs(SCHEMA) do out[p.name] = Get(tuning, class, p.name) end
	return out
end

-- The tuning as plain tables (for JSON), and back; Decode keeps only known
-- knobs of the right kind, on top of the defaults.
function Encode(tuning)
	local classes = {}
	for class, values in pairs(tuning.classes) do
		classes[class] = {}
		for name, v in pairs(values) do classes[class][name] = Copy(v) end
	end
	local base = {}
	for name, v in pairs(tuning.base) do base[name] = Copy(v) end
	return { version = 1, base = base, classes = classes }
end

function Decode(data)
	local tuning = Defaults()
	if type(data) ~= "table" then return tuning end
	if type(data.base) == "table" then
		for name, v in pairs(data.base) do Set(tuning, ALL, name, v) end
	end
	if type(data.classes) == "table" then
		for class, values in pairs(data.classes) do
			if type(class) == "string" and class ~= ALL and type(values) == "table" then
				for name, v in pairs(values) do
					if BY_NAME[name] and not BY_NAME[name].shared then Set(tuning, class, name, v) end
				end
			end
		end
	end
	return tuning
end

local WHITE_TINT = { 1, 1, 1 }

local function TeamColor(values, team)
	local c = (team == "red" and values.red_color) or (team == "blu" and values.blu_color)
	if not c then return nil end
	return { c[1] / 255, c[2] / 255, c[3] / 255 }
end

local function Scaled(c, gain)
	return { c[1] * gain, c[2] * gain, c[3] * gain }
end

-- VertexLitGeneric parameters (key -> number, string, or three numbers) for
-- a material from its class's values (Resolved) and ctx: team ("red",
-- "blu", "original"), strategy (teamtint_catalog's), base (its own base
-- texture), baked (the team's texture, for BAKED), tintMask (it has
-- $blendtintbybasealpha), hasExponent (it has $phongexponenttexture), view.
-- Every view sets the same keys, so leaving a view restores them.
function MaterialParams(values, ctx)
	local view = ctx.view or VIEW_NORMAL
	local team = TeamColor(values, ctx.team)
	local p = {
		["$phong"] = 1,
		["$phongboost"] = values.phong_boost,
		["$phongfresnelranges"] = Copy(values.fresnel),
		["$lightwarptexture"] = values.lightwarp,
		["$rimlight"] = values.rim,
		["$rimlightexponent"] = values.rim_exponent,
		["$rimlightboost"] = values.rim_boost,
		["$basetexture"] = ctx.base,
		["$blendtintbybasealpha"] = ctx.tintMask and 1 or 0,
		["$color2"] = WHITE_TINT,
	}
	-- $phongexponent overrides the exponent texture; the rim mask is that
	-- texture's alpha, so a material without one has none
	if ctx.hasExponent then
		p["$rimmask"] = values.rim_mask
	else
		p["$phongexponent"] = values.phong_exponent
	end
	if view ~= VIEW_TINT_OFF then
		if ctx.strategy == "proxy" and team then p["$color2"] = Scaled(team, values.tint_gain) end
		if ctx.strategy == "baked" and ctx.baked and ctx.team ~= "original" then p["$basetexture"] = ctx.baked end
	end
	if view == VIEW_LIGHTING then
		p["$basetexture"], p["$color2"], p["$blendtintbybasealpha"] = WHITE, WHITE_TINT, 0
	elseif view == VIEW_SPECULAR then
		p["$basetexture"], p["$color2"], p["$blendtintbybasealpha"] = BLACK, WHITE_TINT, 0
	elseif view == VIEW_SILHOUETTE then
		p["$basetexture"], p["$color2"], p["$blendtintbybasealpha"] = WHITE, team or WHITE_TINT, 0
		p["$phongboost"], p["$rimlight"] = 0, 0
	end
	p["$color2"] = Copy(p["$color2"])
	return p
end

-- What a view needs beyond the materials: unlit drawing, a greyscale pass.
function ViewFlags(view)
	return {
		fullbright = view == VIEW_ALBEDO or view == VIEW_SILHOUETTE,
		greyscale = view == VIEW_VALUE,
	}
end

local function KeyValue(v)
	if type(v) == "table" then return "[" .. Number(v[1]) .. " " .. Number(v[2]) .. " " .. Number(v[3]) .. "]" end
	if type(v) == "number" then return Number(v) end
	return v
end

-- A VMT's text: shader, then each key and value in key order.
function VmtText(shader, params)
	local keys = {}
	for k in pairs(params) do keys[#keys + 1] = k end
	sort(keys)
	local lines = { '"' .. shader .. '"', "{" }
	for _, k in ipairs(keys) do lines[#lines + 1] = format('\t"%s" "%s"', k, KeyValue(params[k])) end
	lines[#lines + 1] = "}"
	lines[#lines + 1] = ""
	return concat(lines, "\n")
end
