local T = dofile("tests/harness.lua")

local SOURCE = T.ROOT .. "features/aiwar/sv_bot_soldier.lua"
local goal = { x = 1000, y = 0, z = 400 }
local position = { x = 0, y = 0, z = 0 }

local routeWalk = {
	Trivial = nextsoldier.locomotion.route_walk.Trivial,
	New = function(points)
		return {
			Next = function() return points[1] end,
		}
	end,
}

local environment = setmetatable({
	Vector = function(x, y, z) return { x = x, y = y, z = z } end,
	WS = {
		Feature = function()
			return { BlockerGeneration = function() return 0 end }
		end,
	},
	nextsoldier = {
		senses = { vision = {} },
		body = { player_body = {} },
		locomotion = {
			route_walk = routeWalk,
			RoundCorners = function(points) return points end,
		},
	},
	gameplay = { movement = {}, teams = {} },
}, { __index = _G })

local Map = {
	ToVector = function(point) return point end,
	Point = function(point) return point end,
	DoorOpenable = function() return false end,
	WALK_MAXS = { z = 72 },
	WALK_LIFT = { x = 0, y = 0, z = 0 },
	WALK_MAX_RISE = 18,
}
local BotSoldier = setfenv(assert(loadfile(SOURCE)), environment)(Map, {})

local function NewSoldier(route)
	local navigator = {
		Settled = function() return true end,
		PlanRoute = function() return route end,
	}
	local soldier = setmetatable({
		moveTarget = goal,
		ent = { GetPos = function() return position end },
		nextPlan = 0,
		Navigator = function() return navigator end,
		MeshGoal = function(_, target) return target end,
		RouteCost = function() return function() end end,
		RangeTo = function() return 1000 end,
		CanWalkTo = function() return false end,
	}, BotSoldier)
	return soldier
end

T.test("a failed route does not steer the bot directly at its goal", function()
	local soldier = NewSoldier(nil)
	soldier:Steer(1)
	T.eq(soldier.steer, nil, "wait for a route instead of bypassing obstacles")
	T.eq(soldier.planned, nil, "retry after the route interval")
end)

T.test("an exhausted partial route does not steer directly at its goal", function()
	local soldier = NewSoldier({})
	soldier:Steer(1)
	T.eq(soldier.steer, nil, "do not bypass obstacles after the last partial waypoint")
end)

T.test("the engine's trivial path, from where it stands straight to a far goal, is no route", function()
	local soldier = NewSoldier({ position, goal })
	soldier:Steer(1)
	T.eq(soldier.walk, nil, "not walked: it runs into whatever lies between")
	T.eq(soldier.steer, nil, "waits for a route, as when none was found")
	T.eq(soldier.planned, nil, "planned again after the route interval")
end)

T.test("a route run out short of its goal is planned again, not stood at", function()
	local soldier = NewSoldier(nil)
	-- its goal has moved less than it takes to plan anew, and the walk is over
	soldier.walk = { Next = function() return nil end, Stalled = function() return false end }
	soldier.planned, soldier.nextPlan = goal, 100
	soldier:Steer(2)
	T.eq(soldier.steer, nil, "nothing to walk to this moment")
	T.eq(soldier.planned, nil, "so it plans again")
end)

T.test("a found route steers to its first waypoint", function()
	local waypoint = { x = 200, y = 50, z = 0 }
	local soldier = NewSoldier({ waypoint, goal })
	soldier:Steer(1)
	T.eq(soldier.steer, waypoint, "follow the computed route")
end)

T.test("a nearby clear goal still uses the direct walk", function()
	local soldier = NewSoldier(nil)
	soldier.RangeTo = function() return 100 end
	soldier.CanWalkTo = function() return true end
	soldier:Steer(1)
	T.eq(soldier.steer, goal, "keep the short clear-walk behavior")
end)

T.finish()
