-- Part of the nbdebug view (cl.lua): the AI war overlay's rooms part, the
-- map's rooms (wartactics.rooms) as last sent (game_aiwar_rooms). Each room
-- is a block from its floor to ROOM_HEIGHT over its highest, in its class's
-- colour once the classes are found (the tooling's: restricted dark in its
-- team's, a stronghold in its team's, paler down its gradient, highway
-- orange, commons yellow, unoccupied grey-green, wilds green), until then in
-- a colour of its own by id (pale outdoors); with a mark at its centre, a
-- spoke to each door (a box on it) and window (a cyan diamond on it), and a
-- dim line on to the room each leads to; the corridors between them are
-- grey blocks. Over them each team's tree, a branch in its colour from each
-- space's entry to the entry of the one its walk enters it from; the
-- junctions, white blocks; and the ambush markings, a box on the hiding
-- spot in the team's colour and a line to the doorway it covers.
-- draw: the view's NeonLine, Dim and Label. Returns Draw() and Labels().
local draw = ...

local ROOM_MARK, DOOR_MARK, ROOM_LIFT = Vector(10, 10, 10), Vector(6, 6, 6), Vector(0, 0, 40)
local ROOM_HEIGHT, WINDOW_ANGLE = Vector(0, 0, 96), Angle(45, 45, 0)
local WINDOW_COLOR, PASSAGE_COLOR = Color(80, 240, 255), Color(150, 150, 150)
local GOLDEN = 137.508 -- degrees of hue between one room and the next

local JUNCTION_COLOR, SPOT_MARK = Color(255, 255, 255), Vector(5, 5, 5)
local TEAM_COLOR = { [WS.TEAM_RED] = Color(230, 60, 60), [WS.TEAM_BLUE] = Color(70, 120, 240) }
local CLASS_COLOR = { highway = Color(245, 150, 30), commons = Color(240, 220, 80), unoccupied = Color(190, 200, 170),
	wilds = Color(110, 190, 90), outpost = Color(255, 180, 200) }

local rooms, roomById, passages, branches, junctions, ambushes = {}, {}, {}, {}, {}, {}

WS.Events.Listen("game_aiwar_rooms", "ws_nbdebug_view", function(fields)
	rooms, roomById, passages = fields.rooms, {}, fields.passages
	branches, junctions, ambushes = fields.branches, fields.junctions, fields.ambushes
	for _, room in ipairs(rooms) do roomById[room.id] = room end
end)

-- color faded toward white as share falls from 1 to 0, never below a third.
local function Pale(color, share)
	local keep = 1 / 3 + 2 / 3 * math.Clamp(share, 0, 1)
	return Color(255 - (255 - color.r) * keep, 255 - (255 - color.g) * keep, 255 - (255 - color.b) * keep)
end

local function RoomColor(room)
	local team = TEAM_COLOR[room.team]
	if room.class == "restricted" and team then return Color(team.r * 0.6, team.g * 0.6, team.b * 0.6) end
	if room.class == "stronghold" and team then return Pale(team, room.gradient / 100) end
	if room.class == "commons" then return Pale(CLASS_COLOR.commons, 1 - room.gradient / 100) end
	if CLASS_COLOR[room.class] then return CLASS_COLOR[room.class] end
	return HSVToColor((room.id * GOLDEN) % 360, room.outdoor and 0.35 or 0.75, 1)
end

-- A spoke from a room's centre to a door or window, its mark, and a dim line
-- on to the room it leads to.
local function Connection(center, pos, color, angle)
	draw.NeonLine(center, pos, color)
	render.DrawWireframeBox(pos, angle, -DOOR_MARK, DOOR_MARK, color, false)
end

local function Onward(pos, leads, color)
	local other = roomById[leads]
	if other then draw.NeonLine(pos, other.center + ROOM_LIFT, draw.Dim(color)) end
end

local function Draw()
	for _, passage in ipairs(passages) do
		render.DrawWireframeBox(vector_origin, angle_zero, passage.lo, passage.hi + ROOM_HEIGHT, PASSAGE_COLOR, false)
	end
	for _, room in ipairs(rooms) do
		local color = RoomColor(room)
		render.DrawWireframeBox(vector_origin, angle_zero, room.lo, room.hi + ROOM_HEIGHT, color, false)
		local center = room.center + ROOM_LIFT
		render.DrawWireframeBox(center, angle_zero, -ROOM_MARK, ROOM_MARK, color, false)
		for _, door in ipairs(room.doors) do
			local pos = door.pos + ROOM_LIFT
			Connection(center, pos, color, angle_zero)
			Onward(pos, door.leads, color)
		end
		for _, window in ipairs(room.windows) do
			Connection(center, window.pos, WINDOW_COLOR, WINDOW_ANGLE)
			Onward(window.pos, window.leads, WINDOW_COLOR)
		end
	end
	for _, branch in ipairs(branches) do
		draw.NeonLine(branch.from + ROOM_LIFT, branch.to + ROOM_LIFT, TEAM_COLOR[branch.team] or JUNCTION_COLOR)
	end
	for _, junction in ipairs(junctions) do
		render.DrawWireframeBox(vector_origin, angle_zero, junction.lo, junction.hi + ROOM_LIFT, JUNCTION_COLOR, false)
	end
	for _, mark in ipairs(ambushes) do
		local color = TEAM_COLOR[mark.team] or JUNCTION_COLOR
		local spot = mark.spot + ROOM_LIFT
		render.DrawWireframeBox(spot, angle_zero, -SPOT_MARK, SPOT_MARK, color, false)
		draw.NeonLine(spot, mark.via + ROOM_LIFT, draw.Dim(color))
	end
end

local function Labels()
	for _, room in ipairs(rooms) do draw.Label(room.center + ROOM_LIFT + ROOM_MARK, room.label, RoomColor(room)) end
	for _, passage in ipairs(passages) do
		draw.Label((passage.lo + passage.hi) / 2 + ROOM_LIFT, passage.label, PASSAGE_COLOR)
	end
end

return { Draw = Draw, Labels = Labels }
