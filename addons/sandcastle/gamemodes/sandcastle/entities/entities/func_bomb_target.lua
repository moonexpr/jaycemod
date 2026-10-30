-- func_bomb_target (CS:S): a bomb site. It binds to the defuse controller
-- (features/defuse), which loads with it and makes the site a control point
-- RED captures to plant the bomb and BLU to defuse it, its capture areas on
-- this brush. It is asked whether it holds an entity (Holds), as the
-- gamemode's other volumes are; nothing collides with it.
ENT.Type = "brush"
ENT.Base = "ws_brush_volume"

function ENT:VolumeInit()
	self.defuse = WS.Feature("defuse")
	self.defuse:BindSite(self)
end

function ENT:OnRemove()
	if self.defuse then self.defuse:UnbindSite(self) end
end

-- Whether ent's centre is inside it.
function ENT:Holds(ent)
	return self:WorldToLocal(ent:WorldSpaceCenter()):WithinAABox(self:OBBMins(), self:OBBMaxs())
end
