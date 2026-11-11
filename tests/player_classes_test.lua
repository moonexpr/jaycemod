local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local WEAPON_HELPER = "player_class/simple_weapon_loadout.lua"
local CLASS_FILES = {
	{ path = "player_class/player_combatant.lua", name = "player_combatant", base = "player_sandbox", driver = true },
	{ path = "player_class/player_combatant_cstrike.lua", name = "player_combatant_cstrike", base = "player_base", driver = true },
	{ path = "player_class/player_sandcastle.lua", name = "player_sandcastle", base = "player_default", driver = true },
	{ path = "player_class/player_spectator.lua", name = "player_spectator", base = "player_default" },
}

local file = assert(io.open(ROOT .. "shared.lua"))
local shared = file:read("*a")
file:close()
local gamemode = {}
local helper = assert(loadfile(ROOT .. WEAPON_HELPER))
setfenv(helper, setmetatable({ GM = gamemode }, { __index = _G }))()
local Weapons = gamemode.SimpleWeaponLoadout

T.test("shared loader includes and sends every selected player class", function()
	local ws_core = assert(shared:find('Include("sh_core.lua")', 1, true))
	local helper_included = assert(shared:find('Include("' .. WEAPON_HELPER .. '")', 1, true))
	T.eq(shared:find('AddCSLuaFile("' .. WEAPON_HELPER .. '")', 1, true) ~= nil, true, "the loadout driver is sent to clients")
	T.eq(ws_core < helper_included, true, "WS exists before player classes load")
	for _, class in ipairs(CLASS_FILES) do
		local included = shared:find('Include("' .. class.path .. '")', 1, true)
		T.eq(included ~= nil, true, class.name .. " is included in both realms")
		T.eq(helper_included < (included or 0), true, class.name .. " loads after the loadout driver")
		T.eq(shared:find('AddCSLuaFile("' .. class.path .. '")', 1, true) ~= nil, true, class.name .. " is sent to clients")
	end
end)

T.test("selected player classes register under distinct names and bases", function()
	for _, class in ipairs(CLASS_FILES) do
		local registered
		local env = setmetatable({
			WS = { TEAM_UNASSIGNED = 0, TEAM_SPECTATOR = 1 },
			DEFINE_BASECLASS = function() end,
			GM = gamemode,
			TauntCamera = function() return {} end,
			player_manager = {
				RegisterClass = function(name, definition, base)
					registered = { name = name, definition = definition, base = base }
				end,
			},
		}, { __index = _G })
		setfenv(assert(loadfile(ROOT .. class.path)), env)()
		T.eq(registered.name, class.name, class.path .. " class name")
		T.eq(registered.base, class.base, class.path .. " base class")
		T.eq(type(registered.definition), "table", class.path .. " class definition")
	end
end)

-- A parent nothing registers is an empty table: the class has no SetupDataTables,
-- and player_manager fails on it each time a player is given the class.
T.test("every player class's parent is a registered class", function()
	local registered = { player_default = "player_default", player_sandbox = "player_default" }
	for _, class in ipairs(CLASS_FILES) do
		local env = setmetatable({
			WS = { TEAM_UNASSIGNED = 0, TEAM_SPECTATOR = 1 },
			DEFINE_BASECLASS = function() end,
			GM = gamemode,
			TauntCamera = function() return {} end,
			hook = { Add = function() end },
			player_manager = {
				RegisterClass = function(name, _, base) registered[name] = base end,
			},
		}, { __index = _G })
		setfenv(assert(loadfile(ROOT .. class.path)), env)()
	end
	for name, base in pairs(registered) do
		if name ~= "player_default" then
			T.eq(registered[base] ~= nil, true, name .. "'s parent " .. tostring(base) .. " is registered")
		end
	end
end)

T.test("Simple Weapons player-class driver uses the published HL2, HL2 Extended, and CS:S classes", function()
	local given = {}
	local ply = {
		Give = function(_, class) given[#given + 1] = class end,
		GiveAmmo = function() end,
	}
	local function Contains(values, value)
		for _, candidate in ipairs(values) do
			if candidate == value then return true end
		end
		return false
	end

	Weapons.GiveHL2(ply)
	local HL2 = {
		"simple_hl2_crowbar", "simple_hl2_stunstick", "simple_hl2_pistol", "simple_hl2_smg1", "simple_hl2_frag",
		"simple_hl2_crossbow", "simple_hl2_shotgun", "simple_hl2_357", "simple_hl2_rpg", "simple_hl2_ar2",
	}
	T.eq(#given, #HL2, "HL2's standard weapons and no others")
	for _, class in ipairs(HL2) do
		T.eq(Contains(given, class), true, class .. " is in the HL2 loadout")
	end

	given = {}
	Weapons.GiveHL2AndExtended(ply)
	T.eq(#given, #HL2 + 9, "HL2's and HL2 Extended's")
	for _, class in ipairs(HL2) do
		T.eq(Contains(given, class), true, class .. " is in the HL2 and Extended loadout")
	end
	for _, class in ipairs({
		"simple_hl2e_alyxgun", "simple_hl2e_ar1", "simple_hl2e_ar3", "simple_hl2e_ar3_sniper",
		"simple_hl2e_arp", "simple_hl2e_autogun", "simple_hl2e_crossbow_he", "simple_hl2e_csniper",
		"simple_hl2e_oicw",
	}) do
		T.eq(Contains(given, class), true, class .. " is in the HL2 and Extended loadout")
	end

	given = {}
	Weapons.GiveCStrike(ply)
	T.eq(#given, 28)
	for _, class in ipairs({
		"simple_css_ak47", "simple_css_aug", "simple_css_awp", "simple_css_deagle", "simple_css_elite",
		"simple_css_famas", "simple_css_fiveseven", "simple_css_flashbang", "simple_css_g3sg1",
		"simple_css_galil", "simple_css_glock", "simple_css_hegrenade", "simple_css_knife", "simple_css_m249",
		"simple_css_m3", "simple_css_m4a1", "simple_css_mac10", "simple_css_mp5", "simple_css_p228",
		"simple_css_p90", "simple_css_scout", "simple_css_sg550", "simple_css_sg552", "simple_css_smokegrenade",
		"simple_css_tmp", "simple_css_ump", "simple_css_usp", "simple_css_xm1014",
	}) do
		T.eq(Contains(given, class), true, class .. " is in the CS:S loadout")
	end
end)

T.test("default combatant, CS:S combatant, and Sandcastle use their weapon drivers", function()
	local function Contains(values, value)
		for _, candidate in ipairs(values) do
			if candidate == value then return true end
		end
		return false
	end

	local function NewPlayer()
		local calls = { weapons = {}, ammo = {} }
		local ply = {
			RemoveAllAmmo = function() calls.removedAmmo = true end,
			Give = function(_, class) calls.weapons[#calls.weapons + 1] = class end,
			GiveAmmo = function(_, amount, ammo) calls.ammo[ammo] = amount end,
			SwitchToDefaultWeapon = function() calls.switched = true end,
		}
		return ply, calls
	end

	for _, path in ipairs({
		"player_class/player_combatant.lua",
		"player_class/player_combatant_cstrike.lua",
		"player_class/player_sandcastle.lua",
	}) do
		local definition
		local env = setmetatable({
			DEFINE_BASECLASS = function() end,
			GM = gamemode,
			TauntCamera = function() return {} end,
			player_manager = {
				RegisterClass = function(_, registered) definition = registered end,
			},
		}, { __index = _G })
		setfenv(assert(loadfile(ROOT .. path)), env)()
		local player, captured = NewPlayer()
		definition.Loadout({ Player = player })
		T.eq(captured.removedAmmo, true, path .. " clears old ammo")
		T.eq(captured.switched, true, path .. " selects a default weapon")
		T.eq(Contains(captured.weapons, "weapon_physcannon"), true, path .. " keeps the physcannon")
		T.eq(Contains(captured.weapons, "gmod_tool"), true, path .. " keeps the tool")
		T.eq(Contains(captured.weapons, "gmod_camera"), true, path .. " keeps the camera")
		-- each class its families of Simple Weapons: the combatant HL2's and
		-- HL2 Extended's, the CS:S combatant CS:S's, Sandcastle HL2's
		local FAMILIES = {
			["player_class/player_combatant.lua"] = { simple_hl2_ = true, simple_hl2e_ = true },
			["player_class/player_combatant_cstrike.lua"] = { simple_css_ = true },
			["player_class/player_sandcastle.lua"] = { simple_hl2_ = true },
		}
		local families = {}
		for _, weapon in ipairs(captured.weapons) do
			local family = weapon:match("^(simple_[%w]+_)")
			if family then families[family] = true end
		end
		for family in pairs(FAMILIES[path]) do T.eq(families[family], true, path .. " carries " .. family .. " weapons") end
		for family in pairs(families) do T.eq(FAMILIES[path][family], true, path .. " carries no " .. family .. " weapons") end
		T.eq(Contains(captured.weapons, "weapon_physgun"), path == "player_class/player_sandcastle.lua",
			path .. " preserves its physgun policy")
	end
end)

T.test("player_sandcastle is player_sandbox's sibling, without its move code", function()
	local base = { spawned = 0, modelled = 0 }
	function base.Spawn() base.spawned = base.spawned + 1 end
	function base.SetModel() base.modelled = base.modelled + 1 end
	local camera = {}
	for _, method in ipairs({ "ShouldDrawLocalPlayer", "CreateMove", "CalcView" }) do
		camera[method] = function() return true end
	end
	local definition
	local env = setmetatable({
		DEFINE_BASECLASS = function() end,
		BaseClass = base,
		GM = gamemode,
		TauntCamera = function() return camera end,
		string = setmetatable({
			Explode = function(_, text)
				local parts = {}
				for part in text:gmatch("%S+") do parts[#parts + 1] = part end
				return parts
			end,
		}, { __index = string }),
		Vector = function(text)
			local length = text == "0 0 0" and 0 or 1
			return { text = text, x = text, Length = function() return length end }
		end,
		player_manager = {
			RegisterClass = function(_, registered) definition = registered end,
		},
	}, { __index = _G })
	-- DEFINE_BASECLASS makes a local in the game; here the same name reads from env
	setfenv(assert(loadfile(ROOT .. "player_class/player_sandcastle.lua")), env)()

	for _, method in ipairs({ "StartMove", "Move", "FinishMove" }) do
		T.eq(definition[method], nil, method .. " is left to player_default")
	end
	for _, speed in ipairs({ "SlowWalkSpeed", "WalkSpeed", "RunSpeed", "DuckSpeed", "UnDuckSpeed" }) do
		T.eq(type(definition[speed]), "number", speed .. " is the class's own")
	end

	local info = { cl_playercolor = "1 0 0", cl_weaponcolor = "0 0 0", cl_playerbodygroups = "2 x" }
	local ply = { groups = {} }
	function ply:GetInfo(name) return info[name] end
	function ply:GetInfoNum() return 3 end
	function ply:SetSkin(skin) self.skin = skin end
	function ply:GetNumBodyGroups() return 3 end
	function ply:SetBodygroup(index, value) self.groups[index] = value end
	function ply:SetPlayerColor(color) self.playerColor = color end
	function ply:SetWeaponColor(color) self.weaponColor = color end
	function ply:IsPlayingTaunt() return false end
	local class = { Player = ply, TauntCam = definition.TauntCam }

	definition.Spawn(class)
	T.eq(base.spawned, 1, "Spawn runs player_default's")
	T.eq(ply.playerColor.text, "1 0 0", "the player's colour is their setting")
	T.eq(ply.weaponColor.x, 0.001, "a black weapon colour is lifted off zero")

	definition.SetModel(class)
	T.eq(base.modelled, 1, "SetModel runs player_default's")
	T.eq(ply.skin, 3, "the skin is the player's setting")
	T.eq(ply.groups[0], 2, "a bodygroup is the player's setting")
	T.eq(ply.groups[1], 0, "an unreadable bodygroup is the first")
	T.eq(ply.groups[2], 0, "a missing bodygroup is the first")

	T.eq(definition.ShouldDrawLocal(class), true, "the taunt camera draws the player")
	T.eq(definition.CreateMove(class, {}), true, "the taunt camera takes the command")
	T.eq(definition.CalcView(class, {}), true, "the taunt camera takes the view")
end)

T.finish()
