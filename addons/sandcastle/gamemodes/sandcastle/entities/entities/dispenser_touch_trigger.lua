-- dispenser_touch_trigger (CDispenserTouchTrigger): the volume a
-- mapobj_cart_dispenser heals players in. A disabled trigger touches nobody.
ENT.Type = "brush"
ENT.Base = "ws_brush_volume"

function ENT:IsEnabled()
	return self.enabled
end
