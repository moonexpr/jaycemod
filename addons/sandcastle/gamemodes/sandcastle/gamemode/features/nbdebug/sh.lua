-- The nbdebug feature's game events: what the controller (sv.lua) and the
-- aiwar controller send an admin's overlay (cl.lua). Field widths are
-- foundation.npc.debug's; the AI war's overlay keeps its own below.
local Debug = WS.require("foundation.npc.debug")
local E = WS.Events

local INDEX = E.UInt(Debug.INDEX_BITS)
local CORNERS = E.List(E.Vector(), Debug.CORNER_COUNT_BITS)

-- The admin's view changed: the layers shown and the selected NPC's index.
E.Define("game_nb_debug_state", {
	layers = E.List(E.String(), Debug.LAYER_COUNT_BITS),
	selected = INDEX,
})

-- A watched NPC's search finished (PATH): its report and path points.
E.Define("game_nb_debug_path", {
	index = INDEX,
	strategy = E.String(),
	source = E.String(),
	found = E.Bool(),
	total_cost = E.Optional(E.Float()),
	microseconds = E.Float(),
	nodes_expanded = E.Optional(E.Float()),
	computed_at = E.Float(),
	goal = E.Vector(),
	points = E.List(E.Record({
		pos = E.Vector(),
		move = E.UInt(Debug.MOVE_BITS),
	}), Debug.POINT_COUNT_BITS),
})

-- The areas the selected NPC's search explored (COST), decimated.
E.Define("game_nb_debug_cost", {
	index = INDEX,
	total = E.UInt(Debug.TOTAL_BITS),
	areas = E.List(E.Record({
		id = E.UInt(Debug.AREA_ID_BITS),
		cost = E.Float(),
		impassable = E.Bool(),
		corners = CORNERS,
	}), Debug.AREA_COUNT_BITS),
})

-- Each watched NPC's behavior lines (BEHAVIOR), periodically.
E.Define("game_nb_debug_behavior", {
	npcs = E.List(E.Record({
		index = INDEX,
		lines = E.List(E.String(), Debug.LINE_COUNT_BITS),
	}), Debug.NPC_COUNT_BITS),
})

-- The nav areas near the selected NPC (NAV), periodically.
E.Define("game_nb_debug_nav", {
	areas = E.List(E.Record({
		id = E.UInt(Debug.AREA_ID_BITS),
		corners = CORNERS,
		attributes = E.List(E.String(), Debug.ATTRIBUTE_COUNT_BITS),
	}), Debug.NPC_COUNT_BITS),
})

-- A watched NPC is gone.
E.Define("game_nb_debug_npc_removed", { index = INDEX })
-- The system stepped in on the selected NPC's movement (MARKS): what
-- (a Debug.MARK_* kind and its detail), where it was, and where it was sent.
E.Define("game_nb_debug_mark", {
	index = INDEX,
	kind = E.String(),
	detail = E.String(),
	from = E.Vector(),
	to = E.Optional(E.Vector()),
})

-- The AI war's soldier overlay (AIWAR), sent by the aiwar controller.
local WAR_COUNT_BITS = 8 -- fire teams, soldiers, route points
local WAR_SPHERE_COUNT_BITS = 4
local WAR_LANE_COUNT_BITS = 4
local WAR_LANE_INDEX_BITS = 8
local WAR_LANE_POINT_COUNT_BITS = 6
local WAR_DETAIL_COUNT_BITS = 4
local WAR_LINE_COUNT_BITS = 3
local WAR_LINE_POINT_COUNT_BITS = 6
local WAR_FRONT_COUNT_BITS = 2

-- fire_teams: every squad with a leader, its summary
-- (foundation.ns.inspect), and while it fights its contact and flank.
-- lines: each team's battle lines, their posts in order across the way
-- they face (a ring when closed); fronts: where each team's lanes lead.
E.Define("game_aiwar_debug", {
	fire_teams = E.List(E.Record({
		team = E.Team(),
		name = E.String(),
		summary = E.String(),
		leader = E.Entity(),
		contact = E.Optional(E.Vector()),
		flank = E.Optional(E.Vector()),
	}), WAR_COUNT_BITS),
	lines = E.List(E.Record({
		team = E.Team(),
		kind = E.String(),
		points = E.List(E.Vector(), WAR_LINE_POINT_COUNT_BITS),
		closed = E.Bool(),
	}), WAR_LINE_COUNT_BITS),
	fronts = E.List(E.Record({
		team = E.Team(),
		pos = E.Vector(),
	}), WAR_FRONT_COUNT_BITS),
	spheres = E.List(E.Record({
		team = E.Team(),
		center = E.Vector(),
		radius = E.Float(),
		push = E.Bool(),
	}), WAR_SPHERE_COUNT_BITS),
	lanes = E.List(E.Record({
		team = E.Team(),
		index = E.UInt(WAR_LANE_INDEX_BITS),
		label = E.String(),
		points = E.List(E.Vector(), WAR_LANE_POINT_COUNT_BITS),
	}), WAR_LANE_COUNT_BITS),
	-- fire_team: its fire team's place in fire_teams, 0 for none; fighting:
	-- whether it fights with that fire team (then moving is its element's).
	soldiers = E.List(E.Record({
		ent = E.Entity(),
		team = E.Team(),
		heading = E.String(),
		details = E.List(E.String(), WAR_DETAIL_COUNT_BITS),
		goal = E.Optional(E.Vector()),
		route = E.List(E.Vector(), WAR_COUNT_BITS),
		fire_team = E.UInt(WAR_COUNT_BITS),
		fighting = E.Bool(),
		moving = E.Bool(),
		cover = E.Optional(E.Vector()),
	}), WAR_COUNT_BITS),
})
