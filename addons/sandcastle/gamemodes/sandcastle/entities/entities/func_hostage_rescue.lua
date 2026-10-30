-- func_hostage_rescue (CS:S): a hostage rescue zone. A hostage_entity asks
-- it whether it holds the hostage it observes (Holds), as the gamemode's
-- other volumes are asked rather than touched; a hostage led into it is
-- rescued. The hostage controller also reads it as a box (features/hostage/
-- sv.lua's RescueBoxes), for where the war leads the hostages. Nothing
-- collides with it; Enable and Disable as any volume (ws_brush_volume).
ENT.Type = "brush"
ENT.Base = "ws_brush_volume"

-- Whether ent's centre is inside it, while it is enabled.
function ENT:Holds(ent)
	return self.enabled and self:WorldToLocal(ent:WorldSpaceCenter()):WithinAABox(self:OBBMins(), self:OBBMaxs())
end
