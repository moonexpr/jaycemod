-- The AI node graph's switches: the admin commands that generate, destroy,
-- show and report the graph the nodegraph feature makes from the nav mesh
-- (features/nodegraph), and on clients the Utilities menu entry and the
-- overlay that draws it.

-- Switched off (foundation.features OFF): no commands, menu or overlay.
if WS.require("foundation.features").OFF.nodegraph then return end

-- The overlay's snapshot, which the nodegraph feature fires to an admin who
-- turned it on: which graph (generated, installed or none), the nodes near
-- them with their zone, and the links between those nodes (a, b: places in
-- nodes), human if a soldier's hull can walk it.
local E = WS.Events
local COUNT_BITS = 16
local Settings = WS.require("foundation.settings")

-- Shared, so the Utilities menu's slider shows the server's value.
local MAX_NODES_RANGE = Settings.SETTINGS.ws_nodegraph_max_nodes
CreateConVar("ws_nodegraph_max_nodes", tostring(WS.require("foundation.nodegraph").MAX_NODES),
	{ FCVAR_ARCHIVE, FCVAR_REPLICATED },
	"The most nodes a generated AI node graph may have (the engine's limit is 1500 in the 2013 SDK)",
	MAX_NODES_RANGE.min, MAX_NODES_RANGE.max)

E.Define("nodegraph_debug", {
	source = E.String(),
	nodes = E.List(E.Record({
		pos = E.Vector(),
		zone = E.UInt(COUNT_BITS),
	}), COUNT_BITS),
	links = E.List(E.Record({
		a = E.UInt(COUNT_BITS),
		b = E.UInt(COUNT_BITS),
		human = E.Bool(),
	}), COUNT_BITS),
})

if SERVER then
	local function Command(name, method, help)
		concommand.Add(name, function(ply)
			if not WS.Can(ply, WS.require("foundation.permissions").NEXTSOLDIER) then
				ply:ChatPrint("Node graph: you may not do that")
				return
			end
			local graph = WS.Feature("nodegraph")
			local ok, why = graph[method](graph, ply)
			if not ok then
				local text = "Node graph: " .. why
				if IsValid(ply) then ply:ChatPrint(text) else print(text) end
			end
		end, nil, help)
	end

	Command("ws_nodegraph_generate", "Generate", "Make an AI node graph for this map from its nav mesh")
	Command("ws_nodegraph_destroy", "Destroy", "Delete this map's generated AI node graph")
	Command("ws_nodegraph_debug", "ToggleDebug", "Toggle drawing the AI node graph near you")
	Command("ws_nodegraph_status", "Status", "Report the generated and installed AI node graphs")
	return
end

local HELP = "HL2's NPCs find cover, retreat, flank and patrol over the map's AI node graph, "
	.. "which TF2 maps lack. Generate one from the nav mesh (hiding spots become cover nodes), "
	.. "then copy the file it names into garrysmod/maps/graphs/ (as <map>.ain) and reload the map: "
	.. "the engine only reads a graph as the map loads, and Lua may only write under garrysmod/data."

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help(HELP)
	panel:Button("Generate Node Graph", "ws_nodegraph_generate")
	panel:Button("Destroy Generated Graph", "ws_nodegraph_destroy")
	panel:Button("Toggle Node Graph Overlay", "ws_nodegraph_debug")
	panel:Button("Print Node Graph Status", "ws_nodegraph_status")
	WS.ServerSlider(panel, "Most nodes", "ws_nodegraph_max_nodes")
	panel:Help("The engine's limit is 1500 nodes in the 2013 SDK; raise this only if your build allows more.")
end

hook.Add("PopulateToolMenu", "ws_nodegraph", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "ws_nodegraph", "AI Node Graph", "", "", BuildPanel)
end)

-- The overlay: nodes as small boxes in their zone's colour, links a
-- soldier (the human hull) can walk in green, others in red.
local DEBUG_STALE = 3
local NODE_BOX = Vector(4, 4, 4)
local WALKABLE, HULL_ONLY = Color(80, 230, 120), Color(230, 90, 80)
local shown = { nodes = {}, links = {}, received = 0, source = "none" }

E.Listen("nodegraph_debug", "ws_nodegraph", function(fields)
	shown.source, shown.nodes, shown.links, shown.received = fields.source, fields.nodes, fields.links, CurTime()
end)

local function ZoneColor(zone)
	return HSVToColor((zone * 67) % 360, 0.8, 1)
end

hook.Add("PostDrawTranslucentRenderables", "ws_nodegraph_debug", function(depth, skybox)
	if skybox or CurTime() - shown.received > DEBUG_STALE then return end
	for _, link in ipairs(shown.links) do
		local a, b = shown.nodes[link.a], shown.nodes[link.b]
		if a and b then render.DrawLine(a.pos, b.pos, link.human and WALKABLE or HULL_ONLY, true) end
	end
	for _, node in ipairs(shown.nodes) do
		render.DrawWireframeBox(node.pos, angle_zero, -NODE_BOX, NODE_BOX, ZoneColor(node.zone), true)
	end
end)

hook.Add("HUDPaint", "ws_nodegraph_debug", function()
	if CurTime() - shown.received > DEBUG_STALE then return end
	draw.SimpleTextOutlined(string.format("AI node graph (%s): %d nodes, %d links near you", shown.source, #shown.nodes, #shown.links),
		"DermaDefaultBold", ScrW() / 2, 60, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end)
