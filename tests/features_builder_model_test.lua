-- The builder's model: which maps it runs on, what placed pieces compile to,
-- what a layout still lacks, and the Wire ports each kind of piece offers.
local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_builder.lua")
local Builder = Fake.Builder
local Classes = Fake.classes
local Room, Locker, Node, Sign = Classes[Builder.ROOM], Classes[Builder.LOCKER], Classes[Builder.NODE], Classes[Builder.SIGN]

local RED, BLUE = 2, 3

local function Holds(condition, what)
	T.eq(condition and true or false, true, what)
end

local function Refused(fn, text)
	local ok, err = pcall(fn)
	T.eq(ok, false, "refused: " .. text)
	Holds(tostring(err):find(text, 1, true), "names " .. text)
end

-- One value, as list items: Fake.Piece also gives its variables.
local function Piece(...)
	return (Fake.Piece(...))
end

local function Box()
	return Vector(-64, -64, 0), Vector(64, 64, 128)
end

local function Volume(id, kind, team)
	local mins, maxs = Box()
	return Piece(id, kind, { team = team, mins = mins, maxs = maxs })
end

local function Of(specs, class)
	local found = {}
	for _, spec in ipairs(specs) do
		if spec.class == class then found[#found + 1] = spec end
	end
	return found
end

local function PlaceOf(specs, class)
	for i, spec in ipairs(specs) do
		if spec.class == class then return i end
	end
	return nil
end

local function Lacks(problems, text)
	for _, problem in ipairs(problems) do
		if problem:find(text, 1, true) then return true end
	end
	return false
end

local function Spawns()
	return Piece(1, Builder.SPAWN, { team = RED }), Piece(2, Builder.SPAWN, { team = BLUE })
end

local function Track(count, checkpoint)
	local pieces = { Spawns() }
	pieces[#pieces + 1] = Piece(3, Builder.CART)
	for n = 1, count do
		pieces[#pieces + 1] = Piece(3 + n, Builder.NODE)
		if n == checkpoint then pieces[#pieces + 1] = Piece(20 + n, Builder.POINT, { node = 3 + n, team = RED }) end
	end
	return pieces
end

T.test("a map holding an objective of its own is a scenario's", function()
	local function Finds(wanted)
		return function(class) return class == wanted end
	end
	for _, class in ipairs(Builder.SCENARIO_CLASSES) do
		T.eq(Builder.IsScenarioMap(Finds(class)), true, class)
	end
	T.eq(Builder.IsScenarioMap(Finds("path_track")), false, "a helicopter's path is no objective")
	T.eq(Builder.IsScenarioMap(function() return false end), false, "an empty map")
end)

T.test("two corners make a box around their middle, the floor at the lower", function()
	local center, mins, maxs = Room.BoxFromCorners(Vector(0, 100, 10), Vector(200, 0, 10), 96)
	T.eq(center.x, 100, "center x")
	T.eq(center.y, 50, "center y")
	T.eq(center.z, 10, "the box stands on the lower corner")
	T.eq(mins.x, -100, "mins x")
	T.eq(maxs.y, 50, "maxs y")
	T.eq(mins.z, 0, "mins z")
	T.eq(maxs.z, 96, "the height comes up from the floor")
end)

T.test("corners at different heights span them, at least the height asked", function()
	local center, mins, maxs = Room.BoxFromCorners(Vector(0, 0, 0), Vector(64, 64, 300), 96)
	T.eq(center.z, 0, "the lower corner's floor")
	T.eq(mins.z, 0, "mins z")
	T.eq(maxs.z, 300, "the higher corner is inside")
end)

T.test("a spawn compiles to an info_player_teamspawn of its team", function()
	local specs = Builder.Compile({ Piece(1, Builder.SPAWN, { team = RED }) }).specs
	local spawn = Of(specs, "info_player_teamspawn")[1]
	T.eq(spawn.keys.TeamNum, tostring(RED), "team")
	T.eq(spawn.name, Builder.Name(1), "named for its piece, so Wire reaches it")
end)

T.test("a spawn room compiles to a func_respawnroom with its box", function()
	local specs = Builder.Compile({ Volume(1, Builder.ROOM, BLUE) }).specs
	local room = Of(specs, "func_respawnroom")[1]
	T.eq(room.keys.TeamNum, tostring(BLUE), "team")
	T.eq(room.mins.x, -64, "mins")
	T.eq(room.maxs.z, 128, "maxs")
end)

T.test("a control point compiles to its point, capture area and base, under one master", function()
	local specs = Builder.Compile({
		Piece(1, Builder.POINT, { team = 0, capTime = 8 }),
		Piece(2, Builder.POINT, { team = 0, capTime = 8 }),
	}).specs
	local points, areas = Of(specs, "team_control_point"), Of(specs, "trigger_capture_area")
	T.eq(#points, 2, "points")
	T.eq(#areas, 2, "an area each")
	T.eq(#Of(specs, "team_control_point_master"), 1, "one master")
	T.eq(points[1].keys.point_index, "0", "indexed from 0")
	T.eq(points[2].keys.point_index, "1", "in the order placed")
	T.eq(areas[2].keys.area_cap_point, points[2].name, "the area captures its point")
	T.eq(areas[1].keys.area_time_to_cap, "8", "its capture time")
	Holds(areas[1].mins and areas[1].maxs, "the area has a box")
	T.eq(#Of(specs, "prop_dynamic"), 2, "a base each")
	Holds(PlaceOf(specs, "team_control_point") < PlaceOf(specs, "trigger_capture_area"), "the point exists before the area names it")
end)

T.test("a track compiles to linked nodes in the order placed", function()
	local specs = Builder.Compile(Track(3)).specs
	local nodes = Of(specs, "path_track")
	T.eq(#nodes, 3, "nodes")
	T.eq(nodes[1].keys.target, nodes[2].name, "first to second")
	T.eq(nodes[2].keys.target, nodes[3].name, "second to third")
	T.eq(nodes[3].keys.target, nil, "the goal leads nowhere")
end)

T.test("the cart is a train, its watcher and its capture area, all linked", function()
	local specs = Builder.Compile(Track(2)).specs
	local nodes, train = Of(specs, "path_track"), Of(specs, "func_tracktrain")[1]
	local watcher, area = Of(specs, "team_train_watcher")[1], Of(specs, "trigger_capture_area")[1]
	T.eq(train.keys.target, nodes[1].name, "the train starts on the first node")
	Holds(tonumber(train.keys.manualaccelspeed) > 0, "SetSpeedDirAccel needs an acceleration")
	T.eq(watcher.keys.train, train.name, "the watcher follows the train")
	T.eq(watcher.keys.start_node, nodes[1].name, "start")
	T.eq(watcher.keys.goal_node, nodes[2].name, "goal")
	T.eq(watcher.keys.handle_train_movement, "1", "the watcher drives it")
	T.eq(watcher.keys.teamnum, tostring(BLUE), "BLU pushes")
	T.eq(area.parent, train.name, "the area rides the train")
	T.eq(area.keys.team_cancap_2, "0", "RED cannot push")
	T.eq(area.keys.team_cancap_3, "1", "BLU pushes")
	Holds(PlaceOf(specs, "func_tracktrain") < PlaceOf(specs, "trigger_capture_area"), "the train exists before the area is parented")
	Holds(PlaceOf(specs, "path_track") < PlaceOf(specs, "func_tracktrain"), "the nodes exist before the train")
end)

T.test("the cart has a prop of its own riding the train, which only moves it", function()
	local specs = Builder.Compile(Track(2)).specs
	local train = Of(specs, "func_tracktrain")[1]
	local prop
	for _, spec in ipairs(Of(specs, "prop_dynamic")) do
		if spec.parent then prop = spec end
	end
	T.eq(prop.model, train.model, "the cart's model")
	T.eq(prop.parent, train.name, "rides the train")
	T.eq(prop.onParent, true, "stands at the train's origin, wherever that has moved")
	T.eq(train.hidden, true, "the train itself does not draw")
	local trainAt, propAt
	for i, spec in ipairs(specs) do
		if spec == train then trainAt = i end
		if spec == prop then propAt = i end
	end
	Holds(trainAt < propAt, "the train exists before the prop")
end)

T.test("a checkpoint is a control point helper on its node, wired by its piece", function()
	local specs = Builder.Compile(Track(3, 2)).specs
	local points = Of(specs, "team_control_point")
	T.eq(points[1].name, Builder.Name(22), "named for the helper, so its wires reach it")
	T.eq(#Of(specs, "trigger_capture_area"), 1, "only the cart's area: the cart captures it")
	T.eq(points[1].pos.x, 500, "at its node")
end)

T.test("a helper's owner is the checkpoint's", function()
	local pieces = Track(3, 2)
	for _, piece in ipairs(pieces) do
		if piece.Kind == Builder.POINT then piece.props.DefaultOwner = 0 end
	end
	T.eq(Of(Builder.Compile(pieces).specs, "team_control_point")[1].keys.point_default_owner, "0", "as set")
end)

T.test("a helper whose track cannot run makes no point", function()
	local compiled = Builder.Compile({ Piece(1, Builder.POINT, { node = 99, team = RED }) })
	T.eq(#Of(compiled.specs, "team_control_point"), 0, "none")
end)

T.test("a point's position sets its place in the order, the rest following as placed", function()
	local points = Of(Builder.Compile({
		Piece(1, Builder.POINT, { team = 0 }),
		Piece(2, Builder.POINT, { team = 0, position = 2 }),
		Piece(3, Builder.POINT, { team = 0, position = 1 }),
	}).specs, "team_control_point")
	T.eq(points[1].name, Builder.Name(3), "position 1 first")
	T.eq(points[2].name, Builder.Name(2), "position 2 next")
	T.eq(points[3].name, Builder.Name(1), "no position last")
	T.eq(points[1].keys.point_index, "0", "indexed so")
end)

T.test("a resupply closet is its locker and the volume in front of it", function()
	local ang = { p = 0, y = 90, r = 0 }
	local specs = Builder.Compile({ Piece(1, Builder.LOCKER, { team = BLUE, ang = ang }) }).specs
	local zone, prop = Of(specs, "func_regenerate")[1], Of(specs, "prop_dynamic")[1]
	T.eq(zone.keys.TeamNum, tostring(BLUE), "its team")
	T.eq(zone.keys.associatedmodel, prop.name, "opens its locker")
	T.eq(zone.ang.y, 90, "the volume faces as it does")
	T.eq(prop.ang.y, 90, "the locker too")
	Holds(zone.maxs.x > 0, "reaches out in front")
	T.eq(prop.model, Locker.MarkerModel, "TF2's locker")
	T.eq(Piece(1, Builder.LOCKER):CompiledName(), zone.name, "its wires reach the volume")
end)

T.test("a locker stands flush on a wall with no room, facing out of it", function()
	local pos, yaw = Locker.Placement({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, nil)
	T.near(yaw, 0, 1e-6, "faces the wall's normal")
	T.near(pos.x, Locker.BACK, 1e-6, "its back on the wall")
	T.near(pos.y, 0, 1e-6, "where it was asked")
end)

T.test("a locker in a room turns to its center, its corner on the wall", function()
	local pos, yaw = Locker.Placement({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 100, y = 100 })
	T.near(yaw, 45, 1, "toward the center")
	Holds(pos.x > Locker.BACK, "stands off the wall enough to turn")
	local straight, yawStraight = Locker.Placement({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 100, y = 0 })
	T.near(yawStraight, 0, 1e-3, "straight ahead")
	T.near(straight.x, Locker.BACK, 1e-3, "flush")
end)

T.test("a center behind the wall is no direction to face", function()
	local _, yaw = Locker.Placement({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, { x = -100, y = 0 })
	T.near(yaw, 0, 1e-6, "the wall's normal")
end)

T.test("the room around a point is found among the rooms", function()
	local rooms = { Volume(1, Builder.ROOM, RED), Volume(2, Builder.ROOM, BLUE) }
	local center = Locker.RoomCenterAt(rooms, { x = 210, y = 10, z = 5 })
	T.eq(center.x, 200, "the second")
	T.eq(Locker.RoomCenterAt(rooms, { x = 5000, y = 0, z = 0 }), nil, "none out there")
end)

T.test("a spawner's model is one of the list", function()
	Holds(#Builder.SPAWN_MODELS > 1, "a choice")
	T.eq(Builder.SpawnModel(Builder.SPAWN_MODELS[2]), Builder.SPAWN_MODELS[2], "chosen")
	T.eq(Builder.SpawnModel("models/nonsense.mdl"), Builder.SPAWN_MODELS[1], "nonsense is the first")
end)

T.test("two clicks close together are a double click", function()
	T.eq(Builder.IsDoubleClick(nil, 5), false, "no first click")
	T.eq(Builder.IsDoubleClick(5, 5 + Builder.DOUBLE_CLICK_TIME / 2), true, "soon after")
	T.eq(Builder.IsDoubleClick(5, 5 + Builder.DOUBLE_CLICK_TIME * 2), false, "too late")
end)

T.test("the goal is always a checkpoint, and marked nodes are too", function()
	local specs = Builder.Compile(Track(3, 2)).specs
	local nodes, points = Of(specs, "path_track"), Of(specs, "team_control_point")
	local watcher = Of(specs, "team_train_watcher")[1]
	T.eq(#points, 2, "the marked node and the goal")
	T.eq(watcher.keys.linked_pathtrack_1, nodes[2].name, "first link's track")
	T.eq(watcher.keys.linked_cp_1, points[1].name, "first link's point")
	T.eq(watcher.keys.linked_pathtrack_2, nodes[3].name, "the goal's track")
	T.eq(watcher.keys.linked_cp_2, points[2].name, "the goal's point")
	T.eq(points[1].keys.point_default_owner, tostring(RED), "RED holds the track")
end)

T.test("passing a checkpoint hands its point to BLU and the area on to the next", function()
	local specs = Builder.Compile(Track(3, 2)).specs
	local nodes, points = Of(specs, "path_track"), Of(specs, "team_control_point")
	local area = Of(specs, "trigger_capture_area")[1]
	T.eq(area.keys.area_cap_point, points[1].name, "the area starts on the first point")
	local outputs = nodes[2].outputs
	T.eq(outputs[1].key, "OnPass", "fired as the cart passes")
	T.eq(outputs[1].value, points[1].name .. ",SetOwner," .. BLUE .. ",0,-1", "the point falls")
	T.eq(outputs[2].value, area.name .. ",SetControlPoint," .. points[2].name .. ",0,-1", "the area moves on")
	T.eq(#nodes[3].outputs, 1, "after the goal there is no next point")
	T.eq(nodes[1].outputs, nil, "a plain node fires nothing")
end)

T.test("BLU takes a track's checkpoints in order, each after the one before", function()
	local points = Of(Builder.Compile(Track(4, 2)).specs, "team_control_point")
	T.eq(points[1].keys.team_previouspoint_3_0, points[1].name, "the first is open: it names itself")
	T.eq(points[2].keys.team_previouspoint_3_0, points[1].name, "the goal after it")
end)

T.test("control points fall in the order placed, for either team", function()
	local points = Of(Builder.Compile({
		Piece(1, Builder.POINT, { team = 0 }),
		Piece(2, Builder.POINT, { team = 0 }),
	}).specs, "team_control_point")
	for _, team in ipairs({ RED, BLUE }) do
		local key = "team_previouspoint_" .. team .. "_0"
		T.eq(points[1].keys[key], points[1].name, "the first is open")
		T.eq(points[2].keys[key], points[1].name, "the second after it")
	end
end)

T.test("a payload's master keeps RED from winning by holding the track", function()
	local specs = Builder.Compile(Track(2)).specs
	T.eq(Of(specs, "team_control_point_master")[1].keys.cpm_restrict_team_cap_win, tostring(RED), "restricted")
	local plain = Builder.Compile({ Piece(1, Builder.POINT, { team = 0 }) }).specs
	T.eq(Of(plain, "team_control_point_master")[1].keys.cpm_restrict_team_cap_win, nil, "points: either side wins")
end)

T.test("a payload's clock running out is RED's win", function()
	local specs = Builder.Compile(Track(2)).specs
	local clock, win = Of(specs, "team_round_timer")[1], Of(specs, "game_round_win")[1]
	T.eq(clock.keys.start_paused, "0", "the clock runs")
	T.eq(win.keys.TeamNum, tostring(RED), "the defenders win")
	T.eq(clock.outputs[1].key, "OnFinished", "at its end")
	T.eq(clock.outputs[1].value, win.name .. ",RoundWin,,0,-1", "the win is fired")
end)

T.test("every checkpoint has its plate, the goal's too", function()
	T.eq(#Of(Builder.Compile(Track(3, 2)).specs, "prop_dynamic"), 3, "two plates and the cart")
end)

T.test("rails are laid from one node to the next, the longest pieces first", function()
	local segments = Node.TrackSegments({ x = 0, y = 0, z = 0 }, { x = 288, y = 0, z = 0 })
	T.eq(#segments, 2, "256 and 32")
	T.eq(segments[1].model, "models/props_mining/track_straight_256.mdl", "the longest")
	T.near(segments[1].pos.x, 128, 1e-6, "centered on its length")
	T.near(segments[2].pos.x, 272, 1e-6, "the next from where it ends")
	T.eq(segments[1].alongY, true, "the long ones run along their Y")
	T.eq(segments[2].alongY, false, "the shortest along its X")
end)

T.test("rails follow a slope, and a gap too short for one is left", function()
	local segments = Node.TrackSegments({ x = 0, y = 0, z = 0 }, { x = 0, y = 64, z = 64 })
	T.near(segments[1].pos.z, 16 * 2 ^ 0.5, 40, "rises with the path")
	T.eq(#Node.TrackSegments({ x = 0, y = 0, z = 0 }, { x = 8, y = 0, z = 0 }), 0, "none")
end)

T.test("every helper has a name for the undo list", function()
	for _, kind in ipairs(Builder.KINDS) do T.eq(type(Classes[kind].PrintName), "string", kind) end
	T.eq(Piece(1, Builder.SPAWN):UndoLabel(), "Spawner", "a spawner")
end)

T.test("the goal's own point has no area of its own", function()
	local specs = Builder.Compile(Track(2)).specs
	T.eq(#Of(specs, "trigger_capture_area"), 1, "only the cart's")
end)

T.test("a flag and a capture zone compile to the map entities", function()
	local specs = Builder.Compile({
		Piece(1, Builder.FLAG, { team = RED, returnTime = 45 }),
		Volume(2, Builder.ZONE, BLUE),
	}).specs
	local flag, zone = Of(specs, "item_teamflag")[1], Of(specs, "func_capturezone")[1]
	T.eq(flag.keys.TeamNum, tostring(RED), "flag's team")
	T.eq(flag.keys.ReturnTime, "45", "its return")
	T.eq(zone.keys.TeamNum, tostring(BLUE), "zone's team")
	T.eq(zone.maxs.z, 128, "its box")
end)

T.test("no pieces compile to nothing and lack nothing", function()
	local compiled = Builder.Compile({})
	T.eq(#compiled.specs, 0, "no specs")
	T.eq(#compiled.problems, 0, "no problems")
end)

T.test("signs compile to nothing: the piece is the sign", function()
	T.eq(#Builder.Compile({ Piece(1, Builder.SIGN) }).specs, 0, "no specs")
end)

T.test("an objective with a team missing its spawn says so", function()
	local problems = Builder.Compile({ Piece(1, Builder.POINT, { team = 0 }), Piece(2, Builder.SPAWN, { team = RED }) }).problems
	Holds(Lacks(problems, "BLU has no spawn"), "BLU")
	Holds(not Lacks(problems, "RED has no spawn"), "RED has one")
end)

T.test("a track of one node is told and leaves no cart", function()
	local compiled = Builder.Compile(Track(1))
	Holds(Lacks(compiled.problems, "track"), "told")
	T.eq(#Of(compiled.specs, "func_tracktrain"), 0, "no train")
	T.eq(#Of(compiled.specs, "path_track"), 0, "no nodes")
end)

T.test("a flag lacks the zone its carriers capture in: the enemy's", function()
	local problems = Builder.Compile({ Piece(1, Builder.FLAG, { team = RED }), Volume(2, Builder.ZONE, RED) }).problems
	Holds(Lacks(problems, "BLU has no capture zone"), "RED's flag is carried by BLU")
	local fine = Builder.Compile({ Piece(1, Builder.FLAG, { team = RED }), Volume(2, Builder.ZONE, BLUE) }).problems
	Holds(not Lacks(fine, "capture zone"), "BLU's zone serves")
end)

T.test("every kind names its Wire ports, and each input is answered", function()
	for _, kind in ipairs(Builder.KINDS) do
		local ports = Classes[kind].WirePorts
		T.eq(type(ports.inputs), "table", kind .. " inputs")
		T.eq(type(ports.outputs), "table", kind .. " outputs")
		for _, name in ipairs(ports.inputs) do
			Holds(Piece(1, kind):WireCommand(name, 1), kind .. " answers " .. name)
		end
	end
end)

T.test("all but a path node and a sign report something to Wire", function()
	Holds(#Classes[Builder.CART].WirePorts.outputs > 0, "the cart")
	Holds(#Classes[Builder.POINT].WirePorts.outputs > 0, "a point")
	Holds(#Classes[Builder.FLAG].WirePorts.outputs > 0, "a flag")
	Holds(#Classes[Builder.ZONE].WirePorts.outputs > 0, "a zone")
end)

T.test("a switch input fires its pair by whether the wire is on", function()
	T.eq(Piece(1, Builder.SPAWN):WireCommand("Enabled", 1).input, "Enable", "on")
	T.eq(Piece(1, Builder.SPAWN):WireCommand("Enabled", 0).input, "Disable", "off")
	T.eq(Piece(1, Builder.ROOM):WireCommand("Active", 0).input, "SetInactive", "a room's")
	T.eq(Piece(1, Builder.NODE):WireCommand("Enabled", 0).input, "DisablePath", "a node's")
end)

T.test("a value input passes the wire's value on", function()
	local command = Piece(1, Builder.POINT):WireCommand("Owner", BLUE)
	T.eq(command.input, "SetOwner", "input")
	T.eq(command.param, tostring(BLUE), "value")
end)

T.test("a pulse input fires only as the wire comes on", function()
	T.eq(Piece(1, Builder.FLAG):WireCommand("Reset", 1).input, "ForceReset", "on")
	T.eq(Piece(1, Builder.FLAG):WireCommand("Reset", 0), Builder.NOTHING, "off does nothing")
end)

T.test("a sign's inputs act on the sign itself", function()
	T.eq(Piece(1, Builder.SIGN):WireCommand("Skin", 4).own, "SetSkin", "its skin")
	T.eq(Piece(1, Builder.SIGN):WireCommand("Visible", 0).own, "SetVisible", "whether it shows")
end)

T.test("a port no kind has is our bug, refused", function()
	Refused(function() Piece(1, Builder.SPAWN):WireCommand("Nonsense", 1) end, "Nonsense")
end)

T.test("a sign's model follows its arrow and size", function()
	T.eq(Sign.ModelFor(Sign.ARROW_LEFT, false), "models/props_gameplay/sign_gameplay01_witharrow_l.mdl", "left")
	T.eq(Sign.ModelFor(Sign.ARROW_RIGHT, true), "models/props_gameplay/sign_gameplay01_witharrow_r_sm.mdl", "small right")
	T.eq(Sign.ModelFor(Sign.ARROW_NONE, false), "models/props_gameplay/sign_gameplay01.mdl", "no arrow")
end)

T.test("flipping a sign swaps its arrow and leaves a plain one plain", function()
	T.eq(Sign.Flip(Sign.ARROW_LEFT), Sign.ARROW_RIGHT, "left to right")
	T.eq(Sign.Flip(Sign.ARROW_RIGHT), Sign.ARROW_LEFT, "right to left")
	T.eq(Sign.Flip(Sign.ARROW_NONE), Sign.ARROW_NONE, "none stays")
end)

T.test("a piece's Wire inputs reach the entity that does its work", function()
	local specs = Builder.Compile(Track(2)).specs
	T.eq(Piece(3, Builder.CART):CompiledName(), Of(specs, "team_train_watcher")[1].name, "the cart's is its watcher")
	T.eq(Piece(4, Builder.NODE):CompiledName(), Of(specs, "path_track")[1].name, "a node's is itself")
	local point = Builder.Compile({ Piece(1, Builder.POINT, { team = 0 }) }).specs
	T.eq(Builder.AreaName(1), Of(point, "trigger_capture_area")[1].name, "a point's capture area")
end)

T.test("what a tool's convars say is parsed to what the helpers allow", function()
	T.eq(Builder.PlayingTeam(BLUE), BLUE, "BLU")
	T.eq(Builder.PlayingTeam(99), RED, "nonsense is RED")
	T.eq(Builder.PlayingTeam(0), RED, "neutral is no playing team")
	T.eq(Builder.NextOwner(0), RED, "neutral to RED")
	T.eq(Builder.NextOwner(RED), BLUE, "RED to BLU")
	T.eq(Builder.NextOwner(BLUE), 0, "BLU to neutral")
end)

T.test("every kind has a model to be seen by while building", function()
	for _, kind in ipairs(Builder.KINDS) do
		if kind ~= Builder.SIGN then T.eq(type(Classes[kind].MarkerModel), "string", kind) end
	end
end)

T.test("Wire's own entities are kept through a round's cleanup, and nothing else", function()
	local kept = Builder.WireClasses({ "gmod_wire_gate", "prop_physics", "gmod_wire_value", "gmod_lamp" })
	table.sort(kept)
	T.eq(#kept, 2, "two")
	T.eq(kept[1], "gmod_wire_gate", "a gate")
	T.eq(kept[2], "gmod_wire_value", "a constant")
end)

T.test("every kind is a class of its own, and every property a Hammer keyvalue or a tool's", function()
	for _, kind in ipairs(Builder.KINDS) do
		T.eq(type(Builder.CLASSES[kind]), "string", kind .. " class")
		for _, prop in ipairs(Classes[kind].Properties) do
			T.eq(type(prop.name), "string", kind .. " name")
			T.eq(type(prop.title), "string", kind .. " " .. prop.name .. " title")
			Holds(prop.default ~= nil, kind .. " " .. prop.name .. " default")
			Holds(Builder.NETWORK_TYPES[prop.type], kind .. " " .. prop.name .. " type")
		end
	end
end)

T.test("a property's Hammer key reaches the entity it belongs to", function()
	local specs = Builder.Compile({
		Piece(1, Builder.POINT, { props = { PrintName = "Bridge", DefaultOwner = BLUE, StartLocked = true, TimeToCap = 9, CanCapRed = false, NumCapBlu = 2, SpawnAdjustRed = 5 } }),
	}).specs
	local point, area = Of(specs, "team_control_point")[1], Of(specs, "trigger_capture_area")[1]
	T.eq(point.keys.point_printname, "Bridge", "its name")
	T.eq(point.keys.point_default_owner, tostring(BLUE), "its owner")
	T.eq(point.keys.point_start_locked, "1", "a true is 1")
	T.eq(area.keys.team_cancap_2, "0", "a false is 0")
	T.eq(area.keys.team_numcap_3, "2", "the area's")
	T.eq(area.keys.team_spawn_2, "5", "the area's")
	T.eq(area.keys.area_time_to_cap, "9", "the area's")
	T.eq(point.keys.team_cancap_2, nil, "not the point's")
end)

T.test("a control point without a name is called by its place", function()
	local specs = Builder.Compile({ Piece(1, Builder.POINT), Piece(2, Builder.POINT) }).specs
	T.eq(Of(specs, "team_control_point")[2].keys.point_printname, "Point 2", "numbered")
end)

T.test("the cart's properties reach its train and its watcher", function()
	local pieces = Track(2)
	for _, piece in ipairs(pieces) do
		if piece.Kind == Builder.CART then piece:Update({ MaxSpeed = 120, CanRecede = false, RecedeTime = 7, Height = 40 }) end
	end
	local specs = Builder.Compile(pieces).specs
	local train, watcher = Of(specs, "func_tracktrain")[1], Of(specs, "team_train_watcher")[1]
	T.eq(train.keys.startspeed, "120", "top speed")
	T.eq(train.keys.height, "40", "height")
	T.eq(watcher.keys.train_can_recede, "0", "recede")
	T.eq(watcher.keys.train_recede_time, "7", "recede time")
end)

T.test("RED may push the cart instead, and then BLU holds the track", function()
	local pieces = Track(3, 2)
	for _, piece in ipairs(pieces) do
		if piece.Kind == Builder.CART then piece:Update({ TeamNum = RED }) end
	end
	local specs = Builder.Compile(pieces).specs
	local points, area = Of(specs, "team_control_point"), Of(specs, "trigger_capture_area")[1]
	T.eq(area.keys.team_cancap_2, "1", "RED pushes")
	T.eq(area.keys.team_cancap_3, "0", "BLU cannot")
	T.eq(points[2].keys.point_default_owner, tostring(BLUE), "BLU holds the goal")
	T.eq(points[2].keys.team_previouspoint_2_0, points[1].name, "RED takes them in order")
	T.eq(Of(specs, "path_track")[2].outputs[1].value, points[1].name .. ",SetOwner," .. RED .. ",0,-1", "and takes them")
	T.eq(Of(specs, "team_control_point_master")[1].keys.cpm_restrict_team_cap_win, tostring(BLUE), "BLU cannot win by holding")
	T.eq(Of(specs, "game_round_win")[1].keys.TeamNum, tostring(BLUE), "the clock is BLU's")
end)

T.test("a track node's flags are Hammer's spawnflags, for the watcher's hills", function()
	local pieces = Track(2)
	for _, piece in ipairs(pieces) do
		if piece.Kind == Builder.NODE then piece:Update({ Uphill = true, Disabled = true }) end
	end
	T.eq(Of(Builder.Compile(pieces).specs, "path_track")[1].keys.spawnflags, "33", "disabled and uphill")
	T.eq(Of(Builder.Compile(Track(2)).specs, "path_track")[1].keys.spawnflags, "0", "neither")
end)

T.test("the scenario's properties reach the master, the clock and the rules", function()
	local specs = Builder.Compile({
		Piece(1, Builder.POINT),
		Piece(2, Builder.SCENARIO, { props = {
			CapLayout = "0 1, 2", ScoreStyle = 1, SwitchTeams = true, PlayAllRounds = true, PartialCapRate = 0.5, RestrictWin = BLUE,
			TimerLength = 300, SetupLength = 45, TimerWinner = RED,
		} }),
	}).specs
	local master = Of(specs, "team_control_point_master")[1]
	T.eq(master.keys.caplayout, "0 1, 2", "capture layout")
	T.eq(master.keys.score_style, "1", "scoring style")
	T.eq(master.keys.switch_teams, "1", "switching teams")
	T.eq(master.keys.play_all_rounds, "1", "all rounds")
	T.eq(master.keys.partial_cap_points_rate, "0.5", "partial capture rate")
	T.eq(master.keys.cpm_restrict_team_cap_win, tostring(BLUE), "who may not win by holding")
	local clock = Of(specs, "team_round_timer")[1]
	T.eq(clock.keys.timer_length, "300", "round length")
	T.eq(clock.keys.setup_length, "45", "setup")
	T.eq(Of(specs, "game_round_win")[1].keys.TeamNum, tostring(RED), "who the clock's end favours")
end)

T.test("team timers make the game King of the Hill, tf_logic_koth in place of the round clock", function()
	local specs = Builder.Compile({
		Piece(1, Builder.POINT),
		Piece(2, Builder.SCENARIO, { props = { TeamTimers = true, TeamTimerLength = 120, TeamUnlockPoint = 15, TimerLength = 300 } }),
	}).specs
	local logic = Of(specs, "tf_logic_koth")[1]
	T.eq(logic.keys.timer_length, "120", "each team's clock")
	T.eq(logic.keys.unlock_point, "15", "when the point unlocks")
	T.eq(#Of(specs, "team_round_timer"), 0, "no round clock")
	T.eq(#Of(specs, "game_round_win"), 0, "the team clocks end the round")
	T.eq(#Of(specs, "team_control_point_master"), 1, "the point is still played under a master")
end)

T.test("without team timers the game has its round clock and no King of the Hill", function()
	local specs = Builder.Compile({ Piece(1, Builder.POINT), Piece(2, Builder.SCENARIO) }).specs
	T.eq(#Of(specs, "tf_logic_koth"), 0, "no logic")
	T.eq(#Of(specs, "team_round_timer"), 1, "the round clock")
end)

T.test("team timers without a point make nothing", function()
	local specs = Builder.Compile({ Piece(1, Builder.SCENARIO, { props = { TeamTimers = true } }) }).specs
	T.eq(#Of(specs, "tf_logic_koth"), 0, "there is no hill")
end)

T.test("the scenario tells the rules what a map's outputs would", function()
	local inputs = Builder.Compile({
		Piece(1, Builder.SCENARIO, { props = { RedRespawn = 8, BluRespawn = 0, RedGoal = "Hold the bridge", StalemateOnTimelimit = true } }),
	}).rules
	local by = {}
	for _, input in ipairs(inputs) do by[input.input] = input.param end
	T.eq(by.SetRedTeamRespawnWaveTime, "8", "RED's waves")
	T.eq(by.SetBlueTeamRespawnWaveTime, nil, "0 leaves BLU's to the server's")
	T.eq(by.SetRedTeamGoalString, "Hold the bridge", "RED's goal")
	T.eq(by.SetBlueTeamGoalString, nil, "no goal given")
	T.eq(by.SetStalemateOnTimelimit, "1", "the time limit's stalemate")
end)

T.test("every field of the scenario has Hammer's help", function()
	for _, prop in ipairs(Classes[Builder.SCENARIO].Properties) do
		T.eq(type(prop.help), "string", prop.name)
		Holds(#prop.help > 0, prop.name .. " says something")
	end
end)

T.test("a control point's index and group say what they do", function()
	local help = {}
	for _, prop in ipairs(Classes[Builder.POINT].Properties) do help[prop.name] = prop.help end
	T.eq(type(help.PointIndex), "string", "the index")
	T.eq(type(help.Group), "string", "the group")
end)

T.test("the scenario's goals are chosen from TF2's own, or none", function()
	for _, name in ipairs({ "RedGoal", "BluGoal" }) do
		local prop
		for _, candidate in ipairs(Classes[Builder.SCENARIO].Properties) do
			if candidate.name == name then prop = candidate end
		end
		T.eq(prop.default, "", name .. " starts with none")
		local none, tokens = false, 0
		for label, value in pairs(prop.values) do
			T.eq(type(label), "string", name .. " label")
			if value == "" then none = true else
				Holds(value:sub(1, 1) == "#", name .. " " .. value .. " is a token")
				tokens = tokens + 1
			end
		end
		Holds(none, name .. " may have none")
		Holds(tokens > 1, name .. " has a choice")
	end
end)

T.test("restricting a team takes Hammer's values", function()
	local values
	for _, prop in ipairs(Classes[Builder.SCENARIO].Properties) do
		if prop.name == "RestrictWin" then values = prop.values end
	end
	T.eq(values.Neither, 0, "neither is restricted")
	T.eq(values.Both, 1, "both are")
	T.eq(values.Red, RED, "RED")
	T.eq(values.Blue, BLUE, "BLU")
end)

T.test("help is wrapped to lines a tooltip can show", function()
	local wrapped = Builder.WrapHelp("one two three four five six", 9)
	T.eq(wrapped, "one two\nthree\nfour five\nsix", "at the words")
	T.eq(Builder.WrapHelp("short", 60), "short", "alone")
	T.eq(Builder.WrapHelp("averyveryverylongword x", 4), "averyveryverylongword\nx", "a long word stands alone")
end)

T.test("the scenario makes no objective of its own", function()
	local compiled = Builder.Compile({ Piece(1, Builder.SCENARIO) })
	T.eq(#compiled.specs, 0, "no entities")
	T.eq(#compiled.problems, 0, "lacks nothing")
end)

T.test("the scenario's Wire inputs are the rules' inputs", function()
	T.eq(Piece(1, Builder.SCENARIO):WireCommand("RedRespawnTime", 6).input, "SetRedTeamRespawnWaveTime", "RED's")
	T.eq(Piece(1, Builder.SCENARIO):WireCommand("BluRespawnTime", 6).param, "6", "the value")
	T.eq(Piece(1, Builder.SCENARIO):WireCommand("AddRedScore", 2).input, "AddRedTeamScore", "a score")
end)

T.test("a pasted piece keeps its id unless another has it", function()
	T.eq(Builder.PastedId(5, { [3] = true }, 9), 5, "free")
	T.eq(Builder.PastedId(3, { [3] = true }, 9), 9, "taken: the next")
end)

T.test("control points on a clock end in a stalemate when it runs out", function()
	local specs = Builder.Compile({ Piece(1, Builder.POINT, { team = 0 }) }).specs
	T.eq(Of(specs, "game_round_win")[1].keys.TeamNum, "0", "nobody wins")
end)

T.test("a flag game keeps to its capture limit: no clock", function()
	local specs = Builder.Compile({ Piece(1, Builder.FLAG, { team = RED }), Volume(2, Builder.ZONE, BLUE) }).specs
	T.eq(#Of(specs, "team_round_timer"), 0, "no timer")
end)

T.finish()
