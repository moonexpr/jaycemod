-- Team Tint's runtime materials: for each team and each source material
-- the catalog themes, one VertexLitGeneric copy (CreateMaterial, named
-- teamtint_<team>_<path>), made from the source's own parameters with
-- teamtint_tuning's on top. A knob turned rewrites every copy at once, so
-- every body wearing it changes as the artist drags the slider.
local Catalog, Tuning = TeamTint.Catalog, TeamTint.Tuning

-- key (team | path | softwareskin) -> an entry, or false for a material
-- left as it is (out of the catalog, or a strategy of NONE).
TeamTint.materials = TeamTint.materials or {}
local cache = TeamTint.materials

-- Textures set by name: one missing would draw the error texture, so a
-- missing one is left undefined (the shader's default) instead.
local TEXTURE_KEYS = { ["$basetexture"] = true, ["$lightwarptexture"] = true }
local INT_KEYS = { ["$phong"] = true, ["$rimlight"] = true, ["$rimmask"] = true, ["$blendtintbybasealpha"] = true }

-- VertexLitGeneric takes its phong path, where the warp and the rim live,
-- only with a normal map: a source without one gets this flat one.
local FLAT_NORMAL = "teamtint/flat_normal"

local textureExists = {}
local function TextureExists(name)
	if textureExists[name] == nil then
		textureExists[name] = file.Exists("materials/" .. name .. ".vtf", "GAME")
	end
	return textureExists[name]
end

local function TextureName(mat, key)
	local name = mat:GetString(key)
	if not name or name == "" or name == "error" then return nil end
	return name
end

-- What the catalog decides by, read from the source material.
local function Facts(source, team)
	local base = TextureName(source, "$basetexture")
	local baked = base and Catalog.BakedTexture(team, base)
	return {
		shader = source:GetShader(),
		base = base,
		tintMask = source:GetInt("$blendtintbybasealpha") == 1,
		hasExponent = TextureName(source, "$phongexponenttexture") ~= nil,
		baked = baked and TextureExists(baked) and baked or nil,
	}
end

-- A source's parameters as CreateMaterial takes them: textures by name,
-- vectors as "[x y z]"; matrices and unset textures dropped.
local function SourceKeyValues(source)
	local kv = {}
	for key, value in pairs(source:GetKeyValues()) do
		local kind = type(value)
		if kind == "ITexture" then
			if not value:IsError() and value:GetName() ~= "error" then kv[key] = value:GetName() end
		elseif kind == "Vector" then
			kv[key] = string.format("[%f %f %f]", value.x, value.y, value.z)
		elseif kind == "number" or kind == "string" then
			kv[key] = tostring(value)
		end
	end
	kv["$model"] = "1"
	if not kv["$bumpmap"] and TextureExists(FLAT_NORMAL) then kv["$bumpmap"] = FLAT_NORMAL end
	return kv
end

-- An entry's parameters for view (by default the one teamtint_view shows).
local function Params(entry, view)
	return Tuning.MaterialParams(Tuning.Resolved(TeamTint.tuning, entry.class), {
		team = entry.team, strategy = entry.strategy, base = entry.facts.base, baked = entry.facts.baked,
		tintMask = entry.facts.tintMask, hasExponent = entry.facts.hasExponent, view = view or TeamTint.VIEW:GetInt(),
	})
end
TeamTint.MaterialParamsOf = Params

local function KeyValueText(value)
	if istable(value) then return string.format("[%f %f %f]", value[1], value[2], value[3]) end
	return tostring(value)
end

-- Writes params onto the live material.
local function Write(mat, params)
	for key, value in pairs(params) do
		if TEXTURE_KEYS[key] then
			if value and TextureExists(value) then mat:SetTexture(key, value) else mat:SetUndefined(key) end
		elseif istable(value) then
			mat:SetVector(key, Vector(value[1], value[2], value[3]))
		elseif INT_KEYS[key] then
			mat:SetInt(key, value)
		else
			mat:SetFloat(key, value)
		end
	end
	mat:Recompute()
end

local function Sanitize(path)
	return (string.gsub(Catalog.Normalize(path), "[^%w]", "_"))
end

-- The entry theming path for team, made on first use: { name (for
-- SetSubMaterial, without "!"), material, class, strategy, facts, team, path },
-- or nil when the material is left as it is.
function TeamTint.Material(team, path, softwareSkin)
	local key = team .. "|" .. path .. (softwareSkin and "|ss" or "")
	local entry = cache[key]
	if entry ~= nil then return entry or nil end
	cache[key] = false
	local rule = Catalog.Classify(path)
	if not rule then return nil end
	local source = Material(path)
	if source:IsError() then return nil end
	local facts = Facts(source, team)
	local strategy = Catalog.Strategy(rule.class, facts)
	if strategy == Catalog.NONE or not facts.base then return nil end
	entry = {
		name = "teamtint_" .. team .. (softwareSkin and "_ss_" or "_") .. Sanitize(path),
		class = rule.class, strategy = strategy, facts = facts, team = team, path = path,
	}
	local kv = SourceKeyValues(source)
	for k, v in pairs(Params(entry)) do
		if TEXTURE_KEYS[k] and not (v and TextureExists(v)) then kv[k] = nil else kv[k] = KeyValueText(v) end
	end
	if softwareSkin then kv["$softwareskin"] = "1" end
	entry.sourceKeyValues = kv
	entry.material = CreateMaterial(entry.name, "VertexLitGeneric", kv)
	-- a name made before (a Lua refresh) returns the old material: bring it up to date
	Write(entry.material, Params(entry))
	cache[key] = entry
	return entry
end

-- Every entry made, for the overlay and the export.
function TeamTint.MaterialEntries()
	local list = {}
	for _, entry in pairs(cache) do
		if entry then list[#list + 1] = entry end
	end
	return list
end

-- The tuning or the view changed: every copy takes its new parameters.
function TeamTint.RebuildMaterials()
	for _, entry in pairs(cache) do
		if entry then Write(entry.material, Params(entry)) end
	end
end

cvars.AddChangeCallback("teamtint_view", function() TeamTint.RebuildMaterials() end, "teamtint_materials")
