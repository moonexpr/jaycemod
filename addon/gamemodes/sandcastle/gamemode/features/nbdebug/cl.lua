-- The nbdebug feature's view: the one NPC debug overlay. It draws what the
-- nbdebug controller sends for wetsand_nb_debug's layers (PATH, COST,
-- BEHAVIOR, NAV) and the AI war's soldier overlay (the AIWAR layer, which
-- the aiwar controller sends as wetsand_aiwar_debug) in one pass: lines and
-- areas in the world after the translucent renderables, then in HUDPaint one
-- box per NPC above its head, holding every layer's lines for it (laid out
-- by foundation.aiwar.overlay so none covers another), and the labels.
-- Nothing here needs developer mode, so it works on dedicated servers.
local Debug = WETSAND.require("foundation.npc.debug")
local Overlay = WETSAND.require("foundation.aiwar.overlay")

-- The game events it listens to are sh.lua's; aiwar_debug is the aiwar
-- controller's (Controller:SendDebug).
local NO_SELECTION = Debug.NO_SELECTION
local CORNERS = 4

local STALE = 2 -- seconds a periodic snapshot stays drawn without a newer one
local BOX_MARGIN = 8 -- a box's anchor above the NPC's bounding box
local BOX_PADDING, BOX_LINE_GAP = 6, 1
local BOX_BACKGROUND = Color(24, 24, 28)
local NPC_COLOR = Color(255, 190, 40)
local SELECTED_COLOR = Color(90, 230, 120)
local COST_LIFT, NAV_LIFT = Vector(0, 0, 2), Vector(0, 0, 3)
local COST_FILL_ALPHA = 60
local COST_TEXT_DISTANCE = 400
local NAV_COLOR = Color(220, 220, 220)
local GOAL_RADIUS = 12
local GOAL_REACHED_COLOR, GOAL_SHORT_COLOR = Color(90, 230, 120), Color(255, 60, 60)
local NODE_TICK = Vector(0, 0, 8)
local SELECT_RING_RADIUS, SELECT_RING_SEGMENTS = 25, 24 -- nb_select's circle
local SELECT_RING_LIFT = Vector(0, 0, 5)

surface.CreateFont("WetsandNbDebugHeading", {
	font = "Tahoma",
	size = 15,
	weight = 800,
})
surface.CreateFont("WetsandNbDebugDetail", {
	font = "Tahoma",
	size = 13,
	weight = 500,
})

local function ToColor(rgb, alpha)
	return Color(rgb[1], rgb[2], rgb[3], alpha)
end

local MOVE_COLOR = {}
for move, rgb in pairs(Debug.MOVE_COLORS) do MOVE_COLOR[move] = ToColor(rgb) end

local view = {
	layers = {},
	selected = NO_SELECTION,
	paths = {}, -- entity index -> the last path the server reported
	cost = nil, -- the selected NPC's explored areas
	behavior = {}, -- entity index -> lines
	behaviorReceived = -math.huge,
	nav = {},
	navReceived = -math.huge,
}

local function Live(received)
	return CurTime() - received < STALE
end

local function Lifted(corners, lift)
	local lifted = {}
	for i = 1, CORNERS do lifted[i] = corners[i] + lift end
	return lifted
end

local function Center(corners)
	return (corners[1] + corners[2] + corners[3] + corners[4]) / CORNERS
end

local E = WETSAND.Events

E.Listen("nb_debug_state", "wetsand_nbdebug_view", function(fields)
	local layers = {}
	for _, name in ipairs(fields.layers) do layers[name] = true end
	view.layers = layers
	view.selected = fields.selected
	-- the server resends what the new view needs
	view.paths, view.cost, view.behavior, view.nav = {}, nil, {}, {}
end)

E.Listen("nb_debug_path", "wetsand_nbdebug_view", function(fields)
	view.paths[fields.index] = {
		strategy = fields.strategy,
		source = fields.source,
		found = fields.found,
		totalCost = fields.total_cost,
		microseconds = fields.microseconds,
		nodesExpanded = fields.nodes_expanded,
		computedAt = fields.computed_at,
		goal = fields.goal,
		points = fields.points,
	}
end)

E.Listen("nb_debug_cost", "wetsand_nbdebug_view", function(fields)
	local cost = {
		index = fields.index,
		total = fields.total,
		areas = {},
	}
	for i, sent in ipairs(fields.areas) do
		local area = {
			id = sent.id,
			cost = sent.cost,
			impassable = sent.impassable,
			corners = Lifted(sent.corners, COST_LIFT),
		}
		area.center = Center(area.corners)
		cost.areas[i] = area
	end
	cost.lo, cost.hi = Debug.CostRange(cost.areas)
	for _, area in ipairs(cost.areas) do
		local rgb = Debug.IMPASSABLE_COLOR
		if not area.impassable then rgb = { Debug.CostColor(area.cost, cost.lo, cost.hi) } end
		area.outline, area.fill = ToColor(rgb), ToColor(rgb, COST_FILL_ALPHA)
		area.text = area.impassable and "impassable" or tostring(math.Round(area.cost))
	end
	view.cost = cost
end)

E.Listen("nb_debug_behavior", "wetsand_nbdebug_view", function(fields)
	local behavior = {}
	for _, npc in ipairs(fields.npcs) do behavior[npc.index] = npc.lines end
	view.behavior, view.behaviorReceived = behavior, CurTime()
end)

E.Listen("nb_debug_nav", "wetsand_nbdebug_view", function(fields)
	local nav = {}
	for i, area in ipairs(fields.areas) do
		local corners = Lifted(area.corners, NAV_LIFT)
		nav[i] = {
			corners = corners,
			center = Center(corners),
			label = Debug.NavLabel(area.id, area.attributes),
		}
	end
	view.nav, view.navReceived = nav, CurTime()
end)

E.Listen("nb_debug_npc_removed", "wetsand_nbdebug_view", function(fields)
	local index = fields.index
	view.paths[index], view.behavior[index] = nil, nil
	if view.cost and view.cost.index == index then view.cost = nil end
	if view.selected == index then view.selected, view.nav = NO_SELECTION, {} end
end)

-------------------------------------------------------------------------------
-- The AI war's soldier overlay (AIWAR): what its controller last sent,
-- drawn until it goes stale.

local war = { soldiers = {}, teams = {}, spheres = {}, received = -math.huge }

-- Brighter than the teams' HUD colours, to read over any map.
local WAR_COLOR = { [WETSAND.TEAM_RED] = Color(255, 90, 90), [WETSAND.TEAM_BLUE] = Color(110, 175, 255) }

E.Listen("aiwar_debug", "wetsand_nbdebug_view", function(fields)
	local teams = fields.fire_teams
	war.spheres = fields.spheres
	war.lanes = fields.lanes
	for _, soldier in ipairs(fields.soldiers) do soldier.fireTeam = teams[soldier.fire_team] end
	war.teams, war.soldiers, war.received = teams, fields.soldiers, CurTime()
end)

-- The tactics markers: contacts in amber, cover spots in green, flank
-- points as diamonds in the team's colour.
local CONTACT_COLOR, COVER_COLOR = Color(255, 190, 40), Color(90, 230, 120)
local COVER_BOX, FLANK_BOX, FLANK_ANGLE = Vector(8, 8, 8), Vector(14, 14, 14), Angle(45, 45, 0)
local LANE_MARK = Vector(4, 4, 4)

local function Dim(color)
	return Color(color.r * 0.45, color.g * 0.45, color.b * 0.45)
end

local function DrawWar()
	for _, soldier in ipairs(war.soldiers) do
		if IsValid(soldier.ent) then
			local color = WAR_COLOR[soldier.team] or color_white
			local from = soldier.ent:GetPos() + Vector(0, 0, 8)
			for _, point in ipairs(soldier.route) do
				render.DrawLine(from, point + Vector(0, 0, 8), color, false)
				from = point + Vector(0, 0, 8)
			end
			if soldier.goal then render.DrawWireframeSphere(soldier.goal, 16, 8, 8, color, false) end
			if soldier.cover then render.DrawWireframeBox(soldier.cover, angle_zero, -COVER_BOX, COVER_BOX, COVER_COLOR, false) end
			-- in a fight: a line to its team's contact, bright moving, dim holding
			if soldier.fireTeam then
				local body = soldier.ent:GetPos() + Vector(0, 0, 40)
				render.DrawLine(body, soldier.fireTeam.contact, soldier.moving and color or Dim(color), false)
			end
		end
	end
	-- the cart spheres: rings on the ground, the push sphere bright, the
	-- support sphere dim
	for _, sphere in ipairs(war.spheres) do
		local color = WAR_COLOR[sphere.team] or color_white
		if not sphere.push then color = Dim(color) end
		local segments, lift = sphere.push and 24 or 48, Vector(0, 0, 6)
		local last
		for i = 0, segments do
			local angle = i / segments * math.pi * 2
			local point = sphere.center + Vector(math.cos(angle) * sphere.radius, math.sin(angle) * sphere.radius, 0) + lift
			if last then render.DrawLine(last, point, color, false) end
			last = point
		end
	end
	-- each team's lanes: a dim line along its waypoints, a mark at each
	for _, lane in ipairs(war.lanes or {}) do
		local color = Dim(WAR_COLOR[lane.team] or color_white)
		local lift = Vector(0, 0, 12 + lane.index * 4)
		for j = 2, #lane.points do render.DrawLine(lane.points[j - 1] + lift, lane.points[j] + lift, color, false) end
		for _, point in ipairs(lane.points) do render.DrawWireframeBox(point + lift, angle_zero, -LANE_MARK, LANE_MARK, color, false) end
	end
	-- each fire team in contact: the enemy's last seen place, its flank point
	for _, fireTeam in ipairs(war.teams) do
		local color = WAR_COLOR[fireTeam.team] or color_white
		render.DrawWireframeSphere(fireTeam.contact, 24, 6, 6, CONTACT_COLOR, false)
		render.DrawLine(fireTeam.contact, fireTeam.contact + Vector(0, 0, 96), CONTACT_COLOR, false)
		if fireTeam.flank then
			render.DrawWireframeBox(fireTeam.flank, FLANK_ANGLE, -FLANK_BOX, FLANK_BOX, color, false)
			render.DrawLine(fireTeam.contact, fireTeam.flank, Dim(color), false)
		end
	end
end

-------------------------------------------------------------------------------
-- The world pass

-- PATH, as Path::Draw: each leg in its start's move colour, a tick at each
-- point, seen through walls; the goal as a sphere, green if reached.
local function DrawPath(path)
	local points = path.points
	cam.IgnoreZ(true)
	for i = 1, #points do
		local point = points[i]
		local color = MOVE_COLOR[point.move]
		render.DrawLine(point.pos, point.pos + NODE_TICK, color, false)
		if points[i + 1] then render.DrawLine(point.pos, points[i + 1].pos, color, false) end
	end
	render.DrawWireframeSphere(path.goal, GOAL_RADIUS, 8, 8, path.found and GOAL_REACHED_COLOR or GOAL_SHORT_COLOR, false)
	cam.IgnoreZ(false)
end

local function Outline(corners, color)
	for i = 1, CORNERS do render.DrawLine(corners[i], corners[i % CORNERS + 1], color, false) end
end

-- COST: each area filled and outlined by its cost so far, impassable red.
local function DrawCost(cost)
	render.SetColorMaterial()
	for _, area in ipairs(cost.areas) do
		local c = area.corners
		render.DrawQuad(c[1], c[2], c[3], c[4], area.fill)
		render.DrawQuad(c[4], c[3], c[2], c[1], area.fill)
		Outline(c, area.outline)
	end
end

local function DrawNav(nav)
	for _, area in ipairs(nav) do Outline(area.corners, NAV_COLOR) end
end

-- nb_select's green circle at the selected NPC's feet.
local function DrawSelection(ent)
	local center, last = ent:GetPos() + SELECT_RING_LIFT, nil
	for i = 0, SELECT_RING_SEGMENTS do
		local angle = i / SELECT_RING_SEGMENTS * math.pi * 2
		local point = center + Vector(math.cos(angle) * SELECT_RING_RADIUS, math.sin(angle) * SELECT_RING_RADIUS, 0)
		if last then render.DrawLine(last, point, SELECTED_COLOR, false) end
		last = point
	end
end

hook.Add("PostDrawTranslucentRenderables", "wetsand_nbdebug", function(depth, skybox)
	if skybox then return end
	if Live(war.received) then DrawWar() end
	if view.layers[Debug.COST] and view.cost then DrawCost(view.cost) end
	if view.layers[Debug.NAV] and Live(view.navReceived) then DrawNav(view.nav) end
	if view.layers[Debug.PATH] then
		for _, path in pairs(view.paths) do DrawPath(path) end
	end
	local selected = Entity(view.selected)
	if view.selected ~= NO_SELECTION and IsValid(selected) then DrawSelection(selected) end
end)

-------------------------------------------------------------------------------
-- The HUD pass: one box per NPC with every layer's lines for it

local function Append(list, lines)
	for _, line in ipairs(lines) do list[#list + 1] = line end
end

-- Every NPC with something to show, as { ent, heading, color, details }.
local function Boxes()
	local byIndex, order = {}, {}
	local function BoxOf(ent)
		local index = ent:EntIndex()
		local box = byIndex[index]
		if not box then
			box = {
				ent = ent,
				heading = string.format("%s #%d", ent:GetClass(), index),
				color = NPC_COLOR,
				details = {},
			}
			byIndex[index], order[#order + 1] = box, box
		end
		return box
	end
	if Live(war.received) then
		for _, soldier in ipairs(war.soldiers) do
			if IsValid(soldier.ent) then
				local box = BoxOf(soldier.ent)
				box.heading, box.color = soldier.heading, WAR_COLOR[soldier.team] or color_white
				Append(box.details, soldier.details)
			end
		end
	end
	if view.layers[Debug.PATH] then
		for index, path in pairs(view.paths) do
			local ent = Entity(index)
			if IsValid(ent) then Append(BoxOf(ent).details, Debug.PathLines(path, CurTime())) end
		end
	end
	local cost = view.cost
	if view.layers[Debug.COST] and cost and IsValid(Entity(cost.index)) then
		Append(BoxOf(Entity(cost.index)).details, {
			string.format("Cost: %d areas considered, %d drawn, %s to %s", cost.total, #cost.areas, math.Round(cost.lo), math.Round(cost.hi)),
		})
	end
	if view.layers[Debug.BEHAVIOR] and Live(view.behaviorReceived) then
		for index, lines in pairs(view.behavior) do
			local ent = Entity(index)
			if IsValid(ent) then Append(BoxOf(ent).details, lines) end
		end
	end
	local selected = Entity(view.selected)
	if view.selected ~= NO_SELECTION and IsValid(selected) then
		local box = BoxOf(selected)
		box.heading = box.heading .. " (selected)"
	end
	return order
end

local function Measure(box)
	surface.SetFont("WetsandNbDebugHeading")
	local width, headingHeight = surface.GetTextSize(box.heading)
	surface.SetFont("WetsandNbDebugDetail")
	local _, lineHeight = surface.GetTextSize("Ag")
	for _, detail in ipairs(box.details) do width = math.max(width, (surface.GetTextSize(detail))) end
	local height = headingHeight + #box.details * (lineHeight + BOX_LINE_GAP)
	return width + BOX_PADDING * 2, height + BOX_PADDING * 2, headingHeight, lineHeight
end

-- The heading in bold and the box's colour, then the details in white, on
-- an opaque background; a box moved off its NPC keeps a line to its head.
local function DrawBox(box, rect)
	local color, anchor = box.color, box.anchor
	if rect.moved then
		surface.SetDrawColor(color)
		surface.DrawLine(rect.left + rect.w / 2, rect.top + rect.h, anchor.x, anchor.y)
	end
	draw.RoundedBox(4, rect.left - 1, rect.top - 1, rect.w + 2, rect.h + 2, color)
	draw.RoundedBox(4, rect.left, rect.top, rect.w, rect.h, BOX_BACKGROUND)
	local x, y = rect.left + BOX_PADDING, rect.top + BOX_PADDING
	draw.SimpleText(box.heading, "WetsandNbDebugHeading", x, y, color)
	y = y + box.headingHeight
	for _, detail in ipairs(box.details) do
		draw.SimpleText(detail, "WetsandNbDebugDetail", x, y, color_white)
		y = y + box.lineHeight + BOX_LINE_GAP
	end
end

-- Boxes are laid out nearest NPC first so none covers another.
local function DrawBoxes()
	local eye = EyePos()
	local shown = {}
	for _, box in ipairs(Boxes()) do
		local head = box.ent:GetPos() + Vector(0, 0, box.ent:OBBMaxs().z + BOX_MARGIN)
		local screen = head:ToScreen()
		if screen.visible then
			box.anchor, box.distance = screen, eye:DistToSqr(head)
			shown[#shown + 1] = box
		end
	end
	table.sort(shown, function(a, b) return a.distance < b.distance end)
	local rects = {}
	for i, box in ipairs(shown) do
		local w, h, headingHeight, lineHeight = Measure(box)
		box.headingHeight, box.lineHeight = headingHeight, lineHeight
		rects[i] = { x = box.anchor.x, bottom = box.anchor.y, w = w, h = h }
	end
	rects = Overlay.Layout(rects)
	-- farthest first, so a leader line never crosses a nearer box
	for i = #shown, 1, -1 do DrawBox(shown[i], rects[i]) end
end

local function Label(pos, text, color)
	local screen = pos:ToScreen()
	if not screen.visible then return end
	draw.SimpleTextOutlined(text, "WetsandNbDebugDetail", screen.x, screen.y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
end

local function DrawLabels()
	if Live(war.received) then
		for _, fireTeam in ipairs(war.teams) do
			local color = WAR_COLOR[fireTeam.team] or color_white
			Label(fireTeam.contact + Vector(0, 0, 104), "contact: " .. fireTeam.name, color)
			if fireTeam.flank then Label(fireTeam.flank + Vector(0, 0, 24), "flank: " .. fireTeam.name, color) end
		end
	end
	local eye = EyePos()
	if view.layers[Debug.COST] and view.cost then
		for _, area in ipairs(view.cost.areas) do
			if eye:DistToSqr(area.center) < COST_TEXT_DISTANCE * COST_TEXT_DISTANCE then Label(area.center, area.text, area.outline) end
		end
	end
	if view.layers[Debug.NAV] and Live(view.navReceived) then
		for _, area in ipairs(view.nav) do Label(area.center, area.label, NAV_COLOR) end
	end
end

hook.Add("HUDPaint", "wetsand_nbdebug", function()
	DrawBoxes()
	DrawLabels()
end)

return view
