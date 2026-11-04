-- The Scenario Editor: a game built with the Gameplay tools, as a Sandbox editor
-- like the Sky Editor. Its properties are those of the team_control_point_master,
-- team_round_timer and tf_gamerules a Hammer map would hold (capture layout,
-- scoring, the clock, respawn waves); its Wire inputs set the respawn waves and
-- scores as a game runs. A map has at most one.
local Model = WS.require("features.builder.model")

ENT.Type = "anim"
ENT.Base = "base_gameplay_piece"
ENT.PrintName = "Scenario Editor"
ENT.Information = "Right click on this entity via the context menu and select 'Edit Properties' to set up the game."
ENT.Category = "Editors"
ENT.Kind = Model.SCENARIO
ENT.Spawnable = true
ENT.MarkerModel = "models/maxofs2d/cube_tool.mdl"
ENT.OwnBox = true
ENT.CLOCK = "clock"
local MASTER, TIMER, RULES = "Control Point Master", "Round Timer", "Game Rules"
ENT.Properties = {
	{ name = "CapLayout", key = "caplayout", type = "String", title = "Cap Layout (0 1, 2)", category = MASTER, default = "" },
	{ name = "ScoreStyle", key = "score_style", type = "Int", title = "Scoring style", category = MASTER, default = 0, values = { ["Per round"] = 0, ["Per capture"] = 1 } },
	{ name = "RestrictWin", key = "cpm_restrict_team_cap_win", auto = -1, type = "Int", title = "Restrict team from winning", category = MASTER, default = -1, values = { Automatic = -1, Neither = 1, RED = WS.TEAM_RED, BLU = WS.TEAM_BLUE } },
	{ name = "SwitchTeams", key = "switch_teams", type = "Bool", title = "Switch teams on map win?", category = MASTER, default = false },
	{ name = "PlayAllRounds", key = "play_all_rounds", type = "Bool", title = "Play all rounds before changelevel", category = MASTER, default = false },
	{ name = "PartialCapRate", key = "partial_cap_points_rate", type = "Float", title = "Partial cap rate", category = MASTER, default = 0, min = 0, max = 10 },
	{ name = "TimerLength", key = "timer_length", target = ENT.CLOCK, type = "Int", title = "Timer length (seconds)", category = TIMER, default = 600, min = 1, max = 3600 },
	{ name = "MaxLength", key = "max_length", target = ENT.CLOCK, type = "Int", title = "Max timer length (0: none)", category = TIMER, default = 0, min = 0, max = 3600 },
	{ name = "SetupLength", key = "setup_length", target = ENT.CLOCK, type = "Int", title = "Setup time (seconds)", category = TIMER, default = 0, min = 0, max = 600 },
	{ name = "TimerWinner", type = "Int", title = "When it runs out", category = TIMER, default = -1, values = { Automatic = -1, Stalemate = WS.TEAM_UNASSIGNED, ["RED wins"] = WS.TEAM_RED, ["BLU wins"] = WS.TEAM_BLUE } },
	{ name = "RedRespawn", rules = "SetRedTeamRespawnWaveTime", type = "Float", title = "RED respawn wave (seconds; 0: server's)", category = RULES, default = 0, min = 0, max = 120 },
	{ name = "BluRespawn", rules = "SetBlueTeamRespawnWaveTime", type = "Float", title = "BLU respawn wave (seconds; 0: server's)", category = RULES, default = 0, min = 0, max = 120 },
	{ name = "RedGoal", rules = "SetRedTeamGoalString", type = "String", title = "RED goal", category = RULES, default = "" },
	{ name = "BluGoal", rules = "SetBlueTeamGoalString", type = "String", title = "BLU goal", category = RULES, default = "" },
	{ name = "StalemateOnTimelimit", rules = "SetStalemateOnTimelimit", type = "Bool", title = "Stalemate on the time limit", category = RULES, default = false },
}
ENT.WirePorts = {
	inputs = { "RedRespawnTime", "BluRespawnTime", "AddRedScore", "AddBluScore" },
	outputs = { "RoundState", "Winner" },
}
ENT.WireCommands = {
	RedRespawnTime = Model.WireValue("SetRedTeamRespawnWaveTime"),
	BluRespawnTime = Model.WireValue("SetBlueTeamRespawnWaveTime"),
	AddRedScore = Model.WireValue("AddRedTeamScore"),
	AddBluScore = Model.WireValue("AddBlueTeamScore"),
}
