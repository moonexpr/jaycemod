-- Part of the nbdebug view (cl.lua): the AI war overlay's rooms part, the
-- map's rooms (wartactics.rooms) as last sent (game_aiwar_rooms). Each room
-- is a block in a colour of its own, by id (pale outdoors), from its floor
-- to ROOM_HEIGHT over its highest, with a mark at its centre, a spoke to
-- each door (a box on it) and window (a cyan diamond on it), and a dim line
-- on to the room each leads to; the corridors between them are grey blocks.
-- draw: the view's NeonLine, Dim and Label. Returns Draw() and Labels().
local draw = ...

local ROOM_MARK, DOOR_MARK, ROOM_LIFT = Vector(10, 10, 10), Vector(6, 6, 6), Vector(0, 0, 40)
local ROOM_HEIGHT, WINDOW_ANGLE = Vector(0, 0, 96), Angle(45, 45, 0)
local WINDOW_COLOR, PASSAGE_COLOR = Color(80, 240, 255), Color(150, 150, 150)
local GOLDEN = 137.508 -- degrees of hue between one room and the next

local rooms, roomById, passages = {}, {}, {}

WS.Events.Listen("game_aiwar_rooms", "ws_nbdebug_view", function(fields)
	rooms, roomById, passages = fields.rooms, {}, fields.passages
	for _, room in ipairs(rooms) do roomById[room.id] = room end
end)

local function RoomColor(room)
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
end

local function Labels()
	for _, room in ipairs(rooms) do draw.Label(room.center + ROOM_LIFT + ROOM_MARK, room.label, RoomColor(room)) end
	for _, passage in ipairs(passages) do
		draw.Label((passage.lo + passage.hi) / 2 + ROOM_LIFT, passage.label, PASSAGE_COLOR)
	end
end

return { Draw = Draw, Labels = Labels }
