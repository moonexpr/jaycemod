-- Admins' C-click options on players (Sandbox's properties: hold C,
-- right-click): Spectate, Bring, Go To, Respawn, Slay, Switch Team, Give
-- Money, Kick and Ban, for holders of the players privilege. A cart's,
-- a control point's and the round timer's options are the editors'
-- (WS.EditorAction); a soldier's are ws/cl_nb_menu.lua's and Spectate's.
--
-- WS.AdminProperty(name, def) adds one, def = { label, icon, order,
-- privilege, filter(ent, ply) -> whether it shows on ent, choices (a list of
-- { label, value[, checked] }, or a function of ent giving one; shown as a
-- submenu, a choice with checked as a ticked or unticked entry),
-- run(ply, ent, value) on the server }. Every choice goes to the server as
-- game_admin_property, which checks the filter and the privilege again.
local Permissions = WS.require("foundation.permissions")
local E = WS.Events

local DEFS = {}
local VALUE_BITS = 32

E.Define("game_admin_property", {
	name = E.String(),
	target = E.Entity(),
	value = E.Int(VALUE_BITS),
}, {
	clientSendable = true,
	rate = {
		count = 10,
		seconds = 5,
	},
})

local function Shows(def, ent, ply)
	return IsValid(ent) and IsValid(ply) and def.filter(ent, ply) and WS.Can(ply, def.privilege) == true
end

local function Send(name, ent, value)
	E.Request("game_admin_property", {
		name = name,
		target = ent,
		value = value,
	})
end

function WS.AdminProperty(name, def)
	DEFS[name] = def
	properties.Add(name, {
		MenuLabel = def.label,
		MenuIcon = def.icon,
		Order = def.order,
		Filter = function(self, ent, ply) return Shows(def, ent, ply) end,
		Action = function(self, ent)
			if not def.choices then Send(name, ent, 0) end
		end,
		MenuOpen = def.choices and function(self, option, ent)
			local submenu = option:AddSubMenu()
			local choices = isfunction(def.choices) and def.choices(ent) or def.choices
			for _, choice in ipairs(choices) do
				local item = submenu:AddOption(choice.label, function() Send(name, ent, choice.value) end)
				if choice.checked ~= nil then item:SetChecked(choice.checked) end
			end
		end or nil,
	})
end

if SERVER then
	E.Listen("game_admin_property", "ws_admin_properties", function(fields, ply)
		local def = DEFS[fields.name]
		if not (def and Shows(def, fields.target, ply)) then return end
		local said = def.run(ply, fields.target, fields.value)
		print("[Sandcastle] " .. ply:Nick() .. " used " .. fields.name .. " on " .. tostring(fields.target))
		if said then ply:ChatPrint(said) end
	end)
end

local PLAYERS = Permissions.PLAYERS
local ORDER = 1500 -- after Sandbox's own properties
local AHEAD = 64 -- how far in front of the other player a Bring or Go To lands

local function OtherPlayer(ent, ply)
	return ent:IsPlayer() and ent ~= ply
end

local function Living(ent, ply)
	return OtherPlayer(ent, ply) and ent:Alive()
end

WS.AdminProperty("ws_admin_spectate", {
	label = "Spectate",
	icon = "icon16/eye.png",
	order = ORDER,
	privilege = PLAYERS,
	filter = Living,
	run = function(ply, ent) WS.SpectateNpc(ply, ent) end,
})

WS.AdminProperty("ws_admin_bring", {
	label = "Bring",
	icon = "icon16/arrow_in.png",
	order = ORDER + 1,
	privilege = PLAYERS,
	filter = Living,
	run = function(ply, ent)
		ent:SetPos(ply:GetPos() + ply:GetForward() * AHEAD)
		return "Brought " .. ent:Nick() .. "."
	end,
})

WS.AdminProperty("ws_admin_goto", {
	label = "Go To",
	icon = "icon16/arrow_out.png",
	order = ORDER + 2,
	privilege = PLAYERS,
	filter = Living,
	run = function(ply, ent)
		ply:SetPos(ent:GetPos() - ent:GetForward() * AHEAD)
		return "Went to " .. ent:Nick() .. "."
	end,
})

WS.AdminProperty("ws_admin_respawn", {
	label = "Respawn",
	icon = "icon16/arrow_rotate_clockwise.png",
	order = ORDER + 3,
	privilege = PLAYERS,
	filter = OtherPlayer,
	run = function(_, ent)
		ent:Spawn()
		return "Respawned " .. ent:Nick() .. "."
	end,
})

WS.AdminProperty("ws_admin_slay", {
	label = "Slay",
	icon = "icon16/cross.png",
	order = ORDER + 4,
	privilege = PLAYERS,
	filter = Living,
	run = function(_, ent)
		ent:Kill()
		return "Slew " .. ent:Nick() .. "."
	end,
})

WS.AdminProperty("ws_admin_team", {
	label = "Switch Team",
	icon = "icon16/group.png",
	order = ORDER + 5,
	privilege = PLAYERS,
	filter = OtherPlayer,
	choices = function()
		return {
			{
				label = WS.TeamName[WS.TEAM_RED],
				value = WS.TEAM_RED,
			},
			{
				label = WS.TeamName[WS.TEAM_BLUE],
				value = WS.TEAM_BLUE,
			},
			{
				label = "Spectator",
				value = WS.TEAM_SPECTATOR,
			},
		}
	end,
	run = function(_, ent, t)
		if t ~= WS.TEAM_RED and t ~= WS.TEAM_BLUE and t ~= WS.TEAM_SPECTATOR then return "That is not a team." end
		WS.SetPlayerTeam(ent, t, true)
		return "Moved " .. ent:Nick() .. "."
	end,
})

WS.AdminProperty("ws_admin_give", {
	label = "Give Money",
	icon = "icon16/coins_add.png",
	order = ORDER + 6,
	privilege = PLAYERS,
	filter = function(ent) return ent:IsPlayer() end,
	choices = function()
		local choices = {}
		for _, amount in ipairs(WS.PLAYERS_MENU_GRANTS) do
			choices[#choices + 1] = {
				label = "$" .. amount,
				value = amount,
			}
		end
		return choices
	end,
	run = function(ply, ent, amount) WS.AdminPlayerAction(ply, ent, WS.ADMIN_GRANT, amount) end,
})

WS.AdminProperty("ws_admin_kick", {
	label = "Kick",
	icon = "icon16/door_out.png",
	order = ORDER + 7,
	privilege = PLAYERS,
	filter = OtherPlayer,
	run = function(ply, ent) WS.AdminPlayerAction(ply, ent, WS.ADMIN_KICK, 0) end,
})

WS.AdminProperty("ws_admin_ban", {
	label = "Ban",
	icon = "icon16/delete.png",
	order = ORDER + 8,
	privilege = PLAYERS,
	filter = OtherPlayer,
	choices = function()
		local choices = {}
		for i, ban in ipairs(WS.PLAYERS_MENU_BANS) do
			choices[#choices + 1] = {
				label = ban.label,
				value = i - 1,
			}
		end
		return choices
	end,
	run = function(ply, ent, index) WS.AdminPlayerAction(ply, ent, WS.ADMIN_BAN, index) end,
})
