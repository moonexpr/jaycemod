-- The nbdebug feature's view: the one NPC debug overlay. It draws what the
-- nbdebug controller sends for ws_nb_debug's layers (PATH, COST,
-- BEHAVIOR, NAV) and the AI war's soldier overlay (the AIWAR layer, which
-- the aiwar controller sends as ws_aiwar_debug) in one pass: lines and
-- areas in the world after the translucent renderables, then in HUDPaint one
-- box per NPC above its head, holding every layer's lines for it (laid out
-- by features.nbdebug.aiwar_overlay so none covers another), and the labels.
-- Nothing here needs developer mode, so it works on dedicated servers.
local Debug = WS.require("foundation.npc.debug")
local Overlay = WS.require("features.nbdebug.aiwar_overlay")
local Parts = WS.require("foundation.ns.overlay")

-- The game events it listens to are sh.lua's; game_aiwar_debug is the aiwar
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

surface.CreateFont("WSNbDebugHeading", {
	font = "Tahoma",
	size = 15,
	weight = 800,
})
surface.CreateFont("WSNbDebugDetail", {
	font = "Tahoma",
	size = 13,
	weight = 500,
})
-- The world's labels: bold, to read over bright maps.
surface.CreateFont("WSNbDebugLabel", {
	font = "Tahoma",
	size = 15,
	weight = 800,
})
local LABEL_OUTLINE = 2

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
	marks = {}, -- the selected NPC's marks (cl_marks.lua)
}

local Part = WS.FeatureParts(getfenv(1), "nbdebug")
local Marks = Part("cl_marks", view)

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

local E = WS.Events

E.Listen("game_nb_debug_state", "ws_nbdebug_view", function(fields)
	local layers = {}
	for _, name in ipairs(fields.layers) do layers[name] = true end
	view.layers = layers
	view.selected = fields.selected
	-- the server resends what the new view needs
	view.paths, view.cost, view.behavior, view.nav = {}, nil, {}, {}
	-- the NPC context menu (ws/cl_nb_menu.lua) checks the layers that
	-- are on and the NPC selected
	hook.Run("WSNbDebugState", layers, fields.selected)
end)

E.Listen("game_nb_debug_path", "ws_nbdebug_view", function(fields)
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

E.Listen("game_nb_debug_cost", "ws_nbdebug_view", function(fields)
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

E.Listen("game_nb_debug_behavior", "ws_nbdebug_view", function(fields)
	local behavior = {}
	for _, npc in ipairs(fields.npcs) do behavior[npc.index] = npc.lines end
	view.behavior, view.behaviorReceived = behavior, CurTime()
end)

E.Listen("game_nb_debug_nav", "ws_nbdebug_view", function(fields)
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

E.Listen("game_nb_debug_npc_removed", "ws_nbdebug_view", function(fields)
	local index = fields.index
	view.paths[index], view.behavior[index] = nil, nil
	if view.cost and view.cost.index == index then view.cost = nil end
	if view.selected == index then
		view.selected, view.nav = NO_SELECTION, {}
		hook.Run("WSNbDebugState", view.layers, view.selected)
	end
end)

-------------------------------------------------------------------------------
-- The AI war's soldier overlay (AIWAR): what its controller last sent,
-- drawn until it goes stale. Each part (foundation.ns.overlay's PARTS) is
-- drawn while its client convar is on (the NPC context menu's toggles,
-- ws/cl_nb_menu.lua).

local war = { soldiers = {}, teams = {}, spheres = {}, lanes = {}, lines = {}, fronts = {}, received = -math.huge }

local function Shows(part)
	return GetConVar(Parts.ConVar(part)):GetBool()
end

-- Neon team colours, brighter than the HUD's, to read over any map.
local WAR_COLOR = { [WS.TEAM_RED] = Color(255, 70, 110), [WS.TEAM_BLUE] = Color(60, 210, 255) }

E.Listen("game_aiwar_debug", "ws_nbdebug_view", function(fields)
	local teams = fields.fire_teams
	war.spheres = fields.spheres
	war.lanes = fields.lanes
	war.lines = fields.lines
	war.fronts = fields.fronts
	for _, soldier in ipairs(fields.soldiers) do soldier.fireTeam = teams[soldier.fire_team] end
	war.teams, war.soldiers, war.received = teams, fields.soldiers, CurTime()
end)

-- The tactics markers: contacts in amber, cover spots in green, flank
-- points as diamonds in the team's colour.
local CONTACT_COLOR, COVER_COLOR = Color(255, 190, 40), Color(90, 230, 120)
local COVER_BOX, FLANK_BOX, FLANK_ANGLE = Vector(8, 8, 8), Vector(14, 14, 14), Angle(45, 45, 0)
local LANE_MARK = Vector(4, 4, 4)
-- Squads: a ring at the leader's feet, and a link from each member to it
-- (bright while its element moves, dim while it holds).
local LEADER_RING, LINK_LIFT = 28, Vector(0, 0, 16)
-- Battle lines: a rail through the posts, a post at each; fronts: a pillar.
local LINE_LIFT, LINE_RAIL_GAP, POST_HEIGHT = Vector(0, 0, 10), Vector(0, 0, 3), Vector(0, 0, 56)
local FRONT_RING, FRONT_HEIGHT = 64, Vector(0, 0, 200)
local GROUND_LIFT = Vector(0, 0, 6)
local RING_SEGMENTS = 24

local function Dim(color)
	return Color(color.r * 0.45, color.g * 0.45, color.b * 0.45)
end

-- Neon lines, to read over bright maps: a solid core CORE_WIDTH units
-- thick, lifted toward white, inside a wide additive glow in the colour.
local GLOW = Material("sprites/physbeama")
local GLOW_WIDTH, CORE_WIDTH = 10, 3
local CORE_LIFT = 0.35 -- how far the core moves toward white

local function NeonLine(from, to, color)
	render.SetMaterial(GLOW)
	render.DrawBeam(from, to, GLOW_WIDTH, 0, 1, color)
	local r, g, b = color.r, color.g, color.b
	render.SetColorMaterial()
	render.DrawBeam(from, to, CORE_WIDTH, 0, 1, Color(r + (255 - r) * CORE_LIFT, g + (255 - g) * CORE_LIFT, b + (255 - b) * CORE_LIFT))
end

local function Ring(center, radius, segments, color)
	local last
	for i = 0, segments do
		local angle = i / segments * math.pi * 2
		local point = center + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 0)
		if last then NeonLine(last, point, color) end
		last = point
	end
end

local function DrawSoldier(soldier, color)
	local from = soldier.ent:GetPos() + Vector(0, 0, 8)
	for _, point in ipairs(soldier.route) do
		NeonLine(from, point + Vector(0, 0, 8), color)
		from = point + Vector(0, 0, 8)
	end
	if soldier.goal then render.DrawWireframeSphere(soldier.goal, 16, 8, 8, color, false) end
end

-- Battle lines are where a team holds, not a way anyone walks, so their
-- rails cross walls: they are drawn thin, dashed and paler than the
-- lanes' neon, so the two never read alike. Posts stay neon pillars.
local DASH, DASH_GAP, RAIL_WIDTH = 24, 16, 1.5
local RAIL_LIFT = 0.55 -- how far a rail's colour moves toward white

local function DashedLine(from, to, color)
	local length = from:Distance(to)
	local step = (to - from):GetNormalized()
	render.SetColorMaterial()
	for d = 0, length, DASH + DASH_GAP do
		render.DrawBeam(from + step * d, from + step * math.min(d + DASH, length), RAIL_WIDTH, 0, 1, color)
	end
end

local function DrawBattleLine(line)
	local color = WAR_COLOR[line.team] or color_white
	if line.kind ~= "posts" then color = Dim(color) end
	local r, g, b = color.r, color.g, color.b
	local rail = Color(r + (255 - r) * RAIL_LIFT, g + (255 - g) * RAIL_LIFT, b + (255 - b) * RAIL_LIFT)
	local points = line.points
	for j = 1, #points do
		local base = points[j] + LINE_LIFT
		NeonLine(base, base + POST_HEIGHT, color)
		local nextPoint = points[j + 1] or (line.closed and #points > 2 and points[1])
		if nextPoint then
			DashedLine(base, nextPoint + LINE_LIFT, rail)
			DashedLine(base + LINE_RAIL_GAP, nextPoint + LINE_LIFT + LINE_RAIL_GAP, rail)
		end
	end
end

local function DrawWar()
	local soldiers, squads, contacts = Shows(Parts.SOLDIERS), Shows(Parts.SQUADS), Shows(Parts.CONTACTS)
	for _, soldier in ipairs(war.soldiers) do
		if IsValid(soldier.ent) then
			local color = WAR_COLOR[soldier.team] or color_white
			local fireTeam = soldier.fireTeam
			if soldiers then DrawSoldier(soldier, color) end
			if contacts and soldier.cover then render.DrawWireframeBox(soldier.cover, angle_zero, -COVER_BOX, COVER_BOX, COVER_COLOR, false) end
			-- in a fight: a line to its team's contact, bright moving, dim holding
			if contacts and soldier.fighting and fireTeam and fireTeam.contact then
				local body = soldier.ent:GetPos() + Vector(0, 0, 40)
				NeonLine(body, fireTeam.contact, soldier.moving and color or Dim(color))
			end
			if squads and fireTeam and IsValid(fireTeam.leader) and fireTeam.leader ~= soldier.ent then
				local link = (soldier.fighting and not soldier.moving) and Dim(color) or color
				NeonLine(soldier.ent:GetPos() + LINK_LIFT, fireTeam.leader:GetPos() + LINK_LIFT, link)
			end
		end
	end
	if squads then
		for _, fireTeam in ipairs(war.teams) do
			if IsValid(fireTeam.leader) then
				local color = WAR_COLOR[fireTeam.team] or color_white
				Ring(fireTeam.leader:GetPos() + GROUND_LIFT, LEADER_RING, RING_SEGMENTS, color)
				Ring(fireTeam.leader:GetPos() + GROUND_LIFT, LEADER_RING + 4, RING_SEGMENTS, color)
			end
		end
	end
	if Shows(Parts.BATTLELINES) then
		-- the cart spheres: rings on the ground, the push sphere bright, the
		-- support sphere dim
		for _, sphere in ipairs(war.spheres) do
			local color = WAR_COLOR[sphere.team] or color_white
			if not sphere.push then color = Dim(color) end
			Ring(sphere.center + GROUND_LIFT, sphere.radius, sphere.push and 24 or 48, color)
		end
		for _, line in ipairs(war.lines) do DrawBattleLine(line) end
		for _, front in ipairs(war.fronts) do
			local color = WAR_COLOR[front.team] or color_white
			NeonLine(front.pos, front.pos + FRONT_HEIGHT, color)
			Ring(front.pos + GROUND_LIFT, FRONT_RING, RING_SEGMENTS, color)
		end
	end
	if Shows(Parts.LANES) then
		-- each team's lanes: a dim line along its waypoints, a mark at each
		for _, lane in ipairs(war.lanes) do
			local color = Dim(WAR_COLOR[lane.team] or color_white)
			local lift = Vector(0, 0, 12 + lane.index * 4)
			for j = 2, #lane.points do NeonLine(lane.points[j - 1] + lift, lane.points[j] + lift, color) end
			for _, point in ipairs(lane.points) do render.DrawWireframeBox(point + lift, angle_zero, -LANE_MARK, LANE_MARK, color, false) end
		end
	end
	if contacts then
		-- each fire team in contact: the enemy's last seen place, its flank point
		for _, fireTeam in ipairs(war.teams) do
			if fireTeam.contact then
				local color = WAR_COLOR[fireTeam.team] or color_white
				render.DrawWireframeSphere(fireTeam.contact, 24, 6, 6, CONTACT_COLOR, false)
				NeonLine(fireTeam.contact, fireTeam.contact + Vector(0, 0, 96), CONTACT_COLOR)
				if fireTeam.flank then
					render.DrawWireframeBox(fireTeam.flank, FLANK_ANGLE, -FLANK_BOX, FLANK_BOX, color, false)
					NeonLine(fireTeam.contact, fireTeam.flank, Dim(color))
				end
			end
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

hook.Add("PostDrawTranslucentRenderables", "ws_nbdebug", function(depth, skybox)
	if skybox then return end
	if Live(war.received) then DrawWar() end
	if view.layers[Debug.COST] and view.cost then DrawCost(view.cost) end
	if view.layers[Debug.NAV] and Live(view.navReceived) then DrawNav(view.nav) end
	if view.layers[Debug.MARKS] then Marks.Draw(CurTime()) end
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
	if Live(war.received) and Shows(Parts.SOLDIERS) then
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
	surface.SetFont("WSNbDebugHeading")
	local width, headingHeight = surface.GetTextSize(box.heading)
	surface.SetFont("WSNbDebugDetail")
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
	draw.SimpleText(box.heading, "WSNbDebugHeading", x, y, color)
	y = y + box.headingHeight
	for _, detail in ipairs(box.details) do
		draw.SimpleText(detail, "WSNbDebugDetail", x, y, color_white)
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

-- align: TEXT_ALIGN_BOTTOM (above the point, the default) or TEXT_ALIGN_TOP.
local function Label(pos, text, color, align)
	local screen = pos:ToScreen()
	if not screen.visible then return end
	draw.SimpleTextOutlined(text, "WSNbDebugLabel", screen.x, screen.y, color, TEXT_ALIGN_CENTER, align or TEXT_ALIGN_BOTTOM, LABEL_OUTLINE, color_black)
end

local TEAM_LABEL = { [WS.TEAM_RED] = "RED", [WS.TEAM_BLUE] = "BLU" }

local function Middle(points)
	return points[math.floor((#points + 1) / 2)]
end

local function DrawWarLabels()
	if Shows(Parts.CONTACTS) then
		for _, fireTeam in ipairs(war.teams) do
			local color = WAR_COLOR[fireTeam.team] or color_white
			if fireTeam.contact then Label(fireTeam.contact + Vector(0, 0, 104), "contact: " .. fireTeam.name, color) end
			if fireTeam.flank then Label(fireTeam.flank + Vector(0, 0, 24), "flank: " .. fireTeam.name, color) end
		end
	end
	-- a squad's summary under its leader's feet
	if Shows(Parts.SQUADS) then
		for _, fireTeam in ipairs(war.teams) do
			if IsValid(fireTeam.leader) then
				Label(fireTeam.leader:GetPos(), fireTeam.summary, WAR_COLOR[fireTeam.team] or color_white, TEXT_ALIGN_TOP)
			end
		end
	end
	if Shows(Parts.LANES) then
		for _, lane in ipairs(war.lanes) do
			if #lane.points > 0 then
				Label(Middle(lane.points) + Vector(0, 0, 24 + lane.index * 4), TEAM_LABEL[lane.team] .. " " .. lane.label, WAR_COLOR[lane.team] or color_white)
			end
		end
	end
	if Shows(Parts.BATTLELINES) then
		for _, line in ipairs(war.lines) do
			if #line.points > 0 then
				Label(Middle(line.points) + LINE_LIFT + POST_HEIGHT, TEAM_LABEL[line.team] .. " " .. line.kind, WAR_COLOR[line.team] or color_white)
			end
		end
		for _, front in ipairs(war.fronts) do
			Label(front.pos + FRONT_HEIGHT, TEAM_LABEL[front.team] .. " front", WAR_COLOR[front.team] or color_white)
		end
	end
end

local function DrawLabels()
	if Live(war.received) then DrawWarLabels() end
	local eye = EyePos()
	if view.layers[Debug.COST] and view.cost then
		for _, area in ipairs(view.cost.areas) do
			if eye:DistToSqr(area.center) < COST_TEXT_DISTANCE * COST_TEXT_DISTANCE then Label(area.center, area.text, area.outline) end
		end
	end
	if view.layers[Debug.NAV] and Live(view.navReceived) then
		for _, area in ipairs(view.nav) do Label(area.center, area.label, NAV_COLOR) end
	end
	if view.layers[Debug.MARKS] then Marks.DrawLabels(Label) end
end

WS.HUD:Add("debug.nbdebug", WS.HUD_ORDER.DEBUG, function()
	DrawBoxes()
	DrawLabels()
end)

return view
