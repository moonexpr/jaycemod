-- The Debug NextSoldier panel (Utilities > Sandcastle): toggle buttons for
-- every visualizer of NextSoldier, the soldiers' AI that the AI war's PvE
-- runs on, and buttons for the console reports. Each toggle reads ON or OFF and flips when clicked:
-- - the overlay (the nbdebug feature's AIWAR layer, for admins) and the
--   NextBot layers (PATH, COST, BEHAVIOR, NAV, for superadmins), which the
--   server turns on and off (their state comes back through
--   WetsandNbDebugState, run by features/nbdebug/cl.lua);
-- - what the overlay draws (foundation.ns.overlay's PARTS), each part
--   this client's own convar, read by the overlay as it draws.
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
	[Debug.PATH] = "Paths: each NPC's last path search",
	[Debug.COST] = "Search cost: the selected NPC's explored areas",
	[Debug.BEHAVIOR] = "Behavior: each NPC's action stack",
	[Debug.NAV] = "Nav areas near the selected NPC",
}
local NEXTBOT_LAYERS = { Debug.PATH, Debug.COST, Debug.BEHAVIOR, Debug.NAV }

-- The layers the server last said this player's overlay shows.
local layers = {}
hook.Add("WetsandNbDebugState", "wetsand_ns_debug_panel", function(shown)
	layers = shown
end)

local ON_COLOR, OFF_COLOR = Color(40, 150, 60), Color(110, 110, 110)

-- A button reading "<label>: ON" or "OFF" as IsOn() says, running Flip()
-- when clicked.
local function Toggle(panel, label, IsOn, Flip)
	local button = panel:Button(label)
	function button:Think()
		local on = IsOn()
		if self.on == on then return end
		self.on = on
		self:SetText(label .. ": " .. (on and "ON" or "OFF"))
		self:SetTextColor(on and ON_COLOR or OFF_COLOR)
	end
	function button:DoClick() Flip() end
	return button
end

local function ConVarToggle(panel, label, name)
	return Toggle(panel, label, function() return GetConVar(name):GetBool() end, function()
		RunConsoleCommand(name, GetConVar(name):GetBool() and "0" or "1")
	end)
end

local function ShowParts(on)
	for _, part in ipairs(Overlay.PARTS) do RunConsoleCommand(Overlay.ConVar(part), on and "1" or "0") end
end

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help("Draw what NextSoldier, the AI war's soldiers' AI, is thinking: their squads, lanes and battle lines. "
		.. "The overlay is for admins, the NextBot layers for superadmins.")

	panel:Help("Overlay")
	Toggle(panel, "NextSoldier overlay", function() return layers[Debug.AIWAR] == true end, function()
		RunConsoleCommand("wetsand_aiwar_debug")
	end)
	for _, part in ipairs(Overlay.PARTS) do ConVarToggle(panel, PART_LABELS[part], Overlay.ConVar(part)) end
	panel:Button("Show every part").DoClick = function() ShowParts(true) end
	panel:Button("Hide every part").DoClick = function() ShowParts(false) end
	ConVarToggle(panel, "Soldier boxes show the whole action stack", "wetsand_aiwar_debug_full")

	panel:Help("NextBot layers (COST and NAV draw the selected NPC)")
	for _, layer in ipairs(NEXTBOT_LAYERS) do
		Toggle(panel, LAYER_LABELS[layer], function() return layers[layer] == true end, function()
			RunConsoleCommand("wetsand_nb_debug", layer)
		end)
	end
	panel:Button("Select NPC Aimed At", "wetsand_nb_select")
	panel:Button("Turn Every Layer Off", "wetsand_nb_debug", "OFF")

	panel:Help("Console reports, while the war runs")
	panel:Button("Print Soldiers", "wetsand_aiwar_report")
	panel:Button("Print Squads", "ns_squads_print")
	panel:Button("Print Lanes", "ns_lanes_print")
	panel:Button("Print Battle Lines", "ns_battlelines_print")
	panel:Help("Trace the soldier you aim at: every question DrGBase asks its orders and every event it tells them, "
		.. "in the server console. Aim at nothing to stop.")
	panel:Button("Trace Soldier Aimed At", "wetsand_aiwar_trace")

	panel:Help("Refining: ns_tactics_tune <name> <value> changes a tactics constant until the map changes; "
		.. "ns_tactics_list <word> lists those named like it.")
	panel:Button("Print Tactics Constants", "ns_tactics_list")
	panel:Button("Reset Tactics Constants", "ns_tactics_reset")
	panel:Button("Plan Lanes Again", "ns_lanes_replan")
end

hook.Add("PopulateToolMenu", "wetsand_ns_debug", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_ns_debug", "Debug NextSoldier", "", "", BuildPanel)
end)
