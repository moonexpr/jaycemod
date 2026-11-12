-- Part of the AI war controller (sv.lua): the soldier port
-- (nextsoldier.behavior) over a bot player (player.CreateNextBot, kept
-- by tf_bot_quota: sv_bots.lua), beside sv_soldier.lua's over a DrGBase
-- NextBot. It is that port where the two agree (routes, cover, kits,
-- gadgets, health kits) and differs where the body does: it walks a route
-- of its own to the goal its orders give (as DrGBase plans its own), sees
-- and fights through its vision and body (nextsoldier.senses.vision,
-- player_body; sv_bots.lua presses its keys), and neither sits on carts
-- nor takes poses.
local Map, Soldier = ...
local Vision = nextsoldier.senses.vision
local PlayerBody = nextsoldier.body.player_body
local Movement = gameplay.movement
local RouteWalk = nextsoldier.locomotion.route_walk
local Locomotion = nextsoldier.locomotion
local Geometry = math.geometry
local TFBot = WS.require ("foundation.wetsands.path.tfbot")
local ToVector, Point = Map.ToVector, Map.Point
local DoorOpenable = Map.DoorOpenable
local WALK_MAXS, WALK_LIFT, WALK_MAX_RISE = Map.WALK_MAXS, Map.WALK_LIFT, Map.WALK_MAX_RISE

-- How long it keeps the jump key's wish when its orders ask a hop: long
-- enough to land on the ground and press it.
local HOP_WISH = 0.5
-- A hop's way is swept this high (a crouch jump's lift: a player's jump with
-- its legs tucked), and a bot hops at most once in HOP_RETRY seconds.
local HOP_CLEAR = Vector (0, 0, 56)
local HOP_RETRY = 6
-- How long it remembers an enemy out of sight, where last seen.
local MEMORY = 5
-- Its own routes (Steer): asked again every REPATH_LEAST to REPATH_MOST seconds, as TF2's
-- actions do theirs, its goal moved or not; a goal within DIRECT_RANGE in a clear line is
-- walked straight at (the orders' CHASE_RANGE).
local REPATH_LEAST, REPATH_MOST = 1, 2
-- Moved farther than this between two looks, it was set down elsewhere (a
-- respawn, a side swap, a bench): its route is dropped and planned anew.
local TELEPORTED = 256
-- Set down elsewhere or pinned, it plans no sooner than this after: its
-- navigator follows it on its next think and the engine catches the
-- navigator's area up after that.
local SETTLE_DELAY = 0.5
local DIRECT_RANGE = 256
-- How long it waits for a route it asked for before asking afresh: a search starved or lost
-- shows as a bot asking again, not one standing still.
local PLAN_PATIENCE = 5
-- Which search plans a bot's routes: the war's own (0), or the engine's through a navigator (1),
-- as before the war's own took ladders and a body's fit; kept to compare the two.
local ENGINE_ROUTES = CreateConVar ("ns_bots_routes_engine", "0", FCVAR_ARCHIVE,
	"Whether the AI war's bot players plan routes with the engine's search (1) or the war's own asynchronous one (0)")
local FIRST_PLAN = 0.3
-- What a player's body climbs and falls (RouteCost): a stair step, a crouch
-- jump (JumpReachOf), the fall it survives unhurt.
local STEP_HEIGHT, SAFE_DROP = 18, 300
-- A straight walk's floor is looked for from a step above its line to two
-- below (CanWalkTo): a stair up or down the way is floor, a ledge's edge not.
local FOOTING_ABOVE, FOOTING_BELOW = Vector (0, 0, STEP_HEIGHT), Vector (0, 0, 2 * STEP_HEIGHT)

-- A goal off the mesh is walked to as the nearest point of an area within
-- OFF_MESH_NEAR of it (a flag a unit past its area's edge: ctf_2fort's
-- intel, which sent couriers to a point beside themselves), else as the
-- first point on the mesh along the line back from it toward the bot,
-- looked for OFF_MESH_STEP apart up to OFF_MESH_BACK (a guard's spot on a
-- ring round its charge that falls in or behind a wall: else the bot
-- presses into the wall for as long as it guards), else as itself, which
-- the route search takes to its nearest area.
local OFF_MESH_STEP, OFF_MESH_HEIGHT, OFF_MESH_LIFT = 16, 60, Vector (0, 0, 20)
local OFF_MESH_NEAR, OFF_MESH_BACK = 64, 256

local function OnMesh (p) return navmesh.GetNavArea (p + OFF_MESH_LIFT, OFF_MESH_HEIGHT) ~= nil end

-- A trace filter passing whoever walks about: players and NPCs.
local function Unmoving (ent) return not (ent:IsPlayer () or ent:IsNPC () or ent:IsNextBot ()) end

local BotSoldier = setmetatable ({}, { __index = Soldier })
BotSoldier.__index = BotSoldier
BotSoldier.PLAN_PATIENCE = PLAN_PATIENCE
WS.require ("features.npc.bot_steering").Apply (BotSoldier, { util = util, Vector = Vector, mask = MASK_PLAYERSOLID })

-- reaction: the difficulty's (features.aiwar.marksmanship), before it
-- recognizes an enemy it sees.
function BotSoldier.New (ent, controller, team, reaction)
	return setmetatable (
		{
			ent = ent,
			controller = controller,
			team = team,
			ticket = 0,
			result = nil,
			moveTarget = nil,
			relations = {},
			vision = Vision.New (
				{
					reaction = reaction,
					memory = MEMORY
				}
			),
			body = PlayerBody.New (),
			look = nil, -- where it faces with no enemy (Watch), a Vector
			hopUntil = 0,
			steer = nil, -- the point its body makes for (Steer)
			walk = nil, -- the route of its own it walks (nextsoldier.locomotion.route_walk)
			plan = nil, -- its route being planned (PlanRoute), or nil
			-- its first route waits a moment: a navigator just made knows no nav area yet
			nextPlan = CurTime () + FIRST_PLAN,
			mayFire = false, -- its orders let it fire at its contact (sv_bots.lua asks them)
			loadout = nil, -- features.aiwar.arms' loadout it carries (KitBot)
			wantWeapon = nil -- the weapon its contact's distance calls for
		}, BotSoldier)
end

function BotSoldier:IsAlive () return IsValid (self.ent) and self.ent:Alive () end

-- The enemy it fights: its vision's contact, while the enemy lives.
function BotSoldier:Enemy ()
	local enemy = self.vision:Contact ()
	return IsValid (enemy) and enemy or nil
end

function BotSoldier:HasEnemy ()
	local enemy = self:Enemy ()
	return enemy ~= nil and self.vision:Visible (enemy)
end

function BotSoldier:DoorToOpen ()
	local door = self.doorAhead
	if not DoorOpenable (door) then return nil end
	return Point (door:WorldSpaceCenter ())
end

function BotSoldier:EnemyHealth ()
	local enemy = self:Enemy ()
	if not enemy or enemy:Health () <= 0 then return nil end
	return enemy:Health () / math.max (enemy:GetMaxHealth (), 1)
end

-- Where its enemy is: in sight, where it stands; out of it, where it was
-- last seen.
function BotSoldier:EnemyPosition ()
	local enemy = self:Enemy ()
	if not enemy then return nil end
	if self.vision:Visible (enemy) then return Point (enemy:GetPos ()) end
	return (self.vision:LastKnown (enemy))
end

-- A player's body plans its own way, as DrGBase's does: the orders give it
-- the goal itself (their Chase), and it walks a route of its own there
-- (nextsoldier.locomotion.route_walk), or straight at a goal near and in a clear
-- line. The route is asked of the war's own asynchronous search (MeshSearch), or of
-- the engine's through its navigator (EngineSearch, ns_bots_routes_engine 1), and
-- cleaned up for its body in the war's planning time (PlanRoute), never in the look
-- that asks. It is planned again on a timer (REPATH_LEAST to REPATH_MOST), sooner
-- when its orders ask (Repath).
function BotSoldier:PlansRoutes () return true end

-- Its navigator, made with its first route and kept with the bot player
-- across its lives (it goes when the bot does).
function BotSoldier:Navigator ()
	local ply = self.ent
	if IsValid (ply.NSNavigator) then return ply.NSNavigator end
	local navigator = ents.Create ("ws_bot_navigator")
	navigator:SetOwner (ply)
	navigator:SetPos (ply:GetPos ())
	navigator:Spawn ()
	ply.NSNavigator = navigator
	return navigator
end

-- How high ply's crouch jump reaches, from its own jump power, gravity and
-- hulls (Movement.JumpReach): TF2's body, 72; GMod's, about 69.
local function JumpReachOf (ply)
	local _, stand = ply:GetHull ()
	local _, duck = ply:GetHullDuck ()
	local scale = ply:GetGravity ()
	local gravity = GetConVarNumber ("sv_gravity") * (scale ~= 0 and scale or 1)
	return Movement.JumpReach (ply:GetJumpPower (), gravity, stand.z, duck.z)
end

-- Its body's limits for a route: a stair, its crouch jump, the fall it survives unhurt, and
-- ladders. One table a reach, so bodies alike ask their searches with the same limits (the
-- searches' reach memo keys a request by them).
local limitsByReach = {}

local function LimitsOf (ply)
	local reach = JumpReachOf (ply)
	local limits = limitsByReach [reach]
	if not limits then
		limits = { stepHeight = STEP_HEIGHT, jumpHeight = reach, deathDropHeight = SAFE_DROP, ladders = true }
		limitsByReach [reach] = limits
	end
	return limits
end

-- Who a route is priced for (wetsands.path.tfbot's bot): the shortest way, the enemy's spawn
-- rooms closed to its team, their visualizers stopping players.
function BotSoldier:PathBot ()
	return
	{
		entIndex = self.ent:EntIndex (),
		now = CurTime (),
		team = self.team,
		route = TFBot.FASTEST_ROUTE,
		miniBoss = false,
		roundWon = false
	}
end

-- Whether its body fits an area and the opening into one: the shared primitive, by its own hull.
function BotSoldier:Body ()
	return WS.NavHullClearance (self.ent, WS.ClipMasks ().brushes)
end

-- What the engine's search prices a route by (Path:Compute's generator), or nil until the mesh
-- is ready to price one: TF2's bots' own cost (wetsands.path.tfbot: a jump dearer than its
-- length) priced natively over what its team knows (the npc controller's EngineCost: the areas
-- its doors and brushes close to it, the links a clip or a wall's end refuses) and the doors the
-- war found shut to it, at its own body's limits. Each step is told whether its body fits the
-- area and the opening into it; a ladder has no opening.
function BotSoldier:RouteCost ()
	local cost = WS.Feature ("npc"):EngineCost (self.team, TFBot, LimitsOf (self.ent), self:PathBot (),
		self.controller:ShutDoorAreas (self.team))
	if not cost then return nil end
	local clearance = self:Body ()
	return function (area, fromArea, ladder, elevator, length)
		local fits
		if fromArea then
			fits = clearance:Area (area)
			if fits and not ladder then fits = clearance:Link (fromArea, area) end
		end
		return cost (area, fromArea, ladder, elevator, length, fits)
	end
end

-- How its routes are searched for: search(goal, pos, plan), which answers plan:Answer(route,
-- found) with the route's points (Vectors; nil for none) when it has them, or nil while a
-- search cannot be asked yet.
--
-- The war's own search (the npc controller's RequestRoute: asynchronous, native, a slice a
-- tick), asked as the look asks: priced as RouteCost prices, told the doors shut to its team
-- and its body's fit as rules, from where it stands. No navigator is made.
function BotSoldier:MeshSearch ()
	local npcs, controller, team = WS.Feature ("npc"), self.controller, self.team
	return function (goal, pos, plan)
		local from, to = ToVector (pos), ToVector (goal)
		npcs:RequestRoute (
			{
				from = from,
				to = to,
				strategy = TFBot,
				limits = LimitsOf (self.ent),
				bot = self:PathBot (),
				avoid = function (area) return controller:ShutDoorIn (area, team) end,
				crossable = WS.NavLinkCrossable,
				body = self:Body (),
				onDone = function (areas, found)
					if not areas then return plan:Answer (nil, false) end
					plan:Answer (npcs:RouteWaypoints (areas, to, found, from), found)
				end
			}
		)
	end
end

-- The engine's search (ns_bots_routes_engine 1), through its navigator: one step of the war's
-- planning time that cannot give way. Not until the navigator knows where it stands
-- (Path:Compute starts at its last known area), nor while a route cannot be priced.
function BotSoldier:EngineSearch ()
	local navigator = self:Navigator ()
	local cost = navigator:Settled () and self:RouteCost ()
	if not cost then return nil end
	return function (goal, _, plan)
		plan:Task (function ()
			if plan.Mine () then plan:Answer (navigator:PlanRoute (ToVector (goal), cost)) end
		end)
	end
end

-- As it is enlisted: the engine's search starts from its navigator, which learns where it
-- stands before its first route; the war's own search needs none, and none is made.
function BotSoldier:PrepareRoutes ()
	if ENGINE_ROUTES:GetBool () then self:Navigator () end
end

function BotSoldier:RouteSearch ()
	if ENGINE_ROUTES:GetBool () then return self:EngineSearch () end
	return self:MeshSearch ()
end

function BotSoldier:MoveTo (p, gait)
	if self.pin then return end
	self.moveTarget = p
	self.gait = gait or "run"
end

function BotSoldier:Release ()
	if self.pin then return end
	self.moveTarget = nil
	self.steer = nil
	self.walkSpeed = 0
end

-- A bench's pin (ns_bots_goto): sent to p at a run whatever its orders
-- say, its route planned afresh, until unpinned (ns_bots_release).
function BotSoldier:Pin (p)
	self.pin = p
	self.moveTarget, self.gait = p, "run"
	-- the route it was on goes; the new one is planned once it has settled
	self.walk, self.plan, self.steer, self.nextPlan = nil, nil, nil, CurTime () + SETTLE_DELAY
end

function BotSoldier:Unpin ()
	self.pin = nil
end

function BotSoldier:Repath () self.nextPlan = math.min (self.nextPlan, CurTime () + REPATH_LEAST) end

-- Where to walk for goal (a point): itself on the mesh, else the nearest
-- point of an area close to it, else the first point on the mesh back from
-- it toward where it stands, not far back, else itself.
function BotSoldier:MeshGoal (goal)
	local to = ToVector (goal)
	if OnMesh (to) then return goal end
	local area = navmesh.GetNearestNavArea (to, false, OFF_MESH_NEAR, false, true)
	if IsValid (area) then
		local near = area:GetClosestPointOnArea (to)
		if near:Distance (to) <= OFF_MESH_NEAR then return Point (near) end
	end
	local from = self.ent:GetPos ()
	local length = from:Distance (to)
	for along = OFF_MESH_STEP, math.min (length, OFF_MESH_BACK), OFF_MESH_STEP do
		local p = to + (from - to) * (along / length)
		if OnMesh (p) then return Point (p) end
	end
	return goal
end

-- Its route to goal from pos, asked of search (RouteSearch) and not planned in the look that
-- asks: the search answers in its own time, then the clean-up for its own body runs in the
-- war's planning time (the controller's plans, a list.schedule run a slice a tick), giving way
-- between its traces once the tick's slice is spent. The route is its to walk when the plan is
-- done; until then it keeps the one it has. A plan dropped meanwhile (self.plan another's or
-- none: set down elsewhere, pinned, given up after PLAN_PATIENCE) or whose bot is gone traces
-- no more and leaves nothing; one that fails (our bug, raised where the plans are run) leaves
-- the bot free to ask for its next.
function BotSoldier:PlanRoute (goal, pos, search, now)
	local plans = self.controller.plans
	local plan = { at = now }
	self.plan = plan
	local function Ended ()
		if self.plan == plan then self.plan = nil end
	end
	plan.Mine = function () return self.plan == plan and IsValid (self.ent) end
	-- (the plan's own functions take it as their first argument and name it _: self is the soldier)
	plan.Task = function (_, work)
		plans:Spawn (function ()
			local ok, why = xpcall (work, debug.traceback)
			if not ok then
				Ended ()
				error (why, 0)
			end
		end)
	end
	plan.Answer = function (_, route, found)
		if not plan.Mine () then return end
		plan:Task (function ()
			local points = {}
			for i, v in ipairs (route or {}) do points [i] = Point (v) end
			-- whether the clean-up goes on: asked before each of its traces
			local dropped = false
			local function Going ()
				if not dropped and plans:CheckYield () and not plan.Mine () then dropped = true end
				return not dropped
			end
			-- each point where its body fits, then its turns pushed out off the inside walls
			-- until its body passes them (the map's walls, not who stands there now)
			points = self:StandOnRoute (points, Going)
			points = Locomotion.RoundCorners (points, function (a, b)
				return Going () and self:WalkClear (ToVector (a), ToVector (b), Unmoving)
			end)
			if not dropped and plan.Mine () then
				-- the engine's trivial path, straight from its start to the goal, is a route when
				-- it found one (both in one area); where it found no way it is none
				if route and not found and RouteWalk.Trivial (points, pos, DIRECT_RANGE) then route = nil end
				self.walk = route and RouteWalk.New (points) or nil
			end
			Ended ()
		end)
	end
	search (goal, pos, plan)
end

-- Every look (sv_bots.lua): the point its body makes for now (steer) on
-- its way to its move target. A route is planned from where its navigator
-- knows it stands (Path:Compute starts at the navigator's last known area),
-- so not until the navigator has caught up with a body set down elsewhere.
function BotSoldier:Steer (now)
	local goal = self.moveTarget and self:MeshGoal (self.moveTarget)
	local pos = Point (self.ent:GetPos ())
	if self.lookedFrom and Geometry.Distance (pos, self.lookedFrom) > TELEPORTED then
		self.walk, self.plan, self.nextPlan = nil, nil, now + SETTLE_DELAY
	end
	self.lookedFrom = pos
	-- no nearer its waypoint for a while (fallen off beneath its route,
	-- wedged): planned anew from where it is
	if self.walk and self.walk:Stalled (pos, now) then self.walk = nil end
	if not goal then
		-- nowhere to be: aside from a teammate standing on it, unless it has a fight to see to
		self.steer = not self:HasEnemy () and self:Spread (self.ent:GetPos ()) or nil
		return
	end
	-- a search that has not answered in PLAN_PATIENCE is given up: its bot does not stand waiting
	if self.plan and now - self.plan.at > PLAN_PATIENCE then self.plan = nil end
	-- one route at a time, and none while one cannot be searched for (the engine's: its
	-- navigator not settled, the mesh not ready to price): the route it has is kept meanwhile,
	-- and it asks at its next look
	local search = not self.plan and now >= self.nextPlan and self:RouteSearch ()
	if search then
		self.nextPlan = now + REPATH_LEAST + math.random () * (REPATH_MOST - REPATH_LEAST)
		self:PlanRoute (goal, pos, search, now)
	end
	if self:RangeTo (goal) <= DIRECT_RANGE and self:CanWalkTo (goal) then
		self.steer = goal
		return
	end
	-- A failed route does not make a direct walk safe.
	local walk = self.walk
	local at = self.ent:GetPos ()
	local point = walk and walk:Next (Point (at), function (q) return self:CanWalkTo (q) end)
	self.steer = point and self:SteerOn (at, point) or nil
end

function BotSoldier:Watch (p)
	self.look = p and ToVector (p) or nil
end

-- Its eyes go to p a while, over where Watch points them (Looking).
function BotSoldier:LookAt (p, seconds, priority)
	self.glance, self.glanceUntil = ToVector (p), CurTime () + seconds
	self.glancePriority = priority == true
end

-- It stands still for seconds (a taunt played whole): no steering while it
-- lasts (Still).
function BotSoldier:HoldStill (seconds)
	self.stillUntil = math.max (self.stillUntil or 0, CurTime () + seconds)
end

function BotSoldier:Still (now)
	return now < (self.stillUntil or 0)
end

-- Where its eyes go with no enemy: a glance still held, else what it watches.
function BotSoldier:Looking (now)
	if self.glance and now < self.glanceUntil then return self.glance end
	return self.look
end

-- The box its walks and hops are swept with: its own player hull's width
-- (a TF2 player's 48; Map's 26-wide walk sweep passes lines its shoulders
-- catch on door frames), WALK_MAXS high above WALK_LIFT.
function BotSoldier:Sweep ()
	local mn, mx = self.ent:GetHull ()
	local mins, maxs = Movement.Sweep (mn, mx, WALK_MAXS.z)
	return ToVector (mins), ToVector (maxs)
end

-- A clear walk under player movement's mask: what stops a player stops it,
-- and a floor all along (RouteWalk.Footing), within a step above or two
-- below the line: a line beside a beam is clear of everything, over air.
function BotSoldier:CanWalkTo (p)
	return self:WalkClear (self.ent:GetPos (), ToVector (p))
end

-- The same for a walk from `from` to `to` (Vectors), wherever it stands;
-- filter, a trace filter, in place of its own (only itself).
function BotSoldier:WalkClear (from, to, filter)
	if math.abs (to.z - from.z) > WALK_MAX_RISE then return false end
	local mins, maxs = self:Sweep ()
	local tr = util.TraceHull (
		{
			start = from + WALK_LIFT,
			endpos = to + WALK_LIFT,
			mins = mins,
			maxs = maxs,
			mask = MASK_PLAYERSOLID,
			filter = filter or self.ent
		}
	)
	if tr.Hit then return false end
	for _, q in ipairs (RouteWalk.Footing (Point (from), Point (to))) do
		local at = ToVector (q)
		local floor = util.TraceLine ({ start = at + FOOTING_ABOVE, endpos = at - FOOTING_BELOW, mask = MASK_PLAYERSOLID,
			filter = self.ent })
		if not floor.Hit then return false end
	end
	return true
end

-- What stands between me and p for a player's movement; a player passes
-- nothing that stops it.
function BotSoldier:Blocker (p)
	local controller = self.controller
	local from, to = self.ent:GetPos () + WALK_LIFT, ToVector (p) + WALK_LIFT
	local function NotSoldier (hit) return controller.soldiers [hit] == nil end
	local mins, maxs = self:Sweep ()
	local hit = util.TraceHull ({ start = from, endpos = to, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = NotSoldier })
	if not hit.Hit then return nil, false end
	return hit.HitWorld and game.GetWorld () or hit.Entity, false
end

-- Where my movement heads now for p: the point my route makes for, else p.
function BotSoldier:Heading (p) return ToVector (self.steer or p) end

-- A hop: it jumps (a crouch jump) on its way to p, as a player would, where
-- a jump clears what stands between (a hull swept at the jump's height,
-- under player movement's mask), and not again within HOP_RETRY: a hop
-- that got it nowhere lets the orders step aside and plan again.
function BotSoldier:Hop (p)
	local now = CurTime ()
	if now - (self.hoppedAt or -math.huge) < HOP_RETRY then return false end
	local from, to = self.ent:GetPos () + HOP_CLEAR, ToVector (p) + HOP_CLEAR
	local mins, maxs = self:Sweep ()
	local tr = util.TraceHull ({ start = from, endpos = to, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = self.ent })
	if tr.Hit then return false end
	self.hoppedAt = now
	self.hopUntil = now + HOP_WISH
	return true
end

function BotSoldier:Hopping (now) return now < self.hopUntil end

-- A player's body neither sits on the cart nor strikes poses.
function BotSoldier:Sit () return false end
function BotSoldier:Pose () return nil end
function BotSoldier:Unpose () end

return BotSoldier
