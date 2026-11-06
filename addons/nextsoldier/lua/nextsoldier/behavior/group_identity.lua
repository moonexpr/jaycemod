-- The tree a soldier runs beside its main one, as L4D2's survivors run their legs: who it
-- is with, and where that puts its feet. Its root is native (engine.GroupIdentityBehavior);
-- what it does under that is nextsoldier.behavior.gib_behaviors'. With no group to be part of
-- yet, it waits.
--
-- A group's orders: Muster(point), FallBack(point, from), Assault(room) -> an order, whose
-- Places(members, spacing[, admit[, admitAt]]) gives each member, by its position, a place of its
-- own. An assault fills its room and first stages its squad around the entrance, out of the
-- room's sight (StagingOf(place)), until its leader signals it in (Staged, AllStaged, Signal). A squad's mode is one whole
-- number on its order (SetMode, MODE): STATIONARY, ALERT, CAUTIOUS, PANIC or CLOSE, each the
-- action its members run (gib_behaviors). Its leader (Lead) calls the fall back once, when its
-- casualties are heavy (Casualty, HeavyCasualties, Rout) or a danger is near (Endanger); its
-- members resting take seats apart
-- (Seat), given up as they leave it (Leave).
local Enum = core.enum
local Geometry = math.geometry
local Select = list.select
local floor, ceil, pi, min, cos, sin = math.floor, math.ceil, math.pi, math.min, math.cos, math.sin
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

-- An assault's places keep ROOM_INSET clear of the room's walls, and its stack within
-- STACK_REACH of the entrance, each place hidden from the room with STACK_COVER to spare all
-- round it: a member stops near its place, not on it.
ROOM_INSET, STACK_REACH, STACK_COVER = 48, 384, 32

-- How near another's seat a seat is that one: a body's breadth.
local SEAT_CLEARANCE = 32

-- Whether segments ab and cd cross, apart from touching or running along each other: a point
-- within ON_LINE of a line (twice the area it makes with it) is on it, as a ring's slot due west
-- of its point lies a rounding off the line through it.
local ON_LINE = 1e-6

local function Cross(a, b, c, d)
	local function Side(p, q, r)
		local side = (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
		return (side > ON_LINE and 1) or (side < -ON_LINE and -1) or 0
	end
	return Side(a, b, c) * Side(a, b, d) < 0 and Side(c, d, a) * Side(c, d, b) < 0
end

-- Swaps two members' places where their walks there cross, until none do. Uncrossed, the two
-- walks are shorter together, so it ends; walks that cross nowhere are left as they were chosen.
local function Untangle(places, members)
	local placed = {}
	for member in pairs(places) do placed[#placed + 1] = member end
	local swapped = true
	while swapped do
		swapped = false
		for i = 1, #placed do
			for j = i + 1, #placed do
				local a, b = placed[i], placed[j]
				if Cross(members[a], places[a], members[b], places[b]) then
					places[a], places[b], swapped = places[b], places[a], true
				end
			end
		end
	end
	return places
end

-- Each member in turn, the furthest from point first, takes the nearest slot left, so a
-- straggler keeps to its own side and the crowd fills in around it; then their places are
-- untangled. Members left when the slots run out have none.
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
	return Untangle(places, members)
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
	-- a group (a muster's ring, a fall back's row) at a time, whole but for the last that is
	-- wanted: of it, as many as are left to place, those nearest the members' middle, so a ring
	-- partly filled faces those coming in
	local slots, group, current = {}, {}, nil
	for candidate, of in self:Candidates(#members, spacing) do
		if of ~= current then
			if #slots + #group >= #members then break end
			for _, slot in ipairs(group) do slots[#slots + 1] = slot end
			group, current = {}, of
		end
		local slot = admit(candidate)
		if slot then group[#group + 1] = slot end
	end
	local wanted = min(#members - #slots, #group)
	if wanted > 0 then
		local middle = { x = 0, y = 0 }
		for _, member in ipairs(members) do middle.x, middle.y = middle.x + member.x / #members, middle.y + member.y / #members end
		local nearest = Select.Order(group, function(a, b)
			return Geometry.Distance2D(a, middle) < Geometry.Distance2D(b, middle)
		end)
		for i = 1, wanted do slots[#slots + 1] = group[nearest[i]] end
	end
	return Assign(self.point, slots, members)
end

-- Where the member given place waits to go in, staged (an assault's), or nil.
function Order:StagingOf(place) return self.staging and self.staging[place] end

-- member at its staging place, from now on.
function Order:Staged(member, now)
	self.stagedAt = self.stagedAt or {}
	self.stagedAt[member] = self.stagedAt[member] or now
end

-- When member was staged, or nil.
function Order:StagedAt(member) return self.stagedAt and self.stagedAt[member] end

-- Every member left alive staged.
function Order:AllStaged()
	local staged = 0
	for _ in pairs(self.stagedAt or {}) do staged = staged + 1 end
	return staged > 0 and staged >= self.size - self.lost
end

-- The signal to go in: true the once it is given.
function Order:Signal()
	if self.signalled then return false end
	self.signalled = true
	return true
end

function Order:Signalled() return self.signalled == true end

-- The member who leads the squad, and calls its fall back.
function Order:Lead(member) self.leader = member end

-- A member gone from the squad: no longer its leader, its seat free.
function Order:Leave(member)
	if self.leader == member then self.leader = nil end
	if self.stagedAt then self.stagedAt[member] = nil end
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

-- A danger near, the squad evacuates away from it: true the once it does (a rout's call counts).
function Order:Endanger(threat)
	if self.routed then return false end
	self.routed, self.from = true, threat
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

-- Its point, then whole rings around it, out to SPARE_RINGS past those count needs: each slot
-- and its ring (the point's is 0).
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
		return { x = slot.x, y = slot.y, z = point.z }, ring
	end
end

local Withdraw = setmetatable({}, Order)
Withdraw.__index = Withdraw

-- Rows of ROW across the way from the threat, from its point away, each centred, out to
-- SPARE_ROWS past those count needs: each slot and its row (the point's is 0).
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
		return Geometry.Offset2D(self.point, self.from, row * spacing, (column - (abreast - 1) / 2) * spacing), row
	end
end

local Breach = setmetatable({}, Order)
Breach.__index = Breach

-- Of slots, count spacing apart: the first the furthest from from, then each the one furthest
-- from all those chosen and from; fewer where the slots run out.
local function Farthest(slots, from, count, spacing)
	local chosen, near = {}, {}
	for i, slot in ipairs(slots) do near[i] = Geometry.Distance2D(slot, from) end
	while #chosen < count do
		local best
		for i = 1, #slots do
			if near[i] >= spacing and (not best or near[i] > near[best]) then best = i end
		end
		if not best then break end
		local pick = slots[best]
		chosen[#chosen + 1] = pick
		for i, slot in ipairs(slots) do near[i] = min(near[i], Geometry.Distance2D(slot, pick)) end
	end
	return chosen
end

-- Of slots, count spacing apart, the nearest to from first; fewer where the slots run out.
local function Nearest(slots, from, count, spacing)
	local order = Select.Order(slots, function(a, b) return Geometry.Distance2D(a, from) < Geometry.Distance2D(b, from) end)
	local chosen = {}
	for _, i in ipairs(order) do
		if #chosen == count then break end
		local slot, clear = slots[i], true
		for _, other in ipairs(chosen) do
			if Geometry.Distance2D(slot, other) < spacing then clear = false break end
		end
		if clear then chosen[#chosen + 1] = slot end
	end
	return chosen
end

-- Through one doorway: the members nearest it first, each to the deepest place left, so none
-- stops in the way of those behind. Members left when the slots run out have none.
local function Pair(entry, slots, starts)
	local Depth = function(p) return Geometry.Distance2D(p, entry) end
	local first = Select.Order(starts, function(a, b) return Depth(a) < Depth(b) end)
	local deepest = Select.Order(slots, function(a, b) return Depth(a) > Depth(b) end)
	local places = {}
	for rank, member in ipairs(first) do places[member] = slots[deepest[rank]] end
	return places
end

-- The room's floor in a lattice spacing / 2 apart, ROOM_INSET clear of its walls, that admit lets.
local function Floor(room, spacing, admit)
	local slots, step = {}, spacing / 2
	for x = room.lo.x + ROOM_INSET, room.hi.x - ROOM_INSET + 0.001, step do
		for y = room.lo.y + ROOM_INSET, room.hi.y - ROOM_INSET + 0.001, step do
			local slot = admit({ x = x, y = y, z = room.center.z })
			if slot then slots[#slots + 1] = slot end
		end
	end
	return slots
end

-- Whether the room sees p, or the ground STACK_COVER round it.
local AROUND = {}
for i = 0, 7 do AROUND[i + 1] = { cos(i * pi / 4) * STACK_COVER, sin(i * pi / 4) * STACK_COVER } end

local function InSight(room, p)
	if room.seen(p) then return true end
	for _, d in ipairs(AROUND) do
		if room.seen({ x = p.x + d[1], y = p.y + d[2], z = p.z }) then return true end
	end
	return false
end

-- The ground outside the entrance within STACK_REACH of it, in a lattice spacing / 2 apart, that
-- admit lets and the room does not see, with STACK_COVER to spare.
local function Outside(room, spacing, admit)
	local out = Geometry.Normalize2D(Geometry.Sub(room.entry, room.center))
	local side = Geometry.Left2D(out)
	local slots, step = {}, spacing / 2
	for along = step, STACK_REACH, step do
		for across = -STACK_REACH, STACK_REACH, step do
			if along * along + across * across <= STACK_REACH * STACK_REACH then
				local p = { x = room.entry.x + out.x * along + side.x * across, y = room.entry.y + out.y * along + side.y * across,
					z = room.entry.z }
				local slot = not InSight(room, p) and admit(p)
				if slot and not InSight(room, slot) then slots[#slots + 1] = slot end
			end
		end
	end
	return slots
end

-- Each member's place filling the room, its stack around the entrance first: the stack taken
-- nearest the entrance, its places matched from where the members stand; the room's places taken
-- deepest first, paired with the stack in turn through the doorway, its front deepest. admitAt(around) -> the map's
-- word on slots around a point, for the ground outside the entrance.
function Breach:Places(members, spacing, admit, admitAt)
	if not admitAt then error("an assault is placed around its entrance as well as in its room: admitAt", 2) end
	admit = admit or Anywhere
	self.size = #members
	local out = Geometry.Normalize2D(Geometry.Sub(self.entry, self.point))
	local outside = { x = self.entry.x + out.x * spacing, y = self.entry.y + out.y * spacing, z = self.entry.z }
	local stack = Assign(self.entry, Nearest(Outside(self.room, spacing, admitAt(outside)), self.entry, #members, spacing), members)
	local starts = {}
	for i, member in ipairs(members) do starts[i] = stack[i] or member end
	local places = Pair(self.entry, Farthest(Floor(self.room, spacing, admit), self.entry, #members, spacing), starts)
	self.staging = {}
	for i, place in pairs(places) do self.staging[place] = stack[i] end
	return places
end

function Muster(point)
	return NewOrder(Gather, { kind = "Muster", point = point })
end

-- Nil where point is on the threat, which leaves no way across the ground to fall.
function FallBack(point, from)
	if point.x == from.x and point.y == from.y then return nil end
	return NewOrder(Withdraw, { kind = "FallBack", point = point, from = from })
end

-- room: { center, lo, hi (its block), entry (the doorway the squad comes in by), seen(point) (whether
-- the room's inside sees a point outside, through its doorways) }; refused without seen.
function Assault(room)
	if not room.seen then error("an assault stages out of its room's sight: the room's seen", 2) end
	return NewOrder(Breach, { kind = "Assault", point = room.center, entry = room.entry, room = room })
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
