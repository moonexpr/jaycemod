-- The C menu's Conditions on a player or soldier (Sandbox's properties: hold
-- C, right-click): toggles each of games.gameplay.players.condition_effects'
-- TOGGLES on it, held until toggled off or, for a player, their death (a
-- life starts with none: ws/sv_teams_conditions.lua). Tampering, so for
-- holders of the tamper privilege while mp_tampering_enabled allows it.
local Permissions = WS.require("games.system.permissions")
local Effects = WS.require("games.gameplay.players.condition_effects")
local P = WS.PlayerRules

local ORDER = 1600 -- after the players' admin options

local function Holder(ent)
	return (ent:IsPlayer() and ent:Alive()) or ent.WSSoldier == true
end

-- The client sees each toggle's end (ws_cond_<number>).
local function Held(ent, cond)
	return CurTime() < ent:GetNW2Float("ws_cond_" .. cond, 0)
end

local function Name(ent)
	return ent:IsPlayer() and ent:Nick() or ent:GetClass()
end

WS.AdminProperty("ws_conditions", {
	label = "Conditions",
	icon = "icon16/wand.png",
	order = ORDER,
	privilege = Permissions.TAMPER,
	filter = Holder,
	choices = function(ent)
		local choices = {}
		for _, toggle in ipairs(Effects.TOGGLES) do
			choices[#choices + 1] = {
				label = toggle.label,
				value = toggle.cond,
				checked = Held(ent, toggle.cond),
			}
		end
		return choices
	end,
	run = function(_, ent, cond)
		local toggle = Effects.Toggle(cond)
		if not toggle then return "That is not a condition." end
		if WS.InCondition(ent, cond) then
			WS.RemoveCondition(ent, cond)
			return toggle.label .. " off for " .. Name(ent) .. "."
		end
		WS.AddCondition(ent, cond, P.PERMANENT)
		return toggle.label .. " on for " .. Name(ent) .. "."
	end,
})
