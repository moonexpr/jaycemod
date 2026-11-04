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

T.test("nav clearance sweeps an opening with the supplied agent hull", function()
	local lines = { { start = V(0, 0, 0), finish = V(100, 0, 0) } }
	local heights = {}
	local function Trace(data)
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
	local function Room(top, ceiling)
		return function(data)
			local hit = data.start.z + data.mins.z < top or data.start.z + data.maxs.z > ceiling
			return { Hit = hit, StartSolid = false }
		end
	end
	local mins, maxs = V(-24, -24, 0), V(24, 24, 82)
	T.eq(Clearance.FitsLines(lines, mins, maxs, 7, Room(STEP + 8, 1000), V), true, "over the next steps")
	T.eq(Clearance.FitsLines(lines, mins, maxs, 7, Room(STEP + 8, maxs.z + STEP / 2), V), false, "no room for the head")
	T.eq(Clearance.FitsLines(lines, mins, maxs, 7, Room(2 * STEP + 8, 1000), V), false, "more than a stair")
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
		return { Hit = data.start.x == 20, StartSolid = false }
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

	-- A trace hitting a solid up to `top` above the floor and a ceiling at `ceiling`.
	local function Room(top, ceiling)
		return function(data)
			local hit = data.start.z + data.mins.z < top or data.start.z + data.maxs.z > ceiling
			return { Hit = hit, StartSolid = false }
		end
	end

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

	T.test("what rises more than a step above a body's step is no stair to it", function()
		local clearance = NewClearance(Agent(TF2_MINS, TF2_MAXS), Room(2 * STEP + 8, 1000))
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

T.finish()
