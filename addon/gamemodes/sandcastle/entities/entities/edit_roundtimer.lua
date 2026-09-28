-- The Round Timer Editor: the HUD timer's time left and pause as editable
-- fields, and an amount of seconds the right-click actions add for a team
-- (TF2's AddTeamTime, while the round runs) or take away. See
-- wetsand_editor.
AddCSLuaFile()
DEFINE_BASECLASS("wetsand_editor")

ENT.Type = "anim"
ENT.Base = "wetsand_editor"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PrintName = "Round Timer Editor"
ENT.Category = "Editors"

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local TIME_MAX = 7200
local STEP_MAX, STEP_DEFAULT = 600, 60

ENT.Fields = {
	{
		name = "TimeLeft", type = "Int", title = "Time left (s)", category = "Timer", min = 0, max = TIME_MAX,
		read = function(e) return math.ceil(e:TimeLeft()) end,
		write = function(e, v) e:SetTimeLeft(v) end,
	},
	{
		name = "Paused", type = "Bool", title = "Paused", category = "Timer",
		read = function(e) return e:Paused() end,
		write = function(e, v) e:SetPaused(v) end,
	},
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
