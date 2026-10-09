-- The Game Rules Editor: team scores, respawn waves (per team, both, or
-- none), and the payload cart's speed, as editable fields; resetting the
-- round, moving the cart on to its next checkpoint, and going back to the
-- map's respawn times, as right-click actions. See wetsand_editor.
AddCSLuaFile()
DEFINE_BASECLASS("wetsand_editor")

ENT.Type = "anim"
ENT.Base = "wetsand_editor"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PrintName = "Game Rules Editor"
ENT.Category = "Editors"

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local SCORE_MAX = 100
local RESPAWN_MAX = 60
local CART_SPEED_MIN, CART_SPEED_MAX = 0.1, 4 -- foundation.payload's clamp
local BOTH_DEFAULT = 10 -- mp_respawnwavetime's default

ENT.Fields = {
	{
		name = "RedScore", type = "Int", title = "RED score", category = "Scores", min = 0, max = SCORE_MAX,
		read = function(e) return e:Score(RED) end,
		write = function(e, v) e:SetScore(RED, v) end,
	},
	{
		name = "BluScore", type = "Int", title = "BLU score", category = "Scores", min = 0, max = SCORE_MAX,
		read = function(e) return e:Score(BLUE) end,
		write = function(e, v) e:SetScore(BLUE, v) end,
	},
	{
		name = "RedRespawn", type = "Float", title = "RED respawn wave (s)", category = "Respawns", min = 0, max = RESPAWN_MAX,
		read = function(e) return e:RespawnTime(RED) end,
		write = function(e, v) e:SetRespawnTime(RED, v) end,
	},
	{
		name = "BluRespawn", type = "Float", title = "BLU respawn wave (s)", category = "Respawns", min = 0, max = RESPAWN_MAX,
		read = function(e) return e:RespawnTime(BLUE) end,
		write = function(e, v) e:SetRespawnTime(BLUE, v) end,
	},
	{
		name = "BothRespawn", type = "Float", title = "Both teams' respawn wave (s)", category = "Respawns", min = 0, max = RESPAWN_MAX,
		default = BOTH_DEFAULT,
		write = function(e, v) e:SetRespawnTime(nil, v) end,
	},
	{
		name = "RespawnsDisabled", type = "Bool", title = "Disable respawns", category = "Respawns",
		read = function(e) return e:RespawnsDisabled() end,
		write = function(e, v) e:SetRespawnsDisabled(v) end,
	},
	{
		name = "CartSpeed", type = "Float", title = "Cart speed (x map's)", category = "Payload", min = CART_SPEED_MIN, max = CART_SPEED_MAX,
		read = function(e) return e:CartSpeed() end,
		write = function(e, v) e:SetCartSpeed(v) end,
	},
}

local CLASS = "edit_gamerules"
local TITLE = "Game Rules"

WETSAND.EditorAction("wetsand_reset_round", {
	class = CLASS, title = TITLE, label = "Reset Round", icon = "icon16/arrow_refresh.png", order = 2100,
	run = function(e) return e:ResetRound() end,
	done = "the round restarts",
})

WETSAND.EditorAction("wetsand_retract_cart", {
	class = CLASS, title = TITLE, label = "Retract Cart to Previous Checkpoint", icon = "icon16/arrow_left.png", order = 2101,
	run = function(e) return e:RetractCarts() end,
	done = "the cart is on its way to the previous checkpoint",
})

WETSAND.EditorAction("wetsand_advance_cart", {
	class = CLASS, title = TITLE, label = "Advance Cart to Next Checkpoint", icon = "icon16/arrow_right.png", order = 2101,
	run = function(e) return e:AdvanceCarts() end,
	done = "the cart is on its way to the next checkpoint",
})

WETSAND.EditorAction("wetsand_map_respawn", {
	class = CLASS, title = TITLE, label = "Use Map Respawn Times", icon = "icon16/arrow_undo.png", order = 2102,
	run = function(e) return e:UseMapRespawnTimes() end,
	done = "respawn waves are the map's again",
})
