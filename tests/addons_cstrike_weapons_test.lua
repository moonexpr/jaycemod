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

local function LoadAddon(server)
	local weapons, entities, sent = {}, {}, {}
	local env
	local function Include(path)
		local chunk = assert(loadfile(LUA_ROOT .. path), path)
		setfenv(chunk, env)
		chunk()
	end
	local function Register(registry, definition, class, label)
		T.eq(type(definition), "table", label .. " definition")
		if definition.Base and definition.Base ~= "weapon_base" then
			T.eq(registry[definition.Base] ~= nil, true, label .. " registers after its base")
		end
		registry[class] = definition
	end

	env = setmetatable({
		SERVER = server,
		CLIENT = not server,
		AddCSLuaFile = function(path) sent[path or "<autorun>"] = true end,
		include = Include,
		weapons = { Register = function(definition, class)
			Register(weapons, definition, class, "weapon " .. class)
		end },
		scripted_ents = { Register = function(definition, class)
			Register(entities, definition, class, "entity " .. class)
		end },
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
	}, { __index = _G })

	local chunk = assert(loadfile(LUA_ROOT .. "autorun/cstrike_weapons.lua"))
	setfenv(chunk, env)
	chunk()
	return weapons, entities, sent
end

T.test("the cstrike_weapons addon registers and distributes its classes", function()
	for _, server in ipairs({ true, false }) do
		local weapons, entities, sent = LoadAddon(server)
		for _, class in ipairs(WEAPON_BASES) do
			T.eq(weapons[class] ~= nil, true, class .. " is registered")
		end
		for _, class in ipairs(WEAPON_CLASSES) do
			T.eq(weapons[class] ~= nil, true, class .. " is registered")
			T.eq(weapons[class].CStrikeWeapon, true, class .. " is a CS:S weapon")
		end
		for _, class in ipairs(ENTITY_CLASSES) do
			T.eq(entities[class] ~= nil, true, class .. " is registered")
		end

		local expected_files = 0
		for _, class in ipairs(WEAPON_BASES) do
			expected_files = expected_files + 1
			T.eq(sent["cstrike_weapons/weapons/" .. class .. ".lua"] == true, server, class .. " distribution")
		end
		for _, class in ipairs(WEAPON_CLASSES) do
			expected_files = expected_files + 1
			T.eq(sent["cstrike_weapons/weapons/" .. class .. ".lua"] == true, server, class .. " distribution")
		end
		for _, class in ipairs(ENTITY_CLASSES) do
			expected_files = expected_files + 1
			T.eq(sent["cstrike_weapons/entities/" .. class .. ".lua"] == true, server, class .. " distribution")
		end
		T.eq(sent["<autorun>"] == true, server, "autorun distribution")
		local sent_count = 0
		for _ in pairs(sent) do sent_count = sent_count + 1 end
		T.eq(sent_count, server and expected_files + 1 or 0, "only server distributes shared files")
	end
end)

T.finish()
