-- The Debug NextSoldier panel (Utilities > Sandcastle): showing and clearing
-- every debug view at once, and the console reports that cover the whole
-- war. Each NPC's own debugging (selecting it, printing its behavior, tracing
-- it, and the layers and overlay parts one by one) is on its context menu:
-- hold C and right-click it (wetsand/cl_nb_menu.lua).
local Overlay = WETSAND.require("foundation.ns.overlay")

-- Every NextBot layer and the overlay with all its parts.
local function ShowAll()
	RunConsoleCommand("wetsand_nb_debug", "ALL")
	for _, part in ipairs(Overlay.PARTS) do RunConsoleCommand(Overlay.ConVar(part), "1") end
end

-- Every layer off, the selection cleared, and no soldier traced.
local function ClearAll()
	RunConsoleCommand("wetsand_nb_debug", "OFF")
	RunConsoleCommand("wetsand_nb_select", "0")
	RunConsoleCommand("wetsand_aiwar_trace", "0")
end

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help("Draw what NextSoldier, the AI war's soldiers' AI, is thinking: their squads, lanes and battle lines, "
		.. "and every NPC's paths and action stack. For superadmins.")
	panel:Help("To debug one NPC (select it, print its behavior, trace it, or turn single layers on and off), "
		.. "hold C and right-click it: Debug NPC.")
	panel:Button("Show All").DoClick = ShowAll
	panel:Button("Clear All").DoClick = ClearAll

	panel:Help("Console reports, while the war runs")
	panel:Button("Print Soldiers", "wetsand_aiwar_report")
	panel:Button("Print Squads", "ns_squads_print")
	panel:Button("Print Lanes", "ns_lanes_print")
	panel:Button("Print Battle Lines", "ns_battlelines_print")

	panel:Help("Refining: ns_tactics_tune <name> <value> changes a tactics constant until the map changes; "
		.. "ns_tactics_list <word> lists those named like it.")
	panel:Button("Print Tactics Constants", "ns_tactics_list")
	panel:Button("Reset Tactics Constants", "ns_tactics_reset")
	panel:Button("Plan Lanes Again", "ns_lanes_replan")
end

hook.Add("PopulateToolMenu", "wetsand_ns_debug", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_ns_debug", "Debug NextSoldier", "", "", BuildPanel)
end)
