-- nextsoldier.player.sandbox.navmesh: the world a sandbox player reads, from GMod's nav mesh
-- (its areas' hiding spots, routes planned over its areas with graph.pathfinder) and its
-- traces (whether a straight walk is clear). Over a fake navmesh of areas in a row.
local T = dofile ("tests/harness.lua")
local NavWorld = nextsoldier.player.sandbox.navmesh

local VecMeta = {}
VecMeta.__index = VecMeta
function VecMeta:Distance (o) return math.sqrt ((self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 + (self.z - o.z) ^ 2) end
local function Vec (x, y, z) return setmetatable ({ x = x, y = y, z = z or 0 }, VecMeta) end

-- An area at x along a row, its spots, its neighbours given after, and a step up to each.
local function Area (x, spots)
	local area = { center = Vec (x, 0, 0), spots = spots or {}, adjacent = {}, rise = {} }
	function area:GetCenter () return self.center end
	function area:GetHidingSpots () return self.spots end
	function area:GetAdjacentAreas () return self.adjacent end
	function area:ComputeAdjacentConnectionHeightChange (to) return self.rise [to] or 0 end
	function area:GetClosestPointOnArea (p) return Vec (self.center.x, self.center.y, self.center.z) end
	return area
end

local function Link (a, b)
	a.adjacent [#a.adjacent + 1] = b
	b.adjacent [#b.adjacent + 1] = a
end

local function World (areas, traced)
	local navmesh = {}
	function navmesh.GetAllNavAreas () return areas end
	function navmesh.GetNearestNavArea (p)
		local best, distance
		for _, area in ipairs (areas) do
			local d = math.abs (area.center.x - p.x)
			if not distance or d < distance then best, distance = area, d end
		end
		return best
	end
	local util = {}
	function util.TraceHull (trace)
		traced [#traced + 1] = trace
		return { Hit = trace.endpos.x > 900 }
	end
	return NavWorld.New (
		{
			navmesh = navmesh,
			util = util,
			Vector = Vec,
			random = function (low) return low end,
			mask = 1,
			maxRise = 58
		}
	)
end

T.test ("its hiding spots are every area's", function ()
	local a, b = Area (0, { Vec (1, 0, 0) }), Area (100, { Vec (101, 0, 0), Vec (102, 0, 0) })
	local spots = World ({ a, b }, {}).HidingSpots ()
	T.eq (#spots,      3,   "all three")
	T.eq (spots [3].x, 102, "in the areas' order")
end)

T.test ("a route runs over the areas between, and ends at the goal", function ()
	local a, b, c = Area (0), Area (100), Area (200)
	Link (a, b)
	Link (b, c)
	local route = World ({ a, b, c }, {}).PlanRoute (Vec (5, 0, 0), Vec (210, 0, 0))
	T.eq (#route,           4,   "from, two areas, the goal")
	T.eq (route [1].x,      5,   "from where it stands")
	T.eq (route [2].x,      100, "through the middle area")
	T.eq (route [#route].x, 210, "to the goal itself")
end)

T.test ("no route where the areas do not join, nor up a rise past a jump", function ()
	local a, b, c = Area (0), Area (100), Area (200)
	Link (a, b)
	T.eq (World ({ a, b, c }, {}).PlanRoute (Vec (0, 0, 0), Vec (200, 0, 0)), nil, "apart")
	Link (b, c)
	b.rise [c] = 80
	T.eq (World ({ a, b, c }, {}).PlanRoute (Vec (0, 0, 0), Vec (200, 0, 0)), nil, "too high")
	b.rise [c] = 40
	T.eq (World ({ a, b, c }, {}).PlanRoute (Vec (0, 0, 0), Vec (200, 0, 0)) ~= nil, true, "a step it can jump")
end)

T.test ("a walk is clear when a player's hull swept along it hits nothing", function ()
	local traced = {}
	local world = World ({ Area (0) }, traced)
	T.eq (world.CanWalk (Vec (0, 0, 0), Vec (500, 0, 0)),  true,  "clear")
	T.eq (world.CanWalk (Vec (0, 0, 0), Vec (1000, 0, 0)), false, "blocked")
	T.eq (traced [1].mask,                                 1,     "under the player's mask")
end)

T.finish ()
