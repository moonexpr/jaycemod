local T = dofile ("tests/harness.lua")

local SOURCE = T.ROOT .. "features/aiwar/sv_bot_soldier.lua"
local goal = { x = 1000, y = 0, z = 400 }
local position = { x = 0, y = 0, z = 0 }

local routeWalk =
{
	Trivial = nextsoldier.locomotion.route_walk.Trivial,
	New = function (points)
		return
		{
			Next = function () return points [1] end,
			Stalled = function () return false end
		}
	end
}

-- The convars the bot soldier reads, by name: the cases below that plan through a navigator
-- have it use the engine's search, as ns_bots_routes_engine 1 does.
searches = { ns_bots_routes_engine = true }

local Vec
local VectorMeta = { __add = function (a, b) return Vec (a.x + b.x, a.y + b.y, a.z + b.z) end, __sub = function (a, b) return Vec (a.x - b.x, a.y - b.y, a.z - b.z) end }
Vec = function (x, y, z) return setmetatable ({ x = x, y = y, z = z }, VectorMeta) end

local environment = setmetatable (
	{
		Vector = Vec,
		util =
		{
			TraceHull = function () return { Hit = false } end,
			TraceLine = function (trace) return { Hit = trace.start.z ~= trace.endpos.z } end
		},
		MASK_PLAYERSOLID = 1,
		FCVAR_ARCHIVE = 128,
		CreateConVar = function (name)
			return { GetBool = function () return searches [name] == true end }
		end,
		IsValid = function (ent) return ent ~= nil and ent.gone ~= true end,
		CurTime = function () return 1 end,
		WS =
		{
			require = T.require,
			Feature = function ()
				return { BlockerGeneration = function () return 0 end }
			end
		},
		nextsoldier =
		{
			senses = { vision = {} },
			body = { player_body = {} },
			locomotion =
			{
				route_walk = routeWalk,
				RoundCorners = function (points) return points end
			}
		},
		gameplay = { movement = {}, teams = {} }
	}, { __index = _G })

local Map =
{
	ToVector = function (point) return point end,
	Point = function (point) return point end,
	DoorOpenable = function () return false end,
	WALK_MAXS = { z = 72 },
	WALK_LIFT = { x = 0, y = 0, z = 0 },
	WALK_MAX_RISE = 18
}
local BotSoldier = setfenv (assert (loadfile (SOURCE)), environment) (Map, {})

-- The war's planning time as these tests' looks need it: a plan made as it is asked for.
local AT_ONCE =
{
	Spawn = function (_, plan) plan () end,
	CheckYield = function () return false end
}

local function NewSoldier (route, found, plans)
	local navigator =
	{
		Settled = function () return true end,
		PlanRoute = function (self)
			self.plans = (self.plans or 0) + 1
			return route, found
		end
	}
	local soldier = setmetatable (
		{
			moveTarget = goal,
			controller = { plans = plans or AT_ONCE },
			ent =
			{
				GetPos = function () return position end,
				GetHull = function () return Vec (-24, -24, 0), Vec (24, 24, 82) end
			},
			nextPlan = 0,
			Navigator = function () return navigator end,
			MeshGoal = function (_, target) return target end,
			RouteCost = function () return function () end end,
			RangeTo = function () return 1000 end,
			CanWalkTo = function () return false end
		}, BotSoldier)
	return soldier
end

T.test ("a failed route does not steer the bot directly at its goal", function ()
	local soldier = NewSoldier (nil)
	soldier:Steer (1)
	T.eq (soldier.steer, nil, "wait for a route instead of bypassing obstacles")
end)

T.test ("an exhausted partial route does not steer directly at its goal", function ()
	local soldier = NewSoldier ({})
	soldier:Steer (1)
	T.eq (soldier.steer, nil, "do not bypass obstacles after the last partial waypoint")
end)

T.test ("the engine's trivial path, from where it stands straight to a far goal, is no route", function ()
	local soldier = NewSoldier ({ position, goal })
	soldier:Steer (1)
	T.eq (soldier.walk,  nil, "not walked: it runs into whatever lies between")
	T.eq (soldier.steer, nil, "waits for a route, as when none was found")
end)

T.test ("a straight path the engine found, within one area, is a route however far", function ()
	local soldier = NewSoldier ({ position, goal }, true)
	soldier:Steer (1)
	T.eq (soldier.walk ~= nil, true,     "walked: a nav area has nothing in it to run into")
	T.eq (soldier.steer,       position, "on its way")
end)

T.test ("its route is planned again on a timer, whether or not its goal has moved", function ()
	local soldier = NewSoldier ({ { x = 200, y = 50, z = 0 }, goal })
	local navigator = soldier:Navigator ()
	soldier:Steer (1)
	T.eq (navigator.plans, 1, "its first")
	soldier:Steer (1.5)
	T.eq (navigator.plans, 1, "not every look: not within the least of its interval")
	soldier:Steer (3.1)
	T.eq (navigator.plans, 2, "and again, its goal where it was")
end)

T.test ("a route run out short of its goal is planned again, not stood at", function ()
	local soldier = NewSoldier ({ { x = 200, y = 50, z = 0 }, goal })
	local navigator = soldier:Navigator ()
	soldier.walk = { Next = function () return nil end, Stalled = function () return false end }
	soldier.nextPlan = 2
	soldier:Steer (1)
	T.eq (soldier.steer, nil, "nothing to walk to this moment")
	soldier:Steer (2)
	T.eq (navigator.plans,      1,    "so it has another")
	T.eq (soldier.steer ~= nil, true, "and goes on")
end)

T.test ("its orders asking for a route brings the next one forward", function ()
	local soldier = NewSoldier ({ { x = 200, y = 50, z = 0 }, goal })
	soldier.nextPlan = 1000
	environment.CurTime = function () return 5 end
	soldier:Repath ()
	T.eq (soldier.nextPlan <= 7, true, "not its far-off turn")
	local brought = soldier.nextPlan
	soldier:Repath ()
	T.eq (soldier.nextPlan <= brought, true, "asking again does not put it off")
end)

T.test ("a found route steers to its first waypoint", function ()
	local waypoint = { x = 200, y = 50, z = 0 }
	local soldier = NewSoldier ({ waypoint, goal })
	soldier:Steer (1)
	T.eq (soldier.steer, waypoint, "follow the computed route")
end)

T.test ("a nearby clear goal still uses the direct walk", function ()
	local soldier = NewSoldier (nil)
	soldier.RangeTo = function () return 100 end
	soldier.CanWalkTo = function () return true end
	soldier:Steer (1)
	T.eq (soldier.steer, goal, "keep the short clear-walk behavior")
end)

T.test ("with nowhere to be it steps aside from a teammate, unless it has a fight to see to", function ()
	local engine = nextsoldier.engine
	nextsoldier.engine = { GroupPush = function () return 1, 0 end }
	local soldier = NewSoldier (nil)
	soldier.moveTarget = nil
	soldier.ent.GetPos = function () return Vec (0, 0, 0) end
	soldier.HasEnemy = function () return false end
	soldier:Steer (1)
	T.eq (soldier.steer.x > 16, true, "aside")
	soldier.HasEnemy = function () return true end
	soldier:Steer (2)
	T.eq (soldier.steer, nil, "the fight is its body's to steer")
	nextsoldier.engine = engine
end)

-- Its routes' price: the npc controller's EngineCost, a fake here that keeps what it was asked and
-- answers with the fit each step was told.
local function Pricing (ready)
	local asked = {}
	local shut = { areas = { [7] = true }, stamp = 3 }
	local npcs =
	{
		BlockerGeneration = function () return 0 end,
		EngineCost = function (_, team, strategy, limits, bot, also)
			asked.team, asked.strategy, asked.limits, asked.bot, asked.also = team, strategy, limits, bot, also
			if not ready then return nil end
			return function (_, _, _, _, _, fits) return fits end
		end
	}
	local clearance =
	{
		Area = function (_, area) return area.fits end,
		Link = function (_, _, area)
			asked.links = (asked.links or 0) + 1
			return area.opening
		end
	}
	local feature, hull, masks = environment.WS.Feature, environment.WS.NavHullClearance, environment.WS.ClipMasks
	local convar, reach = environment.GetConVarNumber, environment.gameplay.movement.JumpReach
	environment.WS.Feature = function () return npcs end
	environment.WS.NavHullClearance = function () return clearance end
	environment.WS.ClipMasks = function () return { brushes = 1 } end
	environment.GetConVarNumber = function () return 800 end
	environment.gameplay.movement.JumpReach = function (power) return power / 4 end
	local soldier = setmetatable (
		{
			team = 3,
			controller = { ShutDoorAreas = function (_, team) return team == 3 and shut or nil end },
			ent =
			{
				EntIndex = function () return 12 end,
				GetHull = function () return Vec (-24, -24, 0), Vec (24, 24, 82) end,
				GetHullDuck = function () return Vec (-24, -24, 0), Vec (24, 24, 62) end,
				GetGravity = function () return 1 end,
				GetJumpPower = function () return 280 end
			}
		}, BotSoldier)
	local cost = soldier:RouteCost ()
	environment.WS.Feature, environment.WS.NavHullClearance, environment.WS.ClipMasks = feature, hull, masks
	environment.GetConVarNumber, environment.gameplay.movement.JumpReach = convar, reach
	return cost, asked, shut
end

T.test ("its routes are priced as TF2's bots' are, at its body's limits, past the doors shut to its team", function ()
	local TFBot = T.require ("foundation.wetsands.path.tfbot")
	local _, asked, shut = Pricing (true)
	T.eq (asked.team, 3, "for its team")
	T.eq (asked.strategy, TFBot, "TF2's bot's cost")
	T.eq (asked.also, shut, "the doors the war found shut to its team are closed to it")
	T.eq (asked.limits.jumpHeight, 70, "it climbs what its own crouch jump reaches")
	T.eq (asked.limits.ladders, true, "and ladders, as a player does")
	T.eq (asked.limits.stepHeight > 0 and asked.limits.stepHeight < asked.limits.jumpHeight, true, "a stair is no jump")
	T.eq (asked.limits.deathDropHeight > asked.limits.jumpHeight, true, "it drops farther than it climbs")
	T.eq (asked.bot.team, 3, "the enemy's spawn rooms are closed to its team")
	T.eq (asked.bot.route, TFBot.FASTEST_ROUTE, "the shortest way, no scatter")
	T.eq (asked.bot.roundWon, false, "and stay closed")
	T.eq (asked.bot.entIndex, 12, "its own")
end)

T.test ("each step is told whether its body fits: the area, and the opening into it but for a ladder's", function ()
	local cost, asked = Pricing (true)
	local from, ladder = { fits = true, opening = true }, {}
	T.eq (cost ({ fits = true, opening = true }, nil),   nil,   "its first area: nothing to fit through")
	T.eq (cost ({ fits = true, opening = true }, from),  true,  "an area and opening it fits")
	T.eq (cost ({ fits = false, opening = true }, from), false, "an area its body does not fit in")
	T.eq (cost ({ fits = true, opening = false }, from), false, "an opening its body does not pass")
	local links = asked.links
	T.eq (cost ({ fits = true, opening = false }, from, ladder), true,  "a ladder has no opening to pass")
	T.eq (asked.links,                                           links, "so none is measured")
end)

T.test ("while its routes cannot be priced yet it plans none, and plans as soon as they can", function ()
	T.eq (Pricing (false), nil, "no price while the mesh is not ready")
	local soldier = NewSoldier ({ { x = 200, y = 50, z = 0 }, goal })
	local navigator = soldier:Navigator ()
	local kept = { Next = function () return nil end, Stalled = function () return false end }
	soldier.walk = kept
	soldier.RouteCost = function () return nil end
	soldier:Steer (1)
	T.eq (navigator.plans, nil,  "the engine is not asked for a route it cannot price")
	T.eq (soldier.walk,    kept, "the route it had is kept")
	soldier.RouteCost = function () return function () end end
	soldier:Steer (1.1)
	T.eq (navigator.plans, 1, "planned at its next look, not a whole interval later")
end)

-- A route with turns enough to clean up, and a clock every hull trace of the clean-up takes a
-- millisecond of: the war's planning time (list.schedule) is then spent within a few traces.
local WINDING =
{
	{ x = 0, y = 0, z = 0 },
	{ x = 300, y = 0, z = 0 },
	{ x = 300, y = 300, z = 0 },
	{ x = 600, y = 300, z = 0 },
	{ x = 600, y = 600, z = 0 },
	{ x = 900, y = 600, z = 0 }
}
local PLANNING_SLICE = 0.002

local function Planning ()
	local clock = { at = 0 }
	function clock:Now () return self.at end
	local plans = list.schedule.New (clock)
	local soldier = NewSoldier (WINDING, true, plans)
	local hull = environment.util.TraceHull
	local traced = 0
	environment.util.TraceHull = function (trace)
		traced = traced + 1
		clock.at = clock.at + 0.001
		return hull (trace)
	end
	local function Run ()
		local runs = 0
		while plans:Count () > 0 do
			plans:Run (PLANNING_SLICE)
			runs = runs + 1
			if runs > 1000 then error ("the plan never finished") end
		end
		return runs
	end
	local function Done ()
		environment.util.TraceHull = hull
		return traced
	end
	return soldier, plans, Run, Done
end

T.test ("a look asks for its route and goes on: the route is planned in the war's planning time", function ()
	local soldier, plans, Run, Done = Planning ()
	local navigator = soldier:Navigator ()
	soldier:Steer (1)
	T.eq (navigator.plans, nil, "the look did not search")
	T.eq (soldier.walk,    nil, "nor has it a route yet")
	plans:Run (PLANNING_SLICE)
	T.eq (navigator.plans, 1, "the planning time did")
	Run ()
	T.eq (soldier.walk ~= nil, true, "and its route is its to walk")
	T.eq (Done () > 0,         true, "cleaned up for its body on the way")
end)

T.test ("a plan's clean-up gives way once the planning time is spent, and goes on in the next", function ()
	local soldier, plans, Run, Done = Planning ()
	soldier:Steer (1)
	plans:Run (PLANNING_SLICE)
	T.eq (soldier.walk,   nil, "not finished in one slice")
	T.eq (plans:Count (), 1,   "still under way")
	Run ()
	Done ()
	T.eq (soldier.walk ~= nil, true, "finished in those after")
end)

T.test ("a plan takes as many slices as its clean-up needs, none of them much over", function ()
	local soldier, plans, Run, Done = Planning ()
	soldier:Steer (1)
	local runs = Run ()
	local traced = Done ()
	T.eq (soldier.walk ~= nil, true, "finished")
	T.eq (runs > 1,            true, "over more than one slice")
	-- a millisecond a trace: a slice lets through the traces its time holds and the one that spends it
	T.eq (traced <= runs * (PLANNING_SLICE / 0.001 + 1), true, "no slice ran on past its time")
end)

T.test ("it asks for one route at a time, however many looks pass while it is planned", function ()
	local soldier, plans, Run, Done = Planning ()
	local navigator = soldier:Navigator ()
	soldier:Steer (1)
	soldier:Steer (3.1)
	soldier:Steer (4)
	Run ()
	Done ()
	T.eq (navigator.plans, 1, "one search")
end)

T.test ("set down elsewhere while its route is planned, the plan is dropped and not walked", function ()
	local soldier, plans, Run, Done = Planning ()
	soldier:Steer (1)
	plans:Run (PLANNING_SLICE)
	soldier.ent.GetPos = function () return { x = 5000, y = 5000, z = 0 } end
	soldier:Steer (1.2)
	Run ()
	Done ()
	T.eq (soldier.walk, nil, "a route from where it no longer stands is no route")
end)

T.test ("a bot gone while its route is planned ends the plan quietly", function ()
	local soldier, plans, Run, Done = Planning ()
	soldier:Steer (1)
	plans:Run (PLANNING_SLICE)
	local before = Done ()
	soldier.ent.gone = true
	local traced = 0
	local hull = environment.util.TraceHull
	environment.util.TraceHull = function (trace)
		traced = traced + 1
		return hull (trace)
	end
	Run ()
	environment.util.TraceHull = hull
	T.eq (before > 0,   true, "it was under way")
	T.eq (traced,       0,    "nothing more is traced for a body that is not there")
	T.eq (soldier.walk, nil,  "and no route is kept")
end)

T.test ("a plan that fails is raised where the plans are run, and its bot asks again", function ()
	local soldier, plans, Run, Done = Planning ()
	local navigator = soldier:Navigator ()
	local planRoute = navigator.PlanRoute
	navigator.PlanRoute = function () error ("the search broke") end
	soldier:Steer (1)
	local ok, why = pcall (plans.Run, plans, PLANNING_SLICE)
	T.eq (ok,                                                               false, "our bug is not swallowed")
	T.eq (string.find (tostring (why), "the search broke", 1, true) ~= nil, true,  "and says what broke")
	navigator.PlanRoute = planRoute
	soldier:Steer (10)
	Run ()
	Done ()
	T.eq (navigator.plans,     1,    "it asked again")
	T.eq (soldier.walk ~= nil, true, "and has its route")
end)

-- The war's own search (the npc controller's RequestRoute and RouteWaypoints), a fake that keeps
-- what it was asked and answers when the test says.
local function Searching ()
	local asked = { requests = 0 }
	local clearance = { Area = function () return true end, Link = function () return true end }
	local npcs =
	{
		BlockerGeneration = function () return 0 end,
		RequestRoute = function (_, request)
			asked.requests = asked.requests + 1
			asked.request = request
		end,
		RouteWaypoints = function (_, areas, to, found, from)
			asked.waypoints = { areas = areas, to = to, found = found, from = from }
			return { { x = 200, y = 50, z = 0 }, to }
		end
	}
	local saved =
	{
		engine = searches.ns_bots_routes_engine,
		feature = environment.WS.Feature,
		hull = environment.WS.NavHullClearance,
		masks = environment.WS.ClipMasks,
		crossable = environment.WS.NavLinkCrossable,
		convar = environment.GetConVarNumber,
		reach = environment.gameplay.movement.JumpReach
	}
	searches.ns_bots_routes_engine = false
	environment.WS.Feature = function () return npcs end
	environment.WS.NavHullClearance = function () return clearance end
	environment.WS.ClipMasks = function () return { brushes = 1 } end
	environment.WS.NavLinkCrossable = function () return true end
	environment.GetConVarNumber = function () return 800 end
	environment.gameplay.movement.JumpReach = function (power) return power / 4 end
	local soldier = NewSoldier (nil)
	soldier.team = 3
	soldier.RouteCost = nil
	soldier.Navigator = function () error ("a bot that plans on the mesh needs no navigator") end
	soldier.controller.ShutDoorIn = function (_, area, team) return area.shut == true and team == 3 end
	soldier.ent.EntIndex = function () return 12 end
	soldier.ent.GetHullDuck = function () return Vec (-24, -24, 0), Vec (24, 24, 62) end
	soldier.ent.GetGravity = function () return 1 end
	soldier.ent.GetJumpPower = function () return 280 end
	local function Done ()
		searches.ns_bots_routes_engine = saved.engine
		environment.WS.Feature, environment.WS.NavHullClearance, environment.WS.ClipMasks = saved.feature, saved.hull, saved.masks
		environment.WS.NavLinkCrossable, environment.GetConVarNumber = saved.crossable, saved.convar
		environment.gameplay.movement.JumpReach = saved.reach
	end
	return soldier, asked, clearance, Done
end

T.test ("it asks the war's own search for its route: its body's limits and fit, the doors shut to it", function ()
	local TFBot = T.require ("foundation.wetsands.path.tfbot")
	local soldier, asked, clearance, Done = Searching ()
	soldier:Steer (1)
	local request = asked.request
	T.eq (asked.requests,                        1, "one search asked")
	T.eq (request.from.x .. " " .. request.to.x, position.x .. " " .. goal.x, "from where it stands to its goal")
	T.eq (request.strategy,                      TFBot, "priced as TF2's bots' are")
	T.eq (request.limits.jumpHeight,             70, "what its own crouch jump reaches")
	T.eq (request.limits.ladders,                true, "and ladders")
	T.eq (request.bot.team,                      3, "the enemy's spawn rooms closed to its team")
	T.eq (request.bot.route,                     TFBot.FASTEST_ROUTE, "the shortest way")
	T.eq (request.body,                          clearance, "an area or opening its body does not fit is routed around")
	T.eq (request.crossable,                     environment.WS.NavLinkCrossable, "the map's own uncrossable links, as the search is told them")
	T.eq (request.avoid ({ shut = true }),       true, "a door shut to its team is routed around")
	T.eq (request.avoid ({ shut = false }),      false, "an open way is not")
	soldier:Steer (1.2)
	T.eq (asked.requests, 1, "and no other while it is searched")
	Done ()
end)

T.test ("the search's answer is its route, walked from where it stood", function ()
	local soldier, asked, _, Done = Searching ()
	soldier:Steer (1)
	local areas = { "an area", "another" }
	asked.request.onDone (areas, true)
	T.eq (asked.waypoints.areas,                                 areas, "its areas' points")
	T.eq (asked.waypoints.found,                                 true, "to its goal")
	T.eq (asked.waypoints.from.x .. " " .. asked.waypoints.to.x, position.x .. " " .. goal.x, "from where it stood")
	T.eq (soldier.walk ~= nil,                                   true, "its to walk")
	T.eq (soldier.plan,                                          nil, "and it may ask for its next")
	soldier:Steer (1.2)
	T.eq (soldier.steer.x, 200, "on its way to the first point")
	Done ()
end)

T.test ("a search that finds no way leaves it no route, and it asks again in its turn", function ()
	local soldier, asked, _, Done = Searching ()
	soldier.walk = { Next = function () return nil end, Stalled = function () return false end }
	soldier:Steer (1)
	asked.request.onDone (nil)
	T.eq (soldier.walk, nil, "no route")
	T.eq (soldier.plan, nil, "free to ask")
	soldier:Steer (10)
	T.eq (asked.requests, 2, "asked again")
	Done ()
end)

T.test ("made ready, it gets a navigator only when the engine's search plans its routes", function ()
	local soldier, _, _, Done = Searching ()
	soldier:PrepareRoutes ()
	Done ()
	local made = 0
	soldier.Navigator = function () made = made + 1 end
	soldier:PrepareRoutes ()
	T.eq (made, 1, "the engine's search starts from its navigator, which must learn where it stands")
end)

T.test ("a search that never answers is given up, and its late answer is not walked", function ()
	local soldier, asked, _, Done = Searching ()
	soldier:Steer (1)
	local first = asked.request
	T.defined (BotSoldier.PLAN_PATIENCE, "how long it waits for a route")
	soldier:Steer (1 + BotSoldier.PLAN_PATIENCE / 2)
	T.eq (asked.requests, 1, "still waited for within its patience")
	soldier:Steer (1 + BotSoldier.PLAN_PATIENCE + 0.1)
	T.eq (asked.requests, 2, "given up and asked afresh once it is spent")
	first.onDone ({ "an area" }, true)
	T.eq (soldier.walk, nil, "the answer it gave up on is no route of its")
	Done ()
end)

T.finish ()
