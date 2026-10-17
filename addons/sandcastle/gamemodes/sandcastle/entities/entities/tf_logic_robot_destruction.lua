-- tf_logic_robot_destruction (CTFRobotDestructionLogic): makes the map
-- Robot Destruction (foundation.rounds.destruction), over any payload
-- watchers. Sandcastle plays no RD scoring yet, so it is a stub: it accepts
-- the logic's inputs and does nothing; the round limits decide its rounds.
ENT.Type = "point"
ENT.Base = "ws_stub_point"

ENT.StubReason = "Robot Destruction scoring is not supported; the round limits decide its rounds"
ENT.StubInputs = {
	roundactivate = true,
}

function ENT:Initialize()
	baseclass.Get("ws_stub_point").Initialize(self)
	WS.Feature("rounds"):SetMode(WS.require("foundation.rounds.destruction").Mode)
end
