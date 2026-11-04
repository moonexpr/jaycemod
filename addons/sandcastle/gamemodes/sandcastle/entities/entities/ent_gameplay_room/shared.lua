-- The Spawn tool's spawn room: a func_respawnroom, its bounds two corners clicked.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Spawn Room"
ENT.Kind = Model.ROOM
ENT.MarkerModel = "models/hunter/blocks/cube025x025x025.mdl"
ENT.Properties = {
	{ name = "TeamNum", key = "TeamNum", type = "Int", title = "Team", default = WS.TEAM_RED, values = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE } },
	{ name = "StartDisabled", key = "startdisabled", type = "Bool", title = "Start Disabled", default = false },
}
ENT.WirePorts = { inputs = { "Active", "Team" }, outputs = {} }
ENT.WireCommands = { Active = Model.WireSwitch("SetActive", "SetInactive"), Team = Model.WireValue("SetTeam") }
