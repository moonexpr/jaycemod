-- foundation.aiwar.orders: the Actions a Combine or Resistance soldier
-- follows in the AI war, driven as scenarios against tests/fake_soldier.lua.
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local N = T.require("foundation.npc")
local AiWar = T.require("foundation.aiwar")
local Orders = T.require("foundation.aiwar.orders")
local Soldier = T.require("foundation.aiwar.soldier")
local Track = T.require("foundation.aiwar.track")
local Teams = T.require("foundation.teams")

local RED, BLUE = Teams.RED, Teams.BLUE
local P = FS.Point
local TICK = 0.25

-- A straight track along +x from 0 to 4000, the cart at `distance`.
local function Cart(distance)
	local track = Track.New({ P(0, 0), P(4000, 0) })
	return { track = track, distance = distance, pos = track:PointAt(distance) }
end

local function Field(t)
	return {
		phase = t.phase or AiWar.PHASES.running,
		carts = t.carts or { [BLUE] = Cart(1000) },
	}
end

-- A soldier of `team` in `role` (slot 0), bound as the controller binds one
-- and through its first update, which only starts its actions.
local function Enlist(t)
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	war:SetField(t.field or Field({}))
	local member = war:Enlist("me", t.team or BLUE, true)
	member.role = t.role or member.role
	member.slot = t.slot or 0
	local me = FS.Soldier(t)
	local npc = N.Npc.New(Orders, { war = war, member = member }, me)
	npc:Update(TICK)
	return me, npc, war, member
end

local function Tick(me, npc, n)
	for _ = 1, n or 1 do
		me:Advance(TICK)
		npc:Update(TICK)
	end
end

local function Near(p, q, what)
	T.eq(FS.Distance(p, q) < 1e-6, true, string.format("%s: (%g, %g) vs (%g, %g)", what, p.x, p.y, q.x, q.y))
end

T.test("the fake soldier implements the whole port", function()
	local me = FS.Soldier()
	for _, name in ipairs(Soldier.METHODS) do
		T.eq(type(me[name]), "function", name)
	end
end)

-- Goals ---------------------------------------------------------------------

T.test("a pusher's goal is a spot on a ring around its own cart", function()
	local field = Field({})
	local member = { team = BLUE, role = AiWar.PUSH, slot = 0 }
	local goal = Orders.Goal(field, member)
	T.near(FS.Distance(goal, field.carts[BLUE].pos), Orders.PUSH_RING, 1e-9, "on the ring")
	member.slot = 1
	T.eq(FS.Distance(Orders.Goal(field, member), goal) > 1, true, "another slot, another spot")
end)

T.test("a blocker rings the enemy's cart, and has no goal without one", function()
	local field = Field({})
	local member = { team = RED, role = AiWar.BLOCK, slot = 0 }
	T.near(FS.Distance(Orders.Goal(field, member), field.carts[BLUE].pos), Orders.PUSH_RING, 1e-9, "BLU's cart")
	member.team = BLUE
	T.eq(Orders.Goal(field, member), nil, "RED has no cart")
end)

T.test("an escort leads its cart along the track, spread sideways by slot", function()
	local field = Field({})
	local member = { team = BLUE, role = AiWar.ESCORT, slot = 0 }
	Near(Orders.Goal(field, member), P(1000 + Orders.ESCORT_LEAD, 0), "slot 0 on the track")
	member.slot = 1
	Near(Orders.Goal(field, member), P(1000 + Orders.ESCORT_LEAD, Orders.LATERAL), "slot 1 left")
	member.slot = 2
	Near(Orders.Goal(field, member), P(1000 + Orders.ESCORT_LEAD, -Orders.LATERAL), "slot 2 right")
end)

T.test("defenders hold rows ahead of the enemy's cart, then spread sideways", function()
	local field = Field({})
	local member = { team = RED, role = AiWar.DEFEND, slot = 0 }
	Near(Orders.Goal(field, member), P(1000 + Orders.DEFEND_LEAD, 0), "first row")
	member.slot = 1
	Near(Orders.Goal(field, member), P(1000 + Orders.DEFEND_LEAD + Orders.DEFEND_DEPTH, 0), "second row")
	member.slot = Orders.DEFEND_ROWS
	Near(Orders.Goal(field, member), P(1000 + Orders.DEFEND_LEAD, Orders.LATERAL), "first row, left")
end)

-- Behaviour -----------------------------------------------------------------

T.test("a pusher asks for a route to the cart and walks it waypoint by waypoint", function()
	local route = { P(100, 0), P(500, 0), P(950, 0) }
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return route end })
	Tick(me, npc)
	T.eq(npc:Describe(), "SoldierBehavior/Travel", "travelling")
	T.eq(#me.requests, 1, "one route asked for")
	Tick(me, npc)
	Near(me.moving, route[1], "to the first waypoint")
	me.pos = P(90, 0)
	Tick(me, npc)
	Near(me.moving, route[2], "on to the second")
end)

T.test("a soldier waits in place while its route is being searched", function()
	local me, npc = Enlist({ role = AiWar.PUSH, routeDelay = 1 })
	Tick(me, npc, 2)
	T.eq(me.moving, nil, "not moving yet")
	T.eq(me.releases > 0, true, "left to the engine")
	Tick(me, npc)
	T.eq(me.moving ~= nil, true, "moving once the route came")
end)

T.test("a waypoint it can walk straight to is skipped to", function()
	local route = { P(100, 0), P(200, 0), P(300, 0), P(950, 0) }
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return route end,
		walkable = function(from, to) return to.x <= 300 end,
	})
	Tick(me, npc, 2)
	Near(me.moving, route[3], "the farthest walkable of the next few")
end)

T.test("a soldier that reaches its goal stops travelling and holds", function()
	local me, npc = Enlist({ role = AiWar.PUSH })
	Tick(me, npc, 2)
	me.pos = Orders.Goal(Field({}), { team = BLUE, role = AiWar.PUSH, slot = 0 })
	Tick(me, npc)
	T.eq(npc:Describe(), "SoldierBehavior/Push", "arrived")
	local releases = me.releases
	Tick(me, npc)
	T.eq(me.releases > releases, true, "holds, leaving fights to the engine")
	T.eq(#me.requests, 1, "no new route")
end)

T.test("a defender that sees an enemy near its post fights instead of walking", function()
	local me, npc = Enlist({ team = RED, role = AiWar.DEFEND, pos = P(1300, 0) })
	me.enemy = true
	Tick(me, npc)
	T.eq(npc:Describe(), "SoldierBehavior/Defend", "fighting at the post")
	T.eq(#me.requests, 0, "no route")
end)

T.test("an escort on the way breaks off to fight once near its goal", function()
	local me, npc = Enlist({ role = AiWar.ESCORT, pos = P(0, 0) })
	Tick(me, npc, 2)
	T.eq(npc:Describe(), "SoldierBehavior/Travel", "travelling")
	me.enemy = true
	me.pos = P(1000, 0)
	Tick(me, npc)
	T.eq(npc:Describe(), "SoldierBehavior/Escort", "stopped to fight")
end)

T.test("a pusher rushes the cart through enemy fire", function()
	local me, npc = Enlist({ role = AiWar.PUSH, pos = P(0, 0) })
	me.enemy = true
	Tick(me, npc, 2)
	T.eq(npc:Describe(), "SoldierBehavior/Travel", "still travelling")
	T.eq(me.moving ~= nil, true, "moving")
end)

T.test("with no route the soldier holds and tries again later", function()
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return false end })
	Tick(me, npc, 2)
	T.eq(npc:Describe(), "SoldierBehavior/Push", "gave up for now")
	Tick(me, npc, 2)
	T.eq(#me.requests, 1, "waiting before retrying")
	Tick(me, npc, Orders.RETRY_WAIT / TICK)
	T.eq(#me.requests, 2, "retried")
end)

T.test("a soldier that stops getting closer asks for a new route, and gives up after a few", function()
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return { P(900, 0) } end })
	Tick(me, npc, 2)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.requests, 2, "a new route")
	for _ = 1, Orders.MAX_REPATHS do Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK + 1) end
	T.eq(npc:Describe(), "SoldierBehavior/Push", "gave up")
end)

T.test("a goal that moves far off is routed to again, no more often than REPATH_INTERVAL", function()
	local me, npc, war = Enlist({ role = AiWar.PUSH, route = function(from, goal) return { goal } end })
	Tick(me, npc, 2)
	war:SetField(Field({ carts = { [BLUE] = Cart(1500) } }))
	Tick(me, npc)
	T.eq(#me.requests, 1, "too soon")
	Tick(me, npc, Orders.REPATH_INTERVAL / TICK)
	T.eq(#me.requests, 2, "routed again")
end)

T.test("nobody moves while the round is frozen", function()
	local me, npc = Enlist({ role = AiWar.PUSH, field = Field({ phase = AiWar.PHASES.frozen }) })
	Tick(me, npc, 3)
	T.eq(#me.moves, 0, "no moves")
	T.eq(#me.requests, 0, "no routes")
end)

T.test("a new role changes the soldier's objective", function()
	local me, npc, _, member = Enlist({ role = AiWar.PUSH, pos = Orders.Goal(Field({}), { team = BLUE, role = AiWar.PUSH, slot = 0 }) })
	Tick(me, npc)
	T.eq(npc:Describe(), "SoldierBehavior/Push", "pushing")
	member.role = AiWar.ESCORT
	Tick(me, npc)
	T.eq(npc:Describe() == "SoldierBehavior/Escort" or npc:Describe() == "SoldierBehavior/Travel", true, "escorting")
end)

T.test("a soldier without a role holds, and takes up one when given", function()
	local me, npc, _, member = Enlist({ role = AiWar.PUSH })
	member.role = nil
	Tick(me, npc, 2)
	T.eq(npc:Describe(), "SoldierBehavior/Idle", "idle")
	T.eq(#me.moves, 0, "no moves")
	member.role = AiWar.PUSH
	Tick(me, npc)
	T.eq(npc:Describe() ~= "SoldierBehavior/Idle", true, "back to work")
end)

T.test("a dead soldier's orders end", function()
	local me, npc = Enlist({ role = AiWar.PUSH })
	Tick(me, npc)
	me.alive = false
	Tick(me, npc)
	T.eq(npc:IsEmpty(), true, "empty")
end)

T.test("the soldier's state shows its route and how its last trip ended, for the war report", function()
	local route = { P(100, 0), P(950, 0) }
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return route end })
	Tick(me, npc, 2)
	local state = npc:State()
	T.eq(state.route, route, "the route")
	T.eq(state.routeIndex, 1, "its waypoint")
	T.eq(state.goal ~= nil, true, "its goal")
	me.pos = Orders.Goal(Field({}), { team = BLUE, role = AiWar.PUSH, slot = 0 })
	Tick(me, npc)
	T.eq(state.trip, "arrived", "arrived")
	local lost, lostNpc = Enlist({ role = AiWar.PUSH, route = function() return false end })
	Tick(lost, lostNpc, 2)
	T.eq(lostNpc:State().trip, "no route", "no route")
end)

T.finish()
