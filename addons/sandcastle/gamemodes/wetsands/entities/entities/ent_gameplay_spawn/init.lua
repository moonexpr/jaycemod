AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:BodyModelPath()
	local chosen = self:GetBodyModel()
	return chosen ~= "" and chosen or self.MarkerModel
end

function ENT:Compile(game)
	game:Add({ class = "info_player_teamspawn", name = self:CompiledName(), pos = self:GetPos(), keys = self:Keys() })
end
