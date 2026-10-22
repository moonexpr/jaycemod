-- foundation.settings: the server convars an admin may set from the
-- Utilities menu on a dedicated server (ws_server_set), each held to
-- the range its menu control offers.
local T = dofile("tests/harness.lua")
local Settings = T.require("foundation.settings")
local AiWar = T.require("foundation.aiwar")
local Slots = T.require("foundation.aiwar.slots")

T.test("a value in range is accepted as the convar's text", function()
	T.eq(Settings.Parse("mp_aiwar_team_size", "6"), "6")
	T.eq(Settings.Parse("ws_aiwar_debug_full", "1"), "1")
	T.eq(Settings.Parse("ws_nodegraph_max_nodes", "2048"), "2048")
end)

T.test("a slider's fractional value rounds to the whole number its convar holds", function()
	T.eq(Settings.Parse("mp_aiwar_team_size", "5.6"), "6")
end)

T.test("a value outside the menu's range is refused, naming the range", function()
	local value, why = Settings.Parse("mp_aiwar_team_size", tostring(AiWar.TEAM_SIZE_MAX + 1))
	T.eq(value, nil)
	T.eq(why, "mp_aiwar_team_size takes -1 to " .. AiWar.TEAM_SIZE_MAX)
	T.eq((Settings.Parse("mp_aiwar_team_size", "-2")), nil)
end)

T.test("the team size may be the slot list's, -1, and the sides may be empty", function()
	T.eq(Settings.Parse("mp_aiwar_team_size", tostring(Slots.CUSTOM_SIZE)), "-1", "the slot list's")
	T.eq(Settings.Parse("mp_aiwar_team_size", "0"), "0", "nobody")
end)

T.test("text that is not a number is refused", function()
	local value, why = Settings.Parse("mp_aiwar_team_size", "eight")
	T.eq(value, nil)
	T.eq(why, "mp_aiwar_team_size takes a number, not \"eight\"")
end)

T.test("a convar not on the list is refused, so the command sets nothing else", function()
	local value, why = Settings.Parse("rcon_password", "x")
	T.eq(value, nil)
	T.eq(why, "rcon_password is not a setting the menu may change")
end)

T.test("each setting's range is what its menu control offers", function()
	local s = Settings.SETTINGS.mp_aiwar_team_size
	T.eq(s.min, Slots.CUSTOM_SIZE)
	T.eq(s.max, AiWar.TEAM_SIZE_MAX)
end)

T.test("every setting names the privilege that may change it", function()
	local Permissions = T.require("games.system.permissions")
	local known = {}
	for _, p in ipairs(Permissions.PRIVILEGES) do known[p.name] = true end
	for name, s in pairs(Settings.SETTINGS) do T.eq(known[s.privilege], true, name) end
	T.eq(Settings.SETTINGS.mp_aiwar_team_size.privilege, Permissions.NEXTSOLDIER)
	T.eq(Settings.SETTINGS.mp_winlimit.privilege, Permissions.RULES)
	T.eq(Settings.SETTINGS.mp_economy_enabled.privilege, Permissions.ECONOMY, "a superadmin toggle")
	T.eq(Settings.SETTINGS.tf_weapon_criticals.privilege, Permissions.GAMEPLAY, "a superadmin toggle")
end)

T.test("GMod's host-only NPCs and Server menu options are settings, behind server_options", function()
	local Permissions = T.require("games.system.permissions")
	for _, name in ipairs(Settings.PROXIED) do
		T.eq(Settings.SETTINGS[name] ~= nil, true, name)
		T.eq(Settings.SETTINGS[name].privilege, Permissions.SERVER_OPTIONS, name)
		T.eq(Settings.SETTINGS[name].min, 0, name .. " is a switch")
		T.eq(Settings.SETTINGS[name].max, 1, name .. " is a switch")
	end
	T.eq(#Settings.PROXIED, 11, "the NPCs menu's four and the Server menu's seven")
end)

T.test("Allowed says whether a holder of privileges may change a setting", function()
	local Permissions = T.require("games.system.permissions")
	local function Holds(...)
		local held = {}
		for _, n in ipairs({ ... }) do held[n] = true end
		return function(n) return held[n] == true end
	end
	T.eq(Settings.Allowed("mp_economy_enabled", Holds(Permissions.ECONOMY)), true)
	T.eq(Settings.Allowed("mp_economy_enabled", Holds(Permissions.RULES)), false)
	T.eq(Settings.Allowed("rcon_password", Holds(Permissions.RULES)), false, "not a setting")
end)

T.finish()
