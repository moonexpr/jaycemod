-- func_hostage_rescue (CS:S): a hostage rescue zone. A hostage_entity asks
-- it whether it holds the hostage it observes (Holds), as the gamemode's
-- other volumes are asked rather than touched; a hostage led into it is
-- rescued. The hostage controller also reads it as a box (features/hostage/
-- sv.lua's RescueBoxes), for where the war leads the hostages. Nothing
-- collides with it; Enable and Disable as any volume (base_brush2).
ENT.Type = "brush"
ENT.Base = "base_brush2"

-- Whether ent's centre is inside it, while it is enabled.
function ENT:Holds(ent)
	return self.enabled and self:WorldToLocal(ent:WorldSpaceCenter()):WithinAABox(self:OBBMins(), self:OBBMaxs())
end
