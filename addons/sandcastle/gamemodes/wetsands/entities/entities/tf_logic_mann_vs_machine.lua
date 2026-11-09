-- tf_logic_mann_vs_machine (CMannVsMachineLogic, tf_mann_vs_machine_logic.cpp):
-- makes the map Mann vs. Machine. A binding to the mvm controller, which
-- puts the round in the MvM mode. It has no inputs or outputs we play.
ENT.Type = "point"
ENT.Base = "base_point"

function ENT:Initialize()
	WS.Feature("mvm")
end

function ENT:UpdateTransmitState()
	return TRANSMIT_NEVER
end
