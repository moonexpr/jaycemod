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
	local area = { center = Vec (x, 0, 0), spots = spots or {}, adjacent = {}, rise = {}, sizeX = 50, sizeY = 50 }
	function area:GetSizeX () return self.sizeX end
	function area:GetSizeY () return self.sizeY end
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

local function World (areas, traced, links, boxes)
	local navmesh = {}
	function navmesh.GetAllNavAreas () return areas end
	-- the areas in a box: those the test says lie in it
	function navmesh.FindInBox (mins) return (boxes or {}) [mins] or {} end
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
			maxRise = 58,
			teleports = function () return links or {} end
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

-- A teleporter in area a, sending to c's x, the two not joined.
local function Teleporter (a, c)
	local mins, maxs = Vec (a.center.x - 10, -10, 0), Vec (a.center.x + 10, 10, 50)
	local link =
	{
		mins = mins,
		maxs = maxs,
		entry = { x = a.center.x, y = 0, z = 0, teleport = true },
		exit = Vec (c.center.x, 0, 0)
	}
	return link, { [mins] = { a } }
end

T.test ("a route goes through a teleporter: its entry, then its exit", function ()
	local a, b, c = Area (0), Area (100), Area (5000)
	Link (a, b)
	local link, boxes = Teleporter (b, c)
	local route = World ({ a, b, c }, {}, { link }, boxes).PlanRoute (Vec (0, 0, 0), Vec (5010, 0, 0))
	T.eq (route ~= nil, true, "there is one")
	local entry
	for i, p in ipairs (route) do
		if p.teleport then entry = i end
	end
	T.eq (entry ~= nil,        true, "it walks into the teleporter")
	T.eq (route [entry].x,     100,  "at its entry")
	T.eq (route [entry + 1].x, 5000, "then from its exit")
	T.eq (route [#route].x,    5010, "to the goal")
end)

T.test ("without a teleporter, areas not joined have no route", function ()
	local a, c = Area (0), Area (5000)
	T.eq (World ({ a, c }, {}).PlanRoute (Vec (0, 0, 0), Vec (5000, 0, 0)), nil, "none")
end)

T.test ("its open ground is the middle of each area as wide as asked, both ways", function ()
	local a, b, c = Area (0), Area (100), Area (200)
	a.sizeX, a.sizeY = 400, 300
	b.sizeX, b.sizeY = 400, 100
	c.sizeX, c.sizeY = 300, 300
	local open = World ({ a, b, c }, {}).OpenGround (300)
	T.eq (#open,      2,   "a and c")
	T.eq (open [1].x, 0,   "a's middle")
	T.eq (open [2].x, 200, "c's middle")
end)

T.finish ()
