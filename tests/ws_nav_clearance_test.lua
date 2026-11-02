local T = dofile("tests/harness.lua")
local Clearance = T.require("ws.nav_clearance")

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
	return Clearance.New(agent, 7, trace, V)
end

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
	T.eq(calls[1].mins.z, nextsoldier.nav_gaps.STEP_HEIGHT)
	T.eq(calls[1].maxs.y, 8)
	T.eq(calls[1].maxs.z, 64)
	local world = { IsWorld = function() return true end }
	local brush = { IsWorld = function() return false end, GetClass = function() return "func_brush" end }
	local door = { IsWorld = function() return false end, GetClass = function() return "func_door" end }
	T.eq(calls[1].filter(world), true)
	T.eq(calls[1].filter(brush), true)
	T.eq(calls[1].filter(door), false)
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
	T.eq(calls, 2)
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
