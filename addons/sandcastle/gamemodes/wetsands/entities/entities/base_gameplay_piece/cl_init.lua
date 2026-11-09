include("shared.lua")

-- Edit Properties' rows that show a property's help on their tooltip, as Hammer
-- does beside a keyvalue. A row's type names its control; each of these is the
-- plain one with the help on the row, which its label and field both ask.
for _, kind in ipairs({ "Generic", "Int", "Float", "Boolean", "Combo" }) do
	local plain = "DProperty_" .. kind
	derma.DefineControl("DProperty_Help" .. kind, "", {
		Setup = function(self, vars)
			vgui.GetControlTable(plain).Setup(self, vars)
			self:GetRow():SetTooltip(vars.help)
		end,
	}, plain)
end

-- Its model, and a volume's box.
function ENT:Draw()
	self:DrawModel()
	if self:GetBoxMaxs() ~= vector_origin then
		render.DrawWireframeBox(self:GetPos(), angle_zero, self:GetBoxMins(), self:GetBoxMaxs(), self:GetColor(), true)
	end
end

local HOLOGRAM = "models/effects/cappoint_hologram.mdl"

-- A control point's hologram as it stands while building: in a game the capture
-- feature's point shows it.
function ENT:DrawHologram()
	if not IsValid(self.hologram) then
		self.hologram = ClientsideModel(HOLOGRAM)
		self.hologram:SetNoDraw(true)
	end
	self.hologram:SetPos(self:GetPos())
	local color = self:GetColor()
	render.SetColorModulation(color.r / 255, color.g / 255, color.b / 255)
	self.hologram:DrawModel()
	render.SetColorModulation(1, 1, 1)
end

-- Drawn as far as its box reaches, not its model.
function ENT:UpdateRenderBounds()
	if self:GetBoxMaxs() ~= vector_origin then self:SetRenderBounds(self:GetBoxMins(), self:GetBoxMaxs()) end
end

function ENT:Think()
	self:UpdateRenderBounds()
	self:SetNextClientThink(CurTime() + 0.2)
	return true
end

function ENT:OnRemove()
	if IsValid(self.hologram) then self.hologram:Remove() end
end
