-- The Round Timer Editor: an amount of seconds its right-click actions add
-- for a team (TF2's AddTeamTime, while the round runs) or take away. The
-- timer's time left and pause are in Admin > Gameplay Settings
-- (ws_gameplay_settings). On a map without an objective, whose rounds are
-- untimed, Set Round Time gives every round a timer of RoundTime seconds
-- (0: untimed again); when it runs out the round is a stalemate. See
-- ws_editor.
AddCSLuaFile()
DEFINE_BASECLASS("ws_editor")

ENT.Type = "anim"
ENT.Base = "ws_editor"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PrintName = "Round Timer Editor"
ENT.Category = "Editors"

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE
local STEP_MAX, STEP_DEFAULT = 600, 60
local ROUND_TIME_MAX, ROUND_TIME_DEFAULT = 3600, 300

ENT.Fields = {
	{
		name = "TimeStep", type = "Int", title = "Seconds to add or remove", category = "Adjust", min = 1, max = STEP_MAX,
		default = STEP_DEFAULT,
	},
	{
		name = "RoundTime", type = "Int", title = "Round time in seconds (0: untimed)", category = "Rules", min = 0,
		max = ROUND_TIME_MAX, default = ROUND_TIME_DEFAULT,
	},
}

local CLASS = "edit_roundtimer"
local TITLE = "Round Timer"

WS.EditorAction("ws_add_team_time", {
	class = CLASS, title = TITLE, label = "Add Team Time", icon = "icon16/time_add.png", order = 2100,
	choices = { { label = WS.TeamName[RED], value = RED }, { label = WS.TeamName[BLUE], value = BLUE } },
	run = function(e, ent, team) return e:AddTeamTime(team, ent:GetTimeStep()) end,
	done = "time added",
})

WS.EditorAction("ws_remove_time", {
	class = CLASS, title = TITLE, label = "Remove Time", icon = "icon16/time_delete.png", order = 2101,
	run = function(e, ent) return e:RemoveTime(ent:GetTimeStep()) end,
	done = "time removed",
})

WS.EditorAction("ws_set_round_time", {
	class = CLASS, title = TITLE, label = "Set Round Time", icon = "icon16/clock_edit.png", order = 2102,
	run = function(e, ent) return e:SetRoundTime(ent:GetRoundTime()) end,
	done = "round time set",
})
