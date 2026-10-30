-- Part of the AI war controller (sv.lua): the soldier port
-- (nextsoldier.soldier) over a bot player (player.CreateNextBot, kept
-- by tf_bot_quota: sv_bots.lua), beside sv_soldier.lua's over a DrGBase
-- NextBot. It is that port where the two agree (routes, cover, kits,
-- gadgets, health kits) and differs where the body does: it walks a route
-- of its own to the goal its orders give (as DrGBase plans its own), sees
-- and fights through its vision and body (nextsoldier.vision,
-- player_body; sv_bots.lua presses its keys), and neither sits on carts
-- nor takes poses.
local Map, Soldier = ...
local Vision = nextsoldier.vision
local PlayerBody = nextsoldier.player_body
local Movement = gameplay.movement
local RouteWalk = nextsoldier.route_walk
local Corners = nextsoldier.corners
local Geometry = math.geometry
local Teams = gameplay.teams
local Movement = gameplay.movement
local ToVector, Point = Map.ToVector, Map.Point
local WALK_MAXS, WALK_LIFT, WALK_MAX_RISE = Map.WALK_MAXS, Map.WALK_LIFT, Map.WALK_MAX_RISE

-- How long it keeps the jump key's wish when its orders ask a hop: long
-- enough to land on the ground and press it.
local HOP_WISH = 0.5
-- A hop's way is swept this high (a crouch jump's lift: a player's jump with
-- its legs tucked), and a bot hops at most once in HOP_RETRY seconds.
local HOP_CLEAR = Vector(0, 0, 56)
local HOP_RETRY = 6
-- How long it remembers an enemy out of sight, where last seen.
local MEMORY = 5
-- Its own routes (Steer): asked again when the goal moved this far, at
-- most every REPATH_INTERVAL seconds; a goal within DIRECT_RANGE in a clear
-- line is walked straight at (the orders' CHASE_RANGE).
local REPATH_DISTANCE, REPATH_INTERVAL = 128, 1
-- Moved farther than this between two looks, it was set down elsewhere (a
-- respawn, a side swap, a bench): its route is dropped and planned anew.
local TELEPORTED = 256
-- Set down elsewhere or pinned, it plans no sooner than this after: its
-- navigator follows it on its next think and the engine catches the
-- navigator's area up after that.
local SETTLE_DELAY = 0.5
local DIRECT_RANGE = 256
local FIRST_PLAN = 0.3
-- What a player's body climbs and falls (RouteCost): a stair step, a crouch
-- jump (JumpReachOf), the fall it survives unhurt; a jump costs
-- JUMP_PENALTY times its length more (CTFBotPathCost).
local STEP_HEIGHT, SAFE_DROP = 18, 300
-- A straight walk's floor is looked for from a step above its line to two
-- below (CanWalkTo): a stair up or down the way is floor, a ledge's edge not.
local FOOTING_ABOVE, FOOTING_BELOW = Vector(0, 0, STEP_HEIGHT), Vector(0, 0, 2 * STEP_HEIGHT)
local JUMP_PENALTY = 2

-- A goal off the mesh (a guard's spot on a ring round its charge that falls
-- in or behind a wall) is walked to as the first point on the mesh along the
-- line back from it toward the bot, looked for OFF_MESH_STEP apart: else the
-- bot presses into the wall for as long as it guards.
local OFF_MESH_STEP, OFF_MESH_HEIGHT, OFF_MESH_LIFT = 16, 60, Vector(0, 0, 20)

local function OnMesh(p) return navmesh.GetNavArea(p + OFF_MESH_LIFT, OFF_MESH_HEIGHT) ~= nil end

-- A trace filter passing whoever walks about: players and NPCs.
local function Unmoving(ent) return not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) end

local BotSoldier = setmetatable({}, { __index = Soldier })
BotSoldier.__index = BotSoldier

-- reaction: the difficulty's (features.aiwar.marksmanship), before it
-- recognizes an enemy it sees.
function BotSoldier.New(ent, controller, team, reaction)
	return setmetatable({
		ent = ent,
		controller = controller,
		team = team,
		ticket = 0,
		result = nil,
		moveTarget = nil,
		relations = {},
		vision = Vision.New({
			reaction = reaction,
			memory = MEMORY,
		}),
		body = PlayerBody.New(),
		look = nil, -- where it faces with no enemy (Watch), a Vector
		hopUntil = 0,
		steer = nil, -- the point its body makes for (Steer)
		walk = nil, -- the route of its own it walks (nextsoldier.route_walk)
		planned = nil, -- the goal that route was planned for
		-- its first route waits a moment: a navigator just made knows no nav area yet
		nextPlan = CurTime() + FIRST_PLAN,
		mayFire = false, -- its orders let it fire at its contact (sv_bots.lua asks them)
		loadout = nil, -- features.aiwar.arms' loadout it carries (KitBot)
		wantWeapon = nil, -- the weapon its contact's distance calls for
	}, BotSoldier)
end

function BotSoldier:IsAlive() return IsValid(self.ent) and self.ent:Alive() end

-- The enemy it fights: its vision's contact, while the enemy lives.
function BotSoldier:Enemy()
	local enemy = self.vision:Contact()
	return IsValid(enemy) and enemy or nil
end

function BotSoldier:HasEnemy()
	local enemy = self:Enemy()
	return enemy ~= nil and self.vision:Visible(enemy)
end

function BotSoldier:EnemyHealth()
	local enemy = self:Enemy()
	if not enemy or enemy:Health() <= 0 then return nil end
	return enemy:Health() / math.max(enemy:GetMaxHealth(), 1)
end

-- Where its enemy is: in sight, where it stands; out of it, where it was
-- last seen.
function BotSoldier:EnemyPosition()
	local enemy = self:Enemy()
	if not enemy then return nil end
	if self.vision:Visible(enemy) then return Point(enemy:GetPos()) end
	return (self.vision:LastKnown(enemy))
end

-- A player's body plans its own way, as DrGBase's does: the orders give it
-- the goal itself (their Chase), and it walks a route of its own there
-- (nextsoldier.route_walk), or straight at a goal near and in a clear
-- line. The route is the engine's path search's, through its navigator
-- (ws_bot_navigator), priced by RouteCost, as DrGBase's paths are: the
-- war's own Lua route searches queue behind its lane planning for tens of
-- seconds, which a body waiting on them spends standing still. It is
-- planned again only when the goal has moved REPATH_DISTANCE, what blocks
-- the nav mesh has changed (a door, setup's gates: the npc feature's
-- BlockerGeneration), or its orders ask (Repath), at most every
-- REPATH_INTERVAL.
function BotSoldier:PlansRoutes() return true end

-- Its navigator, made with its first route and kept with the bot player
-- across its lives (it goes when the bot does).
function BotSoldier:Navigator()
	local ply = self.ent
	if IsValid(ply.NSNavigator) then return ply.NSNavigator end
	local navigator = ents.Create("ws_bot_navigator")
	navigator:SetOwner(ply)
	navigator:SetPos(ply:GetPos())
	navigator:Spawn()
	ply.NSNavigator = navigator
	return navigator
end

-- How high ply's crouch jump reaches, from its own jump power, gravity and
-- hulls (Movement.JumpReach): TF2's body, 72; GMod's, about 69.
local function JumpReachOf(ply)
	local _, stand = ply:GetHull()
	local _, duck = ply:GetHullDuck()
	local scale = ply:GetGravity()
	local gravity = GetConVarNumber("sv_gravity") * (scale ~= 0 and scale or 1)
	return Movement.JumpReach(ply:GetJumpPower(), gravity, stand.z, duck.z)
end

-- The price of a step from fromArea into area (Path:Compute's generator),
-- or -1 where a player of my team may not go: an area its doors or brushes
-- close to it (the npc feature's blockers, the doors the war found shut),
-- the enemy's spawn rooms (their visualizers stop players), a rise higher
-- than a crouch jump, a drop farther than a safe fall. A step up past a
-- stair costs JUMP_PENALTY times its length more (CTFBotPathCost's).
function BotSoldier:RouteCost()
	local controller, team = self.controller, self.team
	local npcs = WS.Feature("npc")
	local enemy = Teams.EnemyOf(team)
	local reach = JumpReachOf(self.ent)
	return function(area, fromArea, ladder, _, length)
		if not IsValid(fromArea) then return 0 end
		if npcs:NavBlocks(area, team) or controller:ShutDoorIn(area, team) or npcs:SpawnRoomTeam(area) == enemy then return -1 end
		-- a link its body does not fit through, or that crosses a clip or a wall's end
		if not WS.NavLinkCrossable(fromArea, area) then return -1 end
		local distance
		if IsValid(ladder) then
			distance = ladder:GetLength()
		elseif length > 0 then
			distance = length
		else
			distance = area:GetCenter():Distance(fromArea:GetCenter())
		end
		local cost = distance + fromArea:GetCostSoFar()
		local rise = fromArea:ComputeAdjacentConnectionHeightChange(area)
		if rise > STEP_HEIGHT then
			if rise > reach then return -1 end
			cost = cost + JUMP_PENALTY * distance
		elseif rise < -SAFE_DROP then
			return -1
		end
		return cost
	end
end

function BotSoldier:MoveTo(p, gait)
	if self.pin then return end
	self.moveTarget = p
	self.gait = gait or "run"
end

function BotSoldier:Release()
	if self.pin then return end
	self.moveTarget = nil
	self.steer = nil
	self.walkSpeed = 0
end

-- A bench's pin (ns_bots_goto): sent to p at a run whatever its orders
-- say, its route planned afresh, until unpinned (ns_bots_release).
function BotSoldier:Pin(p)
	self.pin = p
	self.moveTarget, self.gait, self.planned = p, "run", nil
	-- the route it was on goes; the new one is planned once it has settled
	self.walk, self.steer, self.nextPlan = nil, nil, CurTime() + SETTLE_DELAY
end

function BotSoldier:Unpin()
	self.pin = nil
	self.planned = nil
end

function BotSoldier:Repath() self.repath = true end

-- Where to walk for goal (a point): itself on the mesh, else the first
-- point on the mesh back from it toward where it stands, else itself.
function BotSoldier:MeshGoal(goal)
	local to = ToVector(goal)
	if OnMesh(to) then return goal end
	local from = self.ent:GetPos()
	local length = from:Distance(to)
	for along = OFF_MESH_STEP, length, OFF_MESH_STEP do
		local p = to + (from - to) * (along / length)
		if OnMesh(p) then return Point(p) end
	end
	return goal
end

-- Every look (sv_bots.lua): the point its body makes for now (steer) on
-- its way to its move target. A route is planned from where its navigator
-- knows it stands (Path:Compute starts at the navigator's last known area),
-- so not until the navigator has caught up with a body set down elsewhere.
function BotSoldier:Steer(now)
	local goal = self.moveTarget and self:MeshGoal(self.moveTarget)
	local pos = Point(self.ent:GetPos())
	if self.lookedFrom and Geometry.Distance(pos, self.lookedFrom) > TELEPORTED then
		self.walk, self.planned, self.nextPlan = nil, nil, now + SETTLE_DELAY
	end
	self.lookedFrom = pos
	-- no nearer its waypoint for a while (fallen off beneath its route,
	-- wedged): planned anew from where it is
	if self.walk and self.walk:Stalled(pos, now) then self.walk, self.planned = nil, nil end
	if not goal then
		self.steer = nil
		return
	end
	local generation = WS.Feature("npc"):BlockerGeneration()
	local stale = self.planned == nil or self.repath or generation ~= self.routeGeneration
		or Geometry.Distance(goal, self.planned) > REPATH_DISTANCE
	if stale and now >= self.nextPlan and self:Navigator():Settled() then
		self.planned, self.repath, self.routeGeneration, self.nextPlan = goal, false, generation, now + REPATH_INTERVAL
		local route = self:Navigator():PlanRoute(ToVector(goal), self:RouteCost())
		local points = {}
		for i, v in ipairs(route or {}) do points[i] = Point(v) end
		-- its turns pushed out off the inside walls until its body passes them
		-- (the map's, not who stands there now)
		points = Corners.Route(points, function(a, b) return self:WalkClear(ToVector(a), ToVector(b), Unmoving) end)
		self.walk = route and RouteWalk.New(points) or nil
		-- none found: planned again after REPATH_INTERVAL
		if not route then self.planned = nil end
	end
	if self:RangeTo(goal) <= DIRECT_RANGE and self:CanWalkTo(goal) then
		self.steer = goal
		return
	end
	-- with no route there, straight at it, for the orders to unstick
	local walk = self.walk
	self.steer = walk and walk:Next(Point(self.ent:GetPos()), function(q) return self:CanWalkTo(q) end) or goal
end

function BotSoldier:Watch(p)
	self.look = p and ToVector(p) or nil
end

-- Its eyes go to p a while, over where Watch points them (Looking).
function BotSoldier:LookAt(p, seconds)
	self.glance, self.glanceUntil = ToVector(p), CurTime() + seconds
end

-- Where its eyes go with no enemy: a glance still held, else what it watches.
function BotSoldier:Looking(now)
	if self.glance and now < self.glanceUntil then return self.glance end
	return self.look
end

-- The box its walks and hops are swept with: its own player hull's width
-- (a TF2 player's 48; Map's 26-wide walk sweep passes lines its shoulders
-- catch on door frames), WALK_MAXS high above WALK_LIFT.
function BotSoldier:Sweep()
	local mn, mx = self.ent:GetHull()
	local mins, maxs = Movement.Sweep(mn, mx, WALK_MAXS.z)
	return ToVector(mins), ToVector(maxs)
end

-- A clear walk under player movement's mask: what stops a player stops it,
-- and a floor all along (RouteWalk.Footing), within a step above or two
-- below the line: a line beside a beam is clear of everything, over air.
function BotSoldier:CanWalkTo(p)
	return self:WalkClear(self.ent:GetPos(), ToVector(p))
end

-- The same for a walk from `from` to `to` (Vectors), wherever it stands;
-- filter, a trace filter, in place of its own (only itself).
function BotSoldier:WalkClear(from, to, filter)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local mins, maxs = self:Sweep()
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID,
		filter = filter or self.ent,
	})
	if tr.Hit then return false end
	for _, q in ipairs(RouteWalk.Footing(Point(from), Point(to))) do
		local at = ToVector(q)
		local floor = util.TraceLine({ start = at + FOOTING_ABOVE, endpos = at - FOOTING_BELOW, mask = MASK_PLAYERSOLID,
			filter = self.ent })
		if not floor.Hit then return false end
	end
	return true
end

-- What stands between me and p for a player's movement; a player passes
-- nothing that stops it.
function BotSoldier:Blocker(p)
	local controller = self.controller
	local from, to = self.ent:GetPos() + WALK_LIFT, ToVector(p) + WALK_LIFT
	local function NotSoldier(hit) return controller.soldiers[hit] == nil end
	local mins, maxs = self:Sweep()
	local hit = util.TraceHull({ start = from, endpos = to, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = NotSoldier })
	if not hit.Hit then return nil, false end
	return hit.HitWorld and game.GetWorld() or hit.Entity, false
end

-- Where my movement heads now for p: the point my route makes for, else p.
function BotSoldier:Heading(p) return ToVector(self.steer or p) end

-- A hop: it jumps (a crouch jump) on its way to p, as a player would, where
-- a jump clears what stands between (a hull swept at the jump's height,
-- under player movement's mask), and not again within HOP_RETRY: a hop
-- that got it nowhere lets the orders step aside and plan again.
function BotSoldier:Hop(p)
	local now = CurTime()
	if now - (self.hoppedAt or -math.huge) < HOP_RETRY then return false end
	local from, to = self.ent:GetPos() + HOP_CLEAR, ToVector(p) + HOP_CLEAR
	local mins, maxs = self:Sweep()
	local tr = util.TraceHull({ start = from, endpos = to, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = self.ent })
	if tr.Hit then return false end
	self.hoppedAt = now
	self.hopUntil = now + HOP_WISH
	return true
end

function BotSoldier:Hopping(now) return now < self.hopUntil end

-- A player's body neither sits on the cart nor strikes poses.
function BotSoldier:Sit() return false end
function BotSoldier:Pose() return nil end
function BotSoldier:Unpose() end

return BotSoldier
