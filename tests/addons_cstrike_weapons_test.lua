local T = dofile("tests/harness.lua")

local LUA_ROOT = "addons/cstrike_weapons/lua/"
local WEAPON_CLASSES = {
	"weapon_glock", "weapon_usp", "weapon_p228", "weapon_deagle", "weapon_elite", "weapon_fiveseven",
	"weapon_m3", "weapon_xm1014", "weapon_mac10", "weapon_tmp", "weapon_mp5navy", "weapon_ump45", "weapon_p90",
	"weapon_galil", "weapon_famas", "weapon_ak47", "weapon_m4a1", "weapon_sg552", "weapon_aug",
	"weapon_scout", "weapon_awp", "weapon_g3sg1", "weapon_sg550", "weapon_m249",
	"weapon_knife", "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade",
}
local WEAPON_BASES = { "base_cstrike", "base_cstrike_melee", "base_cstrike_grenade" }
local ENTITY_CLASSES = {
	"base_cstrike_grenade", "hegrenade_projectile", "flashbang_projectile", "smokegrenade_projectile",
}

local function LoadDefinition(kind, class)
	local sent = false
	local env = {
		SWEP = {},
		ENT = {},
		SERVER = true,
		CLIENT = false,
		AddCSLuaFile = function() sent = true end,
		game = { AddAmmoType = function() end },
		Model = function(model) return { precached = model } end,
		Material = function(material) return { name = material } end,
		Vector = function(x, y, z) return { x = x, y = y, z = z } end,
		Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
		DMG_BULLET = 1,
		TRACER_LINE_AND_WHIZ = 2,
		HITGROUP_GENERIC = 0,
		HITGROUP_HEAD = 1,
		HITGROUP_CHEST = 2,
		HITGROUP_STOMACH = 3,
		HITGROUP_LEFTARM = 4,
		HITGROUP_RIGHTARM = 5,
		HITGROUP_LEFTLEG = 6,
		HITGROUP_RIGHTLEG = 7,
		HITGROUP_GEAR = 10,
	}
	setmetatable(env, { __index = _G })
	local path = LUA_ROOT .. kind .. "/" .. class .. ".lua"
	local chunk = assert(loadfile(path), "standard GMod definition path missing: " .. path)
	setfenv(chunk, env)()
	T.eq(sent, true, path .. " sends its shared definition to clients")
	return kind == "weapons" and env.SWEP or env.ENT
end

T.test("the cstrike_weapons addon uses GMod's standard auto-loaded folders", function()
	local addon = assert(io.open("addons/cstrike_weapons/addon.json"))
	local metadata = addon:read("*a")
	addon:close()
	T.eq(metadata:find('"type": "weapon"', 1, true) ~= nil, true, "Workshop metadata uses the weapon type")

	local weapons = {}
	for _, class in ipairs(WEAPON_BASES) do
		weapons[class] = LoadDefinition("weapons", class)
	end
	for _, class in ipairs(WEAPON_CLASSES) do
		weapons[class] = LoadDefinition("weapons", class)
		T.eq(weapons[class].CStrikeWeapon, true, class .. " is a CS:S weapon")
		if weapons[class].Base ~= "weapon_base" then
			T.eq(weapons[weapons[class].Base] ~= nil, true, class .. " uses a base loaded from lua/weapons")
		end
	end

	local entities = {}
	for _, class in ipairs(ENTITY_CLASSES) do
		entities[class] = LoadDefinition("entities", class)
	end
	for _, class in ipairs({ "hegrenade_projectile", "flashbang_projectile", "smokegrenade_projectile" }) do
		T.eq(entities[entities[class].Base] ~= nil, true, class .. " uses the base loaded from lua/entities")
	end
end)

T.test("CS:S grenade effects are distributed and flash postprocess fades out", function()
	local sent = {}
	local server = setmetatable({
		AddCSLuaFile = function(path) sent[path] = true end,
	}, { __index = _G })
	local chunk = assert(loadfile(LUA_ROOT .. "autorun/server/cstrike_weapons_effects.lua"))
	setfenv(chunk, server)()
	for _, name in ipairs({ "cstrike_flashbang", "cstrike_smoke", "cstrike_explosion" }) do
		local path = "effects/" .. name .. ".lua"
		T.eq(sent[path], true, path .. " is sent to clients")
		local effect = {}
		local env = setmetatable({
			EFFECT = effect,
			Material = function(material) return { name = material } end,
		}, { __index = _G })
		local effect_chunk = assert(loadfile(LUA_ROOT .. path))
		setfenv(effect_chunk, env)()
		T.eq(type(effect.Init), "function", name .. " defines a Lua effect")
	end

	local now, registered, color = 10, nil, nil
	local env = setmetatable({
		CurTime = function() return now end,
		DrawColorModify = function(value) color = value end,
		math = setmetatable({
			Clamp = function(value, low, high) return math.max(low, math.min(high, value)) end,
		}, { __index = math }),
		hook = { Add = function(_, name, callback)
			T.eq(name, "cstrike_flashbang", "postprocess hook name")
			registered = callback
		end },
	}, { __index = _G })
	local postprocess = assert(loadfile(LUA_ROOT .. "postprocess/cstrike_flashbang.lua"))
	setfenv(postprocess, env)()
	env.CStrikeFlashbang.Apply(2)
	registered()
	T.near(color["$pp_colour_colour"], 0.2, 1e-9, "flash begins washed out")
	now = 11
	registered()
	T.near(color["$pp_colour_colour"], 0.6, 1e-9, "postprocess fades")
	now = 13
	local previous = color
	registered()
	T.eq(color, previous, "postprocess stops after the flash")
end)

T.finish()
