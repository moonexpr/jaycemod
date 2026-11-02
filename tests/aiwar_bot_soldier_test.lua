local T = dofile("tests/harness.lua")

local SOURCE = T.ROOT .. "features/aiwar/sv_bot_soldier.lua"
local goal = { x = 1000, y = 0, z = 400 }
local position = { x = 0, y = 0, z = 0 }

local routeWalk = {
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
		vision = {},
		player_body = {},
		route_walk = routeWalk,
		corners = { Route = function(points) return points end },
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
