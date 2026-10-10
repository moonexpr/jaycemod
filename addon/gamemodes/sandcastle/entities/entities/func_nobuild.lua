-- func_nobuild: where engineers may not build. There are no buildings in GMod,
-- so this only keeps its state and answers its inputs.
ENT.Type = "brush"
ENT.Base = "ws_brush_volume"

function ENT:VolumeInit()
	self.active = true
end

ENT.Inputs = {
	setactive = function(self) self.active = true end,
	setinactive = function(self) self.active = false end,
	toggleactive = function(self) self.active = not self.active end,
}
