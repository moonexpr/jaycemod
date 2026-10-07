local T = dofile("tests/harness.lua")
local FakeCombatant = dofile("tests/fake_combatant.lua")
local NpcSystem = T.require("foundation.npc")
local Merasmus = T.require("foundation.npc.merasmus")
local BossEvents = T.require("foundation.npc.boss_events")
local HalloweenBoss = T.require("foundation.npc.halloween_boss")
local Actor = T.require("foundation.npc.actor")
local Combatant = T.require("foundation.npc.combatant")
local Players = T.require("foundation.players")
local Teams = T.require("foundation.teams")

local V = FakeCombatant.Vector
local COND = Players.COND
local TICK = 0.1
local EPSILON = 1e-6
local GESTURE_TIME = 1 -- the fake's gesture length unless a scene sets one
local ATTACHMENT_HEIGHT = 80 -- where the fake puts every attachment, above the origin
local FAR = 2500 -- beyond the chase range of home: nobody to chase

local function Declared(name)
	for _, declared in ipairs(Merasmus.PARTICLES) do
		if declared == name then return true end
	end
	error(string.format("particle system %q is not in Merasmus's PARTICLES", name), 3)
end

-- The Merasmus port over a fake combatant: every boss and Merasmus method,
-- logging what it is asked.
local function Port(t)
	local me = FakeCombatant.Combatant({
		world = t.world,
		variant = Merasmus,
		origin = t.origin or V(0, 0, 0),
		random = t.random,
		shared = t.shared,
	})
	me.points = t.points or {}
	me.relays = t.relays or {}
	me.areas = t.areas or {}
	me.around = t.around or {}
	me.gestureTimes = t.gestureTimes or {}
	me.activityTimes = t.activityTimes or {}
	me.activityStarted = 0
	me.hidden = false
	me.collidable = true
	me.flying = false
	me.staff = nil
	me.look = nil
	-- An activity given a length in activityTimes finishes by itself.
	local startActivity = me.StartActivity
	function me:StartActivity(act)
		self.activityStarted = self:Now()
		return startActivity(self, act)
	end
	function me:IsActivityFinished()
		local length = self.activityTimes[self.activity]
		if length and self:Now() - self.activityStarted >= length then return true end
		return self.activityFinished
	end
	function me:Break() self:Record("Break") end
	function me:FireGameEvent(name, fields) self:Record("FireGameEvent", name, fields) end
	function me:ControlPoints() return self.points end
	function me:PlayHighPrioritySound(name) self:Record("PlayHighPrioritySound", name) end
	function me:PlayLowPrioritySound(name) self:Record("PlayLowPrioritySound", name) end
	function me:BroadcastGameSound(name) self:Record("BroadcastGameSound", name) end
	function me:AddTimedGesture(act)
		self:Record("AddTimedGesture", act)
		return self.gestureTimes[act] or GESTURE_TIME
	end
	function me:SetStaff(n)
		self.staff = n
		self:Record("SetStaff", n)
	end
	function me:AttachmentPosition(name) return self.origin + V(0, 0, ATTACHMENT_HEIGHT) end
	function me:DispatchParticleAttached(name, attachment)
		Declared(name)
		self:Record("DispatchParticleAttached", name, attachment)
	end
	function me:DispatchBeam(name, attachment, to)
		Declared(name)
		self:Record("DispatchBeam", name, attachment, to)
	end
	function me:SetHidden(hidden) self.hidden = hidden end
	function me:SetCollidable(on) self.collidable = on end
	function me:StartFlying() self.flying = true end
	function me:StopFlying() self.flying = false end
	function me:SetDesiredAltitude(h) self.altitude = h end
	function me:TriggerRelay(name)
		self:Record("TriggerRelay", name)
		return self.relays[name]
	end
	function me:PreferredAreas(minSize)
		local found = {}
		for _, area in ipairs(self.areas) do
			if area.size >= minSize and not area.occupied then found[#found + 1] = area.center end
		end
		return found
	end
	function me:AreasAround(pos, range)
		self:Record("AreasAround", pos, range)
		return self.around
	end
	function me:IsInPreferredArea(t) return t.inPrefer ~= false end
	function me:RemoveGrenades(origin, radius) self:Record("RemoveGrenades", origin, radius) end
	function me:NetworkState(revealed, aoeAttack, stunned)
		self.look = {
			revealed = revealed,
			aoeAttack = aoeAttack,
			stunned = stunned,
		}
	end
	function me:EndStun(t) self:Record("EndStun", t) end
	function me:StartBossTimer(seconds, variation) self:Record("StartBossTimer", seconds, variation) end
	function me:PlayScriptedScene(name) self:Record("PlayScriptedScene", name) end
	function me:RemoveCond(t, cond)
		t.conds[cond] = nil
		self:Record("RemoveCond", t, cond)
	end
	function me:RemoveEntity(t)
		t.valid = false
		self:Record("RemoveEntity", t)
	end
	return me
end

-- Merasmus at the origin (unless told) with the given players.
local function Scene(t)
	t = t or {}
	local world = FakeCombatant.World()
	local players = {}
	for i, p in ipairs(t.players or {}) do players[i] = world:AddPlayer(p) end
	t.world = world
	local me = Port(t)
	local npc = NpcSystem.Npc.New(Merasmus, { convars = Merasmus.CONVARS }, me)
	return {
		world = world,
		players = players,
		me = me,
		npc = npc,
		state = npc:State(),
	}
end

local function Tick(s, seconds)
	local steps = math.floor(seconds / TICK + 0.5)
	for _ = 1, math.max(steps, 1) do
		s.me.clock:Advance(TICK)
		s.npc:Update(TICK)
	end
end

-- Tick until the innermost action is `name`, for at most `limit` seconds.
local function TickUntil(s, name, limit)
	local waited = 0
	while s.npc:Describe() ~= name do
		T.eq(waited <= limit, true, "reached " .. name .. " (at " .. s.npc:Describe() .. ")")
		Tick(s, TICK)
		waited = waited + TICK
	end
end

local function Count(me, name) return #me:Called(name) end
local function ClearLog(me) me.calls = {} end

local function Names(me, method)
	local names = {}
	for _, args in ipairs(me:Called(method)) do names[#names + 1] = args[1] end
	return table.concat(names, ",")
end

local function FiredNamed(me, name)
	local found = {}
	for _, args in ipairs(me:Called("FireGameEvent")) do
		if args[1] == name then found[#found + 1] = args[2] end
	end
	return found
end

local function SpawnedOf(me, class)
	local found = {}
	for _, args in ipairs(me:Called("SpawnEntity")) do
		if args[1] == class then
			found[#found + 1] = {
				config = args[2],
				pos = args[3],
			}
		end
	end
	return found
end

-- Revealed, then attacking: the reveal's activity ends.
local function Arrived(s)
	s.npc:Update(TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Reveal", "revealing")
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "attacking")
end

local function Damage(attacker, amount, position)
	return {
		attacker = attacker,
		amount = amount,
		dmgType = Actor.DMG_GENERIC,
		position = position or V(0, 0, 50),
		crit = false,
	}
end

-------------------------------------------------------------------------------
-- What he is

T.test("Merasmus keeps TF2's numbers as his convars' defaults", function()
	local cv = Merasmus.CONVARS
	T.eq(cv.tf_merasmus_health_base, 33750, "health base")
	T.eq(cv.tf_merasmus_health_per_player, 2500, "per player")
	T.eq(cv.tf_merasmus_min_player_count, 10, "min players")
	T.eq(cv.tf_merasmus_lifetime, 120, "lifetime")
	T.eq(cv.tf_merasmus_speed, 600, "speed")
	T.eq(cv.tf_merasmus_chase_duration, 7, "chase duration")
	T.eq(cv.tf_merasmus_chase_range, 2000, "chase range")
	T.eq(cv.tf_merasmus_should_disguise_threshold, 0.45, "disguise threshold")
	T.eq(cv.tf_merasmus_min_props_to_reveal, 0.7, "props to reveal")
	T.eq(cv.tf_merasmus_attack_range, 200, "attack range")
	T.eq(cv.tf_merasmus_health_regen_rate, 0.001, "regen")
	T.eq(cv.tf_merasmus_bomb_head_duration, 15, "bomb head duration")
	T.eq(cv.tf_merasmus_bomb_head_per_team, 1, "bomb heads per team")
	T.eq(cv.tf_merasmus_stun_duration, 2, "stun")
	T.eq(cv.tf_merasmus_prop_health, 150, "prop health")
	T.eq(Merasmus.BOSS_TYPE, HalloweenBoss.BOSS_MERASMUS, "boss type")
	T.eq(Merasmus.KIND, HalloweenBoss.KIND, "a boss")
	T.eq(Merasmus.PATH, "foundation.npc.path.ground", "path")
	T.eq(Merasmus.LOCOMOTION.runSpeed, 600, "run speed")
	T.eq(Merasmus.LOCOMOTION.stepHeight, 18, "step")
	T.eq(Merasmus.LOCOMOTION.jumpHeight, 18, "jump")
	T.eq(Merasmus.LOCOMOTION.maxYawRate, 200, "yaw rate")
	T.eq(Merasmus.FLYING.hoverHeight, 50, "flying altitude")
	T.eq(Merasmus.FLYING.acceleration, 250, "MERASMUS_ACCELERATION")
	T.eq(Merasmus.FLYING.horizontalDamping, 1, "damping")
	T.eq(Merasmus.FLYING.verticalDamping, 1, "damping")
	T.eq(Merasmus.FLYING_MAX_YAW_RATE, 100, "flying yaw rate")
	T.eq(HalloweenBoss.CLASSES[HalloweenBoss.BOSS_MERASMUS], "merasmus", "his class")
end)

-- CMerasmusLocomotion::ShouldCollideWith, CMerasmusFlyingLocomotion's
T.test("players pass through him, on foot and aloft", function()
	T.eq(Merasmus.PLAYERS_PASS_THROUGH, true, "no collision with players")
	T.eq(T.require("foundation.npc.headless_hatman").PLAYERS_PASS_THROUGH, nil, "the Horsemann collides with them")
	T.eq(T.require("foundation.npc.eyeball_boss").PLAYERS_PASS_THROUGH, nil, "so does the eyeball")
end)

-- CMerasmus::Spawn
T.test("health is 33750, plus 2500 for each RED or BLU player beyond 10", function()
	local cv = Merasmus.CONVARS
	T.eq(Merasmus.Health(0, 1, cv), 33750, "empty")
	T.eq(Merasmus.Health(10, 1, cv), 33750, "ten")
	T.eq(Merasmus.Health(12, 1, cv), 38750, "twelve")
	local players = {}
	for i = 1, 13 do
		players[i] = {
			team = (i % 2 == 0) and Teams.RED or Teams.BLUE,
			origin = V(FAR, 0, 0),
		}
	end
	local s = Scene({ players = players })
	T.eq(s.me:GetMaxHealth(), 41250, "thirteen players")
	T.eq(s.me:GetHealth(), 41250, "full")
end)

-------------------------------------------------------------------------------
-- Arrival (CMerasmus::Spawn, CMerasmusReveal)

T.test("he appears with his line, his music and a puff of smoke, then reveals himself", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(0, 300, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(0, -900, 0),
			},
		},
	})
	local me = s.me
	T.eq(Names(me, "PlayHighPrioritySound"), "Halloween.MerasmusAppears", "everyone hears him appear")
	local summoned = FiredNamed(me, BossEvents.MERASMUS_SUMMONED)
	T.eq(#summoned, 1, "merasmus_summoned once")
	T.eq(summoned[1].level, 1, "at the first level")
	T.eq(Names(me, "TriggerRelay"), Merasmus.ENTER_RELAY, "the map's boss_enter_relay")
	T.eq(me:Called("DispatchParticleEffect")[1][1], "merasmus_spawn", "a puff")
	T.eq(s.state.revealed, false, "not yet revealed")
	s.npc:Update(TICK)
	T.eq(s.state.revealed, true, "revealed")
	T.eq(me:Called("StartActivity")[1][1], "ACT_SHIELD_UP", "the reveal")
	T.eq(Count(me, "PlayHighPrioritySound"), 1, "no 'discovered' line on arrival")
	T.eq(me:Called("SetBossHealth")[1][1], 1, "his bar shows")
	T.near(me.yaw, 90, EPSILON, "faces the nearer player")
	T.eq(me.hidden, false, "seen")
	T.eq(me.collidable, true, "solid")
	T.eq(me:Called("RemoveGrenades")[1][2], 400, "clears grenades near him")
	local pushes = me:Called("ApplyImpulse")
	T.eq(#pushes, 1, "pushes the near player only")
	T.eq(pushes[1][2], V(0, 500, 500), "500 up and away")
	me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "then Attack")
	T.eq(me.look.revealed, true, "the clients see him revealed")
	T.eq(me.look.stunned, false, "not stunned")
end)

T.test("a boss_enter_relay moves him to it; home stays where he spawned", function()
	local s = Scene({ relays = { [Merasmus.ENTER_RELAY] = V(500, 0, 0) } })
	T.eq(s.me.origin, V(500, 0, 0), "at the relay")
	T.eq(s.state.home, V(0, 0, 0), "home")
	T.eq(s.me:Called("DispatchParticleEffect")[1][2], V(500, 0, 0), "the puff at the relay")
end)

T.test("with nobody about he faces a random way", function()
	local s = Scene({ random = FakeCombatant.Random({ 0.25 }) })
	s.npc:Update(TICK)
	T.near(s.me.yaw, 90, EPSILON, "a quarter turn")
end)

-------------------------------------------------------------------------------
-- Attack (CMerasmusAttack, CMerasmusStaffAttack)

T.test("he chases the nearest chaseable player and swings his staff in range", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(150, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(400, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(100, 0, 0),
				inRespawnRoom = true,
			},
		},
		gestureTimes = { ACT_MP_ATTACK_STAND_MELEE = 0.8 },
	})
	local red = s.players[1]
	Arrived(s)
	ClearLog(s.me)
	s.me.yaw = 0
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/StaffAttack", "whack")
	T.eq(s.me:Called("AddTimedGesture")[1][1], "ACT_MP_ATTACK_STAND_MELEE", "the swing")
	T.eq(Count(s.me, "PlayLowPrioritySound"), 0, "no line at a roll of 1 of 0..2")
	Tick(s, 0.3)
	T.eq(Count(s.me, "DealDamage"), 0, "not before half the swing")
	Tick(s, 0.2)
	local hit = s.me:Called("DealDamage")[1]
	T.eq(hit[1], red, "the nearest who is not in a spawn room")
	T.eq(hit[2], 70, "70")
	T.eq(hit[3], Actor.DMG_CLUB, "a club")
	T.eq(Names(s.me, "PlayLowPrioritySound"), "Halloween.HeadlessBossAxeHitFlesh", "thwack")
	T.eq(s.me:Called("ApplyImpulse")[1][2], V(500, 0, 500), "knocked 500 up and away")
	Tick(s, 0.4)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "the swing ends")
end)

T.test("the staff misses outside its cone and beyond 0.9 of the attack range", function()
	local wide = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(0, 150, 0),
			},
		},
	})
	Arrived(wide)
	wide.me.yaw = 0
	Tick(wide, 1)
	T.eq(Count(wide.me, "DealDamage"), 0, "beside him at 150 needs a dot over 0.135")
	local far = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(190, 0, 0),
			},
		},
	})
	Arrived(far)
	far.me.yaw = 0
	Tick(far, TICK)
	T.eq(far.npc:Describe(), "BossBehavior/StaffAttack", "in attack range")
	Tick(far, 1)
	T.eq(Count(far.me, "DealDamage"), 0, "but past 180")
end)

T.test("a third of his swings come with a line, a fifth of those the rare one", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(150, 0, 0),
			},
		},
		random = FakeCombatant.Random({ 0 }),
	})
	Arrived(s)
	Tick(s, TICK)
	T.eq(Names(s.me, "PlayLowPrioritySound"), "Halloween.MerasmusStaffAttackRare", "rare")
end)

-- Out of sight, so his bombs go nowhere and his spells end at once.
T.test("he keeps his victim for 7 s, then takes the nearest again", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
				visible = false,
			},
			{
				team = Teams.BLUE,
				origin = V(1500, 0, 0),
				visible = false,
			},
		},
		activityTimes = { ACT_RANGE_ATTACK2 = 0 },
	})
	local red, blue = s.players[1], s.players[2]
	Arrived(s)
	Tick(s, TICK)
	local path = s.me.paths[1]
	T.eq(path.goal, red.origin, "chases RED")
	red.origin = V(1800, 0, 0)
	Tick(s, 1.2)
	T.eq(path.goal, V(1800, 0, 0), "still RED, now further than BLU")
	Tick(s, 8)
	T.eq(path.goal, blue.origin, "after 7 s, BLU")
end)

T.test("with no victim he heads home, which follows the point BLU must take", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
		},
		points = {
			{
				origin = V(1000, 0, 0),
				inRound = true,
				owner = Teams.BLUE,
				blueMayCapture = false,
			},
			{
				origin = V(1500, 0, 0),
				inRound = true,
				owner = Teams.RED,
				blueMayCapture = true,
			},
		},
	})
	Arrived(s)
	Tick(s, 3.2)
	T.eq(s.me.paths[1].goal, V(1500, 0, 0), "the first point BLU does not own and may capture")
end)

T.test("stuck, he warps to his path's goal; a player who bumps him becomes his victim", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(1900, 0, 0),
			},
		},
	})
	local blue = s.players[2]
	Arrived(s)
	Tick(s, TICK)
	s.npc:Event("OnStuck")
	T.eq(s.me.origin, V(1000, 0, 10), "10 above the goal")
	s.npc:Event("OnContact", blue)
	Tick(s, 1.1)
	T.eq(s.me.paths[1].goal, blue.origin, "chasing who bumped him")
end)

-------------------------------------------------------------------------------
-- Bombs (CMerasmusThrowingGrenade, CMerasmus::CreateMerasmusGrenade)

T.test("every 2-3 s he throws a bomb from his hand at his victim", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(500, 0, 0),
			},
		},
	})
	Arrived(s)
	s.me.yaw = 0
	TickUntil(s, "BossBehavior/ThrowingGrenade", 2.6)
	T.eq(s.me:Called("AddTimedGesture")[1][1], "ACT_MP_ATTACK_STAND_ITEM1", "the throw")
	T.eq(s.me.staff, Merasmus.STAFF_THROWING, "the staff away")
	T.eq(#SpawnedOf(s.me, Merasmus.GRENADE_CLASS), 0, "not yet")
	Tick(s, 0.3)
	local bombs = SpawnedOf(s.me, Merasmus.GRENADE_CLASS)
	T.eq(#bombs, 1, "one bomb")
	local config = bombs[1].config
	T.eq(config.damage, 50, "damage")
	T.eq(config.radius, 300, "radius")
	T.eq(config.fuse, 2, "fuse")
	T.eq(config.explodeOnTouch, false, "only on its fuse")
	T.eq(config.model, "models/props_lakeside_event/bomb_temp.mdl", "his bomb")
	T.eq(config.scale, 1, "scale")
	T.eq(config.team, Teams.UNASSIGNED, "his team")
	T.eq(config.attacker, s.me, "his")
	T.eq(config.particle, "merasmus_dazed_explosion", "its blast")
	T.eq(bombs[1].pos, s.me.origin + V(0, 0, ATTACHMENT_HEIGHT), "from his hand")
	T.eq(config.velocity, V(1750, 0, 200), "forward 1500-2000, up 200, a little spread")
	local shoot = s.me:Called("DispatchParticleAttached")[1]
	T.eq(shoot[1], "merasmus_shoot", "a flash")
	T.eq(shoot[2], Merasmus.HAND_ATTACHMENT, "at his hand")
	Tick(s, 1)
	T.eq(s.npc:Describe() ~= "BossBehavior/ThrowingGrenade", true, "thrown")
	T.eq(s.me.staff, Merasmus.STAFF_SHOWN, "the staff back")
end)

T.test("out of sight, the bomb goes to someone he can see, or nobody", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(500, 0, 0),
				visible = false,
			},
			{
				team = Teams.BLUE,
				origin = V(0, 900, 0),
			},
		},
	})
	Arrived(s)
	TickUntil(s, "BossBehavior/ThrowingGrenade", 2.6)
	local faced = s.me:Called("FaceTowards")
	T.eq(faced[#faced][1], s.players[2].origin + V(0, 0, 36), "turns to the one in sight")
	local alone = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(500, 0, 0),
				visible = false,
			},
		},
	})
	Arrived(alone)
	Tick(alone, 2.6)
	T.eq(#SpawnedOf(alone.me, Merasmus.GRENADE_CLASS), 0, "no bomb")
	T.eq(alone.npc:Describe(), "BossBehavior/Attack", "no target")
	T.eq(alone.me.staff, Merasmus.STAFF_SHOWN, "the staff stays")
end)

-------------------------------------------------------------------------------
-- Spells (CMerasmusZap, CMerasmus::Zap, CastSpell)

T.test("every 3-4 s he zaps up to six players in sight within 600: burnt, flung and hurt by distance", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(250, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(0, 700, 0),
			},
			{
				team = Teams.RED,
				origin = V(-300, 0, 0),
				visible = false,
			},
		},
		random = FakeCombatant.Random({
			1,
			0,
		}),
	})
	local red = s.players[1]
	Arrived(s)
	ClearLog(s.me)
	TickUntil(s, "BossBehavior/Zap", 3.1)
	T.eq(s.me.activity, "ACT_RANGE_ATTACK2", "the cast")
	T.eq(Names(s.me, "PlayLowPrioritySound"), "Halloween.MerasmusCastFireSpell", "a fire spell")
	Tick(s, 1.2)
	T.eq(Count(s.me, "DealDamage"), 0, "not before 1.3 s")
	Tick(s, 0.2)
	local hits = s.me:Called("DealDamage")
	T.eq(#hits, 1, "only RED is near and in sight")
	T.eq(hits[1][1], red, "RED")
	local distSqr = 250 * 250 + 28 * 28
	local expected = 50 + (20 - 50) * (distSqr - 100) / (300 * 300 - 100)
	T.near(hits[1][2], expected, 1e-6, "50 close, 20 at half the range")
	T.eq(hits[1][3], Actor.DMG_BURN, "burning")
	local burn = s.me:Called("AddCond")[1]
	T.eq(burn[2], COND.BURNING, "set alight")
	T.eq(burn[3], 5, "for 5 s")
	T.eq(s.me:Called("ApplyImpulse")[1][2], V(0, 0, 1000), "flung up")
	local beam = s.me:Called("DispatchBeam")[1]
	T.eq(beam[1], "merasmus_zap", "a zap")
	T.eq(beam[2], Merasmus.STAFF_ATTACHMENT, "from his staff")
	T.eq(beam[3], red.origin + V(0, 0, 64), "to their eyes")
	T.eq(Names(s.me, "EmitSound"), "Halloween.Merasmus_Spell", "the spell lands")
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "zapped")
end)

T.test("a levelled Merasmus zaps further, more players, harder", function()
	local players = {}
	for i = 1, 8 do
		players[i] = {
			team = Teams.RED,
			origin = V(620, i, 0),
		}
	end
	local s = Scene({
		players = players,
		shared = { level = 2 },
		random = FakeCombatant.Random({
			1,
			0,
		}),
	})
	Arrived(s)
	TickUntil(s, "BossBehavior/Zap", 3.1)
	Tick(s, 1.4)
	local hits = s.me:Called("DealDamage")
	T.eq(#hits, 7, "seven at level 2, within 650")
	T.near(hits[1][2], 25, 1e-6, "the far damage is 25 at level 2")
	T.eq(Merasmus.Level(s.me), 2, "level")
end)

-------------------------------------------------------------------------------
-- Bomb heads (CMerasmus::BombHeadMode, CTFPlayerShared's bomb head)

-- Players far from home, so nobody is chased. RED's second player has
-- gone longest without a bomb; BLU's second is outside the preferred areas.
local function BombScene(t)
	t = t or {}
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
			{
				team = Teams.RED,
				origin = V(FAR, 200, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(-FAR, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(-FAR, 200, 0),
				inPrefer = false,
			},
		},
		shared = t.shared,
		areas = t.areas,
	})
	s.me:Shared().bombHeadStamps = { [s.players[1]] = 0.5 }
	return s
end

T.test("10 s into his attack, each team's longest-spared player in a preferred area gets a bomb head", function()
	local s = BombScene({ shared = { level = 1 } })
	local redB, blueA = s.players[2], s.players[3]
	Arrived(s)
	Tick(s, 9.8)
	T.eq(#FiredNamed(s.me, BossEvents.HALLOWEEN_BOMB_HEAD), 0, "not before 10 s")
	Tick(s, 0.3)
	local given = FiredNamed(s.me, BossEvents.HALLOWEEN_BOMB_HEAD)
	T.eq(#given, 2, "one per team")
	T.eq(given[1].player, redB, "RED's never-bombed player")
	T.eq(given[1].duration, 15, "for 15 s")
	T.eq(given[2].player, blueA, "BLU's one in a preferred area")
	local stun = s.me:Called("StunPlayer")[1]
	T.eq(stun[1], redB, "stunned")
	T.eq(stun[2], 15, "for the bomb's time")
	T.eq(stun[3], 0, "not slowed")
	T.eq(stun[4], Players.STUN.LOSER_STATE, "but helpless")
	T.eq(redB.conds[COND.HALLOWEEN_BOMB_HEAD], true, "a bomb head")
	T.eq(redB.conds[COND.SPEED_BOOST], true, "and fast")
	T.eq(s.me:Shared().bombHeadStamps[redB], s.me:Now(), "remembered across Merasmuses")
	Tick(s, 4)
	T.eq(#FiredNamed(s.me, BossEvents.HALLOWEEN_BOMB_HEAD), 2, "no more within 16 s")
end)

T.test("a bomb head blows when its time runs out, pushing everyone near; one who dies blows too", function()
	local s = BombScene()
	local redB, blueA = s.players[2], s.players[3]
	Arrived(s)
	Tick(s, 10.1)
	local near = s.world:AddPlayer({
		team = Teams.BLUE,
		origin = redB.origin + V(100, 0, 0),
	})
	blueA.alive = false
	ClearLog(s.me)
	Tick(s, TICK)
	local blasts = s.me:Called("Explode")
	T.eq(#blasts, 1, "the dead one blows")
	T.eq(blasts[1][1].attacker, blueA, "their own bomb")
	T.eq(Count(s.me, "ApplyImpulse"), 0, "a dead one pushes nobody")
	T.eq(Count(s.me, "DealDamage"), 0, "and spares their body")
	ClearLog(s.me)
	Tick(s, 15)
	blasts = s.me:Called("Explode")
	T.eq(#blasts, 1, "RED's blows at the end")
	local blast = blasts[1][1]
	T.eq(blast.origin, redB.origin + V(0, 0, 64), "at their head")
	T.eq(blast.damage, 100, "100 while Merasmus fights")
	T.eq(blast.radius, 100, "radius 100")
	T.eq(blast.attackerTeam, Teams.RED, "their team")
	T.eq(blast.attacker, redB, "theirs")
	local own = s.me:Called("DealDamage")[1]
	T.eq(own[1], redB, "it hurts its carrier too")
	T.eq(own[2], 100, "all of it, at their head")
	T.eq(own[3], Actor.DMG_BLAST, "a blast")
	T.eq(own[4], redB, "their own")
	local pushed = {}
	for _, args in ipairs(s.me:Called("ApplyImpulse")) do pushed[args[1]] = args[2] end
	T.eq(pushed[near], V(400, 0, 400), "the one near flies up and away")
	T.eq(pushed[redB], V(0, 0, 400), "the bomb head straight up")
	T.eq(s.me:Called("DispatchParticleEffect")[1][1], "bombinomicon_burningdebris", "debris")
	T.eq(redB.conds[COND.HALLOWEEN_BOMB_HEAD], nil, "no longer a bomb head")
	local ended = FiredNamed(s.me, BossEvents.HALLOWEEN_BOMB_HEAD)
	T.eq(ended[#ended].duration, 0, "the clients drop the bomb")
end)

T.test("a bomb head who reaches him stuns him, is freed and buffed, and blows on him", function()
	local s = BombScene()
	local redB = s.players[2]
	Arrived(s)
	Tick(s, 10.1)
	ClearLog(s.me)
	redB.origin = V(0, 0, 0)
	Tick(s, TICK)
	T.eq(Names(s.me, "PlayLowPrioritySound"):match("Halloween.MerasmusHitByBomb$") ~= nil, true, "ow")
	T.eq(redB.conds[COND.CRITBOOSTED_PUMPKIN], true, "crits")
	T.eq(redB.conds[COND.SPEED_BOOST], true, "speed")
	T.eq(redB.conds[COND.INVULNERABLE], true, "and safe")
	T.eq(s.me:Called("AddCond")[1][3], 10, "for 10 s")
	T.eq(s.me:Called("EndStun")[1][1], redB, "free to move")
	T.eq(redB.conds[COND.HALLOWEEN_BOMB_HEAD], nil, "the bomb is off")
	T.eq(Count(s.me, "Explode"), 2, "the bomb blows as it comes off, and again on him")
	local pushes = s.me:Called("ApplyImpulse")
	T.eq(pushes[#pushes][2], V(0, 0, 300), "the bomb head bounces off him")
	T.eq(s.state.bombHitCount, 1, "one hit")
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Stunned", "stunned")
	T.eq(Names(s.me, "EmitSound"), "Halloween.Merasmus_Stun", "dazed")
	Tick(s, TICK)
	T.eq(s.me.look.stunned, true, "the clients see the stars")
	T.eq(s.me:Called("SetSkin")[#s.me:Called("SetSkin")][1], Merasmus.SKIN_VULNERABLE, "his stunned skin")
end)

-------------------------------------------------------------------------------
-- Stunned and teleporting (CMerasmusStunned, CMerasmusTeleport)

local function Stunned(s)
	local redB = s.players[2]
	Arrived(s)
	Tick(s, 10.1)
	redB.origin = V(0, 0, 0)
	Tick(s, TICK)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Stunned", "stunned")
end

T.test("stunned, he reels while the stun lasts, then teleports to a free preferred area", function()
	local s = BombScene({
		areas = {
			{
				center = V(3000, 3000, 0),
				size = 200,
			},
			{
				center = V(0, 3000, 0),
				size = 50,
			},
		},
	})
	Stunned(s)
	Tick(s, 1)
	Tick(s, 1)
	T.eq(s.npc:Describe(), "BossBehavior/Stunned", "reeling while the 2 s stun lasts")
	TickUntil(s, "BossBehavior/Teleport", 4)
	T.eq(Names(s.me, "AddTimedGesture"):match("ACT_MP_STUN_END") ~= nil, true, "the stun's end")
	T.eq(s.state.stunned, false, "no longer stunned")
	T.eq(s.me:Called("StartActivity")[#s.me:Called("StartActivity")][1], "ACT_SHIELD_DOWN", "vanishing")
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.me.hidden, true, "gone")
	T.eq(s.me.origin, V(3000, 3000, 0), "to the big area")
	Tick(s, TICK)
	T.eq(s.me.hidden, false, "back")
	T.eq(s.me:Called("StartActivity")[#s.me:Called("StartActivity")][1], "ACT_SHIELD_UP", "appearing")
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "attacking again")
end)

T.test("the third hit sends him home to rain bombs from the air", function()
	local s = BombScene()
	s.state.bombHitCount = 2
	Stunned(s)
	s.me.points = {
		{
			origin = V(2000, 0, 0),
			inRound = true,
			owner = Teams.RED,
			blueMayCapture = true,
		},
	}
	s.me.around = {
		V(2100, 0, 0),
		V(1900, 50, 0),
	}
	TickUntil(s, "BossBehavior/Teleport", 6)
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.me.origin, V(0, 0, 75), "75 above home")
	Tick(s, TICK)
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/AOEAttack", "the bomb rain")
	T.eq(s.me.flying, true, "flying")
	local around = s.me:Called("AreasAround")[1]
	T.eq(around[1], V(2000, 0, 0), "around the first point")
	T.eq(around[2], 400, "within 400")
	T.eq(s.me:Called("StartActivity")[#s.me:Called("StartActivity")][1], "ACT_RANGE_ATTACK1", "the book")
	local scenes = s.me:Called("PlayScriptedScene")
	T.eq(#scenes, 1, "one scripted scene")
	T.eq(scenes[1][1]:match("^scenes/bot/merasmus/low/bomb_attack_00[1-9]%.vcd$") ~= nil, true, "a bomb_attack scene: " .. scenes[1][1])
	Tick(s, 3.9)
	T.eq(s.state.aoe, false, "not firing for 4 s")
	ClearLog(s.me)
	local waited = 0
	while #SpawnedOf(s.me, Merasmus.GRENADE_CLASS) == 0 do
		T.eq(waited <= 1, true, "the first bombs within 4.5 s")
		Tick(s, TICK)
		waited = waited + TICK
	end
	T.eq(s.state.aoe, true, "firing")
	T.eq(s.me.look.aoeAttack, true, "the clients see the book")
	T.eq(s.me.altitude >= 150 and s.me.altitude <= 200, true, "bobbing at 175 ± 25")
	local bombs = SpawnedOf(s.me, Merasmus.GRENADE_CLASS)
	T.eq(#bombs, 4, "four bombs a tick")
	T.eq(bombs[1].pos, s.me:WorldSpaceCenter() + V(0, 0, 150), "150 over him")
	T.eq(bombs[1].config.velocity.z, 750, "up 750")
	Tick(s, 0.7)
	T.eq(#SpawnedOf(s.me, Merasmus.GRENADE_CLASS), 29, "two rings: 11 and 18")
	T.eq(Count(s.me, "Approach") > 0, true, "wandering over the point")
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.me.flying, false, "landed")
	T.eq(s.state.aoe, false, "done")
	T.eq(s.state.bombHitCount, 0, "hits forgotten")
	T.eq(s.me.staff, Merasmus.STAFF_SHOWN, "the staff back")
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "attacking again")
end)

T.test("the bomb rain throws spokes or rings", function()
	local rings = Merasmus.BombRings(0, V)
	T.eq(#rings, 29, "11 at 1050, 18 at 2000")
	T.eq(rings[1], V(1050, 0, 750), "the first along his facing")
	local second = rings[12]
	T.near(second:Length2D(), 2000, 1e-6, "the second ring at 2000")
	T.near(second.x, 2000 * math.cos(math.rad(11 * 35)), 1e-6, "turned on from where the first ended")
	T.eq(second.z, 750, "up 750")
	local spokes = Merasmus.BombSpokes(0, V)
	T.eq(#spokes, 32, "8 spokes of 4")
	T.eq(spokes[1], V(575, 0, 750), "the slowest first")
	T.eq(spokes[4], V(2000, 0, 750), "the fastest")
end)

T.test("with no control point the bomb rain is off", function()
	local s = BombScene()
	s.state.bombHitCount = 2
	Stunned(s)
	TickUntil(s, "BossBehavior/Teleport", 6)
	s.me:FinishActivity()
	Tick(s, TICK)
	Tick(s, TICK)
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.me.flying, false, "not flying")
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "attacking")
end)

-------------------------------------------------------------------------------
-- Damage (CMerasmus::OnTakeDamage_Alive)

T.test("only a revealed Merasmus is hurt; his bar shows what is left", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
		},
	})
	local red = s.players[1]
	T.eq(s.npc:FilterDamage(Damage(red, 100)), false, "not before he is revealed")
	Arrived(s)
	ClearLog(s.me)
	local max = s.me:GetMaxHealth()
	T.eq(s.npc:FilterDamage(Damage(red, 1000, V(1, 2, 3))), true, "revealed")
	T.eq(s.me:Called("SetBossHealth")[1][1], (max - 1000) / max, "the bar")
	local blood = s.me:Called("DispatchParticleEffect")[1]
	T.eq(blood[1], "merasmus_blood_bits", "bits")
	T.eq(blood[2], V(1, 2, 3), "where he was hit")
	s.state.stunned = true
	s.npc:FilterDamage(Damage(red, 10))
	T.eq(s.me:Called("DispatchParticleEffect")[2][1], "merasmus_blood", "blood while stunned")
	T.eq(s.npc:FilterDamage(Damage(s.me, 10)), false, "never himself")
end)

-- MerasmusModifyDamage, by the damage type that stands for TF2's weapon.
T.test("a player's sniper rounds, crossbow bolts and blades hit him x3, buckshot x2", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
		},
	})
	local red = s.players[1]
	Arrived(s)
	local function Taken(attacker, dmgType)
		local hit = Damage(attacker, 10)
		hit.dmgType = dmgType
		local _, amount = s.npc:FilterDamage(hit)
		return amount
	end
	T.eq(Taken(red, Actor.DMG_BULLET + Actor.DMG_SNIPER), 30, "the sniper rifle's")
	T.eq(Taken(red, Actor.DMG_BULLET + Actor.DMG_NEVERGIB), 30, "the bow's")
	T.eq(Taken(red, Actor.DMG_SLASH), 30, "the knife's")
	T.eq(Taken(red, Actor.DMG_BULLET + Actor.DMG_BUCKSHOT), 20, "the scattergun's")
	T.eq(Taken(red, Actor.DMG_BULLET), 10, "a plain bullet")
	T.eq(Taken(red, Actor.DMG_CLUB), 10, "a club")
	T.eq(Taken(red, Actor.DMG_BLAST), 10, "a blast: rockets, grenades, pumpkin bombs, bomb heads")
	T.eq(Taken(red, Actor.DMG_BURN), 10, "a spell's fire")
	local skeleton = s.world:AddNPC("zombie", FakeCombatant.Target({ team = Teams.BLUE }))
	T.eq(Taken(skeleton, Actor.DMG_SLASH), 10, "no weapon: a skeleton's claws")
	local max = s.me:GetMaxHealth()
	ClearLog(s.me)
	Taken(red, Actor.DMG_SLASH)
	T.eq(s.me:Called("SetBossHealth")[1][1], (max - 30) / max, "the bar shows what he took")
end)

-------------------------------------------------------------------------------
-- Hiding (CMerasmusDisguise, CTFMerasmusTrickOrTreatProp)

local HIDING_AREAS = {
	{
		center = V(0, 1000, 0),
		size = 200,
	},
	{
		center = V(0, 2000, 0),
		size = 200,
	},
	{
		center = V(0, 3000, 0),
		size = 200,
	},
	{
		center = V(5000, 0, 0),
		size = 200,
	},
	{
		center = V(6000, 0, 0),
		size = 100,
	},
	{
		center = V(7000, 0, 0),
		size = 300,
		occupied = true,
	},
}

local function Hurt(s, fraction, attacker)
	s.me.health = s.me.health - fraction * s.me:GetMaxHealth()
	s.npc:Event("OnInjured", Damage(attacker, 1))
	Tick(s, TICK)
end

local function Hidden(s)
	Arrived(s)
	Hurt(s, 0.3, s.players[1])
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "0.3 of his health is not enough")
	Hurt(s, 0.2, s.players[1])
	T.eq(s.npc:Describe(), "Disguise", "over 0.45 lost since he was revealed: he hides")
end

local function HidingScene(t)
	t = t or {}
	return Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(-FAR, 0, 0),
			},
		},
		areas = t.areas or HIDING_AREAS,
		shared = t.shared,
	})
end

T.test("badly hurt, he hides among props on separated preferred areas", function()
	local s = HidingScene()
	Hidden(s)
	T.eq(Names(s.me, "PlayHighPrioritySound"):match("Halloween.MerasmusInitiateHiding$") ~= nil, true, "he says so")
	local props = SpawnedOf(s.me, Merasmus.PROP_CLASS)
	T.eq(#props, 4, "one on each big free area")
	local models = {}
	for _, model in ipairs(Merasmus.PROP_MODELS) do models[model] = true end
	for _, prop in ipairs(props) do
		T.eq(prop.config.health, 150, "tf_merasmus_prop_health")
		T.eq(models[prop.config.model], true, "a disguise prop")
		T.eq(prop.config.boss, s.me, "his")
	end
	T.eq(s.me.hidden, true, "unseen")
	T.eq(s.me.collidable, false, "not solid")
	T.eq(s.state.revealed, false, "hiding")
	T.eq(s.state.toReveal, 3, "reveals after 2 to 4 of 4 props")
	Tick(s, TICK)
	T.eq(s.me.look.revealed, false, "the clients lose his glow")
	T.eq(s.npc:FilterDamage(Damage(s.players[1], 100)), false, "and he cannot be hurt")
end)

T.test("props are 500 apart: a near one is left out", function()
	local s = HidingScene({
		areas = {
			{
				center = V(0, 1000, 0),
				size = 200,
			},
			{
				center = V(300, 1000, 0),
				size = 200,
			},
		},
	})
	Hidden(s)
	T.eq(#SpawnedOf(s.me, Merasmus.PROP_CLASS), 1, "one")
end)

T.test("destroying props finds him: he appears at the one he hid in and rewards its finder", function()
	local s = HidingScene()
	local red = s.players[1]
	Hidden(s)
	local props = s.state.props
	T.eq(#props, 4, "four props")
	ClearLog(s.me)
	s.npc:Event("OnPropKilled", props[1], red)
	s.npc:Event("OnPropKilled", props[2], red)
	T.eq(s.me.hidden, true, "still hidden after two")
	T.eq(Count(s.me, "PlayLowPrioritySound"), 0, "a taunt only at a roll of 1 of 1..3")
	s.npc:Event("OnPropKilled", props[3], red)
	T.eq(s.me.origin, props[3].origin, "he was in the third")
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "revealed and back to work")
	T.eq(Names(s.me, "PlayHighPrioritySound"), "Halloween.MerasmusDiscovered", "found")
	T.eq(s.me.hidden, false, "seen")
	T.eq(s.me.collidable, true, "solid")
	T.eq(props[4].valid, false, "the other props go")
	T.eq(red.conds[COND.CRITBOOSTED_PUMPKIN], true, "his finder crits")
	T.eq(red.conds[COND.INVULNERABLE], true, "and is safe")
	T.eq(s.me:Called("SetBossHealth")[1][1], s.me:GetHealth() / s.me:GetMaxHealth(), "his bar")
	Hurt(s, 0.3, red)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "the count starts again from his reveal")
end)

T.test("a third of the decoys taunt their finder", function()
	local s = HidingScene()
	Hidden(s)
	s.me.random = FakeCombatant.Random({ 0 })
	s.npc:Event("OnPropKilled", { origin = V(0, 1000, 0) }, s.players[1])
	T.eq(Names(s.me, "PlayLowPrioritySound"), "Halloween.MerasmusTauntFakeProp", "ha!")
end)

T.test("a bomb head who touches a prop blows it up, and themselves", function()
	local s = HidingScene()
	local red = s.players[1]
	Hidden(s)
	local prop = { origin = V(0, 1000, 0) }
	s.npc:Event("OnPropTouched", prop, red)
	T.eq(Count(s.me, "Explode"), 0, "not a bomb head: nothing")
	s.state.bombHeads[1] = {
		player = red,
		ends = s.me:Now() + 5,
	}
	red.conds[COND.HALLOWEEN_BOMB_HEAD] = true
	s.npc:Event("OnPropTouched", prop, red)
	T.eq(Count(s.me, "Explode"), 2, "the bomb comes off and blows again")
	T.eq(s.me:Called("EndStun")[1][1], red, "freed")
	local kill = nil
	for _, args in ipairs(s.me:Called("DealDamage")) do
		if args[1] == prop then kill = args end
	end
	T.eq(kill[1], prop, "the prop")
	T.eq(kill[2] >= 99999, true, "is destroyed")
	T.eq(kill[3], Actor.DMG_BLAST, "by the blast")
	T.eq(kill[4], red, "credited to the bomb head")
end)

T.test("a soldier's or demo's blast destroys a prop at once", function()
	T.eq(Merasmus.PropDamage(30, true, 150), 300, "twice its health")
	T.eq(Merasmus.PropDamage(30, false, 150), 30, "anything else as dealt")
end)

T.test("with no place to hide he gives up after 3 s and is found at once", function()
	local s = HidingScene({ areas = {} })
	Hidden(s)
	Tick(s, 2.8)
	T.eq(s.npc:Describe(), "Disguise", "still looking")
	Tick(s, 0.4)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "revealed")
	T.eq(#SpawnedOf(s.me, Merasmus.PROP_CLASS), 0, "no props")
end)

T.test("hidden, he taunts every 10-25 s, and past the first level heals", function()
	local s = HidingScene({ shared = { level = 2 } })
	Hidden(s)
	local health = s.me:GetHealth()
	ClearLog(s.me)
	Tick(s, 17)
	T.eq(Count(s.me, "PlayHighPrioritySound"), 0, "not before 17.5 s")
	Tick(s, 0.6)
	T.eq(Names(s.me, "PlayHighPrioritySound"), "Halloween.MerasmusHidden", "where am I?")
	local expected = math.floor(health + 17.6 * 0.001 * s.me:GetMaxHealth())
	T.near(s.me:GetHealth(), expected, 1, "0.1% of his max a second per level past the first")
	T.eq(Count(s.me, "SetBossHealth") > 0, true, "the bar follows")
end)

T.test("at the first level he does not heal while hidden", function()
	local s = HidingScene()
	Hidden(s)
	local health = s.me:GetHealth()
	Tick(s, 5)
	T.eq(s.me:GetHealth(), health, "no regeneration")
end)

-------------------------------------------------------------------------------
-- Leaving (CMerasmus::LeaveWarning, CMerasmusEscape)

T.test("he warns at 60, 30 and 10 s, then goes home after 120 s", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
		},
		shared = { level = 3 },
	})
	Arrived(s)
	Tick(s, 59.5)
	T.eq(#FiredNamed(s.me, BossEvents.MERASMUS_ESCAPE_WARNING), 0, "no warning yet")
	Tick(s, 0.5)
	local warnings = FiredNamed(s.me, BossEvents.MERASMUS_ESCAPE_WARNING)
	T.eq(#warnings, 1, "one minute")
	T.eq(warnings[1].time_remaining, 60, "60")
	T.eq(warnings[1].level, 3, "his level")
	TickUntil(s, "Escape", 61)
	warnings = FiredNamed(s.me, BossEvents.MERASMUS_ESCAPE_WARNING)
	T.eq(#warnings, 3, "three warnings")
	T.eq(warnings[2].time_remaining, 30, "30")
	T.eq(warnings[3].time_remaining, 10, "10")
	T.eq(s.me:Called("StartActivity")[#s.me:Called("StartActivity")][1], "ACT_FLY", "away")
	local lines = s.me:Called("PlayHighPrioritySound")
	T.eq(lines[#lines][1], "Halloween.MerasmusDepart", "goodbye")
	ClearLog(s.me)
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(s.me:Called("DispatchParticleEffect")[1][1], "merasmus_tp", "a puff")
	T.eq(s.me:Called("DispatchParticleEffect")[1][2], s.me.origin + V(0, 0, ATTACHMENT_HEIGHT), "at his robe")
	T.eq(s.me:Called("SetBossHealth")[1][1], 0, "no bar")
	T.eq(FiredNamed(s.me, BossEvents.MERASMUS_ESCAPED)[1].level, 3, "merasmus_escaped")
	T.eq(Names(s.me, "TriggerRelay"), Merasmus.EXIT_RELAY, "boss_exit_relay")
	T.eq(s.me:Shared().level, 1, "the next one starts at level 1")
	local timer = s.me:Called("StartBossTimer")
	T.eq(#timer, 1, "the boss timer starts (CMerasmus::StartRespawnTimer)")
	T.eq(timer[1][1], Merasmus.CONVARS.tf_merasmus_spawn_interval, "at the first level's interval")
	T.eq(timer[1][2], Merasmus.CONVARS.tf_merasmus_spawn_interval_variation, "and variation")
	T.eq(s.me.removed, true, "gone")
end)

T.test("he does not leave while stunned", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
		},
	})
	Arrived(s)
	Tick(s, 110)
	s.state.stunned = true
	Tick(s, 11)
	T.eq(s.npc:Describe(), "BossBehavior/Attack", "stays")
	s.state.stunned = false
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "Escape", "then goes")
end)

T.test("hidden when his time is up, he steps out of a prop and leaves", function()
	local s = HidingScene()
	Hidden(s)
	local spots = {}
	for i, prop in ipairs(s.state.props) do spots[i] = prop.origin end
	Tick(s, 120)
	T.eq(s.npc:Describe(), "Escape", "leaving")
	T.eq(s.me.hidden, false, "seen")
	local onAProp = false
	for _, spot in ipairs(spots) do
		if s.me.origin == spot then onAProp = true end
	end
	T.eq(onAProp, true, "where a prop stood")
end)

-------------------------------------------------------------------------------
-- Death (CMerasmusDying)

T.test("killed, he is banished: his music plays, he bursts, and leaves a vortex to each team's loot", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
		},
	})
	Arrived(s)
	s.me.alive = false
	s.npc:Event("OnKilled", Damage(s.players[1], 100))
	ClearLog(s.me)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "Dying", "dying")
	T.eq(s.me:Called("StartActivity")[1][1], "ACT_DIESIMPLE", "falls")
	T.eq(Names(s.me, "PlayHighPrioritySound"), "Halloween.MerasmusBanish", "his last words")
	T.eq(Names(s.me, "BroadcastGameSound"), "Halloween.Merasmus_Death", "his death music for everyone")
	Tick(s, 1)
	T.eq(s.me.removed, false, "until the activity ends")
	s.me:FinishActivity()
	Tick(s, TICK)
	T.eq(Count(s.me, "Break"), 1, "bursts")
	T.eq(s.me:Called("DispatchParticleEffect")[1][1], "merasmus_spawn", "a puff")
	T.eq(FiredNamed(s.me, BossEvents.MERASMUS_KILLED)[1].level, 1, "merasmus_killed at his level")
	T.eq(Names(s.me, "TriggerRelay"), Merasmus.DEAD_RELAY, "boss_dead_relay")
	local vortex = SpawnedOf(s.me, Merasmus.VORTEX_CLASS)[1]
	T.eq(vortex.config.death, true, "to the loot")
	T.eq(vortex.config.splitTeam, true, "each team to its own")
	T.eq(vortex.pos, s.me:WorldSpaceCenter(), "where he stood")
	T.eq(s.me:Shared().level, 2, "the next one is a level up")
	local timer = s.me:Called("StartBossTimer")
	T.eq(#timer, 1, "the boss timer starts (CMerasmus::StartRespawnTimer)")
	T.eq(timer[1][1], Merasmus.CONVARS.tf_merasmus_spawn_interval, "at his interval")
	T.eq(s.me.removed, true, "gone")
end)

T.test("killed past the third level, the next one is timed a minute away", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(FAR, 0, 0),
			},
		},
		shared = { level = 3 },
	})
	Arrived(s)
	s.me.alive = false
	s.npc:Event("OnKilled", Damage(s.players[1], 100))
	Tick(s, TICK)
	s.me:FinishActivity()
	Tick(s, TICK)
	local timer = s.me:Called("StartBossTimer")
	T.eq(s.me:Shared().level, 4, "the fourth level")
	T.eq(timer[1][1], 60, "a minute")
	T.eq(timer[1][2], 0, "exactly")
end)

-- CMerasmus::UpdateOnRemove
T.test("removed, he hides his bar, blows the bomb heads and takes his props", function()
	local s = HidingScene()
	local red = s.players[1]
	Hidden(s)
	s.state.bombHeads[1] = {
		player = red,
		ends = s.me:Now() + 5,
	}
	local props = s.state.props
	ClearLog(s.me)
	Merasmus.Removed(s.state, s.me)
	T.eq(s.me:Called("SetBossHealth")[1][1], 0, "no bar")
	T.eq(Count(s.me, "Explode"), 1, "the bomb blows")
	T.eq(#s.state.bombHeads, 0, "no bomb heads")
	T.eq(Count(s.me, "RemoveEntity"), #props, "props gone")
end)

-------------------------------------------------------------------------------
-- The port

T.test("the fake implements every boss and Merasmus method, and none shadows another port's", function()
	local s = Scene()
	local taken = {}
	for _, name in ipairs(Actor.METHODS) do taken[name] = true end
	for name in pairs(Actor.ENGINE) do taken[name] = true end
	for _, name in ipairs(Combatant.METHODS) do taken[name] = true end
	for _, name in ipairs(HalloweenBoss.METHODS) do
		T.eq(type(s.me[name]), "function", "fake " .. name)
		taken[name] = true
	end
	for _, name in ipairs(Merasmus.METHODS) do
		T.eq(type(s.me[name]), "function", "fake " .. name)
		T.eq(taken[name], nil, "Merasmus " .. name)
	end
end)

local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("the merasmus binding defines his port and forwards the props' events", function()
	local text = ReadFile(ENTITIES .. "merasmus.lua")
	for _, name in ipairs(Merasmus.METHODS) do
		T.eq(text:find("function ENT:" .. name .. "(", 1, true) ~= nil, true, "merasmus " .. name)
	end
	for _, name in ipairs({ "OnPropKilled", "OnPropTouched" }) do
		T.eq(text:find("function ENT:" .. name .. "(", 1, true) ~= nil, true, "merasmus " .. name)
	end
	T.eq(text:find("Removed(", 1, true) ~= nil, true, "tells the model he is removed")
end)

-- An entity file loads nothing at top level.
T.test("the merasmus bindings load nothing at top level", function()
	for _, file in ipairs({ "merasmus.lua", "tf_merasmus_trick_or_treat_prop.lua" }) do
		for line in ReadFile(ENTITIES .. file):gmatch("[^\n]+") do
			local top = not (line:match("^%s") or line:match("^function "))
			local loads = line:find("WETSAND.require", 1, true) ~= nil or line:find("WETSAND.Feature", 1, true) ~= nil
			T.eq(top and loads, false, file .. ": " .. line)
		end
	end
end)

T.finish()
