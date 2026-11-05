local T = dofile("tests/harness.lua")

local SOURCE = T.ROOT .. "features/aiwar/sv_bot_soldier.lua"
local goal = { x = 1000, y = 0, z = 400 }
local position = { x = 0, y = 0, z = 0 }

local routeWalk = {
	Trivial = nextsoldier.locomotion.route_walk.Trivial,
	New = function(points)
		return {
			Next = function() return points[1] end,
			Stalled = function() return false end,
		}
	end,
}

local Vec
local VectorMeta = { __add = function(a, b) return Vec(a.x + b.x, a.y + b.y, a.z + b.z) end, __sub = function(a, b) return Vec(a.x - b.x, a.y - b.y, a.z - b.z) end }
Vec = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, VectorMeta) end

local environment = setmetatable({
	Vector = Vec,
	util = {
		TraceHull = function() return { Hit = false } end,
		TraceLine = function(trace) return { Hit = trace.start.z ~= trace.endpos.z } end,
	},
	MASK_PLAYERSOLID = 1,
	CurTime = function() return 1 end,
	WS = {
		require = T.require,
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

local function NewSoldier(route, found)
	local navigator = {
		Settled = function() return true end,
		PlanRoute = function(self)
			self.plans = (self.plans or 0) + 1
			return route, found
		end,
	}
	local soldier = setmetatable({
		moveTarget = goal,
		ent = {
			GetPos = function() return position end,
			GetHull = function() return Vec(-24, -24, 0), Vec(24, 24, 82) end,
		},
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
end)

T.test("a straight path the engine found, within one area, is a route however far", function()
	local soldier = NewSoldier({ position, goal }, true)
	soldier:Steer(1)
	T.eq(soldier.walk ~= nil, true, "walked: a nav area has nothing in it to run into")
	T.eq(soldier.steer, position, "on its way")
end)

T.test("its route is planned again on a timer, whether or not its goal has moved", function()
	local soldier = NewSoldier({ { x = 200, y = 50, z = 0 }, goal })
	local navigator = soldier:Navigator()
	soldier:Steer(1)
	T.eq(navigator.plans, 1, "its first")
	soldier:Steer(1.5)
	T.eq(navigator.plans, 1, "not every look: not within the least of its interval")
	soldier:Steer(3.1)
	T.eq(navigator.plans, 2, "and again, its goal where it was")
end)

T.test("a route run out short of its goal is planned again, not stood at", function()
	local soldier = NewSoldier({ { x = 200, y = 50, z = 0 }, goal })
	local navigator = soldier:Navigator()
	soldier.walk = { Next = function() return nil end, Stalled = function() return false end }
	soldier.nextPlan = 2
	soldier:Steer(1)
	T.eq(soldier.steer, nil, "nothing to walk to this moment")
	soldier:Steer(2)
	T.eq(navigator.plans, 1, "so it has another")
	T.eq(soldier.steer ~= nil, true, "and goes on")
end)

T.test("its orders asking for a route brings the next one forward", function()
	local soldier = NewSoldier({ { x = 200, y = 50, z = 0 }, goal })
	soldier.nextPlan = 1000
	environment.CurTime = function() return 5 end
	soldier:Repath()
	T.eq(soldier.nextPlan <= 7, true, "not its far-off turn")
	local brought = soldier.nextPlan
	soldier:Repath()
	T.eq(soldier.nextPlan <= brought, true, "asking again does not put it off")
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

T.test("with nowhere to be it steps aside from a teammate, unless it has a fight to see to", function()
	local engine = nextsoldier.engine
	nextsoldier.engine = { GroupPush = function() return 1, 0 end }
	local soldier = NewSoldier(nil)
	soldier.moveTarget = nil
	soldier.ent.GetPos = function() return Vec(0, 0, 0) end
	soldier.HasEnemy = function() return false end
	soldier:Steer(1)
	T.eq(soldier.steer.x > 16, true, "aside")
	soldier.HasEnemy = function() return true end
	soldier:Steer(2)
	T.eq(soldier.steer, nil, "the fight is its body's to steer")
	nextsoldier.engine = engine
end)

T.finish()
