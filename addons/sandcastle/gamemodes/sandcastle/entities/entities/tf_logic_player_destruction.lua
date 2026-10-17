-- tf_logic_player_destruction (CTFPlayerDestructionLogic): makes the map
-- Player Destruction (foundation.rounds.destruction), over its payload
-- watchers (pd_watergate's UFO). Sandcastle plays no PD scoring yet, so it
-- is a stub: it accepts the logic's inputs (the capture zones' Score*Points)
-- and does nothing; the round limits decide its rounds.
ENT.Type = "point"
ENT.Base = "ws_stub_point"

ENT.StubReason = "Player Destruction scoring is not supported; the round limits decide its rounds"
ENT.StubInputs = {
	scoreredpoints = true,
	scorebluepoints = true,
	enablemaxscoreupdating = true,
	disablemaxscoreupdating = true,
	setcountdowntimer = true,
	setcountdownimage = true,
	setflagresetdelay = true,
	setpointsonplayerdeath = true,
}

function ENT:Initialize()
	baseclass.Get("ws_stub_point").Initialize(self)
	WS.Feature("rounds"):SetMode(WS.require("foundation.rounds.destruction").Mode)
end
