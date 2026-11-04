AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

-- GMod clears the global once the file has run.
local ENT = ENT

local Model = WS.require("features.builder.model")

local FLOOR_HEIGHT = 48
-- A surface this level is ground, and a sign on it stands up and faces the player.
local GROUND_NORMAL_Z = 0.7
local ARROW_SUFFIX = {
	[ENT.ARROW_LEFT] = "_witharrow_l",
	[ENT.ARROW_RIGHT] = "_witharrow_r",
	[ENT.ARROW_NONE] = "",
}
local FLIPPED = {
	[ENT.ARROW_LEFT] = ENT.ARROW_RIGHT,
	[ENT.ARROW_RIGHT] = ENT.ARROW_LEFT,
	[ENT.ARROW_NONE] = ENT.ARROW_NONE,
}

function ENT.ModelFor(arrow, small)
	return "models/props_gameplay/sign_gameplay01" .. ARROW_SUFFIX[arrow] .. (small and "_sm" or "") .. ".mdl"
end

function ENT.Flip(arrow)
	return FLIPPED[arrow]
end

function ENT:BodyModelPath()
	return ENT.ModelFor(self:GetArrow(), self:GetSmall())
end

function ENT:Settle()
	self.BaseClass.Settle(self)
	self:SetSkin(self:GetSignSkin())
end

function ENT:SetInGame()
end

-- A wired sign's own input.
function ENT:SetVisible(value)
	self:SetNoDraw(value == 0)
end

function ENT.Prepare(ply, trace)
	local normal = trace.HitNormal
	if math.abs(normal.z) > GROUND_NORMAL_Z then
		return trace.HitPos + Vector(0, 0, FLOOR_HEIGHT), Angle(0, (ply:GetPos() - trace.HitPos):Angle().y, 0)
	end
	return trace.HitPos + normal, normal:Angle()
end

-- The Signage tool's right click.
function ENT.FlipAt(ply, trace)
	local sign = WS.Feature("builder"):PieceOf(trace, Model.SIGN)
	if not sign then return false end
	sign:Update({ Arrow = ENT.Flip(sign:GetArrow()) })
	return true
end
