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
local RouteWalk = nextsoldier.route_walk
local Geometry = math.geometry
local Teams = gameplay.teams
local ToVector, Point = Map.ToVector, Map.Point
local WALK_MINS, WALK_MAXS, WALK_LIFT, WALK_MAX_RISE = Map.WALK_MINS, Map.WALK_MAXS, Map.WALK_LIFT, Map.WALK_MAX_RISE

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
local DIRECT_RANGE = 256
local FIRST_PLAN = 0.3
-- What a player's body climbs and falls (RouteCost): a stair step, a crouch
-- jump (Sandbox's jump power with the legs tucked), the fall it survives
-- unhurt; a jump costs JUMP_PENALTY times its length more (CTFBotPathCost).
local STEP_HEIGHT, JUMP_HEIGHT, SAFE_DROP = 18, 52, 300
local JUMP_PENALTY = 2

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
	return function(area, fromArea, ladder, _, length)
		if not IsValid(fromArea) then return 0 end
		if npcs:NavBlocks(area, team) or controller:ShutDoorIn(area, team) or npcs:SpawnRoomTeam(area) == enemy then return -1 end
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
			if rise > JUMP_HEIGHT then return -1 end
			cost = cost + JUMP_PENALTY * distance
		elseif rise < -SAFE_DROP then
			return -1
		end
		return cost
	end
end

function BotSoldier:MoveTo(p, gait)
	self.moveTarget = p
	self.gait = gait or "run"
end

function BotSoldier:Release()
	self.moveTarget = nil
	self.steer = nil
	self.walkSpeed = 0
end

function BotSoldier:Repath() self.repath = true end

-- Every look (sv_bots.lua): the point its body makes for now (steer) on
-- its way to its move target.
function BotSoldier:Steer(now)
	local goal = self.moveTarget
	if not goal then
		self.steer = nil
		return
	end
	local generation = WS.Feature("npc"):BlockerGeneration()
	local stale = self.planned == nil or self.repath or generation ~= self.routeGeneration
		or Geometry.Distance(goal, self.planned) > REPATH_DISTANCE
	if stale and now >= self.nextPlan then
		self.planned, self.repath, self.routeGeneration, self.nextPlan = goal, false, generation, now + REPATH_INTERVAL
		local route = self:Navigator():PlanRoute(ToVector(goal), self:RouteCost())
		local points = {}
		for i, v in ipairs(route or {}) do points[i] = Point(v) end
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

-- A clear walk under player movement's mask: what stops a player stops it.
function BotSoldier:CanWalkTo(p)
	local from, to = self.ent:GetPos(), ToVector(p)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = MASK_PLAYERSOLID,
		filter = self.ent,
	})
	return not tr.Hit
end

-- What stands between me and p for a player's movement; a player passes
-- nothing that stops it.
function BotSoldier:Blocker(p)
	local controller = self.controller
	local from, to = self.ent:GetPos() + WALK_LIFT, ToVector(p) + WALK_LIFT
	local function NotSoldier(hit) return controller.soldiers[hit] == nil end
	local hit = util.TraceHull({ start = from, endpos = to, mins = WALK_MINS, maxs = WALK_MAXS, mask = MASK_PLAYERSOLID, filter = NotSoldier })
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
	local tr = util.TraceHull({ start = from, endpos = to, mins = WALK_MINS, maxs = WALK_MAXS, mask = MASK_PLAYERSOLID, filter = self.ent })
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
