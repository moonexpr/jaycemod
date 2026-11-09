-- The Control Point tool's point, or the Trolley tool's checkpoint on a node: a
-- team_control_point, its plate, and, standing alone, its trigger_capture_area.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Control Point"
ENT.Kind = Model.POINT
ENT.MarkerModel = "models/props_gameplay/cap_point_base.mdl"
ENT.OwnBox = true
ENT.AREA = "area"
local OWNERS = { Neutral = WS.TEAM_UNASSIGNED, RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE }
local WARN = { Normal = 0, ["Final point"] = 1, Never = 2 }
ENT.Properties = {
	{ name = "PrintName", key = "point_printname", type = "String", title = "Print Name", default = "" },
	{ name = "DefaultOwner", key = "point_default_owner", type = "Int", title = "Default Owner", default = WS.TEAM_UNASSIGNED, values = OWNERS },
	{ name = "PointIndex", type = "Int", title = "Index (-1: as placed)", default = -1, min = -1, max = 16,
		help = "This point's place in the capture order, lowest first. While tf_caplinear is on, a team must hold the point before it to capture this one. -1 goes after the indexed points, in the order placed." },
	{ name = "Group", key = "point_group", type = "Int", title = "Group Index", default = 0, min = 0, max = 16,
		help = "Points with the same number form a group, and a team holding every point of any one group wins the round. Leave every point at 0 to make a team hold them all; a point alone in its group wins the round by itself." },
	{ name = "StartLocked", key = "point_start_locked", type = "Bool", title = "Start locked", default = false },
	{ name = "WarnOnCap", key = "point_warn_on_cap", type = "Int", title = "Warning Type", default = 0, values = WARN },
	{ name = "TimeToCap", key = "area_time_to_cap", target = ENT.AREA, type = "Float", title = "Time to cap (seconds)", category = "Capture area", default = 5, min = 1, max = 600 },
	{ name = "CanCapRed", key = "team_cancap_2", target = ENT.AREA, type = "Bool", title = "Can RED cap?", category = "Capture area", default = true },
	{ name = "CanCapBlu", key = "team_cancap_3", target = ENT.AREA, type = "Bool", title = "Can BLU cap?", category = "Capture area", default = true },
	{ name = "NumCapRed", key = "team_numcap_2", target = ENT.AREA, type = "Int", title = "Number of RED to cap", category = "Capture area", default = 1, min = 1, max = 16 },
	{ name = "NumCapBlu", key = "team_numcap_3", target = ENT.AREA, type = "Int", title = "Number of BLU to cap", category = "Capture area", default = 1, min = 1, max = 16 },
	{ name = "SpawnAdjustRed", key = "team_spawn_2", target = ENT.AREA, type = "Int", title = "Spawn adjust for RED", category = "Capture area", default = 0, min = -60, max = 60 },
	{ name = "SpawnAdjustBlu", key = "team_spawn_3", target = ENT.AREA, type = "Int", title = "Spawn adjust for BLU", category = "Capture area", default = 0, min = -60, max = 60 },
}
ENT.WirePorts = { inputs = { "Locked", "Owner" }, outputs = { "Owner", "Capturing" } }
ENT.WireCommands = { Locked = Model.WireValue("SetLocked"), Owner = Model.WireValue("SetOwner") }
