-- The AI node graph's switches: the admin commands that generate, destroy,
-- show and report the graph the nodegraph feature makes from the nav mesh
-- (features/nodegraph), and on clients the Utilities menu entry and the
-- overlay that draws it.
if SERVER then
	local function Command(name, method, help)
		concommand.Add(name, function(ply)
			if IsValid(ply) and not ply:IsAdmin() then
				ply:ChatPrint("Node graph: only admins may do that")
				return
			end
			local graph = WETSAND.Feature("nodegraph")
			local ok, why = graph[method](graph, ply)
			if not ok then
				local text = "Node graph: " .. why
				if IsValid(ply) then ply:ChatPrint(text) else print(text) end
			end
		end, nil, help)
	end

	Command("wetsand_nodegraph_generate", "Generate", "Make an AI node graph for this map from its nav mesh")
	Command("wetsand_nodegraph_destroy", "Destroy", "Delete this map's generated AI node graph")
	Command("wetsand_nodegraph_debug", "ToggleDebug", "Toggle drawing the AI node graph near you")
	Command("wetsand_nodegraph_status", "Status", "Report the generated and installed AI node graphs")
	return
end

local HELP = "HL2's NPCs find cover, retreat, flank and patrol over the map's AI node graph, "
	.. "which TF2 maps lack. Generate one from the nav mesh (hiding spots become cover nodes), "
	.. "then copy the file it names into garrysmod/maps/graphs/ (as <map>.ain) and reload the map: "
	.. "the engine only reads a graph as the map loads, and Lua may only write under garrysmod/data."

local function BuildPanel(panel)
	panel:ClearControls()
	panel:Help(HELP)
	panel:Button("Generate Node Graph", "wetsand_nodegraph_generate")
	panel:Button("Destroy Generated Graph", "wetsand_nodegraph_destroy")
	panel:Button("Toggle Node Graph Overlay", "wetsand_nodegraph_debug")
	panel:Button("Print Node Graph Status", "wetsand_nodegraph_status")
	panel:NumSlider("Most nodes", "wetsand_nodegraph_max_nodes", 64, 8192, 0)
	panel:Help("The engine's limit is 1500 nodes in the 2013 SDK; raise this only if your build allows more.")
end

hook.Add("PopulateToolMenu", "wetsand_nodegraph", function()
	spawnmenu.AddToolMenuOption("Utilities", "Sandcastle", "wetsand_nodegraph", "AI Node Graph", "", "", BuildPanel)
end)

-- The overlay: nodes as small boxes in their zone's colour, links a
-- soldier (the human hull) can walk in green, others in red.
local DEBUG_NET = "wetsand_nodegraph_debug"
local DEBUG_STALE = 3
local NODE_BOX = Vector(4, 4, 4)
local WALKABLE, HULL_ONLY = Color(80, 230, 120), Color(230, 90, 80)
local shown = { nodes = {}, links = {}, received = 0, source = "none" }

net.Receive(DEBUG_NET, function()
	local source, nodes, links = net.ReadString(), {}, {}
	for i = 1, net.ReadUInt(16) do nodes[i] = { pos = net.ReadVector(), zone = net.ReadUInt(16) } end
	for i = 1, net.ReadUInt(16) do links[i] = { a = net.ReadUInt(16), b = net.ReadUInt(16), human = net.ReadBool() } end
	shown.source, shown.nodes, shown.links, shown.received = source, nodes, links, CurTime()
end)

local function ZoneColor(zone)
	return HSVToColor((zone * 67) % 360, 0.8, 1)
end

hook.Add("PostDrawTranslucentRenderables", "wetsand_nodegraph_debug", function(depth, skybox)
	if skybox or CurTime() - shown.received > DEBUG_STALE then return end
	for _, link in ipairs(shown.links) do
		local a, b = shown.nodes[link.a], shown.nodes[link.b]
		if a and b then render.DrawLine(a.pos, b.pos, link.human and WALKABLE or HULL_ONLY, true) end
	end
	for _, node in ipairs(shown.nodes) do
		render.DrawWireframeBox(node.pos, angle_zero, -NODE_BOX, NODE_BOX, ZoneColor(node.zone), true)
	end
end)

hook.Add("HUDPaint", "wetsand_nodegraph_debug", function()
	if CurTime() - shown.received > DEBUG_STALE then return end
	draw.SimpleTextOutlined(string.format("AI node graph (%s): %d nodes, %d links near you", shown.source, #shown.nodes, #shown.links),
		"DermaDefaultBold", ScrW() / 2, 60, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, color_black)
end)
