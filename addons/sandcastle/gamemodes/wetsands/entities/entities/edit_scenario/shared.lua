-- The Scenario Editor: a game built with the Gameplay tools, as a Sandbox editor
-- like the Sky Editor. Its properties are those of the team_control_point_master,
-- team_round_timer and tf_gamerules a Hammer map would hold (capture layout,
-- scoring, the clock, respawn waves); its Wire inputs set the respawn waves and
-- scores as a game runs. A map has at most one.
local Model = WS.require ("features.builder.model")

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
ENT.KOTH = "koth"
local MASTER, TIMER, KOTH, RULES = "Control Point Master", "Round Timer", "King of the Hill", "Game Rules"

-- TF2's own goal lines, by the words a player reads: its language files word them
-- in each player's language (WS.Localize).
local RED_GOALS =
{
	["None"] = "",
	["Defend the Control points against team BLU!"] = "#Dustbowl_red_setup_goal",
	["Defend the final two Control Points or the enemy will win the game!"] = "#Dustbowl_red_final_goal",
	["Defend all three Control Points against team BLU to win the game!"] = "#Gravelpit_red_setup_goal",
	["Capture all five of the Control Points to win the game!"] = "#CP5_red_setup_goal",
	["Capture BLU's single Control Point to win the round. Prevent them from doing the same!"] = "#Hydro_red_setup_goal",
	["Capture and hold the Control Point to win the game!"] = "#koth_setup_goal",
	["Prevent the enemy team from moving the cart to your base!"] = "#Goldrush_red_setup_goal",
	["Prevent the cart from moving to your base or the enemy will win the game!"] = "#Goldrush_red_final_goal",
	["Grab the Intelligence Briefcase from the enemy basement. Return to your basement to win!"] = "#2fort_red_setup_goal",
	["Steal the Intelligence Briefcase from the enemy base."] = "#ctf_turbine_winter_team_goal",
	["Kill the enemy team or capture the point!"] = "#arena_perks_team_goal"
}
local BLU_GOALS =
{
	["None"] = "",
	["Capture both Control Points to win the round and advance!"] = "#Dustbowl_blue_setup_goal",
	["Capture the final two Control Points to win the game!"] = "#Dustbowl_blue_final_goal",
	["Capture all three Controls Points to win! First capture A and B, then move on to C."] = "#Gravelpit_blue_setup_goal",
	["Capture all five of the Control Points to win the game!"] = "#CP5_blue_setup_goal",
	["Capture RED's single Control Point to win the round. Prevent them from doing the same!"] = "#Hydro_blue_setup_goal",
	["Capture and hold the Control Point to win the game!"] = "#koth_setup_goal",
	["Move the cart to the Control Points to win the round and advance!"] = "#Goldrush_blue_setup_goal",
	["Move the cart to the enemy base to destroy it and win the game!"] = "#Goldrush_blue_final_goal",
	["Grab the Intelligence Briefcase from the enemy basement. Return to your basement to win!"] = "#2fort_blue_setup_goal",
	["Steal the Intelligence Briefcase from the enemy base."] = "#ctf_turbine_winter_team_goal",
	["Kill the enemy team or capture the point!"] = "#arena_perks_team_goal"
}

-- Titles, choices and help are tf.fgd's, as Hammer shows them. Automatic is ours:
-- what the layout calls for, which a Hammer author would work out by hand.
ENT.Properties =
{
	{ name = "CapLayout", key = "caplayout", type = "String", title = "Cap Layout", category = MASTER, default = "",
		help = "A string that tells the HUD how to lay out the cap points. It should be a string with indexes of cap points seperated by commas to denote a new line. So <2,0 1> would create a pyramid, with cap point 2 on the top and cap points 0 & 1 on the bottom." },
	{ name = "ScoreStyle", key = "score_style", type = "Int", title = "Scoring style", category = MASTER, default = 0,
		values = { ["Add team score for each round won"] = 0, ["Add team score for each captured point"] = 1 },
		help = "Sets the style of scoring used for capture point maps." },
	{ name = "RestrictWin", key = "cpm_restrict_team_cap_win", auto = -1, type = "Int", title = "Restrict team from winning", category = MASTER, default = -1,
		values = { Automatic = -1, Neither = 0, Both = 1, Red = WS.TEAM_RED, Blue = WS.TEAM_BLUE },
		help = "Prevent this team from winning by capping all the points. Automatic: the team holding a track, else neither." },
	{ name = "SwitchTeams", key = "switch_teams", type = "Bool", title = "Switch teams on map win?", category = MASTER, default = false,
		help = "Switch the teams when one team has won the map and the game is going to be reset." },
	{ name = "PlayAllRounds", key = "play_all_rounds", type = "Bool", title = "Play all rounds before changelevel", category = MASTER, default = false,
		help = "Determines whether the server may changelevel when mp_timelimit is up before all mini-rounds have been completed (for maps like Dustbowl)." },
	{ name = "PartialCapRate", key = "partial_cap_points_rate", type = "Float", title = "Partial cap rate", category = MASTER, default = 0, min = 0, max = 10,
		help = "Rate at which to give partial cap points for area captures." },
	{ name = "TimerLength", key = "timer_length", target = ENT.CLOCK, type = "Int", title = "Timer length (in seconds)", category = TIMER, default = 600, min = 1, max = 3600,
		help = "Initial timer length." },
	{ name = "MaxLength", key = "max_length", target = ENT.CLOCK, type = "Int", title = "Max timer length (in seconds)", category = TIMER, default = 0, min = 0, max = 3600,
		help = "Maximum timer length (0 = no max). This value is used to ensure the timer never goes above this value when SetTime and AddTime are used." },
	{ name = "SetupLength", key = "setup_length", target = ENT.CLOCK, type = "Int", title = "Setup timer length (in seconds)", category = TIMER, default = 0, min = 0, max = 600,
		help = "Length of setup time before the round begins and the timer starts to countdown the normal time. (0 = no setup time) Setup time is run at the beginning of every round before the normal time begins." },
	{ name = "TimerWinner", type = "Int", title = "When the timer runs out", category = TIMER, default = -1,
		values = { Automatic = -1, ["Sudden Death"] = WS.TEAM_UNASSIGNED, ["RED wins"] = WS.TEAM_RED, ["BLU wins"] = WS.TEAM_BLUE },
		help = "Tells the game rules that the round has either been won (if a team is assigned) or enter Sudden Death mode (if no team is assigned). Automatic: the team holding a track, else Sudden Death." },
	{ name = "TeamTimers", type = "Bool", title = "Team timers", category = KOTH, default = false,
		help = "Play King of the Hill: each team has its own clock, which runs while it holds the point, in place of the round timer. Needs a control point." },
	{ name = "TeamTimerLength", key = "timer_length", target = ENT.KOTH, type = "Int", title = "Timer length (in seconds)", category = KOTH, default = 180, min = 1, max = 3600,
		help = "Initial timer length for each team." },
	{ name = "TeamUnlockPoint", key = "unlock_point", target = ENT.KOTH, type = "Int", title = "Unlock Point (in seconds)", category = KOTH, default = 30, min = 0, max = 3600,
		help = "Time (in seconds) before the point unlocks." },
	{ name = "RedRespawn", rules = "SetRedTeamRespawnWaveTime", type = "Float", title = "RED respawn wave time", category = RULES, default = 0, min = 0, max = 120,
		help = "Set the RED team's respawn wave time" },
	{ name = "BluRespawn", rules = "SetBlueTeamRespawnWaveTime", type = "Float", title = "BLU respawn wave time", category = RULES, default = 0, min = 0, max = 120,
		help = "Set the BLU team's respawn wave time" },
	{ name = "RedGoal", rules = "SetRedTeamGoalString", type = "String", title = "RED goal", category = RULES, default = "", values = RED_GOALS,
		help = "Set the RED team's goal string to show in the hud" },
	{ name = "BluGoal", rules = "SetBlueTeamGoalString", type = "String", title = "BLU goal", category = RULES, default = "", values = BLU_GOALS,
		help = "Set the BLU team's goal string to show in the hud" },
	{ name = "StalemateOnTimelimit", rules = "SetStalemateOnTimelimit", type = "Bool", title = "Stalemate on timelimit", category = RULES, default = false,
		help = "Determines whether mp_timelimit can end the match in the middle of a round." }
}
ENT.WirePorts =
{
	inputs = { "RedRespawnTime", "BluRespawnTime", "AddRedScore", "AddBluScore" },
	outputs = { "RoundState", "Winner" }
}
ENT.WireCommands =
{
	RedRespawnTime = Model.WireValue ("SetRedTeamRespawnWaveTime"),
	BluRespawnTime = Model.WireValue ("SetBlueTeamRespawnWaveTime"),
	AddRedScore = Model.WireValue ("AddRedTeamScore"),
	AddBluScore = Model.WireValue ("AddBlueTeamScore")
}
