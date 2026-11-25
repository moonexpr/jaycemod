-- nextsoldier.locomotion.airways: a flyer's routes over a map's air nodes (foundation.nodegraph's
-- NODE_AIR, linked by CAP_MOVE_FLY per hull), as HL2's navigator flies its flyers over them; and
-- a course along a route: the point to steer at now, advanced and planned again as it goes.
local T = dofile ("tests/harness.lua")
local Airways = nextsoldier.locomotion.airways
local Graph = nodegraph

local TINY, LARGE = 6, 8

local function P (x, y, z) return { x = x, y = y, z = z or 72 } end
local function Distance (a, b) return math.sqrt ((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end

-- Flown by these hulls.
local function Fly (...)
	local moves = {}
	for hull = 0, Graph.NUM_HULLS - 1 do moves [hull] = 0 end
	for _, hull in ipairs ({ ... }) do moves [hull] = Graph.CAP_MOVE_FLY end
	return moves
end

-- Three air nodes in a row 500 apart, A-B and B-C flown by the tiny hull, A-C only by the large
-- one; a ground node beside A, walked to it.
local function Row ()
	return
	{
		nodes =
		{
			{ pos = P (0, 0), type = Graph.NODE_AIR },
			{ pos = P (500, 0), type = Graph.NODE_AIR },
			{ pos = P (1000, 0), type = Graph.NODE_AIR },
			{ pos = P (-50, 0, 8), type = Graph.NODE_GROUND }
		},
		links =
		{
			{ a = 1, b = 2, moves = Fly (TINY) },
			{ a = 2, b = 3, moves = Fly (TINY) },
			{ a = 1, b = 3, moves = Fly (LARGE) },
			{ a = 4, b = 1, moves = { [0] = Graph.CAP_MOVE_GROUND } }
		}
	}
end

-- It flies straight to whatever is within this of it.
local function Within (range) return function (a, b) return Distance (a, b) <= range end end

local function Xs (points)
	local xs = {}
	for i, p in ipairs (points) do xs [i] = p.x end
	return table.concat (xs, ",")
end

T.test ("its nodes are the graph's air nodes", function ()
	T.eq (Airways.New (Row (), TINY):Count (), 3, "the ground node left out")
end)

T.test ("what it can fly to straight, it flies to straight", function ()
	local route = Airways.New (Row (), TINY):Route (P (-100, 0), P (1100, 0), Within (5000))
	T.eq (Xs (route), "1100")
end)

T.test ("else from the air node nearest it to the one nearest its goal, by the links its hull flies", function ()
	local route = Airways.New (Row (), TINY):Route (P (-100, 0), P (1100, 0), Within (300))
	T.eq (Xs (route), "0,500,1000,1100", "A, B, C, then the goal: not A to C, which only the large hull flies")
	local large = Airways.New (Row (), LARGE):Route (P (-100, 0), P (1100, 0), Within (300))
	T.eq (Xs (large), "0,1000,1100", "the large hull flies A to C")
end)

T.test ("a ground node is never a way in, however near", function ()
	local route = Airways.New (Row (), TINY):Route (P (-60, 0, 8), P (1100, 0), Within (120))
	T.eq (Xs (route), "0,500,1000,1100", "from A, not the ground node beside it")
end)

T.test ("the nearest it cannot reach is passed over for the next", function ()
	local function Reach (a, b)
		if b.x == 0 then return false end -- A is behind glass
		return Distance (a, b) <= 700
	end
	local route = Airways.New (Row (), TINY):Route (P (-100, 0), P (1100, 0), Reach)
	T.eq (Xs (route), "500,1000,1100", "in at B")
end)

T.test ("no way between: no route", function ()
	local graph = Row ()
	table.remove (graph.links, 2)
	T.eq (Airways.New (graph, TINY):Route (P (-100, 0), P (1100, 0), Within (300)), nil)
	T.eq (Airways.New (Row (), TINY):Route (P (-100, 0), P (5000, 0), Within (300)), nil, "no node near its goal")
end)

T.test ("a course steers at its route's next point, and on as it reaches each", function ()
	local course = Airways.Course (Airways.New (Row (), TINY))
	local reach = Within (300)
	local goal = P (1100, 0)
	T.eq (course:Toward (P (-100, 0), goal, 0, reach).x,                             0,    "to A")
	T.eq (course:Toward (P (0 - Airways.WAYPOINT_REACH + 1, 0), goal, 0.1, reach).x, 500,  "A reached: to B")
	T.eq (course:Toward (P (480, 0), goal, 0.2, reach).x,                            1000, "B reached")
	T.eq (course:Toward (P (990, 0), goal, 0.3, reach).x,                            1100, "C reached: the goal")
end)

T.test ("a course plans again once its goal has moved, at most each REPLAN_INTERVAL", function ()
	local planned = 0
	local airways = Airways.New (Row (), TINY)
	local route = airways.Route
	function airways:Route (...)
		planned = planned + 1
		return route (self, ...)
	end
	local course = Airways.Course (airways)
	local reach = Within (300)
	course:Toward (P (-100, 0), P (1100, 0), 0,   reach)
	course:Toward (P (-100, 0), P (1100, 0), 0.1, reach)
	T.eq (planned, 1, "the same goal: the same route")
	course:Toward (P (-100, 0), P (1100, Airways.REPLAN_DISTANCE + 1), 0.2, reach)
	T.eq (planned, 1, "moved, but too soon")
	course:Toward (P (-100, 0), P (1100, Airways.REPLAN_DISTANCE + 1), Airways.REPLAN_INTERVAL, reach)
	T.eq (planned, 2, "moved, and its interval over")
end)

T.test ("with no airways, or no route, a course steers straight at its goal", function ()
	T.eq (Airways.Course (nil):Toward (P (0, 0), P (900, 0), 0, Within (1)).x, 900)
	local course = Airways.Course (Airways.New (Row (), TINY))
	T.eq (course:Toward (P (-100, 0), P (5000, 0), 0, Within (300)).x, 5000, "no route: straight, its traces bounce it")
end)

T.test ("its tolerances", function ()
	T.eq (Airways.WAYPOINT_REACH, 64, "ProgressFlyPath's strict point tolerance, as the scanner passes it")
	T.defined (Airways.REPLAN_DISTANCE, "REPLAN_DISTANCE")
	T.defined (Airways.REPLAN_INTERVAL, "REPLAN_INTERVAL")
	T.defined (Airways.NEAREST_TRIES,   "NEAREST_TRIES")
end)

T.finish ()
