AddCSLuaFile ("shared.lua")
AddCSLuaFile ("cl_init.lua")
include ("shared.lua")

local Model = WS.require ("features.builder.model")

-- A flag's states as Wire numbers.
local STATES = { home = 0, carried = 1, dropped = 2 }
local TEAM_NAMES = { [WS.TEAM_RED] = "RED", [WS.TEAM_BLUE] = "BLU" }

-- A flag is carried by the enemy, who captures it in a zone of their own.
function ENT:Compile (game)
	game:Add ({ class = "item_teamflag", name = self:CompiledName (), pos = self:GetPos (), keys = self:Keys () })
	local team = self:GetTeamNum ()
	local carriers = Model.EnemyOf (team)
	for _, zone in ipairs (game.by [Model.ZONE]) do
		if zone:GetTeamNum () == carriers then return end
	end
	game:ProblemOnce (TEAM_NAMES [carriers] .. " has no capture zone for " .. TEAM_NAMES [team] .. "'s flag")
end

function ENT:WireStatus (target)
	local flag = WS.Feature ("flag"):FlagAt (target)
	return { State = STATES [flag:State ()], CarrierTeam = flag:CarrierTeam () }
end
