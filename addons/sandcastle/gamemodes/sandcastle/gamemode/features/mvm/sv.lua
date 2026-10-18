-- The mvm feature's controller: CTFGameRules::Activate makes a map with a
-- tf_logic_mann_vs_machine MvM (features.mvm.model), and the flag panel
-- shows the bomb (ws_mvm). The bombs and their delivery are the flag
-- feature's; mvm_mannhattan's gates (trigger_timer_door) the capture
-- feature's.
--
-- Loaded by tf_logic_mann_vs_machine. It loads rounds.
local Mvm = WS.require("features.mvm.model")

local Controller = {
	rounds = WS.Feature("rounds"),
}

Controller.rounds:SetMode(Mvm.Mode)
SetGlobal2Bool("ws_mvm", true)

return Controller
