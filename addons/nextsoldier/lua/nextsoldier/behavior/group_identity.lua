-- The tree a soldier runs beside its main one, as L4D2's survivors run their legs: who it
-- is with, and where that puts its feet. Its root is native (engine.GroupIdentityBehavior);
-- what it does under that grows here. With no group to be part of yet, it waits.
--
-- A group's orders: Muster(point), FallBack(point, from) -> an order, whose Places(members,
-- spacing) gives each member, by its position, a place of its own. A member on orders is told
-- them by NSLegsOrder(), senses its group by NSLegsSense() each update and, on an order, heads
-- for its place by NSLegsHeadForPlace() (npc_squadmember only plans and shows its way).
local Action = nextsoldier.behavior.action
local Geometry = math.geometry
local Select = list.select
local floor, ceil, pi = math.floor, math.ceil, math.pi
local ipairs, setmetatable = ipairs, setmetatable
local remove = table.remove
module("nextsoldier.behavior.group_identity")

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

-- On orders, it heads for its place, then hears whether they have changed.
local function OnOrders(self, me)
	me:NSLegsHeadForPlace()
	return Orders(self, me)
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
	return setmetatable({ kind = "Muster", point = point }, Gather)
end

-- Nil where point is on the threat, which leaves no way across the ground to fall.
function FallBack(point, from)
	if point.x == from.x and point.y == from.y then return nil end
	return setmetatable({ kind = "FallBack", point = point, from = from }, Withdraw)
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
