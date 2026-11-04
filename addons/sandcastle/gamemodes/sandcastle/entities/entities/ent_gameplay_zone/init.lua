AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local ZONE_RADIUS, ZONE_HEIGHT = 64, 128

function ENT.Prepare(ply, trace)
	return trace.HitPos + Vector(0, 0, 2), angle_zero, {
		mins = Vector(-ZONE_RADIUS, -ZONE_RADIUS, 0),
		maxs = Vector(ZONE_RADIUS, ZONE_RADIUS, ZONE_HEIGHT),
	}
end

function ENT:Compile(game)
	game:Add({ class = "func_capturezone", name = self:CompiledName(), pos = self:GetPos(), keys = self:Keys(), mins = self:GetBoxMins(), maxs = self:GetBoxMaxs() })
end

function ENT:WireStatus()
	return { Captures = WS.Feature("flag").tally:Captures(self:GetTeamNum()) }
end
