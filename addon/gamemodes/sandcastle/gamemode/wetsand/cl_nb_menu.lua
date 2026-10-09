-- The NPC context menu: hold the context menu key (C) and right-click an NPC
-- for "Debug NPC" (Sandbox's properties), for whoever may run the
-- wetsand_nb_* commands. Every entry runs a command naming the NPC by its
-- entity index, so nothing depends on where the crosshair is:
-- - select it (COST and NAV draw the selected NPC), print its behavior to
--   the console (TDBN, OBN and its recent changes), trace its bridge when it
--   is an AI war soldier;
-- - the NextBot layers and the NextSoldier overlay, which the server turns
--   on and off (their state comes back through WetsandNbDebugState, run by
--   features/nbdebug/cl.lua), and what the overlay draws (foundation.ns.overlay's
--   PARTS), each part this client's own convar, read by the overlay as it draws.
-- Showing or clearing everything at once is the Debug NextSoldier panel's
-- (wetsand/cl_ns_debug.lua).
local Overlay = WETSAND.require("foundation.ns.overlay")
local Debug = WETSAND.require("foundation.npc.debug")

local PART_LABELS = {
	[Overlay.SOLDIERS] = "Soldiers: boxes, routes and goals",
	[Overlay.SQUADS] = "Squads: leaders, formation links and orders",
	[Overlay.CONTACTS] = "Contacts: enemy last seen, flanks and cover",
	[Overlay.LANES] = "Lanes: each team's ways in, and who holds them",
	[Overlay.BATTLELINES] = "Battle lines: posts, fronts and cart spheres",
}

for _, part in ipairs(Overlay.PARTS) do
	CreateClientConVar(Overlay.ConVar(part), "1", true, false, "The NextSoldier overlay (wetsand_aiwar_debug) draws: " .. PART_LABELS[part])
end

local LAYER_LABELS = {
	[Debug.AIWAR] = "NextSoldier overlay",
	[Debug.PATH] = "Paths: each NPC's last path search",
	[Debug.COST] = "Search cost: this NPC's explored areas",
	[Debug.BEHAVIOR] = "Behavior: each NPC's action stack",
	[Debug.NAV] = "Nav areas near this NPC",
}
local EVERY_NPC_LAYERS = { Debug.PATH, Debug.BEHAVIOR }
-- The layers drawn for the selected NPC alone: turning one on from an NPC's
-- menu selects that NPC.
local SELECTED_LAYERS = { Debug.COST, Debug.NAV }

local FULL_STACK = "wetsand_aiwar_debug_full"

-- What the server last said this player's view shows.
local layers, selected = {}, Debug.NO_SELECTION
hook.Add("WetsandNbDebugState", "wetsand_nb_menu", function(shown, index)
	layers, selected = shown, index
end)

-- The wetsand_nb_* commands' gate (wetsand/sv_nbdebug.lua).
local function Allowed(ply)
	return IsValid(ply) and (ply:IsSuperAdmin() or ply:IsListenServerHost())
end

local function Check(menu, label, on, run)
	local option = menu:AddOption(label, run)
	option:SetChecked(on)
	return option
end

local function LayerOption(menu, layer)
	Check(menu, LAYER_LABELS[layer], layers[layer] == true, function()
		RunConsoleCommand("wetsand_nb_debug", layer)
	end)
end

-- Checked while the layer is on and this NPC selected; turning it on
-- selects this NPC first.
local function SelectedLayerOption(menu, layer, index)
	local on = layers[layer] == true
	Check(menu, LAYER_LABELS[layer], on and selected == index, function()
		if selected ~= index then RunConsoleCommand("wetsand_nb_select", tostring(index)) end
		if not on or selected == index then RunConsoleCommand("wetsand_nb_debug", layer) end
	end)
end

local function OverlayMenu(menu)
	local parts = menu:AddSubMenu("Overlay parts")
	for _, part in ipairs(Overlay.PARTS) do
		local name = Overlay.ConVar(part)
		Check(parts, PART_LABELS[part], GetConVar(name):GetBool(), function()
			RunConsoleCommand(name, GetConVar(name):GetBool() and "0" or "1")
		end)
	end
	parts:AddSpacer()
	Check(parts, "Soldier boxes show the whole action stack", GetConVar(FULL_STACK):GetBool(), function()
		WETSAND.SetServerSetting(FULL_STACK, GetConVar(FULL_STACK):GetBool() and 0 or 1)
	end)
end

properties.Add("wetsand_nb_debug", {
	MenuLabel = "Debug NPC",
	MenuIcon = "icon16/bug.png",
	Order = 9000,
	Filter = function(self, ent, ply)
		return IsValid(ent) and ent:IsNextBot() and Allowed(ply)
	end,
	Action = function(self, ent) end,
	MenuOpen = function(self, option, ent)
		local index = ent:EntIndex()
		local menu = option:AddSubMenu()
		Check(menu, "Selected", selected == index, function()
			RunConsoleCommand("wetsand_nb_select", tostring(selected == index and Debug.NO_SELECTION or index))
		end)
		menu:AddOption("Print behavior to console", function()
			RunConsoleCommand("wetsand_nb_behavior_print", tostring(index))
		end)
		if ent.WetsandSoldier then
			menu:AddOption("Trace bridge (server console)", function()
				RunConsoleCommand("wetsand_aiwar_trace", tostring(index))
			end)
		end
		menu:AddSpacer()
		LayerOption(menu, Debug.AIWAR)
		OverlayMenu(menu)
		menu:AddSpacer()
		for _, layer in ipairs(EVERY_NPC_LAYERS) do LayerOption(menu, layer) end
		for _, layer in ipairs(SELECTED_LAYERS) do SelectedLayerOption(menu, layer, index) end
	end,
})
