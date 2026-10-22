-- Admin > Gameplay Settings (ws_gameplay_settings, on the editor base
-- ws_editor): its fields in four sections, the round timer, respawn
-- times, win conditions and team scores, moved out of the Game Rules and
-- Round Timer editors, which keep their cart speed, their step and their
-- actions. The entity files run against a fake ENT and the editors
-- feature's methods.
local T = dofile("tests/harness.lua")

local DIR = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"
local RED, BLUE = 2, 3

local function Load(file, convars)
	local ENT = {}
	local env = setmetatable({
		ENT = ENT,
		AddCSLuaFile = function() end,
		DEFINE_BASECLASS = function() end,
		WS = { TEAM_RED = RED, TEAM_BLUE = BLUE, TeamName = {}, require = T.require, EditorAction = function() end },
		GetConVar = function(name)
			return {
				GetInt = function() return convars[name] end,
				SetInt = function(_, v) convars[name] = v end,
			}
		end,
		SERVER = true,
		CLIENT = false,
	}, { __index = _G })
	setfenv(assert(loadfile(DIR .. file)), env)()
	return ENT
end

local function Categories(ENT)
	local seen, order = {}, {}
	for _, field in ipairs(ENT.Fields) do
		if not seen[field.category] then
			seen[field.category] = true
			order[#order + 1] = field.category
		end
	end
	return order
end

local function Field(ENT, name)
	for _, field in ipairs(ENT.Fields) do if field.name == name then return field end end
end

-- The editors feature, recording what it is asked.
local function Editors()
	local e = { calls = {} }
	setmetatable(e, { __index = function(_, method)
		return function(_, ...)
			e.calls[#e.calls + 1] = { method, ... }
			return 7
		end
	end })
	return e
end

T.test("its fields are in four sections: round timer, respawn times, win conditions, team scores", function()
	local cats = Categories(Load("ws_gameplay_settings.lua", {}))
	T.eq(table.concat(cats, ", "), "Round timer, Respawn times, Win conditions, Team scores")
end)

T.test("it is the server's, never spawned from the menu, and only admins edit it", function()
	local ENT = Load("ws_gameplay_settings.lua", {})
	T.eq(ENT.Base, "ws_editor")
	T.eq(ENT.Spawnable, false)
	T.eq(ENT.AdminOnly, true)
end)

T.test("the win conditions are the rounds' convars, read and written through the editors feature", function()
	local ENT = Load("ws_gameplay_settings.lua", {})
	for name, convar in pairs({ WinLimit = "mp_winlimit", MaxRounds = "mp_maxrounds", TimeLimit = "mp_timelimit" }) do
		local field = Field(ENT, name)
		T.eq(field.category, "Win conditions", name)
		local e = Editors()
		T.eq(field.read(e), 7, name .. " read")
		field.write(e, 9)
		T.eq(e.calls[1][1], "WinCondition", name)
		T.eq(e.calls[1][2], convar, name)
		T.eq(e.calls[2][1], "SetWinCondition", name)
		T.eq(e.calls[2][2], convar, name)
		T.eq(e.calls[2][3], 9, name)
	end
end)

-- The editors feature's controller, its convars faked: those the rounds
-- feature creates exist only on a map with rounds.
local function Controller(convars)
	local env = setmetatable({
		WS = { TEAM_RED = RED, TEAM_BLUE = BLUE, require = function() return {} end },
		GetConVar = function(name)
			if convars[name] == nil then return nil end
			return {
				GetInt = function() return convars[name] end,
				SetInt = function(_, v) convars[name] = v end,
			}
		end,
	}, { __index = _G })
	return setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/features/editors/sv.lua")), env)()
end

T.test("a win condition reads and writes its convar", function()
	local convars = { mp_winlimit = 3 }
	local c = Controller(convars)
	T.eq(c:WinCondition("mp_winlimit"), 3)
	T.eq(c:SetWinCondition("mp_winlimit", 9), true)
	T.eq(convars.mp_winlimit, 9)
end)

T.test("on a map without rounds, whose convars were never made, a win condition reads 0 and refuses a change", function()
	local c = Controller({})
	T.eq(c:WinCondition("mp_maxrounds"), 0)
	local ok, why = c:SetWinCondition("mp_maxrounds", 9)
	T.eq(ok, false)
	T.eq(why, "this map has no rounds")
end)

T.test("scores, respawns and the timer go through the editors feature as before", function()
	local ENT = Load("ws_gameplay_settings.lua", {})
	local e = Editors()
	Field(ENT, "RedScore").write(e, 4)
	Field(ENT, "BluRespawn").write(e, 12)
	Field(ENT, "Paused").write(e, true)
	T.eq(e.calls[1][1], "SetScore")
	T.eq(e.calls[1][2], RED)
	T.eq(e.calls[2][1], "SetRespawnTime")
	T.eq(e.calls[2][2], BLUE)
	T.eq(e.calls[3][1], "SetPaused")
end)

T.test("the Game Rules Editor keeps only the cart speed; the Round Timer Editor its step and round time", function()
	local rules = Load("edit_gamerules.lua", {})
	T.eq(#rules.Fields, 1)
	T.eq(rules.Fields[1].name, "CartSpeed")
	local timer = Load("edit_roundtimer.lua", {})
	T.eq(#timer.Fields, 2)
	T.eq(timer.Fields[1].name, "TimeStep")
	T.eq(timer.Fields[2].name, "RoundTime", "Set Round Time's, on a map without an objective")
end)

T.finish()
