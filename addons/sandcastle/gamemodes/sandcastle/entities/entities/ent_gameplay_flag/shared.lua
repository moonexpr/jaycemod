-- The Flag tool's flag: an item_teamflag.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Flag"
ENT.Kind = Model.FLAG
ENT.MarkerModel = "models/flag/briefcase.mdl"
ENT.OwnBox = true
ENT.Properties = {
	{ name = "TeamNum", key = "TeamNum", type = "Int", title = "Team", default = WS.TEAM_RED, values = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE } },
	{ name = "ReturnTime", key = "ReturnTime", type = "Int", title = "Return Time (seconds)", default = 60, min = 0, max = 600 },
	{ name = "StartDisabled", key = "startdisabled", type = "Bool", title = "Start Disabled", default = false },
}
ENT.WirePorts = { inputs = { "Enabled", "Reset", "Team" }, outputs = { "State", "CarrierTeam" } }
ENT.WireCommands = {
	Enabled = Model.WireSwitch("Enable", "Disable"),
	Reset = Model.WirePulse("ForceReset"),
	Team = Model.WireValue("SetTeam"),
}
