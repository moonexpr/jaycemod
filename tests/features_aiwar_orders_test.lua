-- features.aiwar.orders: the Actions a Combine or Resistance soldier
-- follows in the AI war, driven as scenarios against tests/fake_soldier.lua.
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local N = npc.nextbot
local Debug = T.require("features.nbdebug.model")
local AiWar = T.require("features.aiwar.model")
local Orders = T.require("features.aiwar.orders")
-- what the war registered, compiled as the controller compiles it
local BEHAVIORS = nextsoldier.behaviors.Shared:Compile()
local Soldier = nextsoldier.soldier
local Track = math.polyline
local Teams = gameplay.teams
local Speech = nextsoldier.speech

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
		doctrine = Orders.PAYLOAD,
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
	local npc = N.Npc.New(Orders, { war = war, member = member, behaviors = t.behaviors or BEHAVIORS }, me)
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

-- A role with stages (Stage) runs as the action of its stage under its
-- side's, so a CTF courier shows ScenarioMonitor/CaptureFlagCourier/
-- RetrieveFlag, then ReturnHome once it has the flag.
local STAGED = {
	NAME = "staged",
	ROLES = {
		[AiWar.COURIER] = {
			name = "Courier",
			arrive = 48,
			leash = 300,
			rushes = false,
			Goal = function() return P(500, 0) end,
			Stage = function(field) return field.stage end,
		},
	},
	WaitsForSetup = function() return false end,
	ChaseAnchor = function() return nil end,
	SIDES = { courier = "CaptureFlagCourier" },
	Side = function() return "courier" end,
	Threat = function() return nil end,
	PatrolMark = function() return {} end,
	PatrolHolds = function() return true end,
}

local function StagedField(stage)
	return { phase = AiWar.PHASES.running, carts = {}, doctrine = STAGED, stage = stage }
end

-- A scenario registered with a monitor of its own (wartactics.scenarios)
-- has ScenarioMonitor run it in place of the doctrine's side.
T.test("a registered scenario's own monitor runs under ScenarioMonitor, and leaves with its scenario", function()
	local HoldLine = N.Action:Extend("HoldLine")
	local Holdout = nextsoldier.monitor.New("Holdout", function(state) return HoldLine:New(state) end)
	local registry = nextsoldier.behaviors.New()
	for _, name in ipairs(BEHAVIORS:Names()) do registry:Register({ name = name, behavior = BEHAVIORS:Get(name) }) end
	registry:Register({ name = "Holdout", behavior = Holdout })
	local field = Field({})
	field.scenario = { name = "holdout", monitor = "Holdout" }
	local me, npc, war = Enlist({ field = field, behaviors = registry:Compile() })
	Tick(me, npc)
	T.eq(npc:Describe():find("ScenarioMonitor/Holdout/HoldLine", 1, true) ~= nil, true, npc:Describe())
	local plain = Field({})
	plain.scenario = { name = "payload" }
	war:SetField(plain)
	Tick(me, npc, 2)
	T.eq(npc:Describe():find("Holdout", 1, true), nil, "back to the doctrine's side: " .. npc:Describe())
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "a job again: " .. npc:Describe())
end)

T.test("a role's stage names its action under its side, and a new stage changes it", function()
	local me, npc, war = Enlist({ role = AiWar.COURIER, field = StagedField("RetrieveFlag") })
	local job, _, side = Orders.JobOf(npc:Describe())
	T.eq(side, "CaptureFlagCourier", "the side: its job")
	T.eq(job:match("^[^/]+"), "RetrieveFlag", "its stage: " .. job)
	war:SetField(StagedField("ReturnHome"))
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()):match("^[^/]+"), "ReturnHome", "the next stage")
end)

-- A stage may override its role's settings (STAGES): a defender that
-- picks up the enemy flag delivers it as a courier would, close enough to
-- step into the capture zone.
T.test("a stage's own settings override its role's", function()
	local role = STAGED.ROLES[AiWar.COURIER]
	local asked = {}
	local base = role.Goal
	role.Goal = function() asked.role = true return P(500, 0) end
	role.STAGES = { Deliver = { arrive = 8, Goal = function() asked.stage = true return P(900, 0) end } }
	local me, npc = Enlist({ role = AiWar.COURIER, field = StagedField("Deliver") })
	Tick(me, npc, 4)
	T.eq(asked.stage, true, "the stage's goal")
	T.eq(asked.role, nil, "not the role's")
	role.Goal, role.STAGES = base, nil
end)

-- A stage with its own settings is still its job: its trip goes on under
-- it (an MvM carrier's DeliverFlag travels to the hatch), and ends as the
-- stage does.
T.test("a stage with its own settings travels to its goal, until the stage changes", function()
	local role = STAGED.ROLES[AiWar.COURIER]
	role.STAGES = { Deliver = { arrive = 8, Goal = function() return P(3000, 0) end } }
	local me, npc, war = Enlist({ role = AiWar.COURIER, field = StagedField("Deliver"), walkable = function() return true end })
	Tick(me, npc, 4)
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "travelling: " .. npc:Describe())
	T.eq(me.moving ~= nil, true, "moving")
	Tick(me, npc, 8)
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "still travelling: " .. npc:Describe())
	war:SetField(StagedField("RetrieveFlag"))
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()):match("^[^/]+"), "RetrieveFlag", "a new stage ends the trip: " .. npc:Describe())
	role.STAGES = nil
end)

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

T.test("an escort's goal is the nearest way into the support sphere ahead of its cart", function()
	local field = Field({})
	local center, radius = Orders.SupportSphere(field.carts[BLUE])
	Near(center, P(1000 + Orders.ESCORT_SPHERE_LEAD, 0), "the sphere leads the cart")
	T.eq(radius, Orders.SUPPORT_SPHERE, "a wide one")
	local member = { team = BLUE, role = AiWar.ESCORT, slot = 0, pos = P(3000, 0) }
	Near(Orders.Goal(field, member), P(center.x + radius * Orders.SPHERE_ENTER, 0), "well inside, on its side")
	member.pos = P(1300, 100)
	Near(Orders.Goal(field, member), P(1300, 100), "already well inside: where it is")
end)

T.test("without gates, or once setup ends, defenders hold the track as before", function()
	local member = { team = RED, role = AiWar.DEFEND, slot = 0 }
	Near(Orders.Goal(SetupField({}), member), P(1000 + Orders.DEFEND_LEAD, 0), "no gates found")
	local field = SetupField({ GATE })
	field.setup = false
	Near(Orders.Goal(field, member), P(1000 + Orders.DEFEND_LEAD, 0), "setup over")
	T.eq(Orders.Goal(SetupField({ GATE }), { team = BLUE, role = AiWar.PUSH, slot = 0 }) ~= nil, true, "attackers unchanged")
end)

T.test("DrGBase asks the orders whether to attack: the humiliated hold fire", function()
	local me, npc = Enlist({ role = AiWar.DEFEND, team = RED })
	T.eq(npc:Query("ShouldAttack", "them"), N.ANSWER_UNDEFINED, "armed: DrGBase decides")
	me.disarmed = true
	Tick(me, npc)
	T.eq(npc:Query("ShouldAttack", "them"), N.ANSWER_NO, "humiliated: no")
	T.eq(npc:Query("ShouldHurry"), N.ANSWER_YES, "and away")
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/Humiliated", "the tactical monitor and all under it buried")
	local _, frames = npc:Stack()
	T.eq(Debug.Tdbn(frames), "NextSoldier::TacticalMonitor<Humiliated>", "TDBN: humiliation supersedes the tactical monitor")
	me.disarmed = false
	Tick(me, npc, 2)
	T.eq(npc:Query("ShouldAttack", "them"), N.ANSWER_UNDEFINED, "rearmed")
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "back to its job")
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

local Tactics = wartactics.fireteam

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

T.test("in a race, raiders and support split between the carts by their team's defense share", function()
	local field = Field({ carts = { [BLUE] = Cart(1000), [RED] = Cart(2000) } })
	field.defense = { [RED] = 0.8 }
	local defense = 0
	for slot = 0, 9 do
		if Orders.Focus(field, { team = RED, role = AiWar.RAID, slot = slot }) == "defense" then defense = defense + 1 end
	end
	T.eq(defense, 8, "eight in ten on BLU's cart")
	field.defense[RED] = 0.2
	defense = 0
	for slot = 0, 9 do
		if Orders.Focus(field, { team = RED, role = AiWar.RAID, slot = slot }) == "defense" then defense = defense + 1 end
	end
	T.eq(defense, 2, "two in ten once RED leads")
	T.eq(Orders.Focus(Field({}), { team = RED, slot = 0 }), "defense", "one cart, the enemy's: defense")
	T.eq(Orders.Focus(Field({}), { team = BLUE, slot = 0 }), "offense", "one cart, its own: offense")
end)

T.test("a race raider on offense goes round the line ahead of its own cart, on defense round the enemy's escorts", function()
	local field = Field({ carts = { [BLUE] = Cart(1000), [RED] = Cart(2000) } })
	field.defense = { [RED] = 1 }
	local member = { team = RED, role = AiWar.RAID, slot = 0 }
	T.eq(Orders.Focus(field, member), "defense", "all defense")
	Near(Orders.Goal(field, member), Tactics.FlankPoint(P(4000, 0), P(1000, 0), 1), "beside BLU's cart")
	field.defense[RED] = 0
	Near(Orders.Goal(field, member), Tactics.FlankPoint(P(2000, 0), P(2000 + Orders.DEFEND_LEAD, 0), 1), "beside the track ahead of its own")
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

-- Medics

T.test("a medic heals the teammate that needs it most, players first, and holds fire while it does", function()
	local field = Field({})
	field.patients = { [BLUE] = {
		{ handle = "soldier", pos = P(900, 0), health = 0.3, player = false },
		{ handle = "player", pos = P(1100, 0), health = 0.5, player = true },
		{ handle = "scratched", pos = P(1000, 50), health = 0.97, player = false },
	} }
	local me, npc = Enlist({ role = AiWar.MEDIC, pos = P(1000, 0), field = field, walkable = function() return true end })
	Tick(me, npc)
	T.eq(npc:State().tactic, "healing", "healing")
	T.eq(npc:State().healing.handle, "player", "the player: half its health, counting double")
	T.eq(me.healing, "player", "its beam on it")
	T.eq(npc:Query("ShouldAttack", "them"), N.ANSWER_NO, "holding fire")
	field.patients[BLUE][2].health = 0.99
	Tick(me, npc)
	T.eq(npc:State().healing.handle, "soldier", "healed: the next")
	field.patients[BLUE] = {}
	Tick(me, npc)
	T.eq(me.healing, nil, "no one left: the beam off")
	T.eq(npc:Query("ShouldAttack", "them"), N.ANSWER_UNDEFINED, "free to fight")
end)

-- A medic's own squad comes first, as players and callers do (MvM's medic
-- in the bomb carrier's squad heals the carrier).
T.test("a medic counts its squadmates double", function()
	local field = { patients = { [BLUE] = {
		{ handle = "carrier", pos = P(1100, 0), health = 0.8, player = false },
		{ handle = "stranger", pos = P(1050, 0), health = 0.7, player = false },
	} } }
	local medic = { handle = "medic", team = BLUE }
	T.eq(Orders.PickPatient(field, medic, P(1000, 0)).handle, "stranger", "outside a squad: the more hurt")
	medic.fireTeam = { members = { [0] = medic, [1] = { handle = "carrier" } } }
	T.eq(Orders.PickPatient(field, medic, P(1000, 0)).handle, "carrier", "its squadmate first")
end)

T.test("a medic out of reach closes in before its beam goes on", function()
	local field = Field({})
	field.patients = { [BLUE] = { { handle = "far", pos = P(2000, 0), health = 0.2, player = false } } }
	local me, npc = Enlist({ role = AiWar.MEDIC, pos = P(1000, 0), field = field, walkable = function() return true end })
	Tick(me, npc)
	T.eq(me.healing, nil, "beyond HEAL_RANGE: no beam")
	Near(me.moving, P(2000 - Orders.MEDIC_STANDOFF, 0), "to its standoff")
end)

-- Riding the cart and retreating

T.test("a pusher at its cart sits on it, and gets off when it takes another job", function()
	local me, npc, _, member = Enlist({ role = AiWar.PUSH })
	me.pos = Orders.Goal(Field({}), { team = BLUE, role = AiWar.PUSH, slot = 0 })
	Tick(me, npc, 2)
	T.eq(me.seated, true, "sitting on the cart")
	T.eq(npc:State().tactic, "riding the cart", "riding")
	member.role = AiWar.ESCORT
	Tick(me, npc)
	T.eq(me.seated, false, "off it")
end)

T.test("a soldier badly hurt gets off the cart and retreats to cover, until healed", function()
	local cover = P(700, 0)
	local me, npc = Enlist({ role = AiWar.PUSH, covers = { cover }, enemyPos = P(1400, 0) })
	me.pos = Orders.Goal(Field({}), { team = BLUE, role = AiWar.PUSH, slot = 0 })
	Tick(me, npc, 2)
	T.eq(me.seated, true, "riding")
	me.health = 30
	Tick(me, npc)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "retreating, its squad and job waiting")
	T.eq(me.seated, false, "off the cart")
	Tick(me, npc)
	Near(me.moving, cover, "to cover from the threat")
	T.eq(npc:Query("ShouldHurry"), N.ANSWER_YES, "running")
	me.health = 75
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "healed: back to its job")
	me.health = 30
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "not again before RETREAT_COOLDOWN")
end)

T.test("a soldier hurt hard in a moment retreats even with health left", function()
	local me, npc = Enlist({ role = AiWar.DEFEND, team = RED, enemyPos = P(1400, 0) })
	Tick(me, npc)
	npc:Event("OnInjured", "attacker", 25)
	npc:Event("OnInjured", "attacker", 20)
	me.health = 55
	Tick(me, npc)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "45 of 100 in a moment")
end)

-- Chasing

T.test("a blocker goes after a weakened enemy to finish it, and back to work when it is dead", function()
	local me, npc = Enlist({ role = AiWar.BLOCK, team = RED, pos = P(1000, 0) })
	me.enemy, me.enemyHandle, me.enemyPos, me.enemyHealth = true, "pusher", P(1800, 200), 0.4
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Chase", "chasing")
	Near(me.moving, P(1800, 200), "to it")
	T.eq(npc:Query("ShouldHurry"), N.ANSWER_YES, "running")
	T.eq(npc:Query("SelectMoreDangerousThreat", "other", "pusher"), "pusher", "shooting the one it chases")
	me.enemyHealth = nil
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()) ~= "Chase", true, "killed: back to blocking")
end)

T.test("a line soldier chases only a nearly dead enemy close by, and only when well itself", function()
	local me, npc = Enlist({ role = AiWar.ESCORT, pos = P(1000, 0) })
	me.enemy, me.enemyHandle, me.enemyPos, me.enemyHealth = true, "defender", P(1300, 0), 0.4
	Tick(me, npc, 2)
	T.eq(npc:State().chases, nil, "40% left: not worth it")
	me.enemyHealth = 0.2
	me.health = 50
	Tick(me, npc, 2)
	T.eq(npc:State().chases, nil, "hurt itself: no")
	me.health = 100
	Tick(me, npc, 2)
	T.eq(npc:State().chases, 1, "then it goes")
end)

T.test("a pusher never leaves the cart to chase", function()
	local me, npc = Enlist({ role = AiWar.PUSH })
	me.pos = Orders.Goal(Field({}), { team = BLUE, role = AiWar.PUSH, slot = 0 })
	me.enemy, me.enemyHandle, me.enemyPos, me.enemyHealth = true, "blocker", P(1100, 0), 0.1
	Tick(me, npc, 3)
	T.eq(npc:State().chases, nil, "stays")
end)

T.test("a chase keeps within CHASE_LEASH of the cart", function()
	local me, npc = Enlist({ role = AiWar.BLOCK, team = RED, pos = P(1000, 0) })
	me.enemy, me.enemyHandle, me.enemyHealth = true, "pusher", 0.4
	me.enemyPos = P(1000, Orders.CHASE_LEASH + 100)
	Tick(me, npc, 2)
	T.eq(npc:State().chases, nil, "its quarry beyond the leash: no chase")
	me.enemyPos = P(1000, 800)
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Chase", "within it: after it")
	me.enemyPos = P(1000, Orders.CHASE_LEASH + 100)
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()) ~= "Chase", true, "it ran past the leash: let go")
end)

T.test("a soldier that needs to retreat does not start a chase", function()
	local me, npc = Enlist({ role = AiWar.BLOCK, team = RED, pos = P(1000, 0) })
	me.enemy, me.enemyHandle, me.enemyPos, me.enemyHealth = true, "pusher", P(1400, 0), 0.2
	me.health = 30
	Tick(me, npc, 2)
	T.eq(npc:State().chases, nil, "no chase")
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "it retreats instead")
end)

T.test("a chaser that gets hurt badly still retreats", function()
	local me, npc = Enlist({ role = AiWar.BLOCK, team = RED, pos = P(1000, 0) })
	me.enemy, me.enemyHandle, me.enemyPos, me.enemyHealth = true, "pusher", P(1600, 0), 0.4
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Chase", "chasing")
	me.health = 20
	Tick(me, npc)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "retreat wins")
end)

-- Squads

-- Two soldiers of one role in one squad of one war: a (older) and b (no
-- squads min, so they fill one squad).
local function Squadmates(t)
	local war = AiWar.War.New()
	war:SetSquadsMin(1)
	war:Assign({ [BLUE] = true })
	war:SetField(t.field or Field({}))
	local a = war:Enlist("a", t.team or BLUE, true)
	local b = war:Enlist("b", t.team or BLUE, true)
	war:ChangeRole(a, t.role)
	war:ChangeRole(b, t.role)
	local meA, meB = FS.Soldier(t.a or {}), FS.Soldier(t.b or {})
	meA.enemy, meB.enemy = (t.a or {}).enemy == true, (t.b or {}).enemy == true
	local npcA = N.Npc.New(Orders, { war = war, member = a, behaviors = BEHAVIORS }, meA)
	local npcB = N.Npc.New(Orders, { war = war, member = b, behaviors = BEHAVIORS }, meB)
	local function TickBoth(n)
		for _ = 1, n or 1 do
			meA:Advance(TICK)
			npcA:Update(TICK)
			meB:Advance(TICK)
			npcB:Update(TICK)
		end
	end
	TickBoth()
	return { war = war, a = a, b = b, meA = meA, meB = meB, npcA = npcA, npcB = npcB, Tick = TickBoth }
end

local function SquadRoleOf(npc)
	local _, role = Orders.JobOf(npc:Describe())
	return role
end

T.test("a squad's oldest soldier leads it, the other follows, and leads once the leader is gone", function()
	local s = Squadmates({ role = AiWar.ESCORT })
	T.eq(s.a.fireTeam, s.b.fireTeam, "one squad")
	T.eq(SquadRoleOf(s.npcA), "SquadLeader", "a leads")
	T.eq(SquadRoleOf(s.npcB), "SquadMember", "b follows")
	s.war:Discharge("a")
	s.Tick()
	T.eq(SquadRoleOf(s.npcB), "SquadLeader", "b leads now")
end)

T.test("a hero takes over its squad", function()
	local s = Squadmates({ role = AiWar.ESCORT })
	s.b.hero = true
	s.Tick()
	T.eq(SquadRoleOf(s.npcB), "SquadLeader", "the hero leads")
	T.eq(SquadRoleOf(s.npcA), "SquadMember", "the veteran follows")
end)

T.test("a squad member fights the enemy its leader fights", function()
	local s = Squadmates({ role = AiWar.ESCORT, a = { enemy = true, enemyPos = P(1500, 0) } })
	s.meA.enemyHandle = "e1"
	s.Tick()
	T.eq(s.npcB:Query("SelectMoreDangerousThreat", "e2", "e1"), "e1", "the leader's enemy")
	T.eq(s.npcB:Query("SelectMoreDangerousThreat", "e2", "e3"), N.ANSWER_UNDEFINED, "neither: DrGBase decides")
	T.eq(s.npcA:Query("SelectMoreDangerousThreat", "e2", "e1"), N.ANSWER_UNDEFINED, "the leader chooses for itself")
end)

T.test("a squad member far from its leader in a fight regroups on it first", function()
	local s = Squadmates({ role = AiWar.ESCORT,
		a = { pos = P(1000, 0), enemy = true, enemyPos = P(1400, 300), walkable = function() return true end },
		b = { pos = P(2000, 0), walkable = function() return true end } })
	s.Tick(2)
	local state = s.npcB:State()
	T.eq(state.tactic, "regrouping on its leader", "regrouping")
	T.eq(FS.Distance(s.meB.moving, P(1000, 0)) < FS.Distance(P(2000, 0), P(1000, 0)), true, "toward its leader")
end)

T.test("squadmates never take the same cover", function()
	local covers = { P(1500, 100), P(1450, -120) }
	local s = Squadmates({ team = RED, role = AiWar.DEFEND,
		a = { pos = P(1500, 0), enemy = true, enemyPos = P(900, 0), covers = covers, walkable = function() return true end },
		b = { pos = P(1520, 0), enemy = true, enemyPos = P(900, 0), covers = covers, walkable = function() return true end } })
	s.Tick(2)
	T.eq(s.npcA:State().coverSpot ~= nil and s.npcB:State().coverSpot ~= nil, true, "both in cover")
	T.eq(FS.Distance(s.npcA:State().coverSpot, s.npcB:State().coverSpot) > 1, true, "different spots")
end)

-- Lanes and following

T.test("an offensive squad's member follows its leader, spaced by place", function()
	local s = Squadmates({ role = AiWar.ESCORT, a = { pos = P(3000, 0) }, b = { pos = P(3500, 0) } })
	s.Tick(2)
	T.eq(s.npcB:State().tactic, "following its leader", "following")
	Near(s.meB.moving, P(3000 + Orders.FOLLOW_SPACING * (s.b.place + 1), 0), "behind it")
end)

-- A soldier attached to another's squad (MvM's medic with the bomb's
-- carrier) follows the one it was attached to, not the squad's leader.
T.test("an attached soldier follows its host, not the squad's leader", function()
	local s = Squadmates({ role = AiWar.PUSH, a = { pos = P(4500, 0) }, b = { pos = P(3000, 0) } })
	local medic = s.war:Enlist("medic", BLUE, true)
	s.war:ChangeRole(medic, AiWar.PUSH)
	local meC = FS.Soldier({ pos = P(3600, 0) })
	local npcC = N.Npc.New(Orders, { war = s.war, member = medic, behaviors = BEHAVIORS }, meC)
	s.war:Attach(medic, s.b)
	T.eq(medic.fireTeam, s.a.fireTeam, "in the squad a leads")
	for _ = 1, 2 do
		s.Tick()
		meC:Advance(TICK)
		npcC:Update(TICK)
	end
	T.eq(npcC:State().tactic, "following its leader", "following")
	T.eq(FS.Distance(meC.moving, P(3000, 0)) < FS.Distance(meC.moving, P(4500, 0)), true, "toward b, its host")
end)

-- Capture and hold squads: tests/aiwar_koth_test.lua, on a hill.
T.test("a pushing squad's member follows its leader to the cart", function()
	local s = Squadmates({ role = AiWar.PUSH, a = { pos = P(3000, 0) }, b = { pos = P(3500, 0) } })
	s.Tick(2)
	T.eq(s.npcB:State().tactic, "following its leader", "following")
end)

T.test("a squad member stops following once its leader is at the objective, for its own place", function()
	local s = Squadmates({ role = AiWar.PUSH, a = { pos = P(3000, 0) }, b = { pos = P(3500, 0) } })
	s.Tick(2)
	s.meA.pos = Orders.Goal(s.war.field, s.a)
	s.Tick(2)
	T.eq(s.npcB:State().tactic ~= "following its leader", true, "on to its own place")
end)

-- x in the war's own squad, y in one formed by hand; y is moved into x's.
local function Reassigned(t)
	local war = AiWar.War.New()
	war:SetSquadsMin(1)
	war:Assign({ [BLUE] = true })
	war:SetField(Field({}))
	local x = war:Enlist("x", BLUE, true)
	local y = war:Enlist("y", BLUE, true)
	war:FormSquad(y)
	T.eq(x.fireTeam ~= nil and x.fireTeam ~= y.fireTeam and not x.fireTeam.manual, true, "x in the war's own squad")
	y.hero = t.hero
	local meX, meY = FS.Soldier({ pos = P(3000, 0) }), FS.Soldier({ pos = P(3500, 0) })
	local npcX = N.Npc.New(Orders, { war = war, member = x, behaviors = BEHAVIORS }, meX)
	local npcY = N.Npc.New(Orders, { war = war, member = y, behaviors = BEHAVIORS }, meY)
	local function TickBoth(n)
		for _ = 1, n or 1 do
			meX:Advance(TICK)
			npcX:Update(TICK)
			meY:Advance(TICK)
			npcY:Update(TICK)
		end
	end
	TickBoth()
	T.eq(war:JoinSquad(y, x.fireTeam), true, "joined")
	TickBoth(2)
	return { x = x, y = y, npcX = npcX, npcY = npcY }
end

T.test("a soldier moved into another squad by hand follows that squad's leader", function()
	local s = Reassigned({})
	T.eq(SquadRoleOf(s.npcX), "SquadLeader", "x still leads")
	T.eq(s.npcY:State().tactic, "following its leader", "y follows x")
end)

T.test("a hero moved into a squad by hand follows its leader, never takes it over", function()
	local s = Reassigned({ hero = true })
	T.eq(SquadRoleOf(s.npcX), "SquadLeader", "x still leads")
	T.eq(SquadRoleOf(s.npcY), "SquadMember", "the hero joined as a member")
	T.eq(s.npcY:State().tactic, "following its leader", "and follows x")
end)

T.test("a squad leader walks its lane to its goal, then leaves it", function()
	local field = Field({})
	field.lanes = { [BLUE] = { key = "plan", { ids = { 1, 2, 3 }, points = { P(2500, 500), P(2000, 600), P(1500, 300) }, length = 1800 } } }
	local s = Squadmates({ role = AiWar.ESCORT, field = field, a = { pos = P(3000, 0), walkable = function() return true end } })
	s.war:SetField(field)
	s.Tick(2)
	T.eq(s.a.fireTeam.lane ~= nil, true, "the squad holds the lane")
	Near(s.meA.moving, P(2500, 500), "the lane's first waypoint")
	T.eq(s.npcA:State().onLane, 1, "on lane 1")
	s.meA.pos = P(1500, 300)
	s.Tick(2)
	T.eq(s.npcA:State().onLane, nil, "walked: off the lane")
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

T.test("a defender at a post found for it keeps walking its rounds while the cart creeps forward", function()
	local post = P(1600, 300)
	local function Creeping(distance)
		local field = Field({ carts = { [BLUE] = Cart(distance) } })
		field.posts = { [RED] = { post } }
		return field
	end
	local spot = P(post.x + 100, post.y + 50)
	local me, npc, war = Enlist({ team = RED, role = AiWar.DEFEND, field = Creeping(1000), pos = post, patrolSpots = { spot }, walkable = function() return true end })
	-- the attackers push it a little every tick, more than CART_STILL in all
	local distance, moved = 1000, false
	for _ = 1, Orders.PATROL_REST / TICK + 4 do
		distance = distance + 2
		war:SetField(Creeping(distance))
		Tick(me, npc)
		if me.moving then moved = true break end
	end
	T.eq(moved, true, "off on its round after its rest")
	Near(me.moving, spot, "to its patrol spot")
end)

-- Watching: a soldier standing with no enemy faces where the threat is.

-- The bearing in degrees from p to q.
local function Bearing(p, q) return math.deg(math.atan2(q.y - p.y, q.x - p.x)) end

local function Turned(a, b)
	local d = (a - b) % 360
	return d > 180 and d - 360 or d
end

T.test("a defender watches the enemy's cart, glancing either side of it in turn", function()
	local field = Field({})
	local post = Orders.Goal(field, { team = RED, role = AiWar.DEFEND, slot = 0 })
	local me, npc = Enlist({ team = RED, role = AiWar.DEFEND, field = field, pos = post, now = 0 })
	Tick(me, npc)
	local ahead = Bearing(post, field.carts[BLUE].pos)
	Near(me.watching, field.carts[BLUE].pos, "straight at the cart first")
	local seen = {}
	for _ = 1, #Orders.GLANCES * Orders.GLANCE_TIME / TICK do
		Tick(me, npc)
		seen[math.floor(Turned(Bearing(post, me.watching), ahead) + 0.5)] = true
	end
	for _, glance in ipairs(Orders.GLANCES) do T.eq(seen[glance], true, "a glance of " .. glance .. " degrees") end
end)

T.test("an attacker watches the track ahead of its cart, where the defenders wait", function()
	local field = Field({})
	local cart = field.carts[BLUE]
	local me, npc = Enlist({ team = BLUE, role = AiWar.PUSH, field = field, pos = cart.pos, now = 0 })
	Tick(me, npc)
	Near(me.watching, cart.track:Offset(cart.distance + Orders.DEFEND_LEAD, 0), "ahead along the track")
end)

T.test("a soldier whose fire team has a contact watches the contact", function()
	local field = Field({})
	local post = Orders.Goal(field, { team = RED, role = AiWar.DEFEND, slot = 0 })
	local me, npc, _, member = Enlist({ team = RED, role = AiWar.DEFEND, field = field, pos = post, now = 0 })
	local seen = P(post.x, post.y + 700)
	Tactics.Report(member.fireTeam, seen, me:Now())
	Tick(me, npc)
	Near(me.watching, seen, "where the enemy was seen")
end)

T.test("a soldier that hears gunfire looks there, then back at the threat once it forgets", function()
	local field = Field({})
	local post = Orders.Goal(field, { team = RED, role = AiWar.DEFEND, slot = 0 })
	local me, npc = Enlist({ team = RED, role = AiWar.DEFEND, field = field, pos = post, now = 0 })
	local shot = P(post.x - 400, post.y + 900)
	npc:Event("OnHeard", shot)
	Tick(me, npc)
	Near(me.watching, shot, "toward the shot")
	Tick(me, npc, Orders.HEARD_MEMORY / TICK + 1)
	T.eq(FS.Distance(me.watching, shot) > 1, true, "forgotten")
end)

T.test("with no threat known, a soldier watches nothing in particular", function()
	local me, npc = Enlist({ team = RED, role = AiWar.DEFEND, field = Field({ carts = {} }) })
	Tick(me, npc)
	T.eq(me.watching, nil)
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

-- Battle stances: in setup a soldier at rest takes its stance (Pose), the
-- attackers at each wander rest, the defenders as they rest at their posts.

local function DefenderAtPost(field)
	local member = { team = RED, role = AiWar.DEFEND, slot = 0 }
	local post = Orders.Goal(field, member)
	local spot = P(post.x + 100, post.y + 50)
	local me, npc, war = Enlist({ team = RED, role = AiWar.DEFEND, field = field, pos = post, patrolSpots = { spot }, walkable = function() return true end })
	return me, npc, war, spot
end

T.test("in setup a defender resting at its post takes its stance, and keeps it while it rests", function()
	local me, npc = DefenderAtPost(SetupField({}))
	Tick(me, npc, 2)
	T.eq(me.moving, nil, "resting")
	T.eq(me.posing ~= nil, true, "in its stance")
	T.eq(npc:State().pose, me.posing, "shown")
	local unposes = me.unposes
	Tick(me, npc, 5)
	T.eq(me.posing ~= nil, true, "still in it")
	T.eq(me.unposes, unposes, "never dropped and struck again")
end)

T.test("a defender gets up from its stance to walk its round", function()
	local me, npc, _, spot = DefenderAtPost(SetupField({}))
	TicksUntilMoving(me, npc, Orders.PATROL_REST / TICK + 4)
	Near(me.moving, spot, "off on its round")
	T.eq(me.posing, nil, "up")
	T.eq(npc:State().pose, nil, "shown up")
end)

T.test("once the round runs, a resting defender takes no stance", function()
	local me, npc = DefenderAtPost(Field({}))
	Tick(me, npc, 2)
	T.eq(me.moving, nil, "resting")
	T.eq(me.posing, nil, "no stance")
end)

T.test("a defender drops its stance when setup ends", function()
	local me, npc, war = DefenderAtPost(SetupField({}))
	Tick(me, npc, 2)
	T.eq(me.posing ~= nil, true, "in its stance")
	war:SetField(Field({}))
	Tick(me, npc, 2)
	T.eq(me.posing, nil, "up")
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
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "travelling")
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
	me.seats = false -- no free seat on the cart
	Tick(me, npc, 2)
	me.pos = Orders.Goal(Field({}), { team = BLUE, role = AiWar.PUSH, slot = 0 })
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()), "Push", "arrived")
	local releases = me.releases
	Tick(me, npc)
	T.eq(me.releases > releases, true, "holds, leaving fights to the engine")
	T.eq(#me.requests, 1, "no new route")
end)


T.test("an escort squad's leader roams its sphere, resting at each spot", function()
	local first, second = P(1400, 200), P(900, -300)
	local me, npc = Enlist({ role = AiWar.ESCORT, pos = P(1300, 100), patrolSpots = { first, second } })
	Tick(me, npc, 2)
	T.eq(npc:State().inSphere, true, "in the support sphere")
	T.eq(npc:State().tactic, "roaming the objective", "roaming")
	Near(me.moving, first, "to a spot in it")
	T.eq(#me.requests, 0, "no trip")
	me.pos = first
	local releases = me.releases
	Tick(me, npc)
	T.eq(me.releases > releases, true, "resting there, free to fight")
	Tick(me, npc, Orders.ROAM_REST / TICK + 1)
	Near(me.moving, second, "then on to another")
end)

T.test("a defender that sees an enemy near its post fights instead of walking", function()
	local me, npc = Enlist({ team = RED, role = AiWar.DEFEND, pos = P(1300, 0) })
	me.enemy = true
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()), "EstablishLine", "fighting at the post")
	T.eq(#me.requests, 0, "no route")
end)

T.test("an escort on the way breaks off to fight once near its goal", function()
	local me, npc = Enlist({ role = AiWar.ESCORT, pos = P(0, 0) })
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "travelling")
	me.enemy = true
	me.pos = P(1000, 0)
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()), "Escort", "stopped to fight")
end)

T.test("a pusher rushes the cart through enemy fire", function()
	local me, npc = Enlist({ role = AiWar.PUSH, pos = P(0, 0) })
	me.enemy = true
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "still travelling")
	T.eq(me.moving ~= nil, true, "moving")
end)

T.test("with no route the soldier holds and tries again later", function()
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return false end })
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Push", "gave up for now")
	Tick(me, npc, 2)
	T.eq(#me.requests, 1, "waiting before retrying")
	Tick(me, npc, Orders.RETRY_WAIT / TICK)
	T.eq(#me.requests, 2, "retried")
end)

-- The first stuck plans the soldier's path afresh, and nothing more.
local function FreshPath(me, npc)
	local before = me.repathed or 0
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(me.repathed, before + 1, "a fresh path first")
end

T.test("a soldier that stops getting closer asks for a new route, and gives up after a few", function()
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return { P(900, 0) } end })
	Tick(me, npc, 2)
	FreshPath(me, npc)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.requests, 2, "a new route")
	for _ = 1, Orders.MAX_REPATHS do Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK + 1) end
	T.eq(Orders.JobOf(npc:Describe()), "Push", "gave up")
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
	T.eq(Orders.JobOf(npc:Describe()), "Push", "pushing")
	member.role = AiWar.ESCORT
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()) == "Escort" or Orders.JobOf(npc:Describe()) == "Travel", true, "escorting")
end)

T.test("a soldier without a role holds, and takes up one when given", function()
	local me, npc, _, member = Enlist({ role = AiWar.PUSH })
	member.role = nil
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Idle", "idle")
	T.eq(#me.moves, 0, "no moves")
	member.role = AiWar.PUSH
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()) ~= "Idle", true, "back to work")
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
	me.seats = false -- no free seat on the cart
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
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "still going")
	T.eq(npc:State().trip, nil, "never gave up")
end)

-- The kinds of the marks a soldier made (the port's Mark), in order.
local function Marked(me)
	local kinds = {}
	for i, mark in ipairs(me.marks) do kinds[i] = mark.kind end
	return table.concat(kinds, " ")
end

T.test("a stuck soldier first steps aside, then goes on along its new route", function()
	local route = { P(900, 0) }
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return route end })
	Tick(me, npc, 2)
	FreshPath(me, npc)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.requests, 2, "a new route")
	T.near(FS.Distance(me.moving, P(0, 0)), Orders.SIDESTEP_DISTANCE, 1e-6, "a step aside first")
	T.eq(Marked(me), Debug.MARK_REPATH .. " " .. Debug.MARK_SIDESTEP, "marked")
	Near(me.marks[2].to, me.moving, "marked where it steps to")
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
	T.eq(Marked(me), Debug.MARK_PASS, "marked")
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
	T.eq(Marked(me), Debug.MARK_DETOUR, "marked")
	Near(me.marks[1].to, beside, "marked where it walks round to")
	Near(me.moving, beside, "to the point beside it")
	T.eq(#me.requests, 1, "no new route")
	me.pos = P(beside.x, beside.y)
	Tick(me, npc)
	Near(me.moving, route[1], "back on its route")
end)

-- Pushed off its path (a crowd, a hop, a blast), a soldier heads straight
-- for the path's next point, through whatever stands between: stuck, it
-- first plans its path afresh from where it stands; stuck again within
-- REPATH_AGAIN, it goes on to the remedies below.
T.test("a stuck soldier first plans its path afresh, and hops only when stuck again soon", function()
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return { P(900, 0) } end,
		hoppable = function() return true end,
	})
	Tick(me, npc, 2)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(me.repathed, 1, "a fresh path")
	T.eq(#me.hops, 0, "no hop yet")
	T.eq(Marked(me), Debug.MARK_REPATH, "marked")
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(me.repathed, 1, "not again so soon")
	T.eq(#me.hops, 1, "then a hop")
	T.eq(Orders.REPATH_AGAIN > Orders.STUCK_TIME, true, "a second stuck falls within it")
end)

T.test("a soldier stuck while climbing hops at once, without stepping aside first", function()
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return { P(100, 0, 60), P(900, 0, 120) } end,
		hoppable = function() return true end,
	})
	Tick(me, npc, 2)
	FreshPath(me, npc)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.hops, 1, "hopped up")
	T.eq(me.hops[1].z, 60, "onto the waypoint above")
	T.eq(Marked(me), Debug.MARK_REPATH .. " " .. Debug.MARK_HOP, "marked")
	T.eq(#me.requests, 1, "no step aside, no new route")
end)

-- Something it cannot walk round (a crate across a narrow lane) it leaps
-- over toward its waypoint at once, where the port allows a hop, before any
-- step aside: a step aside and a new route lead back into the same crate.
T.test("a soldier stuck where it may hop hops toward its waypoint at once, without stepping aside", function()
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return { P(900, 0) } end,
		hoppable = function() return true end,
	})
	Tick(me, npc, 2)
	FreshPath(me, npc)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.hops, 1, "one hop")
	Near(me.hops[1], P(Orders.HOP_DISTANCE, 0), "a hop's length toward the waypoint")
	T.eq(#me.requests, 1, "no step aside, no new route")
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "still on its way")
	T.eq(npc:State().hops, 1, "counted for the report")
	T.eq(me.marks[#me.marks].kind, Debug.MARK_HOP, "the hop marked")
	Near(me.marks[#me.marks].to, me.hops[1], "where it hopped to")
end)

T.test("a soldier that may walk round what holds it does, rather than hop", function()
	local beside = P(300, 120)
	local me, npc = Enlist({
		role = AiWar.PUSH,
		route = function() return { P(900, 0) } end,
		detour = function() return beside end,
		hoppable = function() return true end,
	})
	Tick(me, npc, 2)
	Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK)
	T.eq(#me.detours, 1, "walks round")
	T.eq(#me.hops, 0, "no hop")
end)

T.test("a hop to somewhere a player could not walk is refused, and the trip ends", function()
	local me, npc = Enlist({ role = AiWar.PUSH, route = function() return { P(900, 0) } end })
	Tick(me, npc, 2)
	FreshPath(me, npc)
	for _ = 1, Orders.MAX_REPATHS + 1 do Tick(me, npc, (Orders.STUCK_TIME + TICK) / TICK + 1) end
	T.eq(#me.hops, 0, "no hop")
	T.eq(npc:State().trip, "stuck", "gave up")
	T.eq(me.marks[#me.marks].kind, Debug.MARK_GAVE_UP, "marked")
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

-- Sides: the scenario's side action holds the job (ScenarioMonitor >
-- PayloadDefender > EstablishLine > Travel).

T.test("a defender's job runs under PayloadDefender, a pusher's under PayloadAttacker", function()
	local _, defender = Enlist({ team = RED, role = AiWar.DEFEND, field = Field({}) })
	local job, squadRole, side = Orders.JobOf(defender:Describe())
	T.eq(side, "PayloadDefender", defender:Describe())
	T.eq(job:match("^EstablishLine") ~= nil, true, "its job beneath: " .. job)
	T.eq(squadRole ~= nil, true, "its squad role")
	local _, pusher = Enlist({ team = BLUE, role = AiWar.PUSH, field = Field({}) })
	T.eq(select(3, Orders.JobOf(pusher:Describe())), "PayloadAttacker", pusher:Describe())
end)

T.test("a raider's side follows its focus: the enemy's cart is defense, its own offense", function()
	local both = Field({ carts = { [BLUE] = Cart(1000), [RED] = Cart(2000) } })
	for slot = 0, 5 do
		local _, npc = Enlist({ team = RED, role = AiWar.RAID, slot = slot, field = both })
		local focus = Orders.Focus(both, { team = RED, role = AiWar.RAID, slot = slot })
		T.eq(select(3, Orders.JobOf(npc:Describe())), focus == "defense" and "PayloadDefender" or "PayloadAttacker", "slot " .. slot)
	end
end)

T.test("a member whose job moves it to the other side changes its side action", function()
	local me, npc, _, member = Enlist({ team = RED, role = AiWar.DEFEND, field = Field({ carts = { [BLUE] = Cart(1000), [RED] = Cart(2000) } }) })
	member.role = AiWar.PUSH
	Tick(me, npc, 2)
	local job, _, side = Orders.JobOf(npc:Describe())
	T.eq(side, "PayloadAttacker", npc:Describe())
	T.eq(job == "Push" or job == "Travel", true, "and runs its new job: " .. job)
end)

-- Doctrines: the jobs of a scenario (features.aiwar.scenario) ----------------

T.test("the payload doctrine is today's roles, and the shared goal helpers are public", function()
	T.eq(Orders.PAYLOAD.NAME, "payload", "named")
	T.eq(Orders.PAYLOAD.ROLES, Orders.ROLES, "today's roles")
	for _, name in ipairs({ "WaitsForSetup", "ChaseAnchor", "PatrolMark", "PatrolHolds", "Threat", "Side" }) do
		T.eq(type(Orders.PAYLOAD[name]), "function", name)
	end
	for _, name in ipairs({ "Ring", "Lateral", "GateSpot", "Behind", "EntryPoint" }) do
		T.eq(type(Orders[name]), "function", name)
	end
	T.eq(Orders.ROLES[AiWar.RAID].Line, Orders.EnemyLine, "a payload raider's line is the enemy's line")
end)

-- A doctrine with one job, CAPTURE: stand in a zone round ZONE_CENTER. No
-- carts anywhere: nothing but the doctrine may read them.
local ZONE_CENTER, ZONE_RADIUS = P(2000, 0), 200

local function Stub(name)
	return {
		NAME = name,
		ROLES = {
			[AiWar.CAPTURE] = {
				name = name .. "Occupy",
				arrive = 48,
				leash = 300,
				rushes = false,
				Goal = function(field, member) return field.noGoal ~= true and ZONE_CENTER or nil end,
				Zone = function(field, member) return ZONE_CENTER, ZONE_RADIUS end,
				Urgent = function(field, member) return field.urgent == true end,
			},
		},
		WaitsForSetup = function(field, member) return false end,
		ChaseAnchor = function(field, member) return nil end,
		PatrolMark = function(field, member) return {} end,
		PatrolHolds = function(mark, field, member) return true end,
		Threat = function(field, member) return nil end,
		SIDES = { attack = name .. "Attacker", defend = name .. "Defender" },
		Side = function(field, member) return "attack" end,
	}
end

local STUB = Stub("Stub")

local function StubField(t)
	return {
		phase = AiWar.PHASES.running,
		doctrine = t.doctrine or STUB,
		urgent = t.urgent,
		noGoal = t.noGoal,
	}
end

T.test("a job with a zone travels into it, then shuffles between spots in it every ZONE_SHUFFLE", function()
	local first, second = P(2100, 50), P(1900, -80)
	local me, npc = Enlist({ role = AiWar.CAPTURE, field = StubField({}), pos = P(0, 0), patrolSpots = { first, second }, walkable = function() return true end })
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Travel", "on its way")
	T.eq(me.gait, Orders.RUN, "running")
	me.pos = P(1850, 0)
	Tick(me, npc, 2)
	T.eq(npc:State().trip, "in its zone", "arrived on entering the zone")
	Near(me.moving, first, "to a spot in the zone")
	me.pos = first
	Tick(me, npc)
	T.eq(me.moving, nil, "resting there")
	Tick(me, npc, Orders.ZONE_SHUFFLE / TICK + 1)
	Near(me.moving, second, "then on to another")
end)

-- An urgent job's fight (TF2's CTFBotDeliverFlag: the bomb carrier) is
-- fought on the way: it neither regroups on its leader nor bounds or holds
-- with its squad, but travels its route to its goal.
T.test("an urgent job in a fight travels on to its goal instead of fighting as its squad", function()
	local doctrine = Stub("Pressing")
	doctrine.ROLES[AiWar.CAPTURE].tactic = "attack"
	local function Pair(urgent)
		return Squadmates({ role = AiWar.CAPTURE, field = StubField({ doctrine = doctrine, urgent = urgent }),
			a = { pos = P(-1000, 0), walkable = function() return true end },
			b = { pos = P(1000, 0), enemy = true, enemyPos = P(1300, 300), walkable = function() return true end } })
	end
	local s = Pair(true)
	s.Tick(2)
	T.eq(s.a.fireTeam ~= nil and s.a.fireTeam == s.b.fireTeam, true, "squadmates")
	T.eq(SquadRoleOf(s.npcB), "SquadMember", "b follows a")
	T.eq(Orders.JobOf(s.npcB:Describe()), "Travel", "travelling: " .. s.npcB:Describe())
	T.eq(s.npcB:State().tactic, nil, "no squad tactic")
	s.Tick(4)
	T.eq(Orders.JobOf(s.npcB:Describe()), "Travel", "still travelling, its enemy in sight")
	local calm = Pair(false)
	calm.Tick(2)
	T.eq(calm.npcB:State().tactic, "regrouping on its leader", "a job that is not urgent regroups first")
end)

T.test("an urgent job rushes, does not stop at its leash for an enemy, and will not retreat", function()
	local field = StubField({})
	local me, npc, war = Enlist({ role = AiWar.CAPTURE, field = field, pos = P(0, 0), walkable = function() return true end })
	Tick(me, npc, 2)
	me.enemy = true
	me.enemyPos = P(1800, 300)
	me.pos = P(1750, 0)
	Tick(me, npc, 2)
	T.eq(me.moving, nil, "not urgent: stops within its leash to fight")
	T.eq(npc:Query("ShouldRetreat"), N.ANSWER_UNDEFINED, "not urgent: may retreat")
	T.eq(npc:Query("ShouldPickUp", { handle = "kit" }), N.ANSWER_UNDEFINED, "not urgent: may go for health")
	war:SetField(StubField({ urgent = true }))
	Tick(me, npc, 2)
	T.eq(me.moving ~= nil, true, "urgent: on into the zone")
	T.eq(me.gait, Orders.RUSH, "at a rush")
	T.eq(npc:Query("ShouldRetreat"), N.ANSWER_NO, "no retreat")
	T.eq(npc:Query("ShouldPickUp", { handle = "kit" }), N.ANSWER_NO, "no trip for health")
	T.eq(npc:Query("ShouldHurry"), N.ANSWER_YES, "hurrying")
	me.enemyHandle, me.enemyHealth = "weak", 0.1
	Tick(me, npc, 2)
	T.eq(npc:State().chases, nil, "no chase while urgent")
end)

-- A soldier already off for cover or health when its job turns urgent (it
-- picks up the bomb) drops that for the job: TF2's carrier never stops
-- for health.
T.test("a retreat or a trip for health ends as the soldier's job turns urgent", function()
	local kit = { pos = P(300, 0), handle = "kit" }
	local me, npc, war = Enlist({ role = AiWar.CAPTURE, field = StubField({}), pos = P(0, 0), covers = { P(200, 0) },
		enemyPos = P(5000, 0), walkable = function() return true end })
	me.kits = { kit }
	me.health = 30
	Tick(me, npc, 3)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/FindHealth", "for the kit: " .. npc:Describe())
	war:SetField(StubField({ urgent = true }))
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "urgent: back on its job: " .. npc:Describe())
	local them, theirs, theirWar = Enlist({ role = AiWar.CAPTURE, field = StubField({}), pos = P(0, 0), covers = { P(200, 0) },
		enemyPos = P(600, 0), walkable = function() return true end })
	them.health = 30
	Tick(them, theirs)
	T.eq(theirs:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "retreating")
	theirWar:SetField(StubField({ urgent = true }))
	Tick(them, theirs, 2)
	T.eq(Orders.JobOf(theirs:Describe()) ~= nil, true, "urgent: the retreat ends too: " .. theirs:Describe())
end)

T.test("an urgent job hurt badly stays on its job", function()
	local me, npc = Enlist({ role = AiWar.CAPTURE, field = StubField({ urgent = true }), pos = P(1900, 0), enemyPos = P(2400, 0) })
	Tick(me, npc)
	me.health = 20
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "no RetreatToCover")
end)

T.test("a new doctrine changes the job's action", function()
	local me, npc, war = Enlist({ role = AiWar.CAPTURE, field = StubField({ noGoal = true }) })
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()), "StubOccupy", "the stub's job")
	war:SetField(StubField({ noGoal = true, doctrine = Stub("Other") }))
	Tick(me, npc)
	T.eq(Orders.JobOf(npc:Describe()), "OtherOccupy", "the other doctrine's")
end)

T.test("a job its doctrine lacks leaves the soldier idle", function()
	local me, npc = Enlist({ role = AiWar.PUSH, field = StubField({}) })
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()), "Idle", "no push in the stub")
end)

-- FindHealth (CTFBotGetHealth): retreating, a soldier leaves cover for a
-- kit once its urgency and its safety (features.aiwar.health) make 1.
T.test("a soldier in cover leaves for a near kit once the enemy has drawn off", function()
	local kit = { pos = P(300, 0), handle = "kit" }
	local me, npc = Enlist({ role = AiWar.DEFEND, team = RED, covers = { P(200, 0) }, enemyPos = P(600, 0) })
	me.kits = { kit }
	me.health = 30
	Tick(me, npc)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "retreating")
	me.health = 60 -- urgency 0.4: it waits for safety 0.6
	Tick(me, npc, 2)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "the enemy too near to go")
	me.enemyPos = P(5000, 0)
	Tick(me, npc, 2)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/FindHealth", "it has drawn off: for the kit")
	Near(me.moving, kit.pos, "to the kit")
	me.kits = {}
	Tick(me, npc, 2)
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "the kit taken: back to its job")
end)

T.test("a soldier calls out as it falls back to cover, and again as it leaves cover for a kit", function()
	local kit = { pos = P(300, 0), handle = "kit" }
	local me, npc = Enlist({ role = AiWar.DEFEND, team = RED, covers = { P(200, 0) }, enemyPos = P(600, 0) })
	me.kits = { kit }
	me.health = 30
	Tick(me, npc)
	T.eq(table.concat(me.announced or {}, " "), Speech.CONCEPT_RETREAT_TO_COVER, "falling back")
	me.health = 60
	Tick(me, npc, 2)
	T.eq(#me.announced, 1, "once, while it stays in cover")
	me.enemyPos = P(5000, 0)
	Tick(me, npc, 2)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/FindHealth")
	T.eq(me.announced[2], Speech.CONCEPT_GET_HEALTH, "going for health")
	T.eq(#me.announced, 2)
end)

T.test("a soldier on fire goes for health whatever the danger; one with a medic on it does not", function()
	local kit = { pos = P(300, 0), handle = "kit" }
	local me, npc = Enlist({ role = AiWar.DEFEND, team = RED, covers = { P(200, 0) }, enemyPos = P(400, 0) })
	me.kits = { kit }
	me.health, me.burning = 30, true
	Tick(me, npc, 3)
	T.eq(npc:Describe(), "NextSoldier/StrategyMonitor/FindHealth", "burning: straight for it")
	local them, theirs, _, member = Enlist({ role = AiWar.DEFEND, team = RED, covers = { P(200, 0) }, enemyPos = P(400, 0) })
	them.kits = { kit }
	them.health, them.burning = 30, true
	member.medicAt = them.now + 10 -- a medic treats it
	Tick(them, theirs, 3)
	T.eq(theirs:Describe(), "NextSoldier/StrategyMonitor/RetreatToCover", "its medic heals it where it hides")
end)

-- CallMedic: under CALL_MEDIC_HEALTH a soldier calls for a medic, once a
-- CALL_MEDIC_COOLDOWN, and goes on with what it was doing.
T.test("a hurt soldier calls for a medic, then gets on with its job", function()
	local me, npc = Enlist({ role = AiWar.DEFEND, team = RED })
	me.health = Orders.CALL_MEDIC_HEALTH * 100 + 1
	Tick(me, npc)
	T.eq(#(me.medicCalls or {}), 0, "not hurt enough")
	me.health = Orders.CALL_MEDIC_HEALTH * 100 - 5
	Tick(me, npc, 2)
	T.eq(#me.medicCalls, 1, "MEDIC!")
	T.eq(Orders.JobOf(npc:Describe()) ~= nil, true, "back to its job")
	Tick(me, npc, 4)
	T.eq(#me.medicCalls, 1, "not again before the cooldown")
	me:Advance(Orders.CALL_MEDIC_COOLDOWN)
	Tick(me, npc)
	T.eq(#me.medicCalls, 2, "again")
end)

T.test("the war owns its behaviours and gives them to NextSoldier through its registry", function()
	local owned = { "NextSoldier", "StrategyMonitor", "TacticalMonitor", "SquadMonitor", "ScenarioMonitor", "Travel",
		"Chase", "Idle", "Humiliated", "SeekAndDestroy", "RetreatToCover", "FindHealth", "CallMedic" }
	for _, name in ipairs(owned) do T.eq(BEHAVIORS:Has(name), true, name .. " is registered") end
end)

T.test("a soldier's root is the NextSoldier its compiled behaviours give", function()
	local registry = nextsoldier.behaviors.New()
	local Stand = nextsoldier.chart.CHART:State("StandIn")
	registry:Register({ name = "NextSoldier", behavior = Stand })
	local war = AiWar.War.New()
	war:Assign({ [BLUE] = true })
	war:SetField(Field({}))
	local member = war:Enlist("me", BLUE, true)
	local npc = N.Npc.New(Orders, { war = war, member = member, behaviors = registry:Compile() }, FS.Soldier({}))
	npc:Update(TICK)
	T.eq(npc:Describe():match("^StandIn") ~= nil, true, npc:Describe())
end)

T.finish()
