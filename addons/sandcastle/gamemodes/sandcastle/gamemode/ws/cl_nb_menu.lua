-- The NPC context menu: hold the context menu key (C) and right-click an NPC
-- for "Select NPC for Debug" and "Debug NPC" (Sandbox's properties), for
-- whoever may run the ws_nb_* commands. Every entry runs a command
-- naming the NPC by its entity index, so nothing depends on where the
-- crosshair is:
-- - select it for inspection (COST and NAV draw the selected NPC; a check
--   marks the one selected);
-- - in Debug NPC: print its behavior to the console (TDBN, OBN and its
--   recent changes), trace its bridge when it is an AI war soldier;
-- - the NextBot layers and the NextSoldier overlay, which the server turns
--   on and off (their state comes back through WSNbDebugState, run by
--   features/nbdebug/cl.lua), and what the overlay draws (features.nbdebug.ns_overlay's
--   PARTS), each part this client's own convar, read by the overlay as it draws.
-- Showing or clearing everything at once is the Debug NextSoldier panel's
-- (ws/cl_ns_debug.lua).
local Overlay = WS.require("features.nbdebug.ns_overlay")
local Debug = WS.require("features.nbdebug.model")

for _, part in ipairs(Overlay.PARTS) do
	CreateClientConVar(Overlay.ConVar(part), "1", true, false, "The NextSoldier overlay (ws_aiwar_debug) draws: " .. Overlay.LABELS[part])
end

local LAYER_LABELS = {
	[Debug.AIWAR] = "NextSoldier overlay",
	[Debug.PATH] = "Paths: each NPC's last path search",
	[Debug.COST] = "Search cost: this NPC's explored areas",
	[Debug.BEHAVIOR] = "Behavior: each NPC's action stack",
	[Debug.NAV] = "Nav areas near this NPC",
	[Debug.MARKS] = "Marks: when the system stepped in on this NPC (recovered, hopped, sent aside)",
}
local EVERY_NPC_LAYERS = { Debug.PATH, Debug.BEHAVIOR }
-- The layers drawn for the selected NPC alone: turning one on from an NPC's
-- menu selects that NPC.
local SELECTED_LAYERS = { Debug.COST, Debug.NAV, Debug.MARKS }

local FULL_STACK = "ws_aiwar_debug_full"

-- What the server last said this player's view shows.
local layers, selected = {}, Debug.NO_SELECTION
hook.Add("WSNbDebugState", "ws_nb_menu", function(shown, index)
	layers, selected = shown, index
end)

-- The ws_nb_* commands' gate (ws/sv_nbdebug.lua).
function WS.NpcDebugAllowed(ply)
	return IsValid(ply) and WS.Can(ply, WS.require("games.system.permissions").NPC_DEBUG) == true
end

local function Check(menu, label, on, run)
	local option = menu:AddOption(label, run)
	option:SetChecked(on)
	return option
end

local function LayerOption(menu, layer)
	Check(menu, LAYER_LABELS[layer], layers[layer] == true, function()
		RunConsoleCommand("ws_nb_debug", layer)
	end)
end

-- Checked while the layer is on and this NPC selected; turning it on
-- selects this NPC first.
local function SelectedLayerOption(menu, layer, index)
	local on = layers[layer] == true
	Check(menu, LAYER_LABELS[layer], on and selected == index, function()
		if selected ~= index then RunConsoleCommand("ws_nb_select", tostring(index)) end
		if not on or selected == index then RunConsoleCommand("ws_nb_debug", layer) end
	end)
end

local function OverlayMenu(menu)
	local parts = menu:AddSubMenu("Overlay parts")
	for _, part in ipairs(Overlay.PARTS) do
		local name = Overlay.ConVar(part)
		Check(parts, Overlay.LABELS[part], GetConVar(name):GetBool(), function()
			RunConsoleCommand(name, GetConVar(name):GetBool() and "0" or "1")
		end)
	end
	parts:AddSpacer()
	Check(parts, "Soldier boxes show the whole action stack", GetConVar(FULL_STACK):GetBool(), function()
		WS.SetServerSetting(FULL_STACK, GetConVar(FULL_STACK):GetBool() and 0 or 1)
	end)
end

-- The NPC's debugging, by its entity index, as the menus show it (this
-- one, and the AI War panel's slot list, ws/cl_aiwar_slots.lua).

-- "Select NPC for Debug": checked while it is the NPC selected; clicking
-- selects it, or clears the selection.
local function ToggleSelection(index)
	RunConsoleCommand("ws_nb_select", tostring(selected == index and Debug.NO_SELECTION or index))
end

function WS.NpcSelectOption(menu, index)
	local option = Check(menu, "Select NPC for Debug", selected == index, function() ToggleSelection(index) end)
	option:SetIcon("icon16/zoom.png")
	return option
end

-- Debug NPC's entries into menu; soldier: an AI war soldier, whose bridge
-- may be traced.
function WS.NpcDebugMenu(menu, index, soldier)
	menu:AddOption("Print behavior to console", function()
		RunConsoleCommand("ws_nb_behavior_print", tostring(index))
	end)
	if soldier then
		menu:AddOption("Trace bridge (server console)", function()
			RunConsoleCommand("ws_aiwar_trace", tostring(index))
		end)
	end
	menu:AddSpacer()
	LayerOption(menu, Debug.AIWAR)
	OverlayMenu(menu)
	menu:AddSpacer()
	for _, layer in ipairs(EVERY_NPC_LAYERS) do LayerOption(menu, layer) end
	for _, layer in ipairs(SELECTED_LAYERS) do SelectedLayerOption(menu, layer, index) end
end

local function Filter(self, ent, ply)
	return IsValid(ent) and ent:IsNextBot() and WS.NpcDebugAllowed(ply)
end

properties.Add("ws_nb_select", {
	MenuLabel = "Select NPC for Debug",
	MenuIcon = "icon16/zoom.png",
	Order = 8999,
	Type = "toggle",
	Filter = Filter,
	Checked = function(self, ent) return selected == ent:EntIndex() end,
	Action = function(self, ent) ToggleSelection(ent:EntIndex()) end,
})

properties.Add("ws_nb_debug", {
	MenuLabel = "Debug NPC",
	MenuIcon = "icon16/bug.png",
	Order = 9000,
	Filter = Filter,
	Action = function(self, ent) end,
	MenuOpen = function(self, option, ent)
		WS.NpcDebugMenu(option:AddSubMenu(), ent:EntIndex(), ent.WSSoldier == true)
	end,
})
