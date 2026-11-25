-- The nodegraph feature's generation (features/nodegraph/sv.lua) over a fake world: a floor at
-- z 0, solid boxes, and traces worked out from them; its nav mesh a row of areas. Air nodes stand
-- AIR_HEIGHT over the ground nodes where there is room, link only to each other, and are flown
-- by each centred hull whose box clears the way (CAI_NetworkBuilder::ComputeConnection).
local T = dofile ("tests/harness.lua")
local Graph = nodegraph

local AIR_HEIGHT = 72

-------------------------------------------------------------------------------
-- A vector as GMod's: fields, arithmetic, the methods the feature calls.

local VectorMeta = {}
VectorMeta.__index = VectorMeta
local function Vector (x, y, z) return setmetatable ({ x = x or 0, y = y or 0, z = z or 0 }, VectorMeta) end
VectorMeta.__add = function (a, b) return Vector (a.x + b.x, a.y + b.y, a.z + b.z) end
VectorMeta.__sub = function (a, b) return Vector (a.x - b.x, a.y - b.y, a.z - b.z) end
VectorMeta.__mul = function (a, b)
	if type (a) == "number" then a, b = b, a end
	return Vector (a.x * b, a.y * b, a.z * b)
end
function VectorMeta:Length () return math.sqrt (self.x * self.x + self.y * self.y + self.z * self.z) end
function VectorMeta:Distance (o) return (self - o):Length () end
local function LerpVector (t, a, b) return a + (b - a) * t end

-------------------------------------------------------------------------------
-- The world: solid below z 0, and boxes { lo, hi }. A trace is a box swept from start to endpos
-- (a line has no box); the world it meets is grown by the box (Minkowski).

local function Trace (boxes, data, mins, maxs)
	local s, e = data.start, data.endpos
	local best, normal, startSolid = 1, nil, false
	-- the floor: the box's bottom no lower than 0
	local floor = -mins.z
	if s.z < floor - 1e-6 then
		startSolid = true
	elseif e.z < floor then
		local t = (s.z - floor) / (s.z - e.z)
		if t < best then best, normal = t, Vector (0, 0, 1) end
	end
	for _, box in ipairs (boxes) do
		local lo = { x = box.lo.x - maxs.x, y = box.lo.y - maxs.y, z = box.lo.z - maxs.z }
		local hi = { x = box.hi.x - mins.x, y = box.hi.y - mins.y, z = box.hi.z - mins.z }
		if s.x > lo.x and s.x < hi.x and s.y > lo.y and s.y < hi.y and s.z > lo.z and s.z < hi.z then
			startSolid = true
		else
			local tmin, tmax, n = 0, 1, nil
			local missed = false
			for _, axis in ipairs ({ "x", "y", "z" }) do
				local d = e [axis] - s [axis]
				if math.abs (d) < 1e-9 then
					if s [axis] <= lo [axis] or s [axis] >= hi [axis] then missed = true end
				else
					local t1, t2 = (lo [axis] - s [axis]) / d, (hi [axis] - s [axis]) / d
					local face = -1
					if t1 > t2 then t1, t2, face = t2, t1, 1 end
					if t1 > tmin then
						tmin = t1
						n = Vector (0, 0, 0)
						n [axis] = face
					end
					if t2 < tmax then tmax = t2 end
					if tmin > tmax then missed = true end
				end
			end
			if not missed and n and tmin < best then best, normal = tmin, n end
		end
	end
	return
	{
		Hit = best < 1 or startSolid,
		Fraction = startSolid and 0 or best,
		HitPos = s + (e - s) * best,
		HitNormal = normal or Vector (0, 0, 0),
		StartSolid = startSolid
	}
end

-- A nav area of size 100 by 100 about its centre, on the floor.
local function Area (id, x, y)
	local area = { id = id, center = Vector (x, y, 0) }
	function area:GetID () return self.id end
	function area:GetAttributes () return 0 end
	function area:IsUnderwater () return false end
	function area:GetCenter () return self.center end
	function area:GetSizeX () return 100 end
	function area:GetSizeY () return 100 end
	function area:GetHidingSpots () return {} end
	function area:GetCorner () return Vector (x, y, 0) end
	function area:GetAdjacentAreasAtSide () return {} end
	return area
end

-- The feature's controller over a world: its areas, its boxes, its node limit; what it wrote.
local function Load (areas, boxes, maxNodes)
	local written = {}
	local env = setmetatable (
		{
			Vector = Vector,
			LerpVector = LerpVector,
			GetConVar = function () return { GetInt = function () return maxNodes end } end,
			navmesh = { GetAllNavAreas = function () return areas end },
			util =
			{
				TraceLine = function (data) return Trace (boxes, data, Vector (), Vector ()) end,
				TraceHull = function (data) return Trace (boxes, data, data.mins, data.maxs) end
			},
			file =
			{
				CreateDir = function () end,
				Open = function ()
					return { Write = function (_, data) written [#written + 1] = data end, Close = function () end }
				end
			},
			game = { GetMap = function () return "test" end, GetMapVersion = function () return 7 end },
			hook = { Add = function () end },
			table = setmetatable ({ Count = function (t) local n = 0 for _ in pairs (t) do n = n + 1 end return n end },
				{ __index = table }),
			SysTime = function () return -1 end,
			CurTime = function () return 0 end,
			IsValid = function (x) return x ~= nil end,
			print = function () end,
			MASK_NPCSOLID_BRUSHONLY = 1,
			MASK_NPCWORLDSTATIC = 2
		}, { __index = _G })
	local chunk = assert (loadfile ("addons/sandcastle/gamemodes/wetsands/gamemode/features/nodegraph/sv.lua"))
	setfenv (chunk, env)
	local controller = chunk ()
	controller:Build (nil)
	return assert (Graph.Decode (written [1]))
end

-- A row of areas 100 apart along x, from 0 to 2000, but under the wall.
local function Row ()
	local areas = {}
	for x = 0, 2000, 100 do
		if x ~= 1000 then areas [#areas + 1] = Area (#areas + 1, x, 0) end
	end
	return areas
end

-- A wall 50 high at x 1000 to 1010, which no one walks over but the small flyers fly over at 72;
-- a ceiling 60 high over x 1700 and on, which leaves no room for an air node under it.
local WALL = { lo = Vector (1000, -1000, 0), hi = Vector (1010, 1000, 50) }
local CEILING = { lo = Vector (1650, -1000, 60), hi = Vector (3000, 1000, 1000) }

local function Split (graph)
	local ground, air = {}, {}
	for i, node in ipairs (graph.nodes) do
		if node.type == Graph.NODE_AIR then air [i] = node else ground [i] = node end
	end
	return ground, air
end

local function Crosses (graph, link)
	local a, b = graph.nodes [link.a].pos.x, graph.nodes [link.b].pos.x
	return (a < 1000) ~= (b < 1000)
end

T.test ("air nodes stand AIR_HEIGHT over the ground nodes, but where there is no room", function ()
	local graph = Load (Row (), { WALL, CEILING }, 1500)
	local ground, air = Split (graph)
	local count = 0
	for _, node in pairs (air) do
		count = count + 1
		T.near (node.pos.z, AIR_HEIGHT, 1e-3, "at its height")
		T.eq (node.pos.x < 1650, true, "none under the ceiling")
	end
	T.eq (count > 0,            true, "there are air nodes")
	T.eq (next (ground) ~= nil, true, "and ground nodes still")
end)

T.test ("air nodes stand AIR_SPACING apart", function ()
	local _, air = Split (Load (Row (), { WALL, CEILING }, 1500))
	local list = {}
	for _, node in pairs (air) do list [#list + 1] = node.pos end
	for i = 1, #list do
		for j = i + 1, #list do
			T.eq (math.abs (list [i].x - list [j].x) >= 192, true, "spaced")
		end
	end
end)

T.test ("air nodes link only to air nodes, flown; ground nodes only to ground nodes, walked", function ()
	local graph = Load (Row (), { WALL, CEILING }, 1500)
	local flown = 0
	for _, link in ipairs (graph.links) do
		local a, b = graph.nodes [link.a].type, graph.nodes [link.b].type
		T.eq (a == b, true, "never between an air node and a ground one")
		if a == Graph.NODE_AIR then
			flown = flown + 1
			T.eq (link.moves [0], 0, "an air link is walked by no one")
		else
			T.eq (link.moves [6], 0, "a ground link is flown by no one")
		end
	end
	T.eq (flown > 0, true, "there are flown links")
end)

T.test ("over the low wall, the small centred hulls fly and the large one does not; no one walks it", function ()
	local graph = Load (Row (), { WALL, CEILING }, 1500)
	local over = 0
	for _, link in ipairs (graph.links) do
		if Crosses (graph, link) then
			T.eq (graph.nodes [link.a].type, Graph.NODE_AIR, "only flown across")
			over = over + 1
			T.eq (link.moves [6], Graph.CAP_MOVE_FLY, "tiny centred: 68 to 76, over the wall")
			T.eq (link.moves [1], Graph.CAP_MOVE_FLY, "small centred: 52 to 92")
			T.eq (link.moves [8], 0,                  "large centred: 34 to 110, into it")
		end
	end
	T.eq (over > 0, true, "a link flies over the wall")
end)

T.test ("air nodes keep their share of the node limit", function ()
	local graph = Load (Row (), {}, 10)
	local _, air = Split (graph)
	local count = 0
	for _ in pairs (air) do count = count + 1 end
	T.eq (#graph.nodes <= 10, true, "the limit holds")
	T.eq (count,              2,    "a fifth of it")
end)

T.finish ()
