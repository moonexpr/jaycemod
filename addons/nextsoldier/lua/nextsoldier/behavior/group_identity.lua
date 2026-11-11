-- The tree a soldier runs beside its main one, as L4D2's survivors run their legs: who it
-- is with, and where that puts its feet. Its root is native (engine.TacticalLeggings);
-- what it does under that is nextsoldier.behavior.gib_behaviors'. With no group to be part of
-- yet, it waits.
--
-- A group's orders: Muster(point), FallBack(point, from), Assault(room) -> an order, whose
-- Places(members, spacing[, admit[, admitAt]]) gives each member, by its position, a place of its
-- own. An assault fills its room and first stages its squad around the entrance, out of the
-- room's sight (StagingOf(place)), until its leader signals it in (Staged, AllStaged, Signal);
-- going in, each takes an assault point (BreachOf(place)) until the room is clear (Breached,
-- AllBreached, Contact, QuietSince, CallClear). A squad's mode is one whole
-- number on its order (SetMode, MODE): STATIONARY, ALERT, CAUTIOUS, PANIC or CLOSE, each the
-- action its members run (gib_behaviors). Its leader (Lead) calls the fall back once, when its
-- casualties are heavy (Casualty, HeavyCasualties, Rout) or a danger is near (Endanger); its
-- members resting take seats apart
-- (Seat), given up as they leave it (Leave).
local Enum = core.enum
local Geometry = math.geometry
local Select = list.select
local floor, ceil, pi, min, max, cos, sin, atan2, abs = math.floor, math.ceil, math.pi, math.min, math.max, math.cos,
math.sin, math.atan2, math.abs
local huge = math.huge
local ipairs, pairs, setmetatable, error, tostring = ipairs, pairs, setmetatable, error, tostring
local remove, sort = table.remove, table.sort
local nextsoldier = nextsoldier
module ("nextsoldier.behavior.group_identity")

MODE = Enum.New ("LegsMode", 0, { "STATIONARY", "ALERT", "CAUTIOUS", "PANIC", "CLOSE" })

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
-- Going in, its assault points lie within BREACH_REACH of the entrance, BREACH_FUNNEL or more
-- to either side of the line in through the doorway, where those behind come.
BREACH_REACH, BREACH_FUNNEL = 288, 96
-- With an enemy known in the room, its assault points ring it ENCIRCLE_RADIUS off, give or take
-- ENCIRCLE_BAND: a room's breadth to fight across, not on top of it; drawn in by ENCIRCLE_STEP
-- down to ENCIRCLE_MIN where the walls leave too little of the ring to surround it.
ENCIRCLE_RADIUS, ENCIRCLE_BAND, ENCIRCLE_MIN, ENCIRCLE_STEP = 192, 48, 96, 24
-- A room with more than one entrance is taken from those off the squad's flow, while one member,
-- its decoy, shows itself SHOW_OUT outside the front, in the doorway's line.
SHOW_OUT = 64
-- How near another's seat a seat is that one: a body's breadth.
local SEAT_CLEARANCE = 32

-- Whether segments ab and cd cross, apart from touching or running along each other: a point
-- within ON_LINE of a line (twice the area it makes with it) is on it, as a ring's slot due west
-- of its point lies a rounding off the line through it.
local ON_LINE = 1e-6

local function Cross (a, b, c, d)
	local function Side (p, q, r)
		local side = (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
		return (side > ON_LINE and 1) or (side < -ON_LINE and -1) or 0
	end
	return Side (a, b, c) * Side (a, b, d) < 0 and Side (c, d, a) * Side (c, d, b) < 0
end

-- Swaps two members' places where their walks there cross, until none do. Uncrossed, the two
-- walks are shorter together, so it ends; walks that cross nowhere are left as they were chosen.
local function Untangle (places, members)
	local placed = {}
	for member in pairs (places) do placed [#placed + 1] = member end
	local swapped = true
	while swapped do
		swapped = false
		for i = 1, #placed do
			for j = i + 1, #placed do
				local a, b = placed [i], placed [j]
				if Cross (members [a], places [a], members [b], places [b]) then
					places [a], places [b], swapped = places [b], places [a], true
				end
			end
		end
	end
	return places
end

-- Each member in turn, the furthest from point first, takes the nearest slot left, so a
-- straggler keeps to its own side and the crowd fills in around it; then their places are
-- untangled. Members left when the slots run out have none.
local function Assign (point, slots, members)
	local places, open = {}, {}
	for i = 1, #slots do open [i] = slots [i] end
	local order = Select.Order (members, function (a, b)
		return Geometry.DistanceSquared (a, point) > Geometry.DistanceSquared (b, point)
	end)
	for _, member in ipairs (order) do
		local slot, _, place = Select.Lowest (open, function (s) return Geometry.DistanceSquared (members [member], s) end)
		if not slot then break end
		places [member] = slot
		remove (open, place)
	end
	return Untangle (places, members)
end

local function Anywhere (slot) return slot end

local Order = {}
Order.__index = Order

local function NewOrder (class, fields)
	fields.mode, fields.size, fields.lost, fields.seats = MODE.STATIONARY, 0, 0, {}
	return setmetatable (fields, class)
end

-- The squad's mode, a MODE number.
function Order:SetMode (mode)
	if not MODE (mode) then error ("no squad mode " .. tostring (mode), 2) end
	self.mode = mode
end

-- The ways out a panicked squad makes for (points), or nil for none known.
function Order:SetExits (exits) self.exits = exits end

-- The room the squad is in: { center, seen(point) (what it sees), exits (its ways out) }. Its ways
-- out are the order's, and a member evacuating it hides out of its sight (Hideout).
function Order:SetRoom (room)
	self.room = room
	self.exits = room.exits
end

-- Each member's place, by its index in members (a point each), or none where the map had no
-- room: admit(slot) -> where a body would stand for it, or nil where it cannot. The squad is as
-- many as it places.
function Order:Places (members, spacing, admit)
	admit = admit or Anywhere
	self.size = #members
	-- a group (a muster's ring, a fall back's row) at a time, whole but for the last that is
	-- wanted: of it, as many as are left to place, those nearest the members' middle, so a ring
	-- partly filled faces those coming in
	local slots, group, current = {}, {}, nil
	for candidate, of in self:Candidates (#members, spacing) do
		if of ~= current then
			if #slots + #group >= #members then break end
			for _, slot in ipairs (group) do slots [#slots + 1] = slot end
			group, current = {}, of
		end
		local slot = admit (candidate)
		if slot then group [#group + 1] = slot end
	end
	local wanted = min (#members - #slots, #group)
	if wanted > 0 then
		local middle = { x = 0, y = 0 }
		for _, member in ipairs (members) do middle.x, middle.y = middle.x + member.x / #members, middle.y + member.y / #members end
		local nearest = Select.Order (group, function (a, b)
			return Geometry.Distance2D (a, middle) < Geometry.Distance2D (b, middle)
		end)
		for i = 1, wanted do slots [#slots + 1] = group [nearest [i]] end
	end
	return Assign (self.point, slots, members)
end

-- Where the member given place waits to go in, staged (an assault's), or nil.
function Order:StagingOf (place) return self.staging and self.staging [place] end

-- member at its staging place, from now on.
function Order:Staged (member, now)
	self.stagedAt = self.stagedAt or {}
	self.stagedAt [member] = self.stagedAt [member] or now
end

-- When member was staged, or nil.
function Order:StagedAt (member) return self.stagedAt and self.stagedAt [member] end

-- Every member left alive staged.
function Order:AllStaged ()
	local staged = 0
	for _ in pairs (self.stagedAt or {}) do staged = staged + 1 end
	return staged > 0 and staged >= self.size - self.lost
end

-- The signal to go in: true the once it is given.
function Order:Signal ()
	if self.signalled then return false end
	self.signalled = true
	return true
end

function Order:Signalled () return self.signalled == true end

-- The assault point the member given place takes going in (an assault's), or nil.
function Order:BreachOf (place) return self.breach and self.breach [place] end

-- The decoy's part, for the member given place: { show (where it shows itself, outside the front,
-- in the room's sight), hide (where it hides beside the front) }; nil for any other member.
function Order:DecoyOf (place) return self.decoys and self.decoys [place] end

-- member is the squad's decoy: falling, it has drawn the enemy.
function Order:Decoy (member) self.decoy = member end

-- The enemy drawn by the decoy (its contact, or its showing long enough), so the rest may go in.
function Order:Engage () self.engaged = true end

function Order:Engaged () return self.engaged == true end

-- member holding its assault point, from now on.
function Order:Breached (member, now)
	self.breachedAt = self.breachedAt or {}
	if self.breachedAt [member] then return end
	self.breachedAt [member] = now
	self.quiet = max (self.quiet or now, now)
end

-- Every member left alive holding its assault point.
function Order:AllBreached ()
	local held = 0
	for _ in pairs (self.breachedAt or {}) do held = held + 1 end
	return held > 0 and held >= self.size - self.lost
end

-- A member met the enemy now.
function Order:Contact (now) self.quiet = max (self.quiet or now, now) end

-- Since when nothing has happened going in: the last member taking its point, or the last contact.
function Order:QuietSince () return self.quiet end

-- The room called clear: true the once it is.
function Order:CallClear ()
	if self.cleared then return false end
	self.cleared = true
	return true
end

-- The member who leads the squad, and calls its fall back.
function Order:Lead (member) self.leader = member end

-- A member gone from the squad: no longer its leader, its seat free.
function Order:Leave (member)
	if self.leader == member then self.leader = nil end
	if self.decoy ~= nil and self.decoy == member then self.engaged = true end
	if self.stagedAt then self.stagedAt [member] = nil end
	if self.breachedAt then self.breachedAt [member] = nil end
	self.seats [member] = nil
end

-- A member killed: a casualty, and gone.
function Order:Casualty (member)
	self.lost = self.lost + 1
	self:Leave (member)
end

-- A full squad (a leader and others to lead) that has lost its share of those it placed.
function Order:HeavyCasualties ()
	return self.leader ~= nil and self.size > 1 and self.lost >= self.size * CASUALTY_SHARE
end

-- Its casualties heavy, the squad evacuates: true the once it does.
function Order:Rout ()
	if self.routed or not self:HeavyCasualties () then return false end
	self.routed = true
	self:SetMode (MODE.PANIC)
	return true
end

-- A danger near, the squad evacuates away from it: true the once it does (a rout's call counts).
function Order:Endanger (threat)
	if self.routed then return false end
	self.routed, self.from = true, threat
	self:SetMode (MODE.PANIC)
	return true
end

-- Of seats (points), the nearest to near that no other member holds, now member's; nil when
-- every one is held.
function Order:Seat (member, seats, near)
	local held = self.seats
	held [member] = nil
	local seat = Select.Nearest (seats, near, nil, function (spot)
		for _, other in pairs (held) do
			if Geometry.Distance2D (spot, other) < SEAT_CLEARANCE then return false end
		end
		return true
	end)
	held [member] = seat
	return seat
end

local Gather = setmetatable ({}, Order)
Gather.__index = Gather

-- How many rings around a point hold count, each with room for as many as fit spacing apart.
local function RingsFor (count)
	local rings, held = 0, 1
	while held < count do
		rings = rings + 1
		held = held + floor (2 * pi * rings)
	end
	return rings
end

-- Its point, then whole rings around it, out to SPARE_RINGS past those count needs: each slot
-- and its ring (the point's is 0).
function Gather:Candidates (count, spacing)
	local point = self.point
	local ring, around, index = 0, { point }, 0
	local last = RingsFor (count) + SPARE_RINGS
	return function ()
		index = index + 1
		while index > #around do
			ring, index = ring + 1, 1
			if ring > last then return nil end
			around = Geometry.Circle (point, ring * spacing, floor (2 * pi * ring), 0)
		end
		local slot = around [index]
		return { x = slot.x, y = slot.y, z = point.z }, ring
	end
end

local Withdraw = setmetatable ({}, Order)
Withdraw.__index = Withdraw

-- Rows of ROW across the way from the threat, from its point away, each centred, out to
-- SPARE_ROWS past those count needs: each slot and its row (the point's is 0).
function Withdraw:Candidates (count, spacing)
	local rows = ceil (count / ROW)
	local last = rows + SPARE_ROWS
	local row, column = 0, -1
	return function ()
		-- the last row count needs holds what is left of count, every row after it a full one
		local abreast = row == rows - 1 and count - row * ROW or ROW
		column = column + 1
		if column >= abreast then row, column = row + 1, 0 end
		if row >= last then return nil end
		abreast = row == rows - 1 and count - row * ROW or ROW
		return Geometry.Offset2D (self.point, self.from, row * spacing, (column - (abreast - 1) / 2) * spacing), row
	end
end

local Breach = setmetatable ({}, Order)
Breach.__index = Breach

-- Of slots, count spacing apart: the first the furthest from from, then each the one furthest
-- from all those chosen and from; fewer where the slots run out.
local function Farthest (slots, from, count, spacing)
	local chosen, near = {}, {}
	for i, slot in ipairs (slots) do near [i] = Geometry.Distance2D (slot, from) end
	while #chosen < count do
		local best
		for i = 1, #slots do
			if near [i] >= spacing and (not best or near [i] > near [best]) then best = i end
		end
		if not best then break end
		local pick = slots [best]
		chosen [#chosen + 1] = pick
		for i, slot in ipairs (slots) do near [i] = min (near [i], Geometry.Distance2D (slot, pick)) end
	end
	return chosen
end

-- Of slots, count spacing apart, the nearest to from first; fewer where the slots run out.
local function Nearest (slots, from, count, spacing)
	local order = Select.Order (slots, function (a, b) return Geometry.Distance2D (a, from) < Geometry.Distance2D (b, from) end)
	local chosen = {}
	for _, i in ipairs (order) do
		if #chosen == count then break end
		local slot, clear = slots [i], true
		for _, other in ipairs (chosen) do
			if Geometry.Distance2D (slot, other) < spacing then clear = false break end
		end
		if clear then chosen [#chosen + 1] = slot end
	end
	return chosen
end

-- Through one doorway: the members nearest it first, each to the deepest place left, so none
-- stops in the way of those behind. Members left when the slots run out have none.
local function Pair (entry, slots, starts)
	local Depth = function (p) return Geometry.Distance2D (p, entry) end
	local first = Select.Order (starts, function (a, b) return Depth (a) < Depth (b) end)
	local deepest = Select.Order (slots, function (a, b) return Depth (a) > Depth (b) end)
	local places = {}
	for rank, member in ipairs (first) do places [member] = slots [deepest [rank]] end
	return places
end

-- The room's floor in a lattice spacing / 2 apart, ROOM_INSET clear of its walls, that admit lets.
local function Floor (room, spacing, admit)
	local slots, step = {}, spacing / 2
	for x = room.lo.x + ROOM_INSET, room.hi.x - ROOM_INSET + 0.001, step do
		for y = room.lo.y + ROOM_INSET, room.hi.y - ROOM_INSET + 0.001, step do
			local slot = admit ({ x = x, y = y, z = room.center.z })
			if slot then slots [#slots + 1] = slot end
		end
	end
	return slots
end

-- Whether the room sees p, or the ground STACK_COVER round it.
local AROUND = {}
for i = 0, 7 do AROUND [i + 1] = { cos (i * pi / 4) * STACK_COVER, sin (i * pi / 4) * STACK_COVER } end

local function InSight (room, p)
	if room.seen (p) then return true end
	for _, d in ipairs (AROUND) do
		if room.seen ({ x = p.x + d [1], y = p.y + d [2], z = p.z }) then return true end
	end
	return false
end

-- The ground outside the entrance within STACK_REACH of it, in a lattice spacing / 2 apart, that
-- admit lets and the room does not see, with STACK_COVER to spare.
local function Outside (room, spacing, admit)
	local out = Geometry.Normalize2D (Geometry.Sub (room.entry, room.center))
	local side = Geometry.Left2D (out)
	local slots, step = {}, spacing / 2
	for along = step, STACK_REACH, step do
		for across = -STACK_REACH, STACK_REACH, step do
			if along * along + across * across <= STACK_REACH * STACK_REACH then
				local p = { x = room.entry.x + out.x * along + side.x * across, y = room.entry.y + out.y * along + side.y * across,
					z = room.entry.z }
				local slot = not InSight (room, p) and admit (p)
				if slot and not InSight (room, slot) then slots [#slots + 1] = slot end
			end
		end
	end
	return slots
end

-- The assault points going in, for the members ranked by turn through the doorway (each a
-- start): of the floor within BREACH_REACH of the entrance and off the line in through it, the
-- first the best the room scores, each next the best on the other side of the line from the one
-- before (the best anywhere where that side has none left), spacing apart.
local function BreachPoints (room, floor, turn, starts, spacing)
	local into = Geometry.Normalize2D (Geometry.Sub (room.center, room.entry))
	local left = Geometry.Left2D (into)
	local candidates = {}
	for _, p in ipairs (floor) do
		local d = Geometry.Sub (p, room.entry)
		local across = d.x * left.x + d.y * left.y
		if Geometry.Distance2D (p, room.entry) <= BREACH_REACH and (across >= BREACH_FUNNEL or across <= -BREACH_FUNNEL) then
			candidates [#candidates + 1] = { point = p, side = across > 0 and 1 or -1, score = room.score (p) }
		end
	end
	local points, chosen, side = {}, {}, nil
	for _, member in ipairs (turn) do
		local best
		-- the other side first, then either (0)
		for _, wanted in ipairs (side and { -side, 0 } or { 0 }) do
			for _, c in ipairs (candidates) do
				local clear = (wanted == 0 or c.side == wanted) and (not best or c.score > best.score)
				for _, other in ipairs (chosen) do
					if clear and Geometry.Distance2D (c.point, other) < spacing then clear = false end
				end
				if clear then best = c end
			end
			if best then break end
		end
		if not best then break end
		points [member], side = best.point, best.side
		chosen [#chosen + 1] = best.point
	end
	return points
end

-- Where member hides, having evacuated the room by exit: the ground past it, out of the room's
-- sight with STACK_COVER to spare, nearest the way out and apart from where the others hide;
-- kept once found. Nil with no room told, or none such. admitAt(around) -> the map's word on
-- ground around a point.
function Order:Hideout (member, exit, apart, admitAt)
	local room = self.room
	if not (room and room.seen) then return nil end
	self.hideouts = self.hideouts or {}
	if self.hideouts [member] then return self.hideouts [member] end
	local out = Geometry.Normalize2D (Geometry.Sub (exit, room.center))
	local outside = { x = exit.x + out.x * apart, y = exit.y + out.y * apart, z = exit.z }
	local ground = Outside ({ entry = exit, center = room.center, seen = room.seen }, apart, admitAt (outside))
	local nearest = Select.Order (ground, function (a, b) return Geometry.Distance2D (a, exit) < Geometry.Distance2D (b, exit) end)
	for _, i in ipairs (nearest) do
		local spot, clear = ground [i], true
		for other, taken in pairs (self.hideouts) do
			if other ~= member and Geometry.Distance2D (spot, taken) < apart then clear = false break end
		end
		if clear then
			self.hideouts [member] = spot
			return spot
		end
	end
	return nil
end

-- How far apart two angles are, the short way round.
local function AngleApart (a, b)
	local d = abs (a - b) % (2 * pi)
	return d > pi and 2 * pi - d or d
end

-- The floor on a ring radius round enemy, ENCIRCLE_BAND either side, each with its angle round it.
local function Ring (floor, enemy, radius)
	local ring = {}
	for _, p in ipairs (floor) do
		local off = abs (Geometry.Distance2D (p, enemy) - radius)
		if off <= ENCIRCLE_BAND then ring [#ring + 1] = { point = p, angle = atan2 (p.y - enemy.y, p.x - enemy.x), off = off } end
	end
	sort (ring, function (a, b) return a.angle < b.angle end)
	return ring
end

-- The arc of the ring the floor covers: where it starts (the angle after the widest stretch with
-- no floor), how far round it goes, and that widest stretch.
local function Arc (ring)
	local gap, after = ring [1].angle + 2 * pi - ring [#ring].angle, 1
	for i = 2, #ring do
		if ring [i].angle - ring [i - 1].angle > gap then gap, after = ring [i].angle - ring [i - 1].angle, i end
	end
	return ring [after].angle, 2 * pi - gap, gap
end

-- With an enemy in the room, count assault points round it, spacing apart, surrounding it as the
-- walls allow: on a ring ENCIRCLE_RADIUS off, drawn in while the walls leave half of it or more
-- with no floor; the points spread evenly over the arc the floor covers, both its ends taken, or,
-- on a whole ring, evenly round from its far side from the entrance.
local function EncirclePoints (room, floor, count, spacing)
	local enemy = room.enemy
	local ring
	for radius = ENCIRCLE_RADIUS, ENCIRCLE_MIN, -ENCIRCLE_STEP do
		local candidates = Ring (floor, enemy, radius)
		if candidates [1] then
			ring = candidates
			local _, _, gap = Arc (candidates)
			if gap < pi then break end
		end
	end
	if not ring then return {} end
	local first, span, gap = Arc (ring)
	local targets = {}
	if gap <= 2 * pi / count then
		local far = atan2 (enemy.y - room.entry.y, enemy.x - room.entry.x)
		for k = 0, count - 1 do targets [k + 1] = far + 2 * pi * k / count end
	else
		for k = 0, count - 1 do targets [k + 1] = first + (count > 1 and span * k / (count - 1) or span / 2) end
	end
	local points = {}
	for _, target in ipairs (targets) do
		local best, bestApart
		for _, c in ipairs (ring) do
			local clear = true
			for _, other in ipairs (points) do
				if Geometry.Distance2D (c.point, other) < spacing then clear = false break end
			end
			local apart = AngleApart (c.angle, target)
			if clear and (not best or apart < bestApart or (apart == bestApart and c.off < best.off)) then best, bestApart = c, apart end
		end
		if best then points [#points + 1] = best.point end
	end
	return points
end

-- Each member's place filling the room, its stack around the entrance first: the stack taken
-- nearest the entrance, its places matched from where the members stand; the room's places taken
-- deepest first, paired with the stack in turn through the doorway, its front deepest. admitAt(around) -> the map's
-- word on slots around a point, for the ground outside the entrance.
-- The front, the entrance the most of the squad's flow comes in by (the nearest the squad's
-- approach, room.entry, where the flow ties), and the others the rest stage at: those the enemy's
-- flow does not come in by (enemyFlow), where it would meet them on its way in, unless it comes in
-- by all of them; nil for a room with one entrance.
local function Fronts (room)
	local entrances = room.entrances
	if not entrances or #entrances < 2 then return nil end
	local front
	for _, e in ipairs (entrances) do
		local flow, best = e.flow or 0, front and (front.flow or 0)
		if not front or flow > best
			or (flow == best and Geometry.Distance2D (e.pos, room.entry) < Geometry.Distance2D (front.pos, room.entry)) then
			front = e
		end
	end
	local others, theirs = {}, {}
	for _, e in ipairs (entrances) do
		if e ~= front then
			local into = (e.enemyFlow or 0) > 0 and theirs or others
			into [#into + 1] = e.pos
		end
	end
	return front.pos, #others > 0 and others or theirs
end

-- The way out of the room through entrance.
local function OutOf (room, entrance) return Geometry.Normalize2D (Geometry.Sub (entrance, room.center)) end

-- count places to stage at around entrance: the ground outside it the room does not see, nearest it.
local function StackAt (room, entrance, count, spacing, admitAt)
	local out = OutOf (room, entrance)
	local outside = { x = entrance.x + out.x * spacing, y = entrance.y + out.y * spacing, z = entrance.z }
	return Nearest (Outside ({ entry = entrance, center = room.center, seen = room.seen }, spacing, admitAt (outside)),
		entrance, count, spacing)
end

-- The members (indices of starts) split over entrances: each entrance first takes the nearest
-- left (the farthest from them choosing first), so none is empty while members last; the rest
-- each the nearest entrance with room for its share. -> member -> entrance index.
local function Split (starts, members, entrances)
	local share = ceil (#members / #entrances)
	local of, count, left = {}, {}, {}
	for _, m in ipairs (members) do left [m] = true end
	local middle = { x = 0, y = 0 }
	for _, m in ipairs (members) do middle.x, middle.y = middle.x + starts [m].x / #members, middle.y + starts [m].y / #members end
	local far = Select.Order (entrances, function (a, b) return Geometry.Distance2D (a, middle) > Geometry.Distance2D (b, middle) end)
	for _, e in ipairs (far) do
		local nearest
		for _, m in ipairs (members) do
			if left [m] and (not nearest or Geometry.Distance2D (starts [m], entrances [e]) < Geometry.Distance2D (starts [nearest], entrances [e])) then
				nearest = m
			end
		end
		if nearest then of [nearest], count [e], left [nearest] = e, 1, nil end
	end
	for _, m in ipairs (members) do
		if left [m] then
			local best
			for e = 1, #entrances do
				if (count [e] or 0) < share and (not best or Geometry.Distance2D (starts [m], entrances [e]) < Geometry.Distance2D (starts [m], entrances [best])) then
					best = e
				end
			end
			of [m], count [best] = best, (count [best] or 0) + 1
		end
	end
	return of
end

-- Through its one entrance (or a squad of one): the stack nearest it, the room's places taken
-- deepest first, the assault points encircling a known enemy or else the best by the entrance.
function Breach:ThroughOne (members, spacing, floor, admitAt)
	local stack = Assign (self.entry, StackAt (self.room, self.entry, #members, spacing, admitAt), members)
	local starts = {}
	for i, member in ipairs (members) do starts [i] = stack [i] or member end
	local places = Pair (self.entry, Farthest (floor, self.entry, #members, spacing), starts)
	local turn = Select.Order (starts, function (a, b)
		return Geometry.Distance2D (a, self.entry) < Geometry.Distance2D (b, self.entry)
	end)
	local points = self.room.enemy and Pair (self.entry, EncirclePoints (self.room, floor, #members, spacing), starts)
		or BreachPoints (self.room, floor, turn, starts, spacing)
	for i, place in pairs (places) do self.staging [place], self.breach [place] = stack [i], points [i] end
	return places
end

-- Where p lies round the room's middle, an angle; and how far angle a lies on from b, the short
-- way round (-pi to pi).
local function Bearing (room, p) return atan2 (p.y - room.center.y, p.x - room.center.x) end

local function Turn (a, b)
	local d = (a - b) % (2 * pi)
	return d > pi and d - 2 * pi or d
end

-- Stealth on the way to its stack: the entrances a member passes walking round the room from start
-- to goal the short way, leaving out those in skip (entrance -> true), and beside each, of the
-- ground the room does not see there (beside(entrance)), the spot nearest it on its near side,
-- where the member stops (pause), then the one on its far side, crossing the doorway's sight to it
-- (cross). A spot is spacing clear of every stack (stacks), and of the hops already given (taken,
-- which each it picks joins) where the ground leaves one, else shares the nearest.
-- -> hops in the order walked.
local function Clear (p, others, spacing)
	for _, other in ipairs (others) do
		if Geometry.Distance2D (p, other) < spacing then return false end
	end
	return true
end

local function Hops (room, start, goal, skip, beside, stacks, taken, spacing)
	local from = Bearing (room, start)
	local span = Turn (Bearing (room, goal), from)
	local way = span >= 0 and 1 or -1
	local passed = {}
	for _, e in ipairs (room.entrances) do
		local along = Turn (Bearing (room, e.pos), from) * way
		if not skip [e.pos] and along > 0 and along < abs (span) then passed [#passed + 1] = { along = along, pos = e.pos } end
	end
	sort (passed, function (a, b) return a.along < b.along end)
	local hops = {}
	for _, p in ipairs (passed) do
		local door = Bearing (room, p.pos)
		-- the nearest on each side, of those clear of the stacks and the hops given, else of the stacks
		local near, far
		for _, avoid in ipairs ({ taken, {} }) do
			for _, slot in ipairs (beside (p.pos)) do
				local side, d = Turn (Bearing (room, slot), door) * way, Geometry.Distance2D (slot, p.pos)
				if Clear (slot, stacks, spacing) and Clear (slot, avoid, spacing) then
					if not near and side < 0 or near and side < 0 and d < Geometry.Distance2D (near, p.pos) then near = slot end
					if not far and side > 0 or far and side > 0 and d < Geometry.Distance2D (far, p.pos) then far = slot end
				end
			end
			if near and far then break end
			near, far = nil, nil
		end
		if near and far then
			hops [#hops + 1] = { point = near, pause = true }
			hops [#hops + 1] = { point = far, cross = true }
			taken [#taken + 1], taken [#taken + 2] = near, far
		end
	end
	return hops
end

-- The hops the member given place takes to its stack (an assault's): { point, pause or cross }s,
-- none where it passes no entrance.
function Order:HopsOf (place) return self.hops and self.hops [place] or {} end

-- Each member's place filling the room, and first its part going in. Through one entrance, as
-- ThroughOne. With more: the member nearest the front is the decoy, hiding beside it and showing
-- itself outside it; the rest split over the others, each staged around its own out of the
-- room's sight, their assault points encircling a known enemy, else the best by each entrance.
-- admitAt(around) -> the map's word on slots around a point, for the ground outside.
function Breach:Places (members, spacing, admit, admitAt)
	if not admitAt then error ("an assault is placed around its entrance as well as in its room: admitAt", 2) end
	admit = admit or Anywhere
	self.size = #members
	self.staging, self.breach, self.decoys = {}, {}, {}
	local floor = Floor (self.room, spacing, admit)
	local front, others = Fronts (self.room)
	if not front or #members < 2 then return self:ThroughOne (members, spacing, floor, admitAt) end
	local decoy = Select.Lowest (members, function (m) return Geometry.Distance2D (m, front) end)
	local rest = {}
	for i, member in ipairs (members) do
		if member == decoy then decoy = i else rest [#rest + 1] = i end
	end
	local of = Split (members, rest, others)
	local starts, stack = {}, {}
	for e, entrance in ipairs (others) do
		local group, positions = {}, {}
		for _, m in ipairs (rest) do
			if of [m] == e then group [#group + 1], positions [#positions + 1] = m, members [m] end
		end
		for k, slot in pairs (Assign (entrance, StackAt (self.room, entrance, #group, spacing, admitAt), positions)) do
			stack [group [k]] = slot
		end
	end
	for _, m in ipairs (rest) do starts [m] = stack [m] or members [m] end
	local hide = StackAt (self.room, front, 1, spacing, admitAt) [1]
	local out = OutOf (self.room, front)
	local shown = { x = front.x + out.x * SHOW_OUT, y = front.y + out.y * SHOW_OUT, z = front.z }
	local show = admitAt ({ x = front.x + out.x * spacing, y = front.y + out.y * spacing, z = front.z }) (shown)
	starts [decoy] = hide or members [decoy]
	local places = Pair (self.entry, Farthest (floor, self.entry, #members, spacing), starts)
	local points = {}
	if self.room.enemy then
		local going, from = {}, {}
		for k, m in ipairs (rest) do going [k], from [k] = m, starts [m] end
		for k, point in pairs (Assign (self.room.enemy, EncirclePoints (self.room, floor, #rest, spacing), from)) do
			points [going [k]] = point
		end
	else
		for e, entrance in ipairs (others) do
			local group = {}
			for _, m in ipairs (rest) do
				if of [m] == e then group [#group + 1] = m end
			end
			sort (group, function (a, b) return Geometry.Distance2D (starts [a], entrance) < Geometry.Distance2D (starts [b], entrance) end)
			local by = setmetatable ({ entry = entrance }, { __index = self.room })
			for m, point in pairs (BreachPoints (by, floor, group, starts, spacing)) do points [m] = point end
		end
	end
	for i, place in pairs (places) do self.staging [place], self.breach [place] = stack [i], points [i] end
	-- the rest hop door to door round the room to their stacks, past any entrance but the front
	-- (their own too, where the stack lies past it); the ground hidden beside each found once
	local beside = {}
	local function Beside (entrance)
		if not beside [entrance] then
			local out = OutOf (self.room, entrance)
			beside [entrance] = Outside ({ entry = entrance, center = self.room.center, seen = self.room.seen }, spacing,
				admitAt ({ x = entrance.x + out.x * spacing, y = entrance.y + out.y * spacing, z = entrance.z }))
		end
		return beside [entrance]
	end
	-- each hop a spot of its member's own, clear of every stack and of the hops given before it
	local stacks, taken = {}, {}
	for _, m in ipairs (rest) do stacks [#stacks + 1] = stack [m] end
	if hide then stacks [#stacks + 1] = hide end
	self.hops = {}
	for _, m in ipairs (rest) do
		if places [m] and stack [m] then
			self.hops [places [m]] = Hops (self.room, members [m], stack [m], { [front] = true }, Beside, stacks, taken, spacing)
		end
	end
	if places [decoy] then self.staging [places [decoy]], self.breach [places [decoy]] = hide, nil end
	if places [decoy] then self.decoys [places [decoy]] = { show = show, hide = hide } end
	return places
end

function Muster (point)
	return NewOrder (Gather, { kind = "Muster", point = point })
end

-- Nil where point is on the threat, which leaves no way across the ground to fall.
function FallBack (point, from)
	if point.x == from.x and point.y == from.y then return nil end
	return NewOrder (Withdraw, { kind = "FallBack", point = point, from = from })
end

-- room: { center, lo, hi (its block), entry (the doorway the squad comes in by), seen(point) (whether
-- the room's inside sees a point outside, through its doorways), score(point) (what a point inside
-- is worth to fight from: higher, better), enemy (where one is known in it, which the assault points
-- then encircle; nil for none) }; refused without seen or score.
function Assault (room)
	if not room.seen then error ("an assault stages out of its room's sight: the room's seen", 2) end
	if not room.score then error ("an assault goes in to the points best to fight from: the room's score", 2) end
	return NewOrder (Breach, { kind = "Assault", point = room.center, entry = room.entry, room = room, exits = room.exits })
end

-- Its root, holding first (gib_behaviors' LegsWait, for none).
function InitialAction (engine, first)
	return engine.TacticalLeggings ({ initial = first or nextsoldier.behavior.gib_behaviors.LegsWait:New () })
end

-- Puts the tree on ent, telling its actions me. Whether it could: where the binary is not
-- bound, a soldier goes without.
function Give (ent, engine, me)
	if not (engine and engine.InsertGroup) then return false end
	engine.InsertGroup (ent, InitialAction (engine), me)
	return true
end
