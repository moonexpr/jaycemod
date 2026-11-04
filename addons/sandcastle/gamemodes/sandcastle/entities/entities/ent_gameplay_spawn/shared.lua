-- The Spawn tool's spawner: where a team spawns, an info_player_teamspawn.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Spawner"
ENT.Kind = Model.SPAWN
ENT.MarkerModel = Model.SPAWN_MODELS[1]
ENT.Properties = {
	{ name = "TeamNum", key = "TeamNum", type = "Int", title = "Team", default = WS.TEAM_RED, values = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE } },
	{ name = "StartDisabled", key = "startdisabled", type = "Bool", title = "Start Disabled", default = false },
}
ENT.WirePorts = { inputs = { "Enabled", "Team" }, outputs = {} }
ENT.WireCommands = { Enabled = Model.WireSwitch("Enable", "Disable"), Team = Model.WireValue("SetTeam") }
