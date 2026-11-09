include("shared.lua")

local BOUNDS_MINS, BOUNDS_MAXS = Vector(-64, -64, 0), Vector(64, 64, 200)
local LABEL_HEIGHT, LABEL_SCALE = 208, 0.5

-- Its plate and hologram, and its name above them.
function ENT:Draw()
	self:DrawModel()
	self:DrawHologram()
	local name = self:GetPrintName()
	if name == "" then return end
	cam.Start3D2D(self:GetPos() + Vector(0, 0, LABEL_HEIGHT), Angle(0, LocalPlayer():EyeAngles().y - 90, 90), LABEL_SCALE)
		draw.SimpleText(name, "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	cam.End3D2D()
end

function ENT:UpdateRenderBounds()
	self:SetRenderBounds(BOUNDS_MINS, BOUNDS_MAXS)
end
