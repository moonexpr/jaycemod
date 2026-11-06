-- The tree a soldier runs beside its main one, as L4D2's survivors run their legs: who it
-- is with, and where that puts its feet. Its root is native (engine.GroupIdentityBehavior);
-- what it does under that is nextsoldier.behavior.gib_behaviors'. With no group to be part of
-- yet, it waits.
--
-- A group's orders: Muster(point), FallBack(point, from) -> an order, whose Places(members,
-- spacing) gives each member, by its position, a place of its own. A squad's mode is one whole
-- number on its order (SetMode, MODE): STATIONARY, ALERT, CAUTIOUS, PANIC or CLOSE, each the
-- action its members run (gib_behaviors). Its leader (Lead) calls the fall back once its
-- casualties are heavy (Casualty, HeavyCasualties, Rout); its members resting take seats apart
-- (Seat), given up as they leave it (Leave).
local Enum = core.enum
local Geometry = math.geometry
local Select = list.select
local floor, ceil, pi = math.floor, math.ceil, math.pi
local ipairs, pairs, setmetatable, error, tostring = ipairs, pairs, setmetatable, error, tostring
local remove = table.remove
local nextsoldier = nextsoldier
module("nextsoldier.behavior.group_identity")

MODE = Enum.New("LegsMode", 0, { "STATIONARY", "ALERT", "CAUTIOUS", "PANIC", "CLOSE" })

-- The share of a full squad lost that is heavy casualties: its leader calls the fall back.
CASUALTY_SHARE = 0.5

-- How many stand abreast falling back, the rest in rows behind them.
local ROW = 4

-- How much further out than its members need an order looks for places the map refuses
-- nearer: rings around a muster, rows behind a fall back.
local SPARE_RINGS, SPARE_ROWS = 3, 3

-- How near another's seat a seat is that one: a body's breadth.
local SEAT_CLEARANCE = 32

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

local function NewOrder(class, fields)
	fields.mode, fields.size, fields.lost, fields.seats = MODE.STATIONARY, 0, 0, {}
	return setmetatable(fields, class)
end

-- The squad's mode, a MODE number.
function Order:SetMode(mode)
	if not MODE(mode) then error("no squad mode " .. tostring(mode), 2) end
	self.mode = mode
end

-- The ways out a panicked squad makes for (points), or nil for none known.
function Order:SetExits(exits) self.exits = exits end

-- Each member's place, by its index in members (a point each), or none where the map had no
-- room: admit(slot) -> where a body would stand for it, or nil where it cannot. The squad is as
-- many as it places.
function Order:Places(members, spacing, admit)
	admit = admit or Anywhere
	self.size = #members
	local slots = {}
	for candidate in self:Candidates(#members, spacing) do
		local slot = admit(candidate)
		if slot then slots[#slots + 1] = slot end
		if #slots == #members then break end
	end
	return Assign(self.point, slots, members)
end

-- The member who leads the squad, and calls its fall back.
function Order:Lead(member) self.leader = member end

-- A member gone from the squad: no longer its leader, its seat free.
function Order:Leave(member)
	if self.leader == member then self.leader = nil end
	self.seats[member] = nil
end

-- A member killed: a casualty, and gone.
function Order:Casualty(member)
	self.lost = self.lost + 1
	self:Leave(member)
end

-- A full squad (a leader and others to lead) that has lost its share of those it placed.
function Order:HeavyCasualties()
	return self.leader ~= nil and self.size > 1 and self.lost >= self.size * CASUALTY_SHARE
end

-- Its casualties heavy, the squad evacuates: true the once it does.
function Order:Rout()
	if self.routed or not self:HeavyCasualties() then return false end
	self.routed = true
	self:SetMode(MODE.PANIC)
	return true
end

-- Of seats (points), the nearest to near that no other member holds, now member's; nil when
-- every one is held.
function Order:Seat(member, seats, near)
	local held = self.seats
	held[member] = nil
	local seat = Select.Nearest(seats, near, nil, function(spot)
		for _, other in pairs(held) do
			if Geometry.Distance2D(spot, other) < SEAT_CLEARANCE then return false end
		end
		return true
	end)
	held[member] = seat
	return seat
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
	return NewOrder(Gather, { kind = "Muster", point = point })
end

-- Nil where point is on the threat, which leaves no way across the ground to fall.
function FallBack(point, from)
	if point.x == from.x and point.y == from.y then return nil end
	return NewOrder(Withdraw, { kind = "FallBack", point = point, from = from })
end

-- Its root, holding first (gib_behaviors' LegsWait, for none).
function InitialAction(engine, first)
	return engine.GroupIdentityBehavior({ initial = first or nextsoldier.behavior.gib_behaviors.LegsWait:New() })
end

-- Puts the tree on ent, telling its actions me. Whether it could: where the binary is not
-- bound, a soldier goes without.
function Give(ent, engine, me)
	if not (engine and engine.InsertGroup) then return false end
	engine.InsertGroup(ent, InitialAction(engine), me)
	return true
end
