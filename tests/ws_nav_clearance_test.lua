local T = dofile("tests/harness.lua")
local Clearance = T.require("includes.nav_clearance")

local Vec = {}
Vec.__index = Vec

local function V(x, y, z)
	return setmetatable({ x = x, y = y, z = z }, Vec)
end

Vec.__add = function(a, b) return V(a.x + b.x, a.y + b.y, a.z + b.z) end

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function Area(id, x0, y0, x1, y1, z)
	local area = { id = id, lo = V(x0, y0, z), hi = V(x1, y1, z), sides = {} }
	function area:GetID() return self.id end
	function area:GetExtentInfo() return { lo = self.lo, hi = self.hi } end
	function area:GetCenter() return V((self.lo.x + self.hi.x) / 2, (self.lo.y + self.hi.y) / 2, self.lo.z) end
	function area:GetZ() return self.lo.z end
	function area:GetAttributes() return self.attributes or 0 end
	function area:IsConnectedAtSide(other, side) return self.sides[side] == other end
	function area:GetClosestPointOnArea(point)
		return V(Clamp(point.x, self.lo.x, self.hi.x), Clamp(point.y, self.lo.y, self.hi.y), self.lo.z)
	end
	return area
end

local function Agent(mins, maxs)
	return {
		GetCollisionBounds = function() return mins, maxs end,
	}
end

local function NewClearance(agent, trace)
	Clearance.Clear()
	return Clearance.New(agent, 7, trace, V)
end

-- A trace in a room with a solid floor up to `top` and a ceiling at `ceiling`.
local function Room(top, ceiling)
	return function(data)
		local z = data.start.z
		if z + data.mins.z < top or z + data.maxs.z > ceiling then
			return { Hit = true, StartSolid = true }
		end
		local rest = top - data.mins.z
		if data.endpos.z < z and rest > data.endpos.z then
			return { Hit = true, StartSolid = false, HitPos = V(data.endpos.x, data.endpos.y, rest) }
		end
		return { Hit = false, StartSolid = false }
	end
end

T.test("nav clearance sweeps an opening with the supplied agent hull", function()
	local lines = { { start = V(0, 0, 0), finish = V(100, 0, 0) } }
	local heights = {}
	local function Trace(data)
		-- a sole dropped to the floor finds it clear
		if data.endpos.z < data.start.z then return { Hit = false, StartSolid = false } end
		heights[#heights + 1] = data.start.z
		T.eq(data.mins.z, nextsoldier.world.nav_gaps.STEP_HEIGHT)
		T.eq(data.maxs.z, 72)
		return { Hit = data.mins.x < -15, StartSolid = false }
	end
	T.eq(Clearance.FitsLines(lines, V(-13, -13, 0), V(13, 13, 72), 7, Trace, V), true,
		"the narrower agent fits")
	T.eq(heights[1], 1, "on the floor first")
	T.eq(Clearance.FitsLines(lines, V(-24, -24, 0), V(24, 24, 72), 7, Trace, V), false,
		"the wider agent does not fit")
end)

T.test("an opening on a stair is swept a step up too, with room for the head", function()
	local STEP = nextsoldier.world.nav_gaps.STEP_HEIGHT
	local lines = { { start = V(0, 0, 0), finish = V(100, 0, 0) } }
	local mins, maxs = V(-24, -24, 0), V(24, 24, 82)
	T.eq(Clearance.FitsLines(lines, mins, maxs, 7, Room(STEP + 8, 1000), V), true, "over the next steps")
	T.eq(Clearance.FitsLines(lines, mins, maxs, 7, Room(STEP + 8, maxs.z + STEP / 2), V), false, "no room for the head")
end)

T.test("nav clearance accepts an ordinary entity and checks its collision hull", function()
	local calls = {}
	local clearance = NewClearance(Agent(V(-10, -8, 0), V(10, 8, 64)), function(data)
		calls[#calls + 1] = data
		return { Hit = false, StartSolid = false }
	end)
	local area = Area(1, 0, 0, 100, 100, 0)
	T.eq(clearance:Area(area), true)
	T.eq(clearance:Area(area), true, "cached for this path search")
	T.eq(#calls, 1)
	T.eq(calls[1].mask, 7)
	T.eq(calls[1].mins.x, -10)
	T.eq(calls[1].mins.z, nextsoldier.world.nav_gaps.STEP_HEIGHT)
	T.eq(calls[1].maxs.y, 8)
	T.eq(calls[1].maxs.z, 64)
	local world = { IsWorld = function() return true end }
	local brush = { IsWorld = function() return false end, GetClass = function() return "func_brush" end }
	local door = { IsWorld = function() return false end, GetClass = function() return "func_door" end }
	T.eq(calls[1].filter(world), true)
	T.eq(calls[1].filter(brush), true)
	T.eq(calls[1].filter(door), false)
end)

T.test("nav clearance results are reused across repaths for the same hull and reset with the mesh", function()
	Clearance.Clear()
	local calls = 0
	local agent = Agent(V(-10, -8, 0), V(10, 8, 64))
	local trace = function()
		calls = calls + 1
		return { Hit = false, StartSolid = false }
	end
	local area = Area(40, 0, 0, 100, 100, 0)
	local from, to = Area(41, 0, 0, 100, 100, 0), Area(42, 100, 0, 200, 100, 0)
	from.sides[1], to.sides[3] = to, from
	local first = Clearance.New(agent, 7, trace, V)
	T.eq(first:Area(area), true)
	T.eq(first:Link(from, to), true)
	local afterFirstSearch = calls
	local second = Clearance.New(agent, 7, trace, V)
	T.eq(second, first, "same hull shares its spatial cache")
	T.eq(second:Area(area), true, "area clearance is reused after repathing")
	T.eq(second:Link(from, to), true, "link clearance is reused after repathing")
	T.eq(calls, afterFirstSearch, "no additional traces")
	local crouching = Clearance.New(Agent(V(-10, -8, 0), V(10, 8, 36)), 7, trace, V)
	T.eq(crouching == first, false, "a changed collision hull gets its own cache")
	T.eq(crouching:Area(area), true)
	T.eq(calls, afterFirstSearch + 1, "the changed hull gets a fresh trace")
	Clearance.Clear()
	local rebuilt = Clearance.New(agent, 7, trace, V)
	T.eq(rebuilt == first, false, "mesh reset discards cached answers")
	T.eq(rebuilt:Area(area), true)
	T.eq(calls, afterFirstSearch + 2, "clearance is recomputed for the new mesh")
end)

T.test("nav clearance uses the collision trace instead of a nav area's bounding box", function()
	local calls = 0
	local clearance = NewClearance(Agent(V(-10, -8, 0), V(10, 8, 64)), function(data)
		calls = calls + 1
		local blocked = data.start.x == 20
		return { Hit = blocked, StartSolid = blocked }
	end)
	T.eq(clearance:Area(Area(2, 0, 0, 19, 100, 0)), true, "a narrow nav polygon can still have physical clearance")
	T.eq(clearance:Area(Area(2, 0, 0, 19, 100, 0)), true, "cached admission")
	T.eq(clearance:Area(Area(3, 10, 0, 30, 100, 0)), false, "the world trace rejects a blocked area")
	T.eq(clearance:Area(Area(3, 10, 0, 30, 100, 0)), false, "cached rejection")
	T.eq(calls, 3, "once for the admitted area; on the floor and a step up for the refused; none when cached")
end)

T.test("nav clearance tolerates floor overlap within the walkable step height", function()
	local clearance = NewClearance(Agent(V(-10, -8, 0), V(10, 8, 64)), function(data)
		return { Hit = false, StartSolid = data.mins.z == 0 }
	end)
	T.eq(clearance:Area(Area(4, 0, 0, 19, 100, 0)), true,
		"the lower step-height portion of the hull may overlap sloped ground")
end)

T.test("nav clearance uses each entity's hull to admit a link opening", function()
	local from, to = Area(3, 0, 0, 100, 100, 0), Area(4, 100, 0, 200, 100, 0)
	from.sides[1] = to
	to.sides[3] = from
	local function Trace(data)
		if data.start.x ~= data.endpos.x then
			local low, high = data.start.y + data.mins.y, data.start.y + data.maxs.y
			if low < 42 or high > 58 then return { Hit = true, StartSolid = false } end
		end
		return { Hit = false, StartSolid = false }
	end
	local small = NewClearance(Agent(V(-10, -8, 0), V(10, 8, 64)), Trace)
	local large = NewClearance(Agent(V(-10, -16, 0), V(10, 16, 64)), Trace)
	T.eq(small:Link(from, to), true, "the small body clears the opening")
	T.eq(large:Link(from, to), false, "the larger body cannot fit")
	T.eq(large:Link(to, from), false, "the reverse link is checked separately")
end)

T.test("nav clearance preserves each entity's overhead clearance", function()
	local from, to = Area(7, 0, 0, 100, 100, 0), Area(8, 100, 0, 200, 100, 0)
	from.sides[1] = to
	to.sides[3] = from
	local function Trace(data)
		return { Hit = data.maxs.z > 40, StartSolid = false }
	end
	local standing = NewClearance(Agent(V(-10, -8, 0), V(10, 8, 64)), Trace)
	local crouching = NewClearance(Agent(V(-10, -8, 0), V(10, 8, 36)), Trace)
	T.eq(standing:Link(from, to), false, "the standing hull does not fit")
	T.eq(crouching:Link(from, to), true, "the crouching hull fits")
end)

local NAV_MESH_CROUCH = T.require("foundation.wetsands.path.hl2").NAV_MESH_CROUCH
local CROUCH_HEIGHT = 36

local function Crouching(mins, maxs)
	local agent = Agent(mins, maxs)
	agent.NSCrouchHeight = CROUCH_HEIGHT
	return agent
end

-- Fits below the crouch height, not at a standing height.
local function LowCeiling(data)
	return { Hit = data.maxs.z > CROUCH_HEIGHT, StartSolid = false }
end

T.test("a body that crouches is measured crouched in a crouch area, standing elsewhere", function()
	local clearance = NewClearance(Crouching(V(-10, -10, 0), V(10, 10, 72)), LowCeiling)
	local low, open = Area(9, 0, 0, 100, 100, 0), Area(10, 0, 0, 100, 100, 0)
	low.attributes = NAV_MESH_CROUCH
	T.eq(clearance:Area(low), true, "it crouches under the ceiling")
	T.eq(clearance:Area(open), false, "with no crouch flag it stands")
end)

T.test("a body that does not crouch is not excused by a crouch area", function()
	local clearance = NewClearance(Agent(V(-10, -10, 0), V(10, 10, 72)), LowCeiling)
	local low = Area(11, 0, 0, 100, 100, 0)
	low.attributes = NAV_MESH_CROUCH
	T.eq(clearance:Area(low), false)
end)

T.test("a link into or out of a crouch area is measured crouched", function()
	local clearance = NewClearance(Crouching(V(-10, -10, 0), V(10, 10, 72)), LowCeiling)
	local open, low, far = Area(12, 0, 0, 100, 100, 0), Area(13, 100, 0, 200, 100, 0), Area(14, 200, 0, 300, 100, 0)
	low.attributes = NAV_MESH_CROUCH
	open.sides[1], low.sides[3], low.sides[1], far.sides[3] = low, open, far, low
	T.eq(clearance:Link(open, low), true, "ducking in")
	T.eq(clearance:Link(low, open), true, "and out")
	T.eq(clearance:Link(far, open) , false, "neither end low, it stands")
end)

T.test("bodies crouching to different heights keep apart caches", function()
	Clearance.Clear()
	local trace = function() return { Hit = false, StartSolid = false } end
	local a, b = Crouching(V(-10, -10, 0), V(10, 10, 72)), Crouching(V(-10, -10, 0), V(10, 10, 72))
	b.NSCrouchHeight = CROUCH_HEIGHT + 10
	T.eq(Clearance.New(a, 7, trace, V) == Clearance.New(b, 7, trace, V), false)
end)

-- A stair's next steps stand within a wide hull's reach of a point on it or at
-- its foot; the body rides up on them, its feet and head a step higher.
do
	local STEP = nextsoldier.world.nav_gaps.STEP_HEIGHT
	local TF2_MINS, TF2_MAXS = V(-24, -24, 0), V(24, 24, 82)

	-- Two areas a link joins, side by side.
	local function Linked()
		local from, to = Area(1, 0, 0, 100, 100, 0), Area(2, 100, 0, 200, 100, 0)
		from.sides[1] = to
		return from, to
	end

	T.test("a body fits on and at the foot of a stair, whose steps it rides up", function()
		local clearance = NewClearance(Agent(TF2_MINS, TF2_MAXS), Room(STEP + 8, 1000))
		T.eq(clearance:Area(Area(1, 0, 0, 100, 100, 0)), true, "the area")
		T.eq(clearance:Link(Linked()), true, "the link")
	end)

	T.test("a body riding a step still needs room for its head", function()
		local ceiling = TF2_MAXS.z + STEP / 2
		local clearance = NewClearance(Agent(TF2_MINS, TF2_MAXS), Room(STEP + 8, ceiling))
		T.eq(clearance:Area(Area(1, 0, 0, 100, 100, 0)), false, "the area")
		T.eq(clearance:Link(Linked()), false, "the link")
	end)
end

T.test("nav clearance sweeps height-changing links at the higher floor", function()
	local lower, upper = Area(5, 0, 0, 100, 100, 0), Area(6, 100, 0, 200, 100, 24)
	lower.sides[1] = upper
	upper.sides[3] = lower
	local function Trace(data)
		T.eq(data.start.z, 25, "start at the higher floor")
		T.eq(data.endpos.z, 25, "keep the hull level while crossing")
		return { Hit = false, StartSolid = false }
	end
	local clearance = NewClearance(Agent(V(-10, -8, 0), V(10, 8, 64)), Trace)
	T.eq(clearance:Link(lower, upper), true)
	T.eq(clearance:Link(upper, lower), true)
end)

-- A world of solid columns, each cell's solids from the top: a top and its
-- bottom, the lowest a top alone. Traces a hull straight down or level, as a
-- body's clearance does.
local function ColumnWorld(section)
	local function Spans(col, row)
		local cells = section.columns[row + 1]
		return cells and cells[col + 1] or {}
	end
	-- The cells whose centres stand under the span, each measured where it was
	-- sampled, or the nearest when it is narrower than a cell.
	local function Cells(low, high, origin)
		local first = math.ceil((low - origin) / section.cell - 0.5)
		local last = math.floor((high - origin) / section.cell - 0.5)
		if first > last then
			first = math.floor(((low + high) / 2 - origin) / section.cell)
			last = first
		end
		return first, last
	end
	local function EachSpan(x, y, mins, maxs, visit)
		local firstRow, lastRow = Cells(y + mins.y, y + maxs.y, section.y)
		local firstCol, lastCol = Cells(x + mins.x, x + maxs.x, section.x)
		for row = firstRow, lastRow do
			for col = firstCol, lastCol do
				local spans = Spans(col, row)
				for i = 1, #spans, 2 do
					if visit(spans[i], spans[i + 1] or -math.huge) then return true end
				end
			end
		end
		return false
	end
	local function Blocked(x, y, z, mins, maxs)
		return EachSpan(x, y, mins, maxs, function(top, bottom)
			return z + mins.z < top and z + maxs.z > bottom
		end)
	end
	return function(data)
		local from, to, mins, maxs = data.start, data.endpos, data.mins, data.maxs
		if Blocked(from.x, from.y, from.z, mins, maxs) then
			return { Hit = true, StartSolid = true, HitPos = from }
		end
		if to.z < from.z then
			local rest = to.z
			EachSpan(from.x, from.y, mins, maxs, function(top)
				if top - mins.z <= from.z and top - mins.z > rest then rest = top - mins.z end
			end)
			return { Hit = rest > to.z, StartSolid = false, HitPos = V(to.x, to.y, rest) }
		end
		local dx, dy = to.x - from.x, to.y - from.y
		local steps = math.ceil(math.sqrt(dx * dx + dy * dy) / 8)
		for i = 1, steps do
			local x, y = from.x + dx * i / steps, from.y + dy * i / steps
			if Blocked(x, y, from.z, mins, maxs) then
				return { Hit = true, StartSolid = false, HitPos = V(x, y, from.z) }
			end
		end
		return { Hit = false, StartSolid = false, HitPos = to }
	end
end

local function Body(half)
	return Agent(V(-half.x, -half.y, 0), V(half.x, half.y, half.z))
end

-- A flat floor at height 0 with a crate standing on it from x = crateFrom on,
-- `crate` high, and the two areas a link joins across x = 100.
do
	local CELL = 4
	local function CrateFloor(crateFrom, crate)
		local columns = {}
		for row = 0, 60 do
			local cells = {}
			for col = 0, 60 do
				cells[col + 1] = { col * CELL >= crateFrom and crate or 0 }
			end
			columns[row + 1] = cells
		end
		return ColumnWorld({ cell = CELL, x = 0, y = -120, columns = columns })
	end
	local function Linked()
		local from, to = Area(1, 50, -50, 100, 50, 0), Area(2, 100, -50, 200, 50, 0)
		from.sides[1] = to
		return from, to
	end
	local SOLDIER = { x = 24, y = 24, z = 82 }

	T.test("a body stops at what rises more than a step ahead of it", function()
		local STEP = nextsoldier.world.nav_gaps.STEP_HEIGHT
		local crate = 2 * STEP + 8
		local clearance = NewClearance(Body(SOLDIER), CrateFloor(112, crate))
		local from, to = Linked()
		T.eq(clearance:Link(from, to), false, "the crossing onto it")
		T.eq(clearance:Area(to), true, "though a body fits on top of it")
	end)

	T.test("a body steps up what rises no more than a step ahead of it", function()
		local STEP = nextsoldier.world.nav_gaps.STEP_HEIGHT
		local clearance = NewClearance(Body(SOLDIER), CrateFloor(112, STEP))
		T.eq(clearance:Link(Linked()), true)
	end)
end

-- The bridge at cp_5gorge's point B, as captured: a gorge floor sloping up to
-- both sides, under a deck about 134 above it and on piers, its ends meeting
-- the slopes. The bodies are the path follower tool's, by model.
do
	local Section = dofile("tests/fixtures/cp_5gorge_bridge.lua")
	local BODIES = {
		chell = { x = 13, y = 13, z = 72 },
		scout = { x = 19.3, y = 16.6, z = 83.1 },
		worker = { x = 34.5, y = 16, z = 54.4 },
		hatman = { x = 25.6, y = 38.2, z = 138.5 },
		merasmus = { x = 92.8, y = 49.7, z = 190.4 },
		tank = { x = 117.4, y = 79.2, z = 176.2 },
	}
	local GORGE_EAST, GORGE_WEST, DECK = 15844, 1575, 15286
	local UNDER_NORTH, UNDER_SOUTH = 15268, 16965
	-- The slope against the deck's side, where the mesh links up to a deck too
	-- high to climb, and the one further along that meets it within a jump.
	local BESIDE_THE_DECK, DECK_ONRAMP = 15838, 15839
	local Walkable = wetsands.path.Walkable
	local LIMITS = T.require("foundation.wetsands.path.hl2").SOLDIER_LIMITS

	local function SectionAreas()
		local areas = {}
		for _, row in ipairs(Section.areas) do
			local id, x0, y0, x1, y1, nw, ne, se, sw, attributes, sides =
				row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10], row[11]
			local area = Area(id, x0, y0, x1, y1, nw)
			area.attributes = attributes
			function area:GetZ(point)
				local u = Clamp((point.x - x0) / (x1 - x0), 0, 1)
				local v = Clamp((point.y - y0) / (y1 - y0), 0, 1)
				local north, south = nw + u * (ne - nw), sw + u * (se - sw)
				return north + v * (south - north)
			end
			function area:GetCenter() return V((x0 + x1) / 2, (y0 + y1) / 2, (nw + se) / 2) end
			function area:IsConnectedAtSide(other, side)
				for _, to in ipairs(sides[side + 1]) do
					if to == other.id then return true end
				end
				return false
			end
			function area:Neighbors()
				local all = {}
				for side = 1, 4 do
					for _, to in ipairs(sides[side]) do all[#all + 1] = areas[to] end
				end
				return all
			end
			-- Where this area's edge on a side meets another, at the middle of
			-- their overlap (0 north, -y; 1 east, +x; 2 south, +y; 3 west, -x).
			function area:Portal(other, side)
				if side == 0 or side == 2 then
					local x = (math.max(x0, other.lo.x) + math.min(x1, other.hi.x)) / 2
					return V(x, side == 0 and y0 or y1, 0)
				end
				local y = (math.max(y0, other.lo.y) + math.min(y1, other.hi.y)) / 2
				return V(side == 1 and x1 or x0, y, 0)
			end
			-- The engine's ComputeAdjacentConnectionHeightChange: edge to edge.
			function area:ComputeAdjacentConnectionHeightChange(other)
				for side = 0, 3 do
					if self:IsConnectedAtSide(other, side) then
						return other:GetZ(other:Portal(self, (side + 2) % 4)) - self:GetZ(self:Portal(other, side))
					end
				end
				return math.huge
			end
			areas[id] = area
		end
		return areas
	end

	local areas = SectionAreas()
	local world = ColumnWorld(Section)

	local function Measure(body)
		return NewClearance(Body(BODIES[body]), world)
	end

	-- Every area a body reaches from GORGE_EAST over what it fits through and
	-- what it climbs, as a path's cost has it.
	local function Reached(body)
		local clearance = Measure(body)
		local seen, stack = { [GORGE_EAST] = true }, { areas[GORGE_EAST] }
		while #stack > 0 do
			local area = table.remove(stack)
			for _, other in ipairs(area:Neighbors()) do
				if not seen[other.id] and clearance:Area(other) and clearance:Link(area, other)
					and Walkable(area:ComputeAdjacentConnectionHeightChange(other), LIMITS) then
					seen[other.id] = true
					stack[#stack + 1] = other
				end
			end
		end
		return seen
	end

	T.test("the bridge: who fits under the deck", function()
		for body, fits in pairs({ chell = true, scout = true, worker = true,
			hatman = false, merasmus = false, tank = false }) do
			local clearance = Measure(body)
			T.eq(clearance:Area(areas[UNDER_NORTH]), fits, body .. " under the north span")
			T.eq(clearance:Area(areas[UNDER_SOUTH]), fits, body .. " under the south span")
		end
	end)

	T.test("the bridge: a wide body rides the slopes it overlaps", function()
		for _, body in ipairs({ "merasmus", "tank" }) do
			local clearance = Measure(body)
			T.eq(clearance:Area(areas[GORGE_WEST]), true, body .. " in the gorge west of the bridge")
			T.eq(clearance:Area(areas[DECK]), true, body .. " on the deck")
		end
	end)

	T.test("the bridge: a body too big for the gap crosses over the deck, never under it", function()
		for _, body in ipairs({ "hatman", "tank" }) do
			local reached = Reached(body)
			T.eq(reached[GORGE_WEST], true, body .. " reaches the gorge's far side")
			T.eq(reached[DECK], true, body .. " by the deck")
			T.eq(reached[UNDER_NORTH], nil, body .. " stays out of the north span")
			T.eq(reached[UNDER_SOUTH], nil, body .. " stays out of the south span")
		end
	end)

	T.test("the bridge: the deck is climbed where it is within a jump, not from beside it", function()
		local beside, onramp, deck = areas[BESIDE_THE_DECK], areas[DECK_ONRAMP], areas[DECK]
		T.eq(Walkable(beside:ComputeAdjacentConnectionHeightChange(deck), LIMITS), false, "from beside it")
		T.eq(Walkable(onramp:ComputeAdjacentConnectionHeightChange(deck), LIMITS), true, "from the slope along it")
		T.eq(Reached("tank")[DECK_ONRAMP], true, "the tank goes round to climb it")
	end)

	T.test("the bridge: a soldier passes under it", function()
		local reached = Reached("scout")
		T.eq(reached[UNDER_NORTH], true)
		T.eq(reached[UNDER_SOUTH], true)
		T.eq(reached[GORGE_WEST], true)
	end)
end

T.finish()
