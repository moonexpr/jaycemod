-- foundation.settings: the server convars an admin may set from the
-- Utilities menu on a dedicated server (wetsand_server_set), each held to
-- the range its menu control offers.
local T = dofile("tests/harness.lua")
local Settings = T.require("foundation.settings")
local AiWar = T.require("foundation.aiwar")
local Slots = T.require("foundation.aiwar.slots")

T.test("a value in range is accepted as the convar's text", function()
	T.eq(Settings.Parse("mp_aiwar_team_size", "6"), "6")
	T.eq(Settings.Parse("wetsand_aiwar_debug_full", "1"), "1")
	T.eq(Settings.Parse("wetsand_nodegraph_max_nodes", "2048"), "2048")
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

T.finish()
