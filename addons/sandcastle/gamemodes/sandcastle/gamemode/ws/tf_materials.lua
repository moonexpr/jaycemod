-- TF2's materials as a TF2 map's world draws them, where HL2's files of the
-- same names hide TF2's (GMod searches HL2's content first): which of a TF2
-- material's textures to set, and which texture files to copy from the tf
-- mount under ws.sound_paths' RELOCATED (ws/cl_tf_content.lua does both).
-- A map's own patched materials (its cubemaps') include the material they
-- patch; that one's TF2 textures are theirs.
local bit, gmatch, gsub, ipairs, lower, match, pairs = bit, string.gmatch, string.gsub, ipairs, string.lower, string.match, pairs
local tonumber, type = tonumber, type
local SoundPaths = require("ws.sound_paths")
module(...)

-- The texture parameters TF2's world shaders take; the map's own cubemap
-- ($envmap) is left as the map patched it.
TEXTURE_PARAMS = {
	"$basetexture", "$basetexture2", "$bumpmap", "$bumpmap2", "$detail",
	"$envmapmask", "$blendmodulatetexture", "$selfillummask",
}

-- The shader flags a material file sets ($flags' MATERIAL_VAR_* bits,
-- materialsystem/imaterial.h); a material HL2 hides takes TF2's, and keeps
-- any other flag it has (FLAGS' are all a file's own).
FLAGS = {
	["$vertexcolor"] = 16,
	["$vertexalpha"] = 32,
	["$selfillum"] = 64,
	["$additive"] = 128,
	["$alphatest"] = 256,
	["$nocull"] = 8192,
	["$basealphaenvmapmask"] = 1048576,
	["$translucent"] = 2097152,
	["$normalmapalphaenvmapmask"] = 4194304,
}
local MANAGED = 0
for _, flag in pairs(FLAGS) do MANAGED = bit.bor(MANAGED, flag) end

-- The drawing values a material HL2 hides takes from TF2's: numbers, and
-- colours as [r g b] (0 to 1) or {r g b} (0 to 255).
VALUE_PARAMS = {
	"$envmapcontrast", "$envmapsaturation", "$envmaptint", "$detailscale",
	"$detailblendfactor", "$detailblendmode", "$alphatestreference", "$alpha", "$color",
}

-- current's flags with those FLAGS are about replaced by tf's.
function Flags(current, tf)
	return bit.bor(bit.band(current, bit.bnot(MANAGED)), tf)
end

local function Value(raw)
	if type(raw) == "number" then return raw end
	local scale = match(raw, "^%s*{") and 1 / 255 or 1
	local parts = {}
	for n in gmatch(raw, "[-%d%.]+") do parts[#parts + 1] = tonumber(n) * scale end
	if #parts == 0 then return nil end
	if #parts == 1 then return parts[1] end
	return parts
end

-- A material file's texture name in TF2's form: lower case, forward
-- slashes, no .vtf.
function TextureName(value)
	local name = gsub(lower(value), "\\", "/")
	return (gsub(name, "%.vtf$", ""))
end

-- The material a map's patched material includes ("patch": include), as a
-- material name, or nil for a material that patches none.
function Included(params)
	local include = params.include
	if not include then return nil end
	return (gsub(gsub(TextureName(include), "^materials/", ""), "%.vmt$", ""))
end

-- What to do for one TF2 material, from its parameters (KeyValues, keys in
-- lower case): hiddenMaterial, HL2's material of its name hides it, so every
-- texture of TF2's is set; hidden(texture), HL2 hides that texture file, so
-- it plays from its relocated copy. Returns { textures = param -> texture
-- to set, copies = the texture files to copy, and for a hidden material,
-- flags (TF2's FLAGS bits) and values = param -> number or { r, g, b } }.
function Plan(params, hiddenMaterial, hidden)
	local textures, copies = {}, {}
	local flags, values
	if hiddenMaterial then
		flags, values = 0, {}
		for param, bits in pairs(FLAGS) do
			if params[param] and tonumber(params[param]) ~= 0 then flags = bit.bor(flags, bits) end
		end
		for _, param in ipairs(VALUE_PARAMS) do
			if params[param] ~= nil then values[param] = Value(params[param]) end
		end
	end
	for _, param in ipairs(TEXTURE_PARAMS) do
		local value = params[param]
		if value then
			local name = TextureName(value)
			if hidden(name) then
				textures[param] = SoundPaths.RELOCATED .. name
				copies[#copies + 1] = name
			elseif hiddenMaterial then
				textures[param] = name
			end
		end
	end
	return { textures = textures, copies = copies, flags = flags, values = values }
end
