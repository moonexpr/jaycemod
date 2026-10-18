-- The Debug NextSoldier panel (Utilities > Sandcastle): showing and clearing
-- every debug view at once, the console reports that cover the whole war,
-- a checkbox for each layer drawn for every NPC (the overlay itself, paths,
-- behavior: the server's layers, so each box follows what the server says
-- through WSNbDebugState), and a checkbox for each part the overlay draws,
-- in a section for each of its groups: NextSoldier's AI and the tactics
-- engine's planning; ticking a part turns the overlay on, so it shows. Each
-- NPC's own debugging (selecting it, printing its behavior, tracing it, the
-- layers drawn for it alone) is on its context menu: hold C and
-- right-click it (ws/cl_nb_menu.lua).
local Overlay = WS.require("foundation.ns.overlay")
local Debug = WS.require("foundation.npc.debug")

-- The layers with a box here, in order: those drawn for every NPC.
local LAYERS = { Debug.AIWAR, Debug.PATH, Debug.BEHAVIOR }
local LAYER_LABELS = {
	[Debug.AIWAR] = "Show the NextSoldier overlay",
	[Debug.PATH] = "Paths: each NPC's last path search",
	[Debug.BEHAVIOR] = "Behavior: each NPC's action stack",
}

-- What the server last said this player's view shows, and the panel's boxes.
local shown, layerBoxes = {}, {}

hook.Add("WSNbDebugState", "ws_ns_debug", function(layers)
	shown = layers
	for layer, box in pairs(layerBoxes) do
		if IsValid(box) then box:SetChecked(shown[layer] == true) end
	end
end)

local function ShowOverlayOnTick(_, checked)
	if checked and not shown[Debug.AIWAR] then RunConsoleCommand("ws_nb_debug", Debug.AIWAR) end
end

-- Every NextBot layer and the overlay with all its parts.
local function ShowAll()
	RunConsoleCommand("ws_nb_debug", "ALL")
	for _, part in ipairs(Overlay.PARTS) do RunConsoleCommand(Overlay.ConVar(part), "1") end
end

-- Every layer off, the selection cleared, and no soldier traced.
local function ClearAll()
	RunConsoleCommand("ws_nb_debug", "OFF")
	RunConsoleCommand("ws_nb_select", "0")
	RunConsoleCommand("ws_aiwar_trace", "0")
end

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help("Draw what NextSoldier, the AI war's soldiers' AI, is thinking: their squads, lanes and battle lines, "
		.. "and every NPC's paths and action stack. For superadmins.")
	panel:Help("To debug one NPC (select it, print its behavior, trace it, or turn single layers on and off), "
		.. "hold C and right-click it: Debug NPC.")
	panel:Button("Show All").DoClick = ShowAll
	panel:Button("Clear All").DoClick = ClearAll

	-- not convars: ws_nb_debug toggles a layer, and the server's answer sets its box
	for _, layer in ipairs(LAYERS) do
		local box = panel:CheckBox(LAYER_LABELS[layer])
		box:SetChecked(shown[layer] == true)
		box.OnChange = function(_, checked)
			if checked ~= (shown[layer] == true) then RunConsoleCommand("ws_nb_debug", layer) end
		end
		layerBoxes[layer] = box
	end

	for _, group in ipairs(Overlay.GROUPS) do
		panel:Help(group.name .. ": what the overlay draws")
		for _, part in ipairs(group.parts) do panel:CheckBox(Overlay.LABELS[part], Overlay.ConVar(part)).OnChange = ShowOverlayOnTick end
	end

	panel:Help("Console reports, while the war runs")
	panel:Button("Print Soldiers", "ws_aiwar_report")
	panel:Button("Print Squads", "ns_squads_print")
	panel:Button("Print Lanes", "ns_lanes_print")
	panel:Button("Print Battle Lines", "ns_battlelines_print")

	panel:Help("Refining: ns_tactics_tune <name> <value> changes a tactics constant until the map changes; "
		.. "ns_tactics_list <word> lists those named like it.")
	panel:Button("Print Tactics Constants", "ns_tactics_list")
	panel:Button("Reset Tactics Constants", "ns_tactics_reset")
	panel:Button("Plan Lanes Again", "ns_lanes_replan")
end

hook.Add("PopulateToolMenu", "ws_ns_debug", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "ws_ns_debug", "Debug NextSoldier", "", "", BuildPanel)
end)
