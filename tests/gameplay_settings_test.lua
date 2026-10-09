-- Admin > Gameplay Settings (wetsand_gameplay_settings, on the editor base
-- wetsand_editor): its fields in four sections, the round timer, respawn
-- times, win conditions and team scores, moved out of the Game Rules and
-- Round Timer editors, which keep their cart speed, their step and their
-- actions. The entity files run against a fake ENT and the editors
-- feature's methods.
local T = dofile("tests/harness.lua")

local DIR = "addon/gamemodes/sandcastle/entities/entities/"
local RED, BLUE = 2, 3

local function Load(file, convars)
	local ENT = {}
	local env = setmetatable({
		ENT = ENT,
		AddCSLuaFile = function() end,
		DEFINE_BASECLASS = function() end,
		WETSAND = { TEAM_RED = RED, TEAM_BLUE = BLUE, TeamName = {}, EditorAction = function() end },
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
	local cats = Categories(Load("wetsand_gameplay_settings.lua", {}))
	T.eq(table.concat(cats, ", "), "Round timer, Respawn times, Win conditions, Team scores")
end)

T.test("it is the server's, never spawned from the menu, and only admins edit it", function()
	local ENT = Load("wetsand_gameplay_settings.lua", {})
	T.eq(ENT.Base, "wetsand_editor")
	T.eq(ENT.Spawnable, false)
	T.eq(ENT.AdminOnly, true)
end)

T.test("the win conditions are the rounds' convars, read and written", function()
	local convars = { mp_winlimit = 3, mp_maxrounds = 5, mp_timelimit = 30 }
	local ENT = Load("wetsand_gameplay_settings.lua", convars)
	for name, convar in pairs({ WinLimit = "mp_winlimit", MaxRounds = "mp_maxrounds", TimeLimit = "mp_timelimit" }) do
		local field = Field(ENT, name)
		T.eq(field.category, "Win conditions", name)
		T.eq(field.read(Editors()), convars[convar], name .. " read")
		field.write(Editors(), 9)
		T.eq(convars[convar], 9, name .. " written")
	end
end)

T.test("scores, respawns and the timer go through the editors feature as before", function()
	local ENT = Load("wetsand_gameplay_settings.lua", {})
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

T.test("the Game Rules Editor keeps only the cart speed; the Round Timer Editor only its step", function()
	local rules = Load("edit_gamerules.lua", {})
	T.eq(#rules.Fields, 1)
	T.eq(rules.Fields[1].name, "CartSpeed")
	local timer = Load("edit_roundtimer.lua", {})
	T.eq(#timer.Fields, 1)
	T.eq(timer.Fields[1].name, "TimeStep")
end)

T.finish()
