-- The Flag tool's capture zone: a func_capturezone, where its team brings a flag.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Capture Zone"
ENT.Kind = Model.ZONE
ENT.MarkerModel = "models/hunter/blocks/cube025x025x025.mdl"
ENT.Properties = {
	{ name = "TeamNum", key = "TeamNum", type = "Int", title = "Team", default = WS.TEAM_RED, values = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE } },
	{ name = "StartDisabled", key = "startdisabled", type = "Bool", title = "Start Disabled", default = false },
}
ENT.WirePorts = { inputs = { "Enabled", "Team" }, outputs = { "Captures" } }
ENT.WireCommands = { Enabled = Model.WireSwitch("Enable", "Disable"), Team = Model.WireValue("SetTeam") }
