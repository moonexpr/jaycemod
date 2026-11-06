-- The tree a soldier runs beside its main one, as L4D2's survivors run their legs: who it
-- is with, and where that puts its feet. Its root is native (engine.GroupIdentityBehavior);
-- what it does under that grows here. With no group to be part of yet, it waits.
--
-- A group's orders: Muster(point), FallBack(point, from) -> an order, whose Places(members,
-- spacing) gives each member, by its position, a place of its own. A member on orders is told
-- them by NSLegsOrder(), senses its group by NSLegsSense() each update and, on an order, heads
-- where its squad's mode says, by NSLegsHeadFor(spot) (npc_pathfollower, its feet held, only plans and shows
-- its way).
--
-- A squad's mode is one whole number on its order (SetMode, MODE): STATIONARY, its members wait
-- at their places; ALERT, each patrols spots round the squad's point on its own side; CAUTIOUS,
-- each wanders near its own place; PANIC, each makes for the way out furthest from the threat
-- (SetExits; with none known, straight away from it). A member's place is NSLegsPlace(), its
-- clock Now(), its draws NSLegsDraw() (0 to 1), and NSLegsAdmit(around) the map's word on a
-- spot near around, as Places takes it.
local Action = nextsoldier.behavior.action
local Enum = core.enum
local Geometry = math.geometry
local Select = list.select
local floor, ceil, pi, atan2 = math.floor, math.ceil, math.pi, math.atan2
local ipairs, setmetatable, error, tostring = ipairs, setmetatable, error, tostring
local remove = table.remove
module("nextsoldier.behavior.group_identity")

MODE = Enum.New("LegsMode", 0, { "STATIONARY", "ALERT", "CAUTIOUS", "PANIC" })

-- The war's own: a defender's rounds near its post, an attacker's wander in setup.
PATROL_RADIUS, PATROL_REST = 384, 6
WANDER_RADIUS, WANDER_REST = 300, 12
-- How far from the threat a panicked member runs with no way out known.
EVACUATE_DISTANCE = 768
-- How many spots a member draws before it keeps to its place.
local TRIES = 6

-- How many stand abreast falling back, the rest in rows behind them.
local ROW = 4

LegsWait = Action.Extend("LegsWait")

function LegsWait:Update() return self:Continue() end

LegsAtEase = Action.Extend("LegsAtEase")
LegsMuster = Action.Extend("LegsMuster")
LegsFallBack = Action.Extend("LegsFallBack")

local ORDER_ACTIONS = { Muster = LegsMuster, FallBack = LegsFallBack }

-- What a member told order runs.
local function ActionFor(order)
	if not order then return LegsAtEase:New() end
	return ORDER_ACTIONS[order.kind]:New({ order = order })
end

local function Orders(self, me)
	me:NSLegsSense()
	local order = me:NSLegsOrder()
	if order == self.order then return self:Continue() end
	return self:ChangeTo(ActionFor(order), order and ("Told to " .. order.kind) or "Dissolved")
end

-- A spot drawn around center, angle within half a turn of side (or any way, for none), radius
-- between least and most, its height place's; nil if the map refuses TRIES of them.
local function Drawn(me, admit, center, z, side, least, most)
	for _ = 1, TRIES do
		local angle = side and side + (me:NSLegsDraw() - 0.5) * pi or me:NSLegsDraw() * 2 * pi
		local spot = Geometry.Polar(center, least + (most - least) * me:NSLegsDraw(), angle)
		local admitted = admit({ x = spot.x, y = spot.y, z = z })
		if admitted then return admitted end
	end
	return nil
end

-- The side of point place stands on, an angle; nil on the point itself.
local function Side(point, place)
	if place.x == point.x and place.y == point.y then return nil end
	return atan2(place.y - point.y, place.x - point.x)
end

-- Where each mode sends a member at place: a spot (nil: its place) and how long it keeps to it.
local PACES = {
	[MODE.ALERT] = function(order, place, me)
		local point = order.point
		return Drawn(me, me:NSLegsAdmit(point), point, place.z, Side(point, place), PATROL_RADIUS / 2, PATROL_RADIUS),
			PATROL_REST
	end,
	[MODE.CAUTIOUS] = function(_, place, me)
		return Drawn(me, me:NSLegsAdmit(place), place, place.z, nil, 0, WANDER_RADIUS), WANDER_REST
	end,
	[MODE.PANIC] = function(order, place, me)
		local threat, admit = order.from or order.point, me:NSLegsAdmit(place)
		local exits = Select.Order(order.exits or {}, function(a, b)
			return Geometry.Distance2D(threat, a) - Geometry.Distance2D(place, a)
				> Geometry.Distance2D(threat, b) - Geometry.Distance2D(place, b)
		end)
		for _, i in ipairs(exits) do
			local spot = admit(order.exits[i])
			if spot then return spot, PATROL_REST end
		end
		for try = 0, TRIES - 1 do
			local spot = admit(Geometry.Offset2D(place, threat, EVACUATE_DISTANCE / 2 ^ try, 0))
			if spot then return spot, PATROL_REST end
		end
		return nil, PATROL_REST
	end,
}

-- Where the member goes now, by its squad's mode: its place, or a spot it keeps to a while.
local function Pace(self, me)
	local place = me:NSLegsPlace()
	if not place then return nil end
	local order, now = self.order, me:Now()
	if order.mode == MODE.STATIONARY then return place end
	if self.spot and self.spotMode == order.mode and now < self.spotUntil then return self.spot end
	local spot, rest = PACES[order.mode](order, place, me)
	self.spot, self.spotMode, self.spotUntil = spot or place, order.mode, now + rest
	return self.spot
end

-- On orders, it hears whether they have changed, and kept to them, heads where its squad's
-- mode says.
local function OnOrders(self, me)
	local result = Orders(self, me)
	if result.type ~= Action.CONTINUE then return result end
	local spot = Pace(self, me)
	if spot then me:NSLegsHeadFor(spot) end
	return result
end

LegsAtEase.Update = Orders
LegsMuster.Update = OnOrders
LegsFallBack.Update = OnOrders

-- How much further out than its members need an order looks for places the map refuses
-- nearer: rings around a muster, rows behind a fall back.
local SPARE_RINGS, SPARE_ROWS = 3, 3

-- Each member in turn, the furthest from point first, takes the nearest slot left, so a
-- straggler keeps to its own side and the crowd fills in around it. Members left when the
-- slots run out have none.
local function Assign(point, slots, members)
	local places, open = {}, {}
	for i = 1, #slots do open[i] = slots[i] end
	local order = Select.Order(members, function(a, b)
		return Geometry.DistanceSquared(a, point) > Geometry.DistanceSquared(b, point)
	end)
	for _, member in ipairs(order) do
		local slot, _, place = Select.Lowest(open, function(s) return Geometry.DistanceSquared(members[member], s) end)
		if not slot then break end
		places[member] = slot
		remove(open, place)
	end
	return places
end

local function Anywhere(slot) return slot end

local Order = {}
Order.__index = Order

-- The squad's mode, a MODE number.
function Order:SetMode(mode)
	if not MODE(mode) then error("no squad mode " .. tostring(mode), 2) end
	self.mode = mode
end

-- The ways out a panicked squad makes for (points), or nil for none known.
function Order:SetExits(exits) self.exits = exits end

-- Each member's place, by its index in members (a point each), or none where the map had no
-- room: admit(slot) -> where a body would stand for it, or nil where it cannot.
function Order:Places(members, spacing, admit)
	admit = admit or Anywhere
	local slots = {}
	for candidate in self:Candidates(#members, spacing) do
		local slot = admit(candidate)
		if slot then slots[#slots + 1] = slot end
		if #slots == #members then break end
	end
	return Assign(self.point, slots, members)
end

local Gather = setmetatable({}, Order)
Gather.__index = Gather

-- How many rings around a point hold count, each with room for as many as fit spacing apart.
local function RingsFor(count)
	local rings, held = 0, 1
	while held < count do
		rings = rings + 1
		held = held + floor(2 * pi * rings)
	end
	return rings
end

-- Its point, then whole rings around it, out to SPARE_RINGS past those count needs.
function Gather:Candidates(count, spacing)
	local point = self.point
	local ring, around, index = 0, { point }, 0
	local last = RingsFor(count) + SPARE_RINGS
	return function()
		index = index + 1
		while index > #around do
			ring, index = ring + 1, 1
			if ring > last then return nil end
			around = Geometry.Circle(point, ring * spacing, floor(2 * pi * ring), 0)
		end
		local slot = around[index]
		return { x = slot.x, y = slot.y, z = point.z }
	end
end

local Withdraw = setmetatable({}, Order)
Withdraw.__index = Withdraw

-- Rows of ROW across the way from the threat, from its point away, each centred, out to
-- SPARE_ROWS past those count needs.
function Withdraw:Candidates(count, spacing)
	local rows = ceil(count / ROW)
	local last = rows + SPARE_ROWS
	local row, column = 0, -1
	return function()
		-- the last row count needs holds what is left of count, every row after it a full one
		local abreast = row == rows - 1 and count - row * ROW or ROW
		column = column + 1
		if column >= abreast then row, column = row + 1, 0 end
		if row >= last then return nil end
		abreast = row == rows - 1 and count - row * ROW or ROW
		return Geometry.Offset2D(self.point, self.from, row * spacing, (column - (abreast - 1) / 2) * spacing)
	end
end

function Muster(point)
	return setmetatable({ kind = "Muster", point = point, mode = MODE.STATIONARY }, Gather)
end

-- Nil where point is on the threat, which leaves no way across the ground to fall.
function FallBack(point, from)
	if point.x == from.x and point.y == from.y then return nil end
	return setmetatable({ kind = "FallBack", point = point, from = from, mode = MODE.STATIONARY }, Withdraw)
end

function InitialAction(engine, first)
	return engine.GroupIdentityBehavior({ initial = first or LegsWait:New() })
end

-- Puts the tree on ent, telling its actions me. Whether it could: where the binary is not
-- bound, a soldier goes without.
function Give(ent, engine, me)
	if not (engine and engine.InsertGroup) then return false end
	engine.InsertGroup(ent, InitialAction(engine), me)
	return true
end
