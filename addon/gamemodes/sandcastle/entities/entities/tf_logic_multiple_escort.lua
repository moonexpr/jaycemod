-- tf_logic_multiple_escort (CMultipleEscort, tf_gamerules.cpp): marks a
-- payload race map, one train per team. It has no keyvalues or I/O; binding
-- it makes the payload controller's HasMultipleTrains() true, which shows
-- both carts on the HUD and plays the race outcome lines.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:Initialize()
	WETSAND.Feature("payload"):BindEscort(self)
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end
