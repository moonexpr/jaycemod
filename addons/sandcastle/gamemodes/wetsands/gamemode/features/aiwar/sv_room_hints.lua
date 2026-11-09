-- Part of the AI war controller (sv.lua): the map's info_rooms (wartactics.room_hints) over the
-- rooms and classes the war finds. Each is placed in the room it stands in once the rooms are found,
-- what is wrong with one printed (a class the war has not, a second in a room, one in no room); the
-- classes read with them over the war's own, a room tied to a control point held by its owner.
local Controller = ...
local Hints = wartactics.room_hints
local Rooms = wartactics.rooms

-- The classes' names of the teams, by number.
local TEAM_NAMES = { [WS.TEAM_RED] = "RED", [WS.TEAM_BLUE] = "BLU" }

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

-- room -> its hint, for the rooms found now; nil while they are being found.
function Controller:RoomHints()
	local partition = self:Rooms()
	if not partition then return nil end
	if self.roomHintsOf == partition then return self.roomHints end
	local hints, trouble = {}, {}
	for _, ent in ipairs(ents.FindByClass("info_room")) do
		local name = ent:GetName() ~= "" and ent:GetName() or tostring(ent)
		-- the map's word, parsed here: a wrong one is the mapper's, told and left out
		local ok, hint = pcall(Hints.Hint, { name = name, pos = Point(ent:GetPos()), label = ent.label, class = ent.class,
			team = TEAM_NAMES[ent.team], point = ent.point })
		if ok then hints[#hints + 1] = hint else trouble[#trouble + 1] = tostring(hint) end
	end
	local placed, unplaced = Hints.Place(hints, function(p)
		local area = navmesh.GetNearestNavArea(Vector(p.x, p.y, p.z))
		return IsValid(area) and Rooms.RoomOf(partition, area:GetID()) or nil
	end)
	for _, line in ipairs(unplaced) do trouble[#trouble + 1] = line end
	for _, line in ipairs(trouble) do print("info_room: " .. line) end
	self.roomHints, self.roomHintsOf = placed, partition
	return placed
end

-- A control point's owner by its name, as the classes name teams; nil for none, or a map without points.
local function PointOwner(name)
	if not WS.FeatureLoaded("capture") then return nil end
	local point = ents.FindByName(name)[1]
	return IsValid(point) and TEAM_NAMES[WS.Feature("capture"):Owner(point)] or nil
end

-- Each room's class with the map's hints over the war's own: room -> { cls, team, gradient, label?,
-- point? }; nil while they are being found.
function Controller:Classed()
	local found = self:Classes()
	if not found then return nil end
	return Hints.Override(found.classed, self:RoomHints() or {}, PointOwner)
end
