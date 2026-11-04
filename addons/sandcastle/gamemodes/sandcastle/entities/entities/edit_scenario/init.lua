AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

-- GMod clears the global once the file has run.
local ENT = ENT

local Model = WS.require("features.builder.model")

local MASTER_NAME, CLOCK_NAME, WIN_NAME = "build_master", "build_clock", "build_win"
local Properties = ENT.Properties

function ENT:SpawnFunction(ply, tr, class)
	if not GetGlobal2Bool("ws_builder_available", false) then
		ply:ChatPrint("[Gameplay] This map has its own objectives.")
		return
	end
	if IsValid(ents.FindByClass(class)[1]) then
		ply:ChatPrint("There is already a " .. self.PrintName .. " on this map")
		return
	end
	if not tr.Hit then return end
	return WS.Feature("builder"):Create(ply, Model.SCENARIO, tr.HitPos + tr.HitNormal * 16, angle_zero)
end

-- A property's value from the editor, or its default on a map with none.
local function Reader(editor)
	return function(name)
		if editor then return editor["Get" .. name](editor) end
		for _, prop in ipairs(Properties) do
			if prop.name == name then return prop.default end
		end
	end
end

-- The master and clock points play under, and what it tells the gamerules: what
-- a map's outputs would. A game takes these with or without an editor.
function ENT.CompileAll(editors, game)
	local read = Reader(editors[1])
	for _, prop in ipairs(Properties) do
		local value = read(prop.name)
		if prop.rules and value ~= prop.default then game.rules[#game.rules + 1] = { input = prop.rules, param = Model.Text(value) } end
	end
	if game.pointIndex == 0 then return end
	local track = game.track
	local holder = track and Model.EnemyOf(track.pusher)
	local master = Model.Keys(Properties, read)
	if holder and not master.cpm_restrict_team_cap_win then master.cpm_restrict_team_cap_win = tostring(holder) end
	game:Add({ class = "team_control_point_master", name = MASTER_NAME, keys = master })
	local chosen = read("TimerWinner")
	local winner = chosen ~= -1 and chosen or holder or WS.TEAM_UNASSIGNED
	game:Add({ class = "game_round_win", name = WIN_NAME, keys = { TeamNum = tostring(winner), force_map_reset = "1" } })
	local clock = Model.Keys(Properties, read, ENT.CLOCK)
	clock.start_paused, clock.show_in_hud, clock.auto_countdown = "0", "1", "1"
	game:Add({
		class = "team_round_timer",
		name = CLOCK_NAME,
		keys = clock,
		outputs = { { key = "OnFinished", value = string.format("%s,RoundWin,,0,-1", WIN_NAME) } },
	})
end

-- Its inputs are the gamerules', whether a game has entities of its own or not.
function ENT:WireTarget()
	return WS.Rules
end

function ENT:WireStatus()
	return { RoundState = WS.State(), Winner = GetGlobal2Int("ws_round_winner", WS.TEAM_UNASSIGNED) }
end
