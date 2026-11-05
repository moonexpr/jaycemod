-- The tree a soldier runs beside its main one, as L4D2's survivors run their legs: who it
-- is with, and where that puts its feet. Its root is native (engine.GroupIdentityBehavior);
-- what it does under that grows here. With no group to be part of yet, it waits.
--
-- A group's orders: Muster(point), FallBack(point, from) -> an order, whose Places(members,
-- spacing) gives each member, by its position, a place of its own. A member on orders is told
-- them by NSLegsOrder() and senses its group by NSLegsSense() each update (npc_squadmember).
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

LegsAtEase.Update = Orders
LegsMuster.Update = Orders
LegsFallBack.Update = Orders

-- Each member in turn, the furthest from point first, takes the nearest slot left, so a
-- straggler keeps to its own side and the crowd fills in around it.
local function Assign(point, slots, members)
	local places, open = {}, {}
	for i = 1, #slots do open[i] = slots[i] end
	local order = Select.Order(members, function(a, b)
		return Geometry.DistanceSquared(a, point) > Geometry.DistanceSquared(b, point)
	end)
	for _, member in ipairs(order) do
		local slot, _, place = Select.Lowest(open, function(s) return Geometry.DistanceSquared(members[member], s) end)
		places[member] = slot
		remove(open, place)
	end
	return places
end

local Order = {}
Order.__index = Order

function Order:Places(members, spacing)
	return Assign(self.point, self:Slots(#members, spacing), members)
end

local Gather = setmetatable({}, Order)
Gather.__index = Gather

-- Its point, then whole rings around it, each with room for as many as fit its spacing apart.
function Gather:Slots(count, spacing)
	local point = self.point
	local slots = {}
	if count > 0 then slots[1] = { x = point.x, y = point.y, z = point.z } end
	local ring = 1
	while #slots < count do
		local around = Geometry.Circle(point, ring * spacing, floor(2 * pi * ring), 0)
		for _, slot in ipairs(around) do
			if #slots < count then slots[#slots + 1] = { x = slot.x, y = slot.y, z = point.z } end
		end
		ring = ring + 1
	end
	return slots
end

local Withdraw = setmetatable({}, Order)
Withdraw.__index = Withdraw

-- Rows across the way from the threat, from its point away, each centred.
function Withdraw:Slots(count, spacing)
	local slots = {}
	for row = 0, ceil(count / ROW) - 1 do
		local abreast = row == ceil(count / ROW) - 1 and count - row * ROW or ROW
		for column = 0, abreast - 1 do
			slots[#slots + 1] = Geometry.Offset2D(self.point, self.from, row * spacing, (column - (abreast - 1) / 2) * spacing)
		end
	end
	return slots
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
