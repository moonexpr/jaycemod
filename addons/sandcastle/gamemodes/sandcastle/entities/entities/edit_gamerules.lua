-- The Game Rules Editor: the payload cart's speed as an editable field;
-- resetting the round and going back to the map's respawn times, as
-- right-click actions (a cart's own right-click moves it between
-- checkpoints: ws/sh_editors_cart.lua). Team scores and
-- respawn waves are in Admin > Gameplay Settings (ws_gameplay_settings).
-- See ws_editor.
AddCSLuaFile()
DEFINE_BASECLASS("ws_editor")

ENT.Type = "anim"
ENT.Base = "ws_editor"

ENT.Spawnable = true
ENT.AdminOnly = true
ENT.PrintName = "Game Rules Editor"
ENT.Category = "Editors"

local CART_SPEED_MIN, CART_SPEED_MAX = 0.1, 4 -- features.payload.model's clamp

ENT.Fields = {
	{
		name = "CartSpeed", type = "Float", title = "Cart speed (x map's)", category = "Payload", min = CART_SPEED_MIN, max = CART_SPEED_MAX,
		read = function(e) return e:CartSpeed() end,
		write = function(e, v) e:SetCartSpeed(v) end,
	},
}

local CLASS = "edit_gamerules"
local TITLE = "Game Rules"

WS.EditorAction("ws_reset_round", {
	class = CLASS, title = TITLE, label = "Reset Round", icon = "icon16/arrow_refresh.png", order = 2100,
	privilege = WS.require("games.system.permissions").ROUND,
	run = function(e) return e:ResetRound() end,
	done = "the round restarts",
})

WS.EditorAction("ws_map_respawn", {
	class = CLASS, title = TITLE, label = "Use Map Respawn Times", icon = "icon16/arrow_undo.png", order = 2102,
	run = function(e) return e:UseMapRespawnTimes() end,
	done = "respawn waves are the map's again",
})
