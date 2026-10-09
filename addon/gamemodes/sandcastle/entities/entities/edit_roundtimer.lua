-- The Round Timer Editor: an amount of seconds its right-click actions add
-- for a team (TF2's AddTeamTime, while the round runs) or take away. The
-- timer's time left and pause are in Admin > Gameplay Settings
-- (wetsand_gameplay_settings). See wetsand_editor.
AddCSLuaFile()
DEFINE_BASECLASS("wetsand_editor")

ENT.Type = "anim"
ENT.Base = "wetsand_editor"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PrintName = "Round Timer Editor"
ENT.Category = "Editors"

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local STEP_MAX, STEP_DEFAULT = 600, 60

ENT.Fields = {
	{
		name = "TimeStep", type = "Int", title = "Seconds to add or remove", category = "Adjust", min = 1, max = STEP_MAX,
		default = STEP_DEFAULT,
	},
}

local CLASS = "edit_roundtimer"
local TITLE = "Round Timer"

WETSAND.EditorAction("wetsand_add_team_time", {
	class = CLASS, title = TITLE, label = "Add Team Time", icon = "icon16/time_add.png", order = 2100,
	choices = { { label = WETSAND.TeamName[RED], value = RED }, { label = WETSAND.TeamName[BLUE], value = BLUE } },
	run = function(e, ent, team) return e:AddTeamTime(team, ent:GetTimeStep()) end,
	done = "time added",
})

WETSAND.EditorAction("wetsand_remove_time", {
	class = CLASS, title = TITLE, label = "Remove Time", icon = "icon16/time_delete.png", order = 2101,
	run = function(e, ent) return e:RemoveTime(ent:GetTimeStep()) end,
	done = "time removed",
})
