-- tf_spell_pickup: a stub until the spellbook package (W7 in
-- docs/pass3-halloween.md) replaces it with the real pickup on
-- wetsand_pickup_base. It exists so the maps' point_templates holding spell
-- pickups (spell_pickup_template) have their templates and their I/O
-- (Enable, Disable, Toggle, Kill) resolves. It shows nothing and gives
-- nothing: OnPlayerTouch never fires. A pickup dropped by a skeleton king
-- (the holiday controller's DropSpellPickup, Configure{ tier, dropped,
-- velocity }) removes itself at once.
ENT.Type = "point"
ENT.Base = "wetsand_inert_point"

local Base = baseclass.Get("wetsand_inert_point")

function ENT:Configure(config)
	self.configured = config
end

function ENT:Initialize()
	Base.Initialize(self)
	if self.configured and self.configured.dropped then self:Remove() end
end
