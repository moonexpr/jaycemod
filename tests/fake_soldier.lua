-- An in-memory foundation.aiwar.soldier for model tests: a fake clock, a
-- position the test moves by hand, a scripted enemy, a route finder that
-- answers after a set number of polls, and a log of the moves and releases
-- the model asked for. It implements every name in
-- foundation.aiwar.soldier.METHODS (aiwar_orders_test checks that).
local Fake = {}

function Fake.Point(x, y, z)
	return { x = x, y = y, z = z or 0 }
end

local function Distance(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end
Fake.Distance = Distance

local Soldier = {}
Soldier.__index = Soldier

-- t = { now, pos, route = function(from, goal) -> points | false,
-- routeDelay = polls before the answer, walkable = function(from, to) ->
-- bool, hoppable = function(from, to) -> bool (default: never),
-- passable = function(from, to) -> bool: a blocker only NPCs collide with
-- stands between (default: never), detour = function(from, to) -> point
-- beside a solid entity in the way, or nil (default: nil), wanderSpots =
-- list of points WanderSpot hands out in turn (default: none) }. Without
-- route, a route is the goal alone; without walkable,
-- nothing past the current waypoint counts as walkable.
function Fake.Soldier(t)
	t = t or {}
	return setmetatable({
		now = t.now or 1,
		pos = t.pos or Fake.Point(0, 0, 0),
		alive = true,
		enemy = false,
		route = t.route or function(from, goal) return { goal } end,
		routeDelay = t.routeDelay or 0,
		walkable = t.walkable or function() return false end,
		hoppable = t.hoppable or function() return false end,
		passable = t.passable or function() return false end,
		passed = {},
		detour = t.detour or function() return nil end,
		detours = {},
		wanderSpots = t.wanderSpots or {},
		patrolSpots = t.patrolSpots,
		plansRoutes = t.plansRoutes,
		follows = t.follows,
		enemyPos = t.enemyPos,
		covers = t.covers,
		wandered = 0,
		hops = {},
		requests = {},
		pending = nil,
		moves = {},
		releases = 0,
		moving = nil,
	}, Soldier)
end

function Soldier:Advance(dt) self.now = self.now + dt end

-- port
function Soldier:Now() return self.now end
function Soldier:IsAlive() return self.alive end
function Soldier:Position() return { x = self.pos.x, y = self.pos.y, z = self.pos.z } end
function Soldier:RangeTo(p) return Distance(self.pos, p) end
function Soldier:HasEnemy() return self.enemy end

function Soldier:RequestRoute(goal)
	self.requests[#self.requests + 1] = goal
	self.pending = { polls = self.routeDelay, answer = self.route(self.pos, goal) }
end

function Soldier:RouteResult()
	local pending = self.pending
	if pending.polls > 0 then
		pending.polls = pending.polls - 1
		return nil
	end
	return pending.answer
end

function Soldier:CanWalkTo(p) return self.walkable(self.pos, p) end

function Soldier:PassBlocker(p)
	if not self.passable(self.pos, p) then return false end
	self.passed[#self.passed + 1] = p
	return true
end

function Soldier:Detour(p)
	local point = self.detour(self.pos, p)
	if point then self.detours[#self.detours + 1] = point end
	return point
end

-- The test sets me.stale for the next poll.
function Soldier:RouteStale()
	local stale = self.stale
	self.stale = false
	return stale == true
end

-- patrolSpots: the points PatrolSpot hands out in turn (default: none).
function Soldier:PatrolSpot(center, radius)
	self.patrolled = (self.patrolled or 0) + 1
	return (self.patrolSpots or {})[self.patrolled]
end

-- plansRoutes: the engine finds its own way (default: no).
function Soldier:PlansRoutes() return self.plansRoutes == true end

-- follows: whether FollowCart succeeds (default: no).
function Soldier:FollowCart()
	if self.follows then self.following = true end
	return self.follows == true
end

function Soldier:Unfollow() self.following = false end

-- enemyPos: where the enemy is (default: none); covers: the spots
-- CoverSpot hands out in turn (default: none); hurtAt: when last hurt.
function Soldier:EnemyPosition() return self.enemyPos end

function Soldier:CoverSpot(center, radius, threat, exclude)
	self.covered = (self.covered or 0) + 1
	return (self.covers or {})[self.covered]
end

function Soldier:HurtSince(t) return self.hurtAt ~= nil and self.hurtAt > (t or 0) end

function Soldier:Hold()
	self.holding = true
	self.moving = self.pos
end

function Soldier:WanderSpot()
	self.wandered = self.wandered + 1
	return self.wanderSpots[self.wandered]
end

function Soldier:Hop(p)
	if not self.hoppable(self.pos, p) then return false end
	self.hops[#self.hops + 1] = p
	self.pos = { x = p.x, y = p.y, z = p.z }
	return true
end

function Soldier:MoveTo(p, gait)
	self.moving = p
	self.gait = gait
	self.posing = nil
	self.moves[#self.moves + 1] = p
end

function Soldier:Pose()
	self.posing = self.posing or "sitting"
	return self.posing
end

function Soldier:Unpose() self.posing = nil end

function Soldier:Release()
	self.moving = nil
	self.releases = self.releases + 1
end

return Fake
