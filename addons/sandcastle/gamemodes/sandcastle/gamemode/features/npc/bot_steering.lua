-- What a bot player does with its route's points as its own body finds them, the traces
-- behind nextsoldier.locomotion's Avoid, StepOff and StandPoints, for any class holding its
-- player as self.ent: a NextSoldier's (sv_next_soldiers.lua) and an AI war bot's.
local Locomotion = nextsoldier.locomotion
local Movement = gameplay.movement
local abs, sqrt = math.abs, math.sqrt
local kit = nextsoldier
module(...)

local SWEEP_HEIGHT = 36
-- How deep and how near a route's point is a drop to step off.
local DROP_DEPTH, DROP_NEAR = 40, 48
local SOLE, FOOTHOLD, LANDING_SLACK = 2, 18, 24

local function Point(v) return { x = v.x, y = v.y, z = v.z } end

-- How far off its way its group's push leans it, and the least push it moves aside for: its
-- teammates do not block it (they pass through), so this is spread, never a wall.
local PUSH_LEAD, PUSH_LEAST = 64, 0.15

local function GroupPush(ent)
	local engine = kit.engine
	if not (engine and engine.GroupPush) then return 0, 0 end
	return engine.GroupPush(ent)
end

-- world: { util, Vector, mask } as the realm has them.
function Apply(class, world)
	local util, Vector, mask = world.util, world.Vector, world.mask
	local LIFT = Vector(0, 0, 20)
	local FOOTING_ABOVE, FOOTING_BELOW = Vector(0, 0, 18), Vector(0, 0, 36)
	local function ToVector(p) return Vector(p.x, p.y, p.z) end

	-- Whether its whole body fits at q, over a floor.
	function class:Stands(q)
		local hullMin, hullMax = self.ent:GetHull()
		local mins, maxs = Movement.Sweep(hullMin, hullMax, SWEEP_HEIGHT)
		local at = ToVector(q)
		if util.TraceHull({ start = at + LIFT, endpos = at + LIFT, mins = ToVector(mins), maxs = ToVector(maxs), mask = mask, filter = self.ent }).Hit then
			return false
		end
		return util.TraceLine({ start = at + FOOTING_ABOVE, endpos = at - FOOTING_BELOW, mask = mask, filter = self.ent }).Hit
	end

	-- Whether no wall stands between two places on a route.
	function class:Reaches(p, q)
		return not util.TraceLine({ start = ToVector(p) + LIFT, endpos = ToVector(q) + LIFT, mask = mask, filter = self.ent }).Hit
	end

	-- The point it makes for on its way to point, veered off a jamb on one side of it.
	function class:Avoid(pos, point)
		local ply = self.ent
		local _, hullMax = ply:GetHull()
		local half = hullMax.x
		local mins, maxs = Vector(-half / 2, -half / 2, 0), Vector(half / 2, half / 2, SWEEP_HEIGHT)
		return Locomotion.Avoid(Point(pos), point, half, function(from, to)
			return util.TraceHull({
				start = ToVector(from) + LIFT,
				endpos = ToVector(to) + LIFT,
				mins = mins,
				maxs = maxs,
				mask = mask,
				filter = ply,
			}).Hit
		end)
	end

	-- Where to walk to fall to a drop's landing, kept for that landing: nil with no way off.
	function class:StepOff(pos, landing)
		if self.stepOffOf == landing then return self.stepOffTo end
		local ply = self.ent
		local hullMin, hullMax = ply:GetHull()
		local mins, maxs = Vector(hullMin.x, hullMin.y, 0), Vector(hullMax.x, hullMax.y, SWEEP_HEIGHT)
		local function Trace(from, to)
			return util.TraceHull({ start = from, endpos = to, mins = mins, maxs = maxs, mask = mask, filter = ply })
		end
		local function Clear(q)
			return not Trace(pos + LIFT, ToVector(q) + LIFT).Hit
		end
		local function Falls(q)
			local at = ToVector(q)
			local above = at + Vector(0, 0, SOLE)
			if Trace(above, at - Vector(0, 0, FOOTHOLD)).Hit then return false end
			local under = Trace(above, Vector(at.x, at.y, landing.z - LANDING_SLACK))
			return under.Hit and abs(under.HitPos.z - landing.z) <= LANDING_SLACK
		end
		self.stepOffOf, self.stepOffTo = landing, Locomotion.StepOff(Point(pos), landing, Clear, Falls)
		return self.stepOffTo
	end

	-- The point its body makes for, its route's next being point: past a drop's ledge, or
	-- off a jamb. pos: where it stands, a Vector.
	function class:SteerOn(pos, point)
		if Locomotion.DropBelow(Point(pos), point, DROP_DEPTH, DROP_NEAR) then
			return self:StepOff(pos, point) or point
		end
		local way = self:Avoid(pos, point)
		local x, y = GroupPush(self.ent)
		if x == 0 and y == 0 then return way end
		return { x = way.x + x * PUSH_LEAD, y = way.y + y * PUSH_LEAD, z = way.z }
	end

	-- Where it steps to, standing with a teammate on it: nil with room enough. pos: a Vector.
	function class:Spread(pos)
		local x, y = GroupPush(self.ent)
		local length = sqrt(x * x + y * y)
		if length < PUSH_LEAST then return nil end
		return { x = pos.x + x / length * PUSH_LEAD, y = pos.y + y / length * PUSH_LEAD, z = pos.z }
	end

	-- The route with each point its body cannot stand on moved to where it can.
	function class:StandOnRoute(points)
		return Locomotion.StandPoints(points, function(q) return self:Stands(q) end, function(p, q) return self:Reaches(p, q) end)
	end
end
