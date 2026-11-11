-- The Spawn tool's resupply closet: TF2's locker and the func_regenerate before it.
local Model = WS.require ("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Resupply Closet"
ENT.Kind = Model.LOCKER
ENT.MarkerModel = "models/props_gameplay/resupply_locker.mdl"
ENT.OwnBox = true
ENT.Properties =
{
	{ name = "TeamNum", key = "TeamNum", type = "Int", title = "Team", default = WS.TEAM_RED, values = { RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE } },
	{ name = "StartDisabled", key = "startdisabled", type = "Bool", title = "Start Disabled", default = false }
}
ENT.WirePorts = { inputs = { "Enabled", "Team" }, outputs = {} }
ENT.WireCommands = { Enabled = Model.WireSwitch ("Enable", "Disable"), Team = Model.WireValue ("SetTeam") }
