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

T.test("blockers stand across the enemy cart's nose, and have no goal without one", function()
	local field = Field({})
	local member = { team = RED, role = AiWar.BLOCK, slot = 0 }
	Near(Orders.Goal(field, member), P(1000 + Orders.BLOCK_LEAD, 0), "slot 0 dead ahead")
	member.slot = 1
	Near(Orders.Goal(field, member), P(1000 + Orders.BLOCK_LEAD, Orders.BLOCK_SPREAD), "slot 1 left")
	member.slot = 2
	Near(Orders.Goal(field, member), P(1000 + Orders.BLOCK_LEAD, -Orders.BLOCK_SPREAD), "slot 2 right")
	member.slot = Orders.BLOCK_COLUMNS
	Near(Orders.Goal(field, member), P(1000 + Orders.BLOCK_LEAD + Orders.BLOCK_DEPTH, 0), "a row further ahead")
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

-- Setup: the defenders line up past the gates the attackers must come through.

local function SetupField(gates)
	local field = Field({})
	field.setup = true
	field.gates = { [BLUE] = gates }
	return field
end

-- A gate at x = 500 that BLU passes going +x.
local GATE = { pos = P(500, 0), dir = { x = 1, y = 0 } }

T.test("in setup a defender stands in line past the attackers' gate, not at the cart", function()
	local field = SetupField({ GATE })
	local member = { team = RED, role = AiWar.DEFEND, slot = 0 }
	Near(Orders.Goal(field, member), P(500 + Orders.GATE_STANDOFF, 0), "the middle of the line")
	member.slot = 1
	Near(Orders.Goal(field, member), P(500 + Orders.GATE_STANDOFF, Orders.GATE_SPACING), "next along, left")
	member.slot = 2
	Near(Orders.Goal(field, member), P(500 + Orders.GATE_STANDOFF, -Orders.GATE_SPACING), "next along, right")
	member.slot = 3
	Near(Orders.Goal(field, member), P(500 + Orders.GATE_STANDOFF, 2 * Orders.GATE_SPACING), "further along, left")
end)

T.test("blockers line up too, a row behind the defenders", function()
	local field = SetupField({ GATE })
	Near(Orders.Goal(field, { team = RED, role = AiWar.BLOCK, slot = 0 }), P(500 + Orders.GATE_STANDOFF + Orders.GATE_ROW, 0), "second row")
end)

T.test("several gates share the line out between them", function()
	local other = { pos = P(0, 900), dir = { x = 0, y = -1 } }
	local field = SetupField({ GATE, other })
	Near(Orders.Goal(field, { team = RED, role = AiWar.DEFEND, slot = 1 }), P(0, 900 - Orders.GATE_STANDOFF), "the second gate")
end)

T.test("defenders establish their line at the posts found for them, one each by slot", function()
	local field = Field({})
	field.posts = { [RED] = { P(1400, 300, 128), P(1300, -200, -96) } }
	Near(Orders.Goal(field, { team = RED, role = AiWar.DEFEND, slot = 0 }), P(1400, 300, 128), "the first post")
	Near(Orders.Goal(field, { team = RED, role = AiWar.DEFEND, slot = 1 }), P(1300, -200, -96), "the second")
	Near(Orders.Goal(field, { team = RED, role = AiWar.DEFEND, slot = 2 }), P(1000 + Orders.DEFEND_LEAD + 2 * Orders.DEFEND_DEPTH, 0), "more defenders than posts hold the track")
	local setup = SetupField({ GATE })
	setup.posts = field.posts
	Near(Orders.Goal(setup, { team = RED, role = AiWar.DEFEND, slot = 0 }), P(500 + Orders.GATE_STANDOFF, 0), "setup's gate line comes first")
end)

T.test("escorts establish their line at the posts pushed ahead of their cart", function()
	local field = Field({})
	field.forwardPosts = { [BLUE] = { P(1500, 200, 64) } }
	Near(Orders.Goal(field, { team = BLUE, role = AiWar.ESCORT, slot = 0 }), P(1500, 200, 64), "the forward post")
	Near(Orders.Goal(field, { team = BLUE, role = AiWar.ESCORT, slot = 1 }), P(1000 + Orders.ESCORT_LEAD, Orders.LATERAL), "beyond the posts, the track")
end)

T.test("without gates, or once setup ends, defenders hold the track as before", function()
	local member = { team = RED, role = AiWar.DEFEND, slot = 0 }
	Near(Orders.Goal(SetupField({}), member), P(1000 + Orders.DEFEND_LEAD, 0), "no gates found")
	local field = SetupField({ GATE })
	field.setup = false
	Near(Orders.Goal(field, member), P(1000 + Orders.DEFEND_LEAD, 0), "setup over")
	T.eq(Orders.Goal(SetupField({ GATE }), { team = BLUE, role = AiWar.PUSH, slot = 0 }) ~= nil, true, "attackers unchanged")
end)

T.test("a route planned before a door shut is planned again", function()
	local me, npc = Enlist({ role = AiWar.PUSH, field = Field({}) })
	Tick(me, npc, 3)
	T.eq(#me.requests, 1, "one route")
	me.stale = true
	Tick(me, npc, 2)
	T.eq(#me.requests, 2, "another, around the door")
end)

-- Tactics in a fight.

local Tactics = T.require("foundation.aiwar.tactics")

local function Fighting(t)
	local me, npc, war, member = Enlist(t)
	me.enemy = true
	me.enemyPos = t.enemyAt or P(2000, 300)
	return me, npc, war, member
end

T.test("an attacker in contact bounds to cover toward its goal", function()
	local cover = P(1300, 60)
	local me, npc, _, member = Fighting({ role = AiWar.ESCORT, pos = P(1000, 0), covers = { cover }, walkable = function() return true end })
	member.fireTeam.index = 0
	Tick(me, npc, 2)
	T.eq(npc:State().fighting, true, "fighting")
	Near(me.moving, cover, "to the cover ahead")
	T.eq(npc:State().tactic, "bounding", "bounding")
	T.eq(npc:State().element, "moving", "the moving element")
	Near(npc:State().goal, cover, "its goal shows the bound spot")
	Near(npc:State().coverSpot, cover, "and marks it as cover")
end)

T.test("the other element holds and fires while its mates bound", function()
	local me, npc, _, member = Fighting({ role = AiWar.ESCORT, pos = P(1000, 0), walkable = function() return true end })
	member.fireTeam.index = 0
	member.fireTeam.members[member.place] = nil
	member.place = 1
	member.fireTeam.members[1] = member
	member.fireTeam.members[0] = { place = 0, fireTeam = member.fireTeam } -- a mate still bounding
	Tick(me, npc, 2)
	T.eq(npc:State().tactic, "overwatch", "overwatch")
	T.eq(me.holding, true, "holding its ground")
	T.eq(npc:State().element, "holding", "the holding element")
end)

T.test("a flanking team swings out beside the enemy first", function()
	local me, npc, _, member = Fighting({ role = AiWar.ESCORT, pos = P(1000, 0), enemyAt = P(2000, 0), walkable = function() return true end })
	member.fireTeam.index = 1
	Tick(me, npc, 2)
	T.eq(npc:State().tactic, "flanking", "flanking")
	T.near(math.abs(me.moving.y), Tactics.FLANK_OFFSET, 1, "off to the enemy's side")
end)

T.test("a defender in contact takes cover near its post, and moves when hurt", function()
	local first, second = P(1500, 100), P(1450, -120)
	local me, npc = Fighting({ team = RED, role = AiWar.DEFEND, pos = P(1500, 0), enemyAt = P(900, 0), covers = { first, second }, walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(npc:State().tactic, "holding cover", "holding")
	Near(me.moving, first, "to cover")
	Near(npc:State().goal, first, "its goal shows the cover")
	me.hurtAt = me.now
	Tick(me, npc, 8)
	Near(me.moving, second, "to other cover once hurt")
end)

T.test("a defender's team falls back when the enemy is on its post", function()
	local member0
	local me, npc, _, member = Fighting({ team = RED, role = AiWar.DEFEND, pos = P(1500, 0), walkable = function() return true end })
	local post = Orders.Goal(Field({}), member)
	me.enemyPos = { x = post.x + 50, y = post.y, z = 0 }
	Tick(me, npc, 2)
	T.eq(member.fireTeam.fallback, 1, "a step back")
	T.eq(npc:State().tactic, "falling back, step 1", "shown")
end)

T.test("raiders go round the enemy's line, to either side by slot", function()
	local field = Field({})
	local blue = { team = BLUE, role = AiWar.RAID, slot = 0 }
	Near(Orders.Goal(field, blue), P(1000 + Orders.DEFEND_LEAD, Tactics.FLANK_OFFSET), "beside the track ahead, no posts")
	field.posts = { [RED] = { P(1600, -300) } }
	blue.slot = 1
	Near(Orders.Goal(field, blue), Tactics.FlankPoint(P(1000, 0), P(1600, -300), -1), "beside the defenders' post")
	local red = { team = RED, role = AiWar.RAID, slot = 0 }
	Near(Orders.Goal(field, red), P(1000, -Tactics.FLANK_OFFSET), "beside BLU's cart, coming from the checkpoint")
end)

T.test("an attacking raider round the line joins the push", function()
	local me, npc = Enlist({ role = AiWar.RAID, pos = P(1000 + Orders.DEFEND_LEAD, Tactics.FLANK_OFFSET), walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(npc:State().cleared, true, "the line broken")
	T.near(FS.Distance(npc:State().goal, P(1000, 0)), Orders.PUSH_RING, 1e-6, "on to its cart")
end)

T.test("a raider in contact always goes round first, and uses its gadget now and then", function()
	local me, npc, _, member = Fighting({ role = AiWar.RAID, pos = P(1000, 0), enemyAt = P(1500, 0), walkable = function() return true end })
	member.fireTeam.index = 0
	me.gadget = "grenade"
	Tick(me, npc, 2)
	T.eq(npc:State().tactic, "flanking", "flanking though its team is even")
	T.eq(#me.gadgetsAt, 1, "a grenade at the contact")
	Near(me.gadgetsAt[1], P(1500, 0), "thrown at the enemy")
	Tick(me, npc, 4)
	T.eq(#me.gadgetsAt, 1, "not again before GADGET_INTERVAL")
	Tick(me, npc, Orders.GADGET_INTERVAL / TICK)
	T.eq(#me.gadgetsAt, 2, "again after it")
end)

T.test("support stands behind its side's line", function()
	local field = Field({})
	Near(Orders.Goal(field, { team = BLUE, role = AiWar.SUPPORT, slot = 0 }), P(1000 - Orders.SUPPORT_BEHIND, 0), "behind its own cart")
	field.posts = { [RED] = { P(1600, 0) } }
	Near(Orders.Goal(field, { team = RED, role = AiWar.SUPPORT, slot = 0 }), P(1600 + Orders.SUPPORT_BEHIND, 0), "behind the defenders' post")
end)

T.test("support holds its cover and never falls back", function()
	local me, npc, _, member = Fighting({ team = RED, role = AiWar.SUPPORT, pos = P(1920, 0), walkable = function() return true end })
	me.enemyPos = P(1700, 0)
	me.gadget = "manhack"
	Tick(me, npc, 2)
	T.eq(member.fireTeam.fallback, nil, "no step back with the enemy at its post")
	T.eq(npc:State().tactic, "holding cover", "holding")
	T.eq(me.gadgetsAt ~= nil, true, "sends its manhack")
end)

T.test("a trip to the objective ends on contact, for the fight", function()
	local me, npc = Enlist({ role = AiWar.ESCORT, pos = P(0, 0), walkable = function() return true end })
	Tick(me, npc, 2)
	me.enemy = true
	me.enemyPos = P(700, 0)
	Tick(me, npc, 2)
	T.eq(npc:State().trip, "contact", "the trip ended")
	T.eq(npc:State().fighting, true, "into the fight")
end)

-- Escorts follow their cart.

T.test("an escort that can follows its cart, and stops when setup comes", function()
	local field = Field({})
	local me, npc, war = Enlist({ role = AiWar.ESCORT, field = field, follows = true })
	Tick(me, npc, 2)
	T.eq(me.following, true, "following the cart")
	T.eq(me.moving, nil, "its own AI moves it")
	T.eq(npc:State().following, true, "shown")
	war:SetField(SetupField({}))
	Tick(me, npc, 2)
	T.eq(me.following, false, "setup: no following")
end)

T.test("an escort that cannot follow travels to its post as before", function()
	local me, npc = Enlist({ role = AiWar.ESCORT, field = Field({}), follows = false, walkable = function() return true end })
	Tick(me, npc, 3)
	T.eq(me.moving ~= nil or #me.requests > 0, true, "on its way")
end)

-- The defenders' patrol.

-- Ticks until the soldier moves (at most `limit`); how many it took.
local function TicksUntilMoving(me, npc, limit)
	for i = 1, limit do
		Tick(me, npc)
		if me.moving then return i end
	end
	return limit
end

T.test("a defender at its post walks its rounds while the cart stands still", function()
	local field = Field({})
	local member = { team = RED, role = AiWar.DEFEND, slot = 0 }
	local post = Orders.Goal(field, member)
	local spot = P(post.x + 100, post.y + 50)
	local me, npc = Enlist({ team = RED, role = AiWar.DEFEND, field = field, pos = post, patrolSpots = { spot }, walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(me.moving, nil, "resting at the post first")
	T.eq(npc:State().patrolling, true, "shown as patrolling")
	local ticks = TicksUntilMoving(me, npc, Orders.PATROL_REST / TICK + 4)
	T.eq(ticks * TICK >= Orders.PATROL_REST - 1, true, "after its rest")
	Near(me.moving, spot, "then off on its round")
	T.eq(me.gait, Orders.WALK, "at a walk")
end)

T.test("a patrolling defender goes back to its post when the cart is pushed", function()
	local field = Field({})
	local member = { team = RED, role = AiWar.DEFEND, slot = 0 }
	local post = Orders.Goal(field, member)
	local spot = P(post.x + 200, post.y + 100)
	local me, npc, war = Enlist({ team = RED, role = AiWar.DEFEND, field = field, pos = post, patrolSpots = { spot }, walkable = function() return true end })
	TicksUntilMoving(me, npc, Orders.PATROL_REST / TICK + 4)
	Near(me.moving, spot, "on its round")
	me.pos = P(post.x - 300, post.y)
	war:SetField(Field({ carts = { [BLUE] = Cart(1100) } }))
	Tick(me, npc, 4)
	T.eq(npc:State().patrolling, false, "the round is over")
	Near(npc:State().goal, Orders.Goal(Field({ carts = { [BLUE] = Cart(1100) } }), member), "back to the post")
end)

-- Setup: the attackers wander near where they are until it ends.

T.test("in setup an attacker wanders from spot to spot, resting at each, with no route searches for spots in sight", function()
	local spots = { P(100, 0), P(0, 150) }
	local field = SetupField({})
	local me, npc, war = Enlist({ role = AiWar.PUSH, field = field, wanderSpots = spots, walkable = function() return true end })
	Tick(me, npc, 2)
	Near(me.moving, spots[1], "to a spot")
	T.eq(me.gait, Orders.WALK, "at a walk")
	me.pos = P(100, 0)
	Tick(me, npc, 2)
	T.eq(me.moving, nil, "resting there")
	T.eq(me.posing ~= nil, true, "striking a pose")
	T.eq(npc:State().pose, me.posing, "shown")
	Tick(me, npc, Orders.WANDER_REST / TICK + 2)
	Near(me.moving, spots[2], "then on to another")
	T.eq(#me.requests, 0, "no routes")
	T.eq(npc:State().wandering, true, "shown as wandering")
end)

T.test("a wander spot out of sight, rooms away behind the gates, is reached by a route", function()
	local spot = P(900, 600)
	local me, npc = Enlist({
		role = AiWar.ESCORT,
		field = SetupField({}),
		wanderSpots = { spot },
		walkable = function(from, to) return FS.Distance(from, to) < 200 end,
		route = function() return { P(0, 600), spot } end,
	})
	Tick(me, npc, 3)
	T.eq(#me.requests, 1, "a route searched")
	Near(me.requests[1], spot, "to the spot")
	T.eq(npc:State().wandering, true, "still wandering")
end)

T.test("a far goal is reached by a route even when the line to it looks clear", function()
	local spot = P(1000, 0)
	local me, npc = Enlist({ role = AiWar.ESCORT, field = SetupField({}), wanderSpots = { spot }, walkable = function() return true end })
	Tick(me, npc, 3)
	T.eq(#me.requests, 1, "a route searched")
	local near = P(100, 0)
	local me2, npc2 = Enlist({ role = AiWar.ESCORT, field = SetupField({}), wanderSpots = { near }, walkable = function() return true end })
	Tick(me2, npc2, 3)
	T.eq(#me2.requests, 0, "a spot close by and in sight is walked to straight")
end)

T.test("an engine that plans its own routes is given the goal itself, however far", function()
	local spot = P(3000, 0)
	local me, npc = Enlist({ role = AiWar.ESCORT, field = SetupField({}), wanderSpots = { spot }, plansRoutes = true })
	Tick(me, npc, 3)
	Near(me.moving, spot, "straight to the goal")
	T.eq(#me.requests, 0, "no route of ours")
end)

T.test("a wander spot not reached in time is given up for another", function()
	local spots = { P(100, 0), P(0, 150) }
	local me, npc = Enlist({ role = AiWar.ESCORT, field = SetupField({}), wanderSpots = spots })
	Tick(me, npc, 2)
	Tick(me, npc, Orders.WANDER_GIVE_UP / TICK + 2)
	T.eq(me.wandered >= 2, true, "another spot picked")
	local tried = false
	for _, move in ipairs(me.moves) do tried = tried or FS.Distance(move, spots[2]) < 1e-6 end
	T.eq(tried, true, "and headed for")
end)

T.test("when setup ends the attackers head for the cart", function()
	local field = SetupField({})
	local me, npc, war = Enlist({ role = AiWar.PUSH, field = field, wanderSpots = { P(100, 0) } })
	Tick(me, npc)
	war:SetField(Field({}))
	Tick(me, npc, 3)
	T.eq(#me.requests, 1, "a route to the cart")
	T.eq(npc:State().wandering, false, "no longer wandering")
end)

T.test("in setup the defenders race to their line in a panic, and run once it ends", function()
	local field = SetupField({ GATE })
	local me, npc, war = Enlist({ team = RED, role = AiWar.DEFEND, field = field, walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(me.gait, Orders.PANIC, "panicked")
	local after = Field({})
	war:SetField(after)
	Tick(me, npc, 2)
	T.eq(me.gait, Orders.RUN, "a run")
end)

T.test("a wanderer drops its pose when setup ends", function()
	local field = SetupField({})
	local me, npc, war = Enlist({ role = AiWar.PUSH, field = field, wanderSpots = { P(100, 0) }, walkable = function() return true end })
	Tick(me, npc, 2)
	me.pos = P(100, 0)
	Tick(me, npc, 2)
	T.eq(me.posing ~= nil, true, "posing")
	war:SetField(Field({}))
	Tick(me, npc, 2)
	T.eq(me.posing, nil, "up and off to the cart")
end)

T.test("the defenders do not wander in setup", function()
	local me, npc = Enlist({ team = RED, role = AiWar.DEFEND, field = SetupField({}), wanderSpots = { P(100, 0) } })
	Tick(me, npc, 2)
	T.eq(me.wandered, 0, "no wandering")
end)

-- Behaviour -----------------------------------------------------------------

T.test("a pusher asks for a route to the cart and walks it waypoint by waypoint", function()
	local route = { P(100, 0), P(500, 0), P(950, 0) }
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return route end })
	Tick(me, npc)
	T.eq(npc:Describe(), "SoldierBehavior/Travel", "travelling")
	Tick(me, npc)
	T.eq(#me.requests, 1, "one route asked for, the cart being out of walking line")
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
	T.eq(npc:Describe(), "SoldierBehavior/EstablishLine", "fighting at the post")
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

-- Following a moving cart ------------------------------------------------------

local function PushSpot(distance)
	return Orders.Goal(Field({ carts = { [BLUE] = Cart(distance) } }), { team = BLUE, role = AiWar.PUSH, slot = 0 })
end

T.test("a pusher at the cart keeps to its spot as the cart moves, without searching", function()
	local me, npc, war = Enlist({ role = AiWar.PUSH, walkable = function() return true end })
	me.pos = PushSpot(1000)
	Tick(me, npc)
	T.eq(me.moving, nil, "in place: left to the engine")
	war:SetField(Field({ carts = { [BLUE] = Cart(1040) } }))
	Tick(me, npc)
	Near(me.moving, PushSpot(1040), "runs after its spot")
	T.eq(#me.requests, 0, "no route needed")
	me.pos = PushSpot(1040)
	Tick(me, npc)
	T.eq(me.moving, nil, "caught up: left to the engine")
end)

T.test("a soldier near its goal that can walk straight to it chases it without waiting on a route", function()
	local me, npc, war = Enlist({ role = AiWar.PUSH, routeDelay = 100, pos = P(900, 0), walkable = function() return true end })
	Tick(me, npc, 2)
	Near(me.moving, PushSpot(1000), "straight at the cart")
	war:SetField(Field({ carts = { [BLUE] = Cart(1100) } }))
	Tick(me, npc)
	Near(me.moving, PushSpot(1100), "follows it as it moves")
end)

T.test("a soldier chasing a goal it keeps closing on is not stuck, however far the goal moves", function()
	local me, npc, war = Enlist({ role = AiWar.PUSH, walkable = function() return true end })
	Tick(me, npc)
	for i = 1, (Orders.STUCK_TIME * 3) / TICK do
		war:SetField(Field({ carts = { [BLUE] = Cart(1000 + i * 20) } }))
		me.pos = P(me.pos.x + 20, 0)
		Tick(me, npc)
	end
	T.eq(npc:Describe(), "SoldierBehavior/Travel", "still going")
	T.eq(npc:State().trip, nil, "never gave up")
end)

T.test("a stuck soldier first steps aside, then goes on along its new route", function()
	local route = { P(900, 0) }
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return route end })
	Tick(me, npc, 2)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.requests, 2, "a new route")
	T.near(FS.Distance(me.moving, P(0, 0)), Orders.SIDESTEP_DISTANCE, 1e-6, "a step aside first")
	local aside = me.moving
	Tick(me, npc, Orders.SIDESTEP_TIME / TICK + 1)
	Near(me.moving, route[1], "then the route again")
	local before = #me.moves
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	local another = false
	for i = before + 1, #me.moves do
		local move = me.moves[i]
		if math.abs(FS.Distance(move, P(0, 0)) - Orders.SIDESTEP_DISTANCE) < 1e-6 and FS.Distance(move, aside) > 1 then another = true end
	end
	T.eq(another, true, "the next step aside goes another way")
end)

T.test("a soldier stuck on something only NPCs collide with is let through it, and runs on", function()
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return { P(900, 0) } end,
		passable = function() return true end,
	})
	Tick(me, npc, 2)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.passed, 1, "let through")
	Near(me.passed[1], P(900, 0), "toward its waypoint")
	T.eq(#me.requests, 1, "no new route needed")
	Near(me.moving, P(900, 0), "running on")
	T.eq(npc:State().passed, 1, "counted for the report")
end)

T.test("a soldier stuck against a solid entity walks round it, then goes on along its route", function()
	local route = { P(900, 0) }
	local beside = P(300, 120)
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return route end,
		detour = function() return beside end,
	})
	Tick(me, npc, 2)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.detours, 1, "a detour")
	Near(me.moving, beside, "to the point beside it")
	T.eq(#me.requests, 1, "no new route")
	me.pos = P(beside.x, beside.y)
	Tick(me, npc)
	Near(me.moving, route[1], "back on its route")
end)

T.test("a soldier stuck while climbing hops at once, without stepping aside first", function()
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return { P(100, 0, 60), P(900, 0, 120) } end,
		hoppable = function() return true end,
	})
	Tick(me, npc, 2)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.hops, 1, "hopped up")
	T.eq(me.hops[1].z, 60, "onto the waypoint above")
	T.eq(#me.requests, 1, "no step aside, no new route")
end)

T.test("a soldier stuck through every step aside hops toward its waypoint when a player could walk there", function()
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return { P(900, 0) } end,
		hoppable = function() return true end,
	})
	Tick(me, npc, 2)
	for _ = 1, Orders.MAX_REPATHS + 1 do Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK + 1) end
	T.eq(#me.hops, 1, "one hop")
	Near(me.hops[1], P(Orders.HOP_DISTANCE, 0), "a hop's length toward the waypoint")
	T.eq(npc:Describe(), "SoldierBehavior/Travel", "still on its way")
	T.eq(npc:State().hops, 1, "counted for the report")
end)

T.test("a hop to somewhere a player could not walk is refused, and the trip ends", function()
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return { P(900, 0) } end })
	Tick(me, npc, 2)
	for _ = 1, Orders.MAX_REPATHS + 1 do Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK + 1) end
	T.eq(#me.hops, 0, "no hop")
	T.eq(npc:State().trip, "stuck", "gave up")
end)

T.test("a straight chase that goes nowhere falls back to a route", function()
	local me, npc = Enlist({ role = AiWar.PUSH, walkable = function() return true end })
	Tick(me, npc)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK + 1)
	T.eq(#me.requests >= 1, true, "asked for a route")
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
