local T = dofile("tests/harness.lua")

-- The bot player's soldier (sv_next_soldiers.lua) over fakes of the player and the
-- engine: what it sweeps with and what it prices its routes by.
local Vec
local Methods = {}
function Methods:Distance(other) return math.geometry.Distance(self, other) end
local Meta = {
	__index = Methods,
	__add = function(a, b) return Vec(a.x + b.x, a.y + b.y, a.z + b.z) end,
	__sub = function(a, b) return Vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
}
Vec = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, Meta) end

local swept, planned, asked, ready
local verdicts = {}
local navigator = {
	Settled = function() return true end,
	PlanRoute = function(_, _, cost) planned = cost return { Vec(0, 0, 0), Vec(100, 0, 0) } end,
}
local function ValidPlayer()
	local ply = { NSNavigator = navigator }
	function ply:GetPos() return Vec(0, 0, 0) end
	function ply:Team() return 3 end
	function ply:EntIndex() return 7 end
	function ply:GetHull() return Vec(-24, -24, 0), Vec(24, 24, 82) end
	return ply
end
local added
local environment = setmetatable({
	Vector = Vec,
	IsValid = function(value) return value ~= nil end,
	CurTime = function() return 1 end,
	MASK_PLAYERSOLID = 1,
	util = { TraceHull = function(trace) swept = trace return { Hit = false } end, TraceLine = function() return { Hit = true } end },
	navmesh = { GetNearestNavArea = function() return nil end },
	hook = { Add = function() end },
	concommand = { Add = function() end },
	player = { CreateNextSoldier = function() return added end },
	wartactics = { scenarios = {} },
	WS = {
		TEAM_RED = 2,
		TEAM_BLUE = 3,
		SetPlayerTeam = function() end,
		require = function(name)
			if name == "features.flag.soldier" then return { Apply = function() end } end
			return T.require(name)
		end,
		ClipMasks = function() return { brushes = 1 } end,
		NavHullClearance = function()
			return {
				Area = function(_, area) return area ~= "narrow" end,
				Link = function(_, _, area) return area ~= "behind a frame" end,
			}
		end,
		Feature = function()
			return {
				EngineCost = function(_, team, strategy, limits, bot)
					asked = { team = team, strategy = strategy, limits = limits, bot = bot }
					return ready and function(area, fromArea, ladder, elevator, length, fits)
						verdicts[area] = fits
						return 1
					end or nil
				end,
			}
		end,
	},
	nextsoldier = setmetatable({
		engine = { Insert = function() end },
		behavior = { ctfbot = { Compile = function() return {} end, InitialAction = function() return {} end } },
	}, { __index = nextsoldier }),
}, { __index = _G })

setfenv(assert(loadfile(T.ROOT .. "sv_next_soldiers.lua")), environment)()

local function New()
	added = ValidPlayer()
	function added:KillSilent() end
	function added:Nick() return "bot" end
	local soldier
	environment.WS.AddNextSoldier(3, "bot")
	soldier = environment.WS.NextSoldierOf(added)
	return soldier
end

T.test("its walks are swept with its own width, not a narrower box", function()
	local soldier = New()
	soldier:WalkClear(Vec(0, 0, 0), Vec(100, 0, 0))
	T.eq(swept.mins.x, -24, "its shoulders, which catch on door frames")
	T.eq(swept.maxs.y, 24, "its shoulders, the other way")
end)

T.test("its routes are priced as TF2's bots are, over what its team knows", function()
	ready, planned = true, nil
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(asked.strategy, T.require("foundation.wetsands.path.tfbot"), "CTFBotPathCost")
	T.eq(asked.team, 3, "its team's")
	T.eq(asked.bot.team, 3, "its team's spawn rooms are its own")
	T.eq(planned ~= nil, true, "the route is priced")
end)

T.test("each step is told whether its body fits", function()
	ready, planned = true, nil
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	planned("open", "from")
	planned("narrow", "from")
	planned("behind a frame", "from")
	planned("up a ladder", "from", "ladder")
	T.eq(verdicts["open"], true, "room to pass")
	T.eq(verdicts["narrow"], false, "its body does not stand there")
	T.eq(verdicts["behind a frame"], false, "its shoulders catch on the way in")
	T.eq(verdicts["up a ladder"], true, "a ladder crosses no opening")
end)

T.test("no route is planned until the mesh is ready", function()
	ready, planned = false, nil
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(planned, nil, "a route without its price would walk into what TF2's refuses")
end)

T.test("a route's drop right below it is stepped off, past the ledge, not stood over", function()
	ready, planned = true, nil
	local soldier = New()
	local ledge = 30
	environment.util.TraceHull = function(trace)
		-- the floor ends at the ledge, and the landing lies far below it
		if trace.start.z == trace.endpos.z then return { Hit = false } end
		if trace.start.x + trace.mins.x < ledge then return { Hit = true, HitPos = trace.start } end
		if trace.endpos.z < -100 then return { Hit = true, HitPos = Vec(trace.start.x, trace.start.y, -188) } end
		return { Hit = false }
	end
	soldier.walk = {
		Stalled = function() return false end,
		Next = function() return { x = 20, y = 0, z = -188 } end,
	}
	soldier.planned = Vec(5000, 0, 0)
	soldier.nextPlan = 100
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(soldier.steer.z, 0, "a point on its own level")
	T.eq(soldier.steer.x - 24 >= ledge, true, "its whole body past the edge")
end)

T.test("a jamb beside its way veers its steering away", function()
	ready, planned = true, nil
	local soldier = New()
	environment.util.TraceHull = function(trace)
		-- going +x, its left is +y: a wall along that side
		return { Hit = trace.start.y > 0 }
	end
	soldier.walk = {
		Stalled = function() return false end,
		Next = function() return { x = 500, y = 0, z = 0 } end,
	}
	soldier.planned = Vec(5000, 0, 0)
	soldier.nextPlan = 100
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(soldier.steer.y < 0, true, "toward the open side")
end)

local function Route(points)
	navigator.PlanRoute = function(_, _, cost) planned = cost return points end
end

-- A pillar at x = 100 on the route's line: a floor everywhere, no wall but it.
local function BesidePillar(gap)
	environment.util.TraceHull = function(trace)
		local at = trace.start
		return { Hit = trace.start.x == trace.endpos.x and trace.start.y == trace.endpos.y
			and math.abs(at.x - 100) < 24 and math.abs(at.y) < 24 }
	end
	environment.util.TraceLine = function(trace)
		if trace.start.z ~= trace.endpos.z then return { Hit = not gap } end
		return { Hit = false }
	end
end

T.test("a route's point its body does not fit on is walked to where it does", function()
	ready, planned = true, nil
	BesidePillar(false)
	Route({ Vec(0, 0, 0), Vec(100, 0, 0), Vec(500, 0, 0) })
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	local point = soldier.walk.points[2]
	T.eq(math.abs(point.x - 100) >= 24 or math.abs(point.y) >= 24, true, "clear of the pillar")
end)

T.test("nor is a point moved off the floor to fit", function()
	ready, planned = true, nil
	BesidePillar(true)
	Route({ Vec(0, 0, 0), Vec(100, 0, 0), Vec(500, 0, 0) })
	local soldier = New()
	soldier:FollowPath(Vec(5000, 0, 0))
	soldier:Steer(1)
	T.eq(soldier.walk.points[2].x, 100, "no floor anywhere near: left as planned")
	T.eq(soldier.walk.points[2].y, 0, "left as planned")
end)

T.finish()
