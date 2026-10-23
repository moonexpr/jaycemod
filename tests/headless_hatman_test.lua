local T = dofile("tests/harness.lua")
local FakeCombatant = dofile("tests/fake_combatant.lua")
local NpcSystem = T.require("games.npc.nextbot")
local HHH = T.require("foundation.npc.headless_hatman")
local BossEvents = T.require("foundation.npc.boss_events")
local HalloweenBoss = T.require("foundation.npc.halloween_boss")
local Tag = T.require("features.tag.model")
local Holiday = T.require("features.holiday.model")
local Halloween = T.require("features.holiday.halloween")
local Actor = T.require("games.npc.actor")
local Players = T.require("games.gameplay.players")
local Teams = T.require("games.gameplay.teams")

local V = FakeCombatant.Vector
local TICK = 0.1
local EPSILON = 1e-6

-- The tag controller over the real tag model, on a Halloween map unless
-- told otherwise; it keeps every notice and every Set.
local function TagController(world, halloween)
	local model = Tag.New({
		HolidayActive = function(_, h) return halloween and h == Holiday.HALLOWEEN end,
		Mode = function() return halloween and Halloween or nil end,
		IsAlive = function(_, p) return p.alive end,
		TeamOf = function(_, p) return p.team end,
	})
	local controller = {
		notices = {},
		sets = 0,
	}
	local function Keep(notices)
		for _, n in ipairs(notices) do controller.notices[#controller.notices + 1] = n end
	end
	function controller:Get() return model:Get() end
	function controller:Warn(p) Keep(model:Warn(p)) end
	function controller:Set(p)
		self.sets = self.sets + 1
		Keep(model:Set(p))
	end
	world.tag = controller
	return controller
end

-- A Horsemann at the origin with the given players ({ team, origin, ... }).
local function Scene(t)
	local world = FakeCombatant.World()
	local players = {}
	for i, p in ipairs(t.players or {}) do players[i] = world:AddPlayer(p) end
	local tag = TagController(world, t.halloween ~= false)
	local me = FakeCombatant.Combatant({
		world = world,
		variant = HHH,
		team = Teams.HALLOWEEN,
		origin = t.origin or V(0, 0, 0),
		random = t.random,
	})
	me.points = t.points or {}
	function me:ControlPoints() return self.points end
	function me:Break() self:Record("Break") end
	function me:FireGameEvent(name, fields) self:Record("FireGameEvent", name, fields) end
	local npc = NpcSystem.Npc.New(HHH, { convars = HHH.CONVARS }, me)
	return {
		world = world,
		players = players,
		tag = tag,
		me = me,
		npc = npc,
	}
end

local function Tick(s, seconds)
	local steps = math.floor(seconds / TICK + 0.5)
	for _ = 1, math.max(steps, 1) do
		s.me.clock:Advance(TICK)
		s.npc:Update(TICK)
	end
end

local function Count(me, name) return #me:Called(name) end

-- The game events it fired, by name.
local function Fired(me)
	local names = {}
	for _, args in ipairs(me:Called("FireGameEvent")) do names[#names + 1] = args[1] end
	return table.concat(names, ",")
end

local function Sounds(me)
	local sounds = {}
	for _, args in ipairs(me:Called("EmitSound")) do sounds[#sounds + 1] = args[1] end
	return table.concat(sounds, ",")
end

local function SoundCount(me, name)
	local n = 0
	for _, args in ipairs(me:Called("EmitSound")) do
		if args[1] == name then n = n + 1 end
	end
	return n
end

local function ClearLog(me) me.calls = {} end

-- Emerge fully, then attack from `at` (home), facing along +x. The fake's
-- FaceTowards only records, so the yaw stays where a test puts it.
local function Emerged(s, at)
	s.npc:Update(TICK)
	s.me.clock:Advance(HHH.RISE_TIME + TICK)
	s.me.origin = at or V(0, 0, 0)
	s.me:FinishActivity()
	s.npc:Update(TICK)
	s.me.yaw = 0
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "attacking")
end

T.test("the Horsemann keeps TF2's numbers as its convars' defaults", function()
	local cv = HHH.CONVARS
	T.eq(cv.tf_halloween_bot_health_base, 3000, "health base")
	T.eq(cv.tf_halloween_bot_health_per_player, 200, "per player")
	T.eq(cv.tf_halloween_bot_min_player_count, 10, "min players")
	T.eq(cv.tf_halloween_bot_speed, 400, "speed")
	T.eq(cv.tf_halloween_bot_attack_range, 200, "attack range")
	T.eq(cv.tf_halloween_bot_terrify_radius, 500, "terrify radius")
	T.eq(cv.tf_halloween_bot_chase_range, 1500, "chase range")
	T.eq(cv.tf_halloween_bot_quit_range, 2000, "quit range")
	T.eq(HHH.BOSS_TYPE, HalloweenBoss.BOSS_HHH, "boss type")
	T.eq(HHH.KIND, HalloweenBoss.KIND, "a boss")
	T.eq(HHH.PATH, "games.nextsoldier.path.ground", "path")
	T.eq(HHH.LOCOMOTION.runSpeed, 400, "run speed")
	T.eq(HHH.LOCOMOTION.stepHeight, 18, "step")
	T.eq(HHH.LOCOMOTION.jumpHeight, 18, "jump")
	T.eq(HHH.LOCOMOTION.maxYawRate, 200, "yaw rate")
end)

-- CHeadlessHatman::Spawn
T.test("health is 3000, plus 200 for each RED or BLU player beyond 10", function()
	local cv = HHH.CONVARS
	T.eq(HHH.Health(0, 0, cv), 3000, "empty")
	T.eq(HHH.Health(10, 0, cv), 3000, "ten")
	T.eq(HHH.Health(14, 0, cv), 3800, "fourteen")
	local players = {}
	for i = 1, 12 do players[i] = { team = (i % 2 == 0) and Teams.RED or Teams.BLUE } end
	local s = Scene({ players = players })
	T.eq(s.me:GetMaxHealth(), 3400, "twelve players")
	T.eq(s.me:GetHealth(), 3400, "full")
	T.eq(s.me:Called("AttachProp")[1][1], HHH.AXE_MODEL, "the axe")
end)

-- CHeadlessHatmanEmerge
T.test("it rises 200 over 3 s from 10 above its spawn, rumbling, facing the nearest player", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(0, 600, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(0, -900, 0),
			},
		},
	})
	s.npc:Update(TICK)
	local me = s.me
	T.eq(me:Called("StartActivity")[1][1], "ACT_TRANSITION", "emerge activity")
	T.eq(me:Called("DispatchParticleEffect")[1][1], "halloween_boss_summon", "summon particle")
	T.eq(Sounds(me), "Halloween.HeadlessBossSpawnRumble", "rumble")
	T.eq(Fired(me), BossEvents.PUMPKIN_LORD_SUMMONED, "tells everyone it rose (the clients play its music)")
	T.eq(me.origin, V(0, 0, 10 - 200), "sunk")
	T.near(me.yaw, 90, EPSILON, "faces RED, the nearer")
	Tick(s, 1.5)
	T.near(me.origin.z, 10 - 200 * 0.5, EPSILON, "half risen")
	T.eq(Count(me, "ScreenShake"), 5, "a shake every 0.25 s, on 0.1 s ticks")
	T.eq(me:Called("ScreenShake")[1][2], 15, "shake amplitude")
	Tick(s, 2)
	T.eq(me.origin.z >= 10 - 200 * TICK / HHH.RISE_TIME - EPSILON and me.origin.z <= 10, true, "risen, and no further")
	T.eq(s.npc:Describe(), "BossBehavior/Emerge", "until the activity ends")
	me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "then Attack")
end)

T.test("with nobody about it faces a random way", function()
	local s = Scene({ random = FakeCombatant.Random({ 0.25 }) })
	s.npc:Update(TICK)
	T.near(s.me.yaw, 90, EPSILON, "a quarter turn")
end)

T.test("emerging pushes players within 250 of the emerge point up and away", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(100, 0, -54),
			},
			{
				team = Teams.BLUE,
				origin = V(400, 0, 0),
			},
		},
	})
	s.npc:Update(TICK)
	Tick(s, TICK)
	local pushes = s.me:Called("ApplyImpulse")
	T.eq(#pushes >= 1, true, "pushed")
	for _, push in ipairs(pushes) do T.eq(push[1], s.players[1], "only the near one") end
	T.eq(pushes[1][2], V(200, 0, 200), "200 along the flat direction, and 200 up")
end)

-- CHeadlessHatmanAttack::SelectVictim
T.test("it makes the nearest chaseable player within 1500 of home IT and chases them", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1200, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(-600, 0, 0),
				inRespawnRoom = true,
			},
			{
				team = Teams.BLUE,
				origin = V(0, 900, 0),
				conds = { Players.COND.INVULNERABLE },
			},
			{
				team = Teams.BLUE,
				origin = V(0, -800, 0),
				onMesh = false,
			},
			{
				team = Teams.RED,
				origin = V(0, 300, 0),
				conds = { Players.COND.HALLOWEEN_GHOST_MODE },
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	T.eq(s.tag:Get(), s.players[1], "the only chaseable one")
	T.eq(s.tag.notices[1].player, s.players[1], "warned")
	local path = s.me.paths[1]
	T.eq(path.lookAhead, 100, "look ahead")
	T.eq(path.goal, V(1200, 0, 0), "chasing IT")
	T.eq(s.me.desiredSpeed, 400, "at the Horsemann's speed")
	local computes = path.computes
	Tick(s, 0.5)
	T.eq(path.computes, computes, "no repath inside a second")
	Tick(s, 0.6)
	T.eq(path.computes, computes + 1, "repath after a second")
end)

T.test("with no player to make IT, it chases the nearest AI war soldier near home, who is never IT", function()
	local s = Scene({})
	local near = s.world:AddMember({ team = Teams.RED, origin = V(900, 0, 0) })
	s.world:AddMember({ team = Teams.BLUE, origin = V(1300, 0, 0) })
	s.world:AddMember({ team = Teams.BLUE, origin = V(1700, 0, 0) }) -- beyond 1500 of home
	Emerged(s)
	Tick(s, TICK)
	T.eq(s.tag:Get(), nil, "no IT")
	T.eq(s.me.paths[1].goal, near.origin, "after the nearest soldier")
end)

T.test("a player off the mesh counts only while standing on the ground", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(500, 0, 0),
				onMesh = false,
				onGround = false,
				withinReach = true,
			},
		},
	})
	-- An airborne player is chaseable while any nav area lies below.
	function s.me:IsOnNavMesh(t, tolerance) return t.withinReach and tolerance > 50 or t.onMesh end
	Emerged(s)
	Tick(s, TICK)
	T.eq(s.tag:Get(), s.players[1], "airborne over the mesh")
end)

T.test("nobody beyond 1500 of home becomes IT, and IT is dropped beyond 2000", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1600, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(0, 1000, 0),
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	T.eq(s.tag:Get(), s.players[2], "RED is too far from home")
	s.tag:Set(s.players[1])
	Tick(s, TICK)
	T.eq(s.tag:Get(), s.players[1], "a tagged player 1600 away stays IT")
	s.players[1].origin = V(2100, 0, 0)
	Tick(s, TICK)
	T.eq(s.tag:Get(), s.players[2], "beyond 2000 IT is dropped and a new one chosen")
end)

T.test("a dead IT is dropped", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(500, 0, 0),
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	s.players[1].alive = false
	Tick(s, TICK)
	T.eq(s.tag:Get(), nil, "nobody")
end)

T.test("home follows the first point of the round BLU does not own and may capture, every 3 s", function()
	local s = Scene({
		players = {},
		points = {
			{
				origin = V(100, 0, 0),
				inRound = true,
				owner = Teams.BLUE,
				blueMayCapture = false,
			},
			{
				origin = V(200, 0, 0),
				inRound = false,
				owner = Teams.RED,
				blueMayCapture = true,
			},
			{
				origin = V(300, 0, 0),
				inRound = true,
				owner = Teams.RED,
				blueMayCapture = true,
			},
			{
				origin = V(400, 0, 0),
				inRound = true,
				owner = Teams.RED,
				blueMayCapture = true,
			},
		},
	})
	Emerged(s)
	Tick(s, 1)
	T.eq(s.me.paths[1].goal, nil, "at home, nothing to walk to")
	Tick(s, 2.5)
	T.eq(s.me.paths[1].goal, V(300, 0, 0), "home is the third point")
	s.me.points = {
		{
			origin = V(100, 0, 0),
			inRound = true,
			owner = Teams.BLUE,
			blueMayCapture = false,
		},
		{
			origin = V(500, 0, 0),
			inRound = false,
			owner = Teams.RED,
			blueMayCapture = false,
		},
	}
	Tick(s, 3.1)
	T.eq(s.me.paths[1].goal, V(500, 0, 0), "with no such point, the last one looked at (TF2's loop)")
end)

T.test("home walks repath only after 3 s, and at home it faces the nearest visible player", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(0, 1800, 0),
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	T.eq(s.tag:Get(), nil, "too far to chase")
	local faced = s.me:Called("FaceTowards")
	T.eq(faced[#faced][1], V(0, 1800, 36), "faces the visible player's centre")
	s.me.origin = V(-100, 0, 0)
	Tick(s, TICK)
	local path = s.me.paths[1]
	T.eq(path.goal, V(0, 0, 0), "walks home")
	Tick(s, 2)
	T.eq(path.computes, 1, "no repath yet")
	Tick(s, 1.1)
	T.eq(path.computes, 2, "repath after 3 s")
end)

-- The axe: CHeadlessHatmanAttack::Update, UpdateAxeSwing and AttackTarget
T.test("the swing lands 0.58 s after it starts and cleaves a target in front for 80% of its max health", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(150, 0, 0),
				maxHealth = 125,
			},
		},
	})
	Emerged(s)
	ClearLog(s.me)
	Tick(s, TICK)
	local red = s.players[1]
	T.eq(s.me:Called("AddGesture")[1][1], "ACT_MP_ATTACK_STAND_ITEM1", "swing gesture")
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossAttack"), 1, "attack yell")
	T.eq(s.me:Called("FaceTowards")[1][1], V(150, 0, 36), "faces the target")
	Tick(s, 0.5)
	T.eq(Count(s.me, "DealDamage"), 0, "not yet")
	Tick(s, TICK)
	local hits = s.me:Called("DealDamage")
	T.eq(#hits, 1, "one hit")
	T.eq(hits[1][1], red, "the target")
	T.near(hits[1][2], 100, EPSILON, "80% of max health")
	T.eq(hits[1][3], Actor.DMG_CLUB, "club damage")
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossAxeHitFlesh"), 1, "flesh")
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossAxeHitWorld"), 1, "world")
	T.eq(s.me:Called("DispatchParticleEffect")[1][1], "halloween_boss_axe_hit_world", "axe particle")
	Tick(s, 0.3)
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossAttack"), 1, "one swing a second")
	Tick(s, 0.2)
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossAttack"), 2, "the next swing")
end)

-- AttackTarget's cone: a hit needs dot(forward, toTarget) above
-- 0.27 * closeness, where closeness is 0 inside 100 and 1 at 200.
T.test("the swing hits only inside the cone, which widens as the target closes", function()
	local cases = {
		{
			name = "straight ahead at 150",
			origin = V(150, 0, 0),
			hit = true,
		},
		{
			name = "behind",
			origin = V(-150, 0, 0),
			hit = false,
		},
		{
			name = "to the side at 150",
			origin = V(0, 150, 0),
			hit = false,
		},
		{
			name = "barely ahead, close",
			origin = V(10, 80, 0),
			hit = true,
		},
		{
			name = "barely ahead, far",
			origin = V(10, 180, 0),
			hit = false,
		},
		{
			name = "ahead but out of sight",
			origin = V(150, 0, 0),
			visible = false,
			hit = false,
		},
	}
	for _, case in ipairs(cases) do
		local s = Scene({
			players = {
				{
					team = Teams.RED,
					origin = case.origin,
					visible = case.visible,
				},
			},
		})
		Emerged(s)
		Tick(s, 0.7)
		T.eq(Count(s.me, "DealDamage") > 0, case.hit, case.name)
		T.eq(SoundCount(s.me, "Halloween.HeadlessBossAxeHitWorld") > 0, true, case.name .. ": the swing lands anyway")
	end
end)

-- CHeadlessHatmanTerrify
T.test("20 s into the attack, a target in range makes it terrify everyone within 500 in sight", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(0, 400, 0),
				visible = false,
				inRespawnRoom = true,
			},
			{
				team = Teams.BLUE,
				origin = V(0, -600, 0),
				inRespawnRoom = true,
			},
			{
				team = Teams.BLUE,
				origin = V(0, 450, 0),
				inRespawnRoom = true,
			},
		},
	})
	Emerged(s)
	Tick(s, 19.5)
	T.eq(s.tag:Get(), s.players[1], "RED is IT")
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "no target in range yet")
	s.players[1].origin = V(150, 0, 0)
	ClearLog(s.me)
	Tick(s, 0.6)
	T.eq(s.npc:Describe(), "BossBehavior/Terrify", "terrifying")
	local gestures = s.me:Called("AddGesture")
	T.eq(gestures[#gestures][1], "ACT_MP_GESTURE_VC_HANDMOUTH_ITEM1", "hand to mouth")
	T.eq(Count(s.me, "DealDamage"), 0, "no swing")
	Tick(s, 0.3)
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossBoo"), 1, "boo at 0.25 s")
	T.eq(Count(s.me, "StunPlayer"), 0, "no scare before 0.75 s")
	Tick(s, 0.5)
	local stunned = {}
	for _, args in ipairs(s.me:Called("StunPlayer")) do
		stunned[args[1]] = true
		T.eq(args[2], 2, "2 s")
		T.eq(args[3], 0, "no slow")
		T.eq(args[4], Players.STUN.LOSER_STATE + Players.STUN.BY_TRIGGER, "loser state by trigger")
	end
	T.eq(stunned[s.players[1]], true, "IT")
	T.eq(stunned[s.players[4]], true, "the one at 450")
	T.eq(stunned[s.players[2]], nil, "not the one out of sight")
	T.eq(stunned[s.players[3]], nil, "not the one at 600")
	Tick(s, 0.5)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "done at 1.25 s")
	ClearLog(s.me)
	Tick(s, 1)
	T.eq(Count(s.me, "AddGesture") > 0 and s.me:Called("AddGesture")[1][1], "ACT_MP_ATTACK_STAND_ITEM1", "swings again")
end)

T.test("a target that is not a player is never terrified", function()
	local s = Scene({ players = {} })
	Emerged(s)
	local skeleton = s.world:AddNPC("zombie", FakeCombatant.Target({
		team = Teams.RED,
		origin = V(150, 0, 0),
	}))
	s.me.clock:Advance(25)
	s.npc:Event("OnContact", skeleton)
	Tick(s, 0.7)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "no terrify")
	T.eq(s.me:Called("DealDamage")[1][1], skeleton, "but it is hit")
end)

-- CHeadlessHatmanAttack::OnContact and OnStuck
T.test("bumping a living combatant makes it the target for 3 s; the world and the dead do not", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(0, 150, 0),
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	T.eq(s.tag:Get(), s.players[2], "the nearer is IT")
	s.me.yaw = 0
	s.players[1].origin = V(150, 0, 0)
	s.npc:Event("OnContact", FakeCombatant.Target({ alive = false }))
	s.npc:Event("OnContact", s.world)
	s.npc:Event("OnContact", s.players[1])
	Tick(s, 0.7)
	T.eq(s.me:Called("DealDamage")[1][1], s.players[1], "the bumped one is cleaved")
	Tick(s, 3)
	local faced = s.me:Called("FaceTowards")
	T.eq(faced[#faced][1], V(0, 150, 36), "IT again after 3 s")
end)

T.test("stuck, it warps to its path's goal, 10 up", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	s.npc:Event("OnStuck")
	T.eq(s.me.origin, V(1000, 0, 10), "warped")
end)

-- Laughs: every 3 to 5 s while not swinging; with no IT, a gesture a
-- quarter of the time each.
T.test("it laughs every 3 to 5 s, gesturing its frustration when nobody is IT", function()
	local s = Scene({
		players = {},
		random = FakeCombatant.Random({ 0 }),
	})
	Emerged(s)
	Tick(s, TICK)
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossLaugh"), 1, "laughs at once")
	T.eq(s.me:Called("AddGesture")[1][1], "ACT_MP_GESTURE_VC_FISTPUMP_MELEE", "RandomInt 0: fist pump")
	Tick(s, 2.9)
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossLaugh"), 1, "not before 3 s")
	s.me.random = FakeCombatant.Random({ 0.3 })
	Tick(s, 0.2)
	T.eq(SoundCount(s.me, "Halloween.HeadlessBossLaugh"), 2, "at 3 s")
	T.eq(s.me:Called("AddGesture")[2][1], "ACT_MP_GESTURE_VC_FINGERPOINT_MELEE", "RandomInt 30: finger point")
	s.me.random = FakeCombatant.Random({ 0.9 })
	Tick(s, 5.1)
	T.eq(#s.me:Called("AddGesture"), 2, "RandomInt 90: no gesture")
end)

T.test("IT is warned every 7 s, and only on Halloween", function()
	for _, halloween in ipairs({ true, false }) do
		local s = Scene({
			halloween = halloween,
			players = {
				{
					team = Teams.RED,
					origin = V(1000, 0, 0),
				},
			},
		})
		Emerged(s)
		Tick(s, 7.5)
		local warnings = 0
		for _, n in ipairs(s.tag.notices) do
			if n.kind == Tag.PRINT_CENTER then warnings = warnings + 1 end
		end
		-- Becoming IT warns once; the Horsemann warns at once and after 7 s.
		T.eq(warnings, halloween and 3 or 0, halloween and "Halloween" or "no holiday")
	end
end)

-- Animation (CHeadlessHatmanAttack::Update) and CHeadlessHatman::Update
T.test("it runs with the axe above half health, holding its wound below, and stands still otherwise", function()
	local s = Scene({ players = {} })
	Emerged(s)
	ClearLog(s.me)
	s.me.attemptingToMove = true
	s.me.activity = nil
	Tick(s, TICK)
	T.eq(s.me.activity, "ACT_MP_RUN_ITEM1", "healthy run")
	T.eq(s.me:Called("ScreenShake")[1][2], 15, "footfall shake")
	Tick(s, 0.2)
	T.eq(Count(s.me, "ScreenShake"), 1, "a footfall every 0.25 s")
	Tick(s, TICK)
	T.eq(Count(s.me, "ScreenShake"), 2, "the next footfall")
	s.me.health = s.me.maxHealth / 2
	Tick(s, TICK)
	T.eq(s.me.activity, "ACT_MP_RUN_MELEE", "wounded run at 50%")
	T.near(s.me.pose.damage, 0.5, EPSILON, "the damage pose follows health")
	s.me.attemptingToMove = false
	Tick(s, TICK)
	T.eq(s.me.activity, "ACT_MP_STAND_ITEM1", "standing")
end)

T.test("a hit sprays the injured particle where it lands and is taken in full", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
			},
		},
	})
	local taken = s.npc:FilterDamage({
		attacker = s.players[1],
		amount = 40,
		position = V(1, 2, 3),
		dmgType = Actor.DMG_CLUB,
		crit = false,
	})
	T.eq(taken, true, "taken")
	local particle = s.me:Called("DispatchParticleEffect")[1]
	T.eq(particle[1], "halloween_boss_injured", "injured")
	T.eq(particle[2], V(1, 2, 3), "at the hit")
	T.eq(s.npc:State().samples[1].damage, 40, "in full")
end)

-- CHeadlessHatmanDying
T.test("killed, nobody is IT; it dies, breaks into gibs and is removed", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	T.eq(s.tag:Get(), s.players[1], "IT")
	s.me.alive = false
	s.npc:Event("OnKilled", {
		attacker = s.players[1],
		amount = 100,
	})
	ClearLog(s.me)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "Dying", "dying")
	T.eq(s.tag:Get(), nil, "nobody is IT")
	T.eq(s.me.activity, "ACT_DIESIMPLE", "death activity")
	T.eq(Sounds(s.me), "Halloween.HeadlessBossDying", "dying sound")
	Tick(s, 1)
	T.eq(s.me.removed, false, "until the activity ends")
	T.eq(Fired(s.me), "", "no word while it dies")
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(Fired(s.me), BossEvents.PUMPKIN_LORD_KILLED, "tells everyone it was killed, once gone")
	T.eq(Count(s.me, "Break"), 1, "gibs")
	T.eq(s.me:Called("DispatchParticleEffect")[1][1], "halloween_boss_death", "death particle")
	T.eq(s.me.removed, true, "removed")
	T.eq(s.npc:IsEmpty(), true, "the behavior is over")
	T.eq(s.tag:Get(), nil, "still nobody")
end)

T.test("removed without dying (a map's Kill), it lets IT go", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
			},
		},
	})
	Emerged(s)
	Tick(s, TICK)
	s.npc:Destroy()
	T.eq(s.tag:Get(), nil, "nobody is IT")
end)

-- The binding (read as text) defines the port as function ENT:<Name>(.
T.test("the headless_hatman binding defines the Horsemann's port", function()
	local f = assert(io.open("addons/sandcastle/gamemodes/sandcastle/entities/entities/headless_hatman.lua", "r"))
	local text = f:read("*a")
	f:close()
	for _, name in ipairs(HHH.METHODS) do
		T.eq(text:find("function ENT:" .. name .. "(", 1, true) ~= nil, true, "headless_hatman " .. name)
		T.eq(Actor.ENGINE[name], nil, "not an engine method: " .. name)
	end
end)

T.finish()
