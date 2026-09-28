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
-- bool }. Without route, a route is the goal alone; without walkable,
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

function Soldier:MoveTo(p)
	self.moving = p
	self.moves[#self.moves + 1] = p
end

function Soldier:Release()
	self.moving = nil
	self.releases = self.releases + 1
end

return Fake
