-- A mapper's word on the rooms the war finds (wartactics.rooms, wartactics.classes): an info_room
-- standing in a room names it (label), gives its class (one of the war's seven, CLASSES) and its
-- holder (team), and may tie its holder to a control point (point: a team_control_point's name),
-- the room then held by whoever owns the point (docs/places-plan.md §2.2, occupation's objective
-- source). What a hint leaves out is the war's to find.
--
-- Hint{ name, pos, label?, class?, team?, point? } -> a hint, or refused (an unknown class, no
-- pos); the map's empty values ("", 0) are none. Place(hints, roomAt) -> room -> hint, and the
-- trouble as lines (a second hint in a room, the first kept; a hint in no room); roomAt(pos) -> the
-- room at a point, or nil. Override(classed, placed, ownerOf) -> classes.Classify's room -> { cls,
-- team, gradient } with each hinted room's over it ({ cls, team, gradient, label, point }); a
-- point's owner from ownerOf(point) (nil: none holds it). The war's own is left as it was.
local Classes = wartactics.classes
local Sets = world.sets
local error, ipairs, pairs, tostring, format = error, ipairs, pairs, tostring, string.format
module(...)

CLASSES = Sets.Named("room classes", { Classes.RESTRICTED, Classes.STRONGHOLD, Classes.OUTPOST, Classes.HIGHWAY,
	Classes.COMMONS, Classes.UNOCCUPIED, Classes.WILDS })

local function Given(value)
	if value == nil or value == "" or value == 0 then return nil end
	return value
end

function Hint(fields)
	if not fields.pos then error("a room hint stands in a room: " .. tostring(fields.name) .. " has no pos", 2) end
	local class = Given(fields.class)
	if class and not CLASSES:Has(class) then
		error(format("room hint %s: no room class %q", tostring(fields.name), class), 2)
	end
	return { name = fields.name, pos = fields.pos, label = Given(fields.label), class = class, team = Given(fields.team),
		point = Given(fields.point) }
end

function Place(hints, roomAt)
	local placed, trouble = {}, {}
	for _, hint in ipairs(hints) do
		local room = roomAt(hint.pos)
		if not room then
			trouble[#trouble + 1] = hint.name .. ": in no room"
		elseif placed[room] then
			trouble[#trouble + 1] = format("%s: a second hint in the room of %s", hint.name, placed[room].name)
		else
			placed[room] = hint
		end
	end
	return placed, trouble
end

function Override(classed, placed, ownerOf)
	local out = {}
	for room, found in pairs(classed) do out[room] = found end
	for room, hint in pairs(placed) do
		local found = classed[room] or {}
		local team = hint.team or found.team
		if hint.point then team = ownerOf(hint.point) end
		out[room] = { cls = hint.class or found.cls, team = team, gradient = found.gradient or 1, label = hint.label,
			point = hint.point }
	end
	return out
end
