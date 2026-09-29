local T = dofile("tests/harness.lua")
local FakeCombatant = dofile("tests/fake_combatant.lua")
local Projectile = T.require("foundation.projectile")
local Rocket = T.require("foundation.projectile.rocket")
local Combat = T.require("foundation.combat")
local Teams = T.require("foundation.teams")
local NpcSystem = T.require("foundation.npc")
local Eyeball = T.require("foundation.npc.eyeball_boss")
local HalloweenBoss = T.require("foundation.npc.halloween_boss")
local Actor = T.require("foundation.npc.actor")
local Players = T.require("foundation.players")

local V = FakeCombatant.Vector

-------------------------------------------------------------------------------
-- The rocket (CTFBaseRocket, CTFProjectile_Rocket)

local function NewRocket(overrides)
	local config = {
		damage = 50,
		crit = true,
		team = Teams.HALLOWEEN,
		attacker = "eyeball",
	}
	for k, v in pairs(overrides or {}) do config[k] = v end
	return Projectile.New(Rocket, config, 0)
end

T.test("a rocket flies straight and blows up on whatever it touches", function()
	T.eq(Rocket.GRAVITY, 0, "straight")
	T.eq(NewRocket():Touch({
		world = true,
		enemy = false,
	}), Projectile.DETONATE, "the world")
	T.eq(NewRocket():Touch({
		world = false,
		enemy = true,
	}), Projectile.DETONATE, "an enemy")
	T.eq(NewRocket():Touch({
		world = false,
		enemy = false,
	}), Projectile.DETONATE, "a teammate's body")
	local rocket = NewRocket()
	T.eq(rocket:Tick(1000), Projectile.NONE, "no fuse")
	rocket:Touch({ world = true })
	T.eq(rocket:Touch({ world = true }), Projectile.NONE, "only once")
end)

T.test("a rocket's blast is TF_ROCKET_RADIUS with its damage, team, attacker and crit", function()
	T.eq(Rocket.ROCKET_RADIUS, 146, "TF_ROCKET_RADIUS")
	local rocket = NewRocket()
	local blast = Rocket.Blast(rocket.state, V(1, 2, 3))
	T.eq(blast.origin, V(1, 2, 3), "origin")
	T.eq(blast.radius, Rocket.ROCKET_RADIUS, "radius")
	T.eq(blast.damage, 50, "base damage: the explosion applies the crit")
	T.eq(blast.attackerTeam, Teams.HALLOWEEN, "team")
	T.eq(blast.attacker, "eyeball", "attacker")
	T.eq(blast.crit, true, "crit")
	T.eq(blast.halfFalloff, false, "full falloff")
	T.eq(blast.forceFriendlyFire, false, "no friendly fire")
	local amount = Combat.Explosion.New(blast):DamageTo({
		team = Teams.RED,
		isAttacker = false,
		distance = 0,
		visible = true,
	})
	T.eq(amount, 50 * Combat.CRIT_MULTIPLIER, "a crit rocket's direct hit")
	T.eq(Rocket.Blast(NewRocket({ radius = 200 }).state, V(0, 0, 0)).radius, 200, "a launcher's own radius")
end)

T.test("a rocket trails smoke, and a crit one its team's crit glow or the eyeball's", function()
	local function Trails(overrides) return table.concat(Rocket.Trails(NewRocket(overrides).state), ",") end
	T.eq(Trails({ crit = false }), Rocket.TRAIL, "plain")
	T.eq(Trails({
		crit = true,
		team = Teams.RED,
	}), Rocket.TRAIL .. ",critical_rocket_red", "RED crit")
	T.eq(Trails({
		crit = true,
		team = Teams.BLUE,
	}), Rocket.TRAIL .. ",critical_rocket_blue", "BLU crit")
	T.eq(Trails({ crit = true }), Rocket.TRAIL .. ",eyeboss_projectile", "the eyeball's crit")
end)

T.test("every trail a rocket carries is in the rocket's PARTICLES, which its binding precaches", function()
	local declared = {}
	for _, name in ipairs(Rocket.PARTICLES) do declared[name] = true end
	for _, team in ipairs({ Teams.RED, Teams.BLUE, Teams.HALLOWEEN }) do
		for _, crit in ipairs({ false, true }) do
			for _, trail in ipairs(Rocket.Trails(NewRocket({
				crit = crit,
				team = team,
			}).state)) do
				T.eq(declared[trail], true, trail)
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- MONOCULUS (CEyeballBoss and eyeball_behavior/*.cpp)

local TICK = 0.1
local EPSILON = 1e-6
local CV = Eyeball.CONVARS

-- A fake eyeball: a fake combatant with the eyeball's port. The ground is
-- at z = 0 and a nav area is near unless a test says otherwise.
local function Eye(world, t)
	local me = FakeCombatant.Combatant({
		world = world,
		variant = Eyeball,
		team = t.team or Teams.HALLOWEEN,
		origin = t.origin or V(0, 0, 0),
		random = t.random,
		shared = t.shared,
		owner = t.owner,
	})
	me.ground = 0
	me.navNear = true
	me.hidden = false
	me.altitude = nil
	function me:SetDesiredAltitude(h) self.altitude = h end
	function me:AimHeadTowards(v) self:Record("AimHeadTowards", v) end
	function me:GroundHeight(v) return self.ground end
	function me:IsNearNavMesh(v, range) return self.navNear end
	function me:SetHidden(hidden) self.hidden = hidden end
	function me:TraceWorld(from, to) return self.traceHit end
	function me:Announce(text) self:Record("Announce", text) end
	function me:Break() self:Record("Break") end
	-- SpawnEntity also records when, as a fourth value.
	function me:SpawnEntity(class, config, pos)
		self:Record("SpawnEntity", class, config, pos, self:Now())
		return FakeCombatant.Target({ origin = pos })
	end
	return me
end

local function Scene(t)
	local world = FakeCombatant.World()
	local players = {}
	for i, p in ipairs(t.players or {}) do players[i] = world:AddPlayer(p) end
	world:SetSpawnPoints("spawn_boss_alt", t.spots or {})
	local me = Eye(world, t)
	local npc = NpcSystem.Npc.New(Eyeball, { convars = CV }, me)
	return {
		world = world,
		players = players,
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
local function ClearLog(me) me.calls = {} end

local function Played(me)
	local names = {}
	for _, args in ipairs(me:Called("PlaySequence")) do names[#names + 1] = args[1] end
	return table.concat(names, ",")
end

local function SoundCount(me, name)
	local n = 0
	for _, args in ipairs(me:Called("EmitSound")) do
		if args[1] == name then n = n + 1 end
	end
	return n
end

local function Particles(me)
	local names = {}
	for _, args in ipairs(me:Called("DispatchParticleEffect")) do names[#names + 1] = args[1] end
	return table.concat(names, ",")
end

-- Past the emerge and just into Idle, hovering at `at`.
local function Arrived(s, at)
	s.npc:Update(TICK)
	s.me.clock:Advance(Eyeball.RISE_TIME + TICK)
	s.me:FinishSequence()
	s.me.origin = at or V(0, 0, 200)
	s.npc:Update(TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "idle")
end

local function Rockets(me)
	local rockets = {}
	for _, args in ipairs(me:Called("SpawnEntity")) do
		if args[1] == "tf_projectile_rocket" then rockets[#rockets + 1] = args end
	end
	return rockets
end

T.test("MONOCULUS keeps TF2's numbers", function()
	T.eq(CV.tf_eyeball_boss_lifetime, 120, "lifetime")
	T.eq(CV.tf_eyeball_boss_lifetime_spell, 8, "spell lifetime")
	T.eq(CV.tf_eyeball_boss_speed, 250, "speed")
	T.eq(CV.tf_eyeball_boss_attack_range, 750, "attack range")
	T.eq(CV.tf_eyeball_boss_health_base, 8000, "health base")
	T.eq(CV.tf_eyeball_boss_health_per_player, 400, "per player")
	T.eq(CV.tf_eyeball_boss_health_at_level_2, 17000, "level 2")
	T.eq(CV.tf_eyeball_boss_health_per_level, 3000, "per level")
	T.eq(CV.tf_halloween_bot_min_player_count, 10, "min players")
	T.eq(Eyeball.HOVER.hoverHeight, 200, "hover height")
	T.eq(Eyeball.HOVER.acceleration, 500, "acceleration")
	T.eq(Eyeball.HOVER.horizontalDamping, 2, "horizontal damping")
	T.eq(Eyeball.HOVER.verticalDamping, 1, "vertical damping")
	T.eq(Eyeball.SKIN_NORMAL, 0, "normal skin")
	T.eq(Eyeball.SKIN_RED, 1, "red skin")
	T.eq(Eyeball.SKIN_TEAM_RED, 2, "team red skin")
	T.eq(Eyeball.SKIN_TEAM_BLUE, 3, "team blue skin")
	T.eq(Eyeball.ROCKET_DAMAGE, 50, "rocket damage")
	T.eq(Eyeball.ROCKET_SPEED, 1100, "rocket speed")
	T.eq(Eyeball.BOSS_TYPE, HalloweenBoss.BOSS_MONOCULUS, "boss type")
	T.eq(Eyeball.KIND, HalloweenBoss.KIND, "a boss")
end)

-- CEyeballBoss::Spawn
T.test("health: 8000 plus 400 per player beyond 10; once beaten, 17000 plus 3000 a level", function()
	T.eq(Eyeball.Health(10, 1, CV), 8000, "level 1, ten players")
	T.eq(Eyeball.Health(12, 1, CV), 8800, "level 1, twelve")
	T.eq(Eyeball.Health(30, 2, CV), 17000, "level 2 ignores players")
	T.eq(Eyeball.Health(0, 4, CV), 23000, "level 4")
end)

T.test("the level is shared by every eyeball, and starts at 1", function()
	local s = Scene({})
	T.eq(s.me:Shared().level, 1, "first level")
	T.eq(s.npc:State().level, 1, "this eyeball's level")
	local later = Scene({ shared = { level = 3 } })
	T.eq(later.me:GetMaxHealth(), 20000, "a level 3 eyeball")
end)

T.test("a map's eyeball shows the boss bar full at spawn; a spell's does not", function()
	local s = Scene({})
	T.eq(s.me:Called("SetBossHealth")[1][1], 1, "full")
	local spell = Scene({ team = Teams.RED })
	T.eq(Count(spell.me, "SetBossHealth"), 0, "no bar for a spell")
end)

-- CEyeballBossEmerge
T.test("a map's eyeball rises 150 over 3 s from 100 above its spawn, pushing players away", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(0, 150, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(0, 400, 0),
			},
		},
	})
	s.npc:Update(TICK)
	local me = s.me
	T.eq(Played(me), "arrives", "arrives")
	T.eq(Particles(me), "halloween_boss_summon", "summon")
	T.eq(SoundCount(me, "Halloween.HeadlessBossSpawnRumble"), 1, "rumble")
	T.eq(me.origin, V(0, 0, 100 - 150), "sunk")
	Tick(s, 1.5)
	T.near(me.origin.z, 100 - 150 * 0.5, EPSILON, "half risen")
	local pushes = me:Called("ApplyImpulse")
	T.eq(#pushes > 0, true, "pushed")
	for _, push in ipairs(pushes) do T.eq(push[1], s.players[1], "only the near one") end
	T.eq(pushes[1][2], V(0, 200, 200), "up and away")
	me:FinishSequence()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "then idle")
end)

T.test("for 2 s the summon kills players within 100 of it, or 200 once the eyeball has levelled", function()
	local function Killed(level)
		local s = Scene({
			shared = { level = level },
			players = {
				{
					team = Teams.RED,
					origin = V(50, 0, 0),
					maxHealth = 150,
				},
				{
					team = Teams.BLUE,
					origin = V(150, 0, 0),
				},
			},
		})
		s.npc:Update(TICK)
		Tick(s, 2.1)
		local hits = #s.me:Called("DealDamage")
		Tick(s, 1)
		T.eq(#s.me:Called("DealDamage"), hits, "no deaths after 2 s")
		return s.me:Called("DealDamage"), s
	end
	local hits, s = Killed(1)
	T.eq(#hits > 0, true, "level 1 kills")
	for _, hit in ipairs(hits) do
		T.eq(hit[1], s.players[1], "only within 100")
		T.eq(hit[2], 300, "twice max health")
		T.eq(hit[3], Actor.DMG_BLAST, "blast")
	end
	local levelled = {}
	for _, hit in ipairs((Killed(2))) do levelled[hit[1]] = true end
	local count = 0
	for _ in pairs(levelled) do count = count + 1 end
	T.eq(count, 2, "level 2 kills both")
end)

T.test("a spell's eyeball teleports in, and neither pushes nor kills", function()
	local s = Scene({
		team = Teams.RED,
		players = {
			{
				team = Teams.BLUE,
				origin = V(10, 0, 0),
			},
		},
	})
	s.npc:Update(TICK)
	T.eq(Played(s.me), "teleport_in", "teleport in")
	T.eq(Particles(s.me), "eyeboss_tp_normal", "teleport particle")
	T.eq(s.me.origin, V(0, 0, 0), "not sunk")
	Tick(s, 1)
	T.eq(Count(s.me, "ApplyImpulse"), 0, "no push")
	T.eq(Count(s.me, "DealDamage"), 0, "no kill")
end)

-- The mood: CEyeballBoss::IsEnraged, IsGrumpy and Update
T.test("the mood sets the skin and the anger pose: calm, grumpy under 2/3, enraged under 1/3", function()
	local s = Scene({})
	Arrived(s)
	local me = s.me
	local function Skin()
		local skins = me:Called("SetSkin")
		return skins[#skins][1]
	end
	T.eq(Skin(), Eyeball.SKIN_NORMAL, "calm skin")
	T.eq(me.pose.anger, 0, "calm")
	me.health = 5000
	Tick(s, TICK)
	T.eq(Skin(), Eyeball.SKIN_NORMAL, "grumpy skin")
	T.near(me.pose.anger, 0.4, EPSILON, "grumpy")
	me.health = 2000
	Tick(s, TICK)
	T.eq(Skin(), Eyeball.SKIN_RED, "enraged skin")
	T.eq(me.pose.anger, 1, "enraged")
end)

T.test("a crit, or more than 300 damage a second from players, enrages it for 5 s", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(5000, 0, 0),
				visible = false,
			},
		},
	})
	Arrived(s)
	local red = s.players[1]
	local state = s.npc:State()
	local crit = {
		attacker = red,
		amount = 10,
		crit = true,
	}
	T.eq(s.npc:FilterDamage(crit), true, "taken")
	s.npc:Event("OnInjured", crit)
	T.eq(SoundCount(s.me, "Halloween.EyeballBossBecomeEnraged"), 1, "becomes enraged")
	T.eq(Eyeball.IsEnraged(state, s.me), true, "enraged")
	Tick(s, 5.1)
	T.eq(Eyeball.IsEnraged(state, s.me), false, "calm after 5 s")
	local hit = {
		attacker = red,
		amount = 1600,
		crit = false,
	}
	s.npc:FilterDamage(hit)
	Tick(s, TICK)
	s.npc:Event("OnInjured", hit)
	T.eq(Eyeball.IsEnraged(state, s.me), true, "320 damage a second")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossBecomeEnraged"), 2, "enraged again")
end)

T.test("each hit updates the boss bar with the health left", function()
	local s = Scene({ players = { { team = Teams.RED } } })
	s.npc:FilterDamage({
		attacker = s.players[1],
		amount = 2000,
	})
	local bars = s.me:Called("SetBossHealth")
	T.near(bars[#bars][1], 0.75, EPSILON, "three quarters left")
	s.npc:FilterDamage({
		attacker = s.players[1],
		amount = 9000,
	})
	bars = s.me:Called("SetBossHealth")
	T.eq(bars[#bars][1], 0, "none left hides it")
end)

-- Idle, Notice, ApproachTarget, LaunchRockets
T.test("a visible victim is noticed, approached, and shot at: calm, one slow rocket after 0.5 s", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1000, 0, 0),
				index = 2,
			},
		},
	})
	Arrived(s)
	ClearLog(s.me)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Notice", "notices")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossBecomeAlert"), 1, "alert")
	Tick(s, 0.3)
	T.eq(s.npc:Describe(), "BossBehavior/ApproachTarget", "approaches after 0.25 s")
	Tick(s, TICK)
	local approach = s.me:Called("Approach")
	T.eq(approach[#approach][1], V(1000, 0, 36), "towards its centre")
	T.eq(s.me.desiredSpeed, 250, "at 250")
	s.players[1].origin = V(700, 0, 0)
	ClearLog(s.me)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/LaunchRockets", "within 750")
	T.eq(Played(s.me), "firing1", "calm firing")
	Tick(s, 0.4)
	T.eq(#Rockets(s.me), 0, "not before 0.5 s")
	Tick(s, 0.2)
	local rockets = Rockets(s.me)
	T.eq(#rockets, 1, "one rocket")
	local config = rockets[1][2]
	T.near(config.velocity:Length(), 330, EPSILON, "a third of full speed")
	T.eq(config.damage, 50, "damage")
	T.eq(config.crit, true, "crit")
	T.eq(config.team, Teams.HALLOWEEN, "its team")
	T.eq(config.attacker, s.me, "credited to the eyeball")
	T.eq(config.launcher, s.me, "launched by it")
	T.eq(config.model, Eyeball.ROCKET_MODEL, "eyeball projectile")
	T.eq(rockets[1][3], s.me:WorldSpaceCenter(), "from its centre")
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "done, back to idle")
end)

T.test("grumpy it fires 3 slow rockets 0.3 s apart after 0.25 s, circling by the victim's index", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(500, 0, 0),
				index = 3,
			},
		},
	})
	Arrived(s)
	s.me.health = 5000
	Tick(s, 0.5)
	T.eq(s.npc:Describe(), "BossBehavior/LaunchRockets", "attacking")
	T.eq(Played(s.me):match("firing2") ~= nil, true, "grumpy firing")
	local started = s.me:Now()
	Tick(s, TICK)
	local circles = s.me:Called("Approach")
	T.eq(circles[#circles][1], s.me:WorldSpaceCenter() + V(0, -100, 0), "odd index: to its right")
	Tick(s, 1.2)
	local rockets = Rockets(s.me)
	T.eq(#rockets, 3, "three rockets")
	local first = rockets[1][4] - started
	T.eq(first > 0.25 - EPSILON and first <= 0.25 + TICK + EPSILON, true, "the first after 0.25 s")
	for i = 2, 3 do
		local gap = rockets[i][4] - rockets[i - 1][4]
		T.eq(gap > 0.3 - EPSILON and gap <= 0.3 + TICK + EPSILON, true, "0.3 s apart")
		T.near(rockets[i][2].velocity:Length(), 330, EPSILON, "slow")
	end
end)

T.test("enraged it fires 3 fast rockets from 1100 away, leading a moving target", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1100, 0, 0),
				velocity = V(0, 100, 0),
				index = 2,
			},
		},
	})
	Arrived(s)
	s.me.health = 2000
	ClearLog(s.me)
	Tick(s, 0.5)
	T.eq(s.npc:Describe(), "BossBehavior/LaunchRockets", "twice the range when enraged")
	T.eq(Played(s.me), "firing3", "enraged firing")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossRage") >= 1, true, "rage")
	Tick(s, 0.3)
	local rocket = Rockets(s.me)[1][2]
	T.near(rocket.velocity:Length(), 1100, EPSILON, "full speed")
	-- The lead: the range to the target over the rocket's speed, times the
	-- target's velocity.
	local range = (V(1100, 0, 0) - s.me.origin):Length()
	local aim = V(1100, range / 1100 * 100, 0) - s.me:WorldSpaceCenter()
	T.near(rocket.velocity:GetNormalized():Dot(aim:GetNormalized()), 1, EPSILON, "aimed ahead of the target")
end)

T.test("a lead that would hit a wall far from the target is dropped", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(1100, 0, 0),
				velocity = V(0, 100, 0),
			},
		},
	})
	Arrived(s)
	s.me.health = 2000
	s.me.traceHit = V(400, 0, 0)
	Tick(s, 0.8)
	local rocket = Rockets(s.me)[1][2]
	local aim = V(1100, 0, 0) - s.me:WorldSpaceCenter()
	T.near(rocket.velocity:GetNormalized():Dot(aim:GetNormalized()), 1, EPSILON, "straight at the target")
end)

T.test("approach gives up after 5 s, and lingers without sight while it keeps its victim", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(3000, 0, 0),
			},
		},
	})
	Arrived(s)
	Tick(s, 0.5)
	T.eq(s.npc:Describe(), "BossBehavior/ApproachTarget", "approaching")
	s.players[1].visible = false
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/ApproachTarget", "lingers out of sight")
	s.players[1].visible = true
	Tick(s, 4.5)
	T.eq(s.npc:Describe(), "BossBehavior/ApproachTarget", "still approaching")
	Tick(s, 0.4)
	T.eq(s.npc:Describe() ~= "BossBehavior/ApproachTarget", true, "gave up after 5 s")
end)

T.test("out of sight past the first half second, the victim is dropped", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(3000, 0, 0),
			},
		},
	})
	Arrived(s)
	Tick(s, 1)
	s.players[1].visible = false
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "dropped")
end)

-- CEyeballBoss::FindClosestVisibleVictim
T.test("victims: the nearest visible player not hidden, and skeletons of other teams", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(300, 0, 0),
				conds = { Players.COND.STEALTHED },
			},
			{
				team = Teams.BLUE,
				origin = V(0, 400, 0),
				visible = false,
			},
			{
				team = Teams.BLUE,
				origin = V(0, -900, 0),
			},
		},
	})
	local state = s.npc:State()
	T.eq(Eyeball.FindClosestVisibleVictim(state, s.me), s.players[3], "the visible, unhidden one")
	s.world:AddNPC("zombie", FakeCombatant.Target({
		team = Teams.HALLOWEEN,
		origin = V(100, 0, 0),
	}))
	T.eq(Eyeball.FindClosestVisibleVictim(state, s.me), s.players[3], "not a Halloween skeleton")
	local red = s.world:AddNPC("zombie", FakeCombatant.Target({
		team = Teams.RED,
		origin = V(200, 0, 0),
	}))
	T.eq(Eyeball.FindClosestVisibleVictim(state, s.me), red, "a RED skeleton")
end)

T.test("victims: AI war soldiers count as their team's players", function()
	local s = Scene({ players = { { team = Teams.BLUE, origin = V(0, -900, 0) } } })
	local soldier = s.world:AddMember({ team = Teams.RED, origin = V(0, 300, 0) })
	T.eq(Eyeball.FindClosestVisibleVictim(s.npc:State(), s.me), soldier, "the nearer soldier")
end)

T.test("a spell's eyeball hunts only the enemy team, and other teams' bosses", function()
	local s = Scene({
		team = Teams.RED,
		players = {
			{
				team = Teams.RED,
				origin = V(100, 0, 0),
			},
			{
				team = Teams.BLUE,
				origin = V(900, 0, 0),
			},
		},
	})
	local state = s.npc:State()
	T.eq(Eyeball.FindClosestVisibleVictim(state, s.me), s.players[2], "BLU")
	s.world:AddNPC(HalloweenBoss.KIND, s.me)
	local horsemann = s.world:AddNPC(HalloweenBoss.KIND, FakeCombatant.Target({
		team = Teams.HALLOWEEN,
		origin = V(500, 0, 0),
	}))
	T.eq(Eyeball.FindClosestVisibleVictim(state, s.me), horsemann, "the Horsemann")
	local map = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(900, 0, 0),
			},
		},
	})
	map.world:AddNPC(HalloweenBoss.KIND, horsemann)
	T.eq(Eyeball.FindClosestVisibleVictim(map.npc:State(), map.me), map.players[1], "a map's eyeball ignores bosses")
end)

-- Idle's timers
T.test("idle it talks every 3 to 5 s, looks around, and laughs after someone dies", function()
	local s = Scene({})
	Arrived(s)
	Tick(s, TICK)
	T.eq(Played(s.me):match("lookaround1") ~= nil, true, "calm look around")
	ClearLog(s.me)
	Tick(s, 4.1)
	T.eq(SoundCount(s.me, "Halloween.EyeballBossIdle"), 1, "talks at 4 s")
	T.eq(Count(s.me, "AimHeadTowards") > 0, true, "looks around")
	s.npc:Event("OnOtherKilled", "someone", {})
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Emote", "laughs")
	T.eq(Played(s.me):match("laugh") ~= nil, true, "laugh sequence")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossLaugh"), 1, "laugh sound")
	s.me:FinishSequence()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "back to idle")
end)

-- CEyeballBossTeleport
T.test("on the move timer, low enough, it sinks and teleports to a spawn_boss_alt, leaving a vortex", function()
	local s = Scene({ spots = { V(1000, 0, 0) } })
	Arrived(s, V(0, 0, 400))
	Tick(s, 12.6)
	T.eq(s.me.altitude, 0, "sinks")
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "too high to teleport")
	s.me.origin = V(0, 0, 100)
	ClearLog(s.me)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Teleport", "teleporting")
	T.eq(Played(s.me), "teleport_out", "out")
	s.me:FinishSequence()
	Tick(s, TICK)
	local vortex = s.me:Called("SpawnEntity")[1]
	T.eq(vortex[1], "teleport_vortex", "a vortex")
	T.eq(vortex[2].death, false, "a purgatory vortex")
	T.eq(vortex[3], V(0, 0, 100), "where it was")
	T.eq(Particles(s.me), "eyeboss_tp_normal", "particle")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossTeleport"), 1, "sound")
	T.eq(s.me.hidden, true, "hidden")
	T.eq(s.me.origin, V(1000, 0, 75), "75 above the spot")
	Tick(s, TICK)
	T.eq(s.me.hidden, false, "shown")
	T.eq(Played(s.me), "teleport_out,teleport_in", "in")
	s.me:FinishSequence()
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "idle again")
	Tick(s, TICK)
	T.eq(s.me.altitude, Eyeball.HOVER.hoverHeight, "hovers again")
end)

T.test("with no nav area or ground below it does not teleport", function()
	local s = Scene({ spots = { V(1000, 0, 0) } })
	Arrived(s, V(0, 0, 100))
	s.me.navNear = false
	Tick(s, 13)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "stays")
	s.me.navNear = true
	s.me.ground = nil
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "no ground either")
end)

-- CEyeballBossIdle's warnings and CEyeballBossEscape
T.test("it warns at 60, 30 and 10 s left, and escapes at the next move once its life is over", function()
	local s = Scene({})
	Arrived(s, V(0, 0, 100))
	s.me.navNear = false
	Tick(s, 61)
	local said = s.me:Called("Announce")
	T.eq(#said, 1, "60 s warning")
	T.eq(said[1][1], "MONOCULUS! is leaving in 60 seconds...", "60 s text")
	Tick(s, 30)
	T.eq(s.me:Called("Announce")[2][1], "MONOCULUS! is leaving in 30 seconds...", "30 s")
	Tick(s, 20)
	T.eq(s.me:Called("Announce")[3][1], "MONOCULUS! is leaving in 10 seconds!", "10 s")
	Tick(s, 10)
	T.eq(#s.me:Called("Announce"), 3, "three warnings")
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "stays while it cannot move")
	s.me.navNear = true
	ClearLog(s.me)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "BossBehavior/Escape", "escaping")
	T.eq(Played(s.me), "escape", "escape")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossLaugh"), 1, "laughs")
	s.me.shared.level = 3
	s.me:FinishSequence()
	Tick(s, TICK)
	T.eq(Particles(s.me), "eyeboss_tp_escape", "escape particle")
	T.eq(s.me:Called("SetBossHealth")[1][1], 0, "bar hidden")
	T.eq(s.me.removed, true, "gone")
	T.eq(s.me.shared.level, 1, "the level resets")
end)

T.test("a levelled eyeball's warnings name its level", function()
	local s = Scene({ shared = { level = 2 } })
	Arrived(s, V(0, 0, 100))
	s.me.navNear = false
	Tick(s, 61)
	T.eq(s.me:Called("Announce")[1][1], "MONOCULUS! (LEVEL 2) is leaving in 60 seconds...", "levelled")
end)

-- CEyeballBossDead
T.test("killed it falls, then pops: jarates players within 750, leaves a loot vortex and levels up", function()
	local s = Scene({
		players = {
			{
				team = Teams.RED,
				origin = V(700, 0, 0),
				visible = false,
			},
			{
				team = Teams.BLUE,
				origin = V(0, 600, 0),
				inRespawnRoom = true,
			},
			{
				team = Teams.BLUE,
				origin = V(0, -800, 0),
			},
		},
	})
	Arrived(s, V(0, 0, 400))
	s.me.alive = false
	s.npc:Event("OnKilled", {
		attacker = s.players[2],
		amount = 100,
	})
	ClearLog(s.me)
	Tick(s, TICK)
	T.eq(s.npc:Describe(), "Dead", "dead")
	T.eq(Played(s.me), "death", "death")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossStunned"), 1, "stunned sound")
	Tick(s, 1)
	T.eq(s.me.removed, false, "still falling")
	s.me.origin = V(0, 0, 50)
	Tick(s, TICK)
	T.eq(Particles(s.me), "eyeboss_death", "death particle")
	T.eq(SoundCount(s.me, "Cart.Explode"), 1, "boom")
	T.eq(SoundCount(s.me, "Halloween.EyeballBossDie"), 1, "die")
	local shake = s.me:Called("ScreenShake")[1]
	T.eq(shake[2], 25, "amplitude")
	T.eq(shake[4], 5, "duration")
	T.eq(s.me.removed, true, "removed")
	T.eq(s.me.shared.level, 2, "next time tougher")
	local jarated = {}
	for _, args in ipairs(s.me:Called("AddCond")) do
		T.eq(args[2], Players.COND.URINE, "jarate")
		T.eq(args[3], 10, "10 s")
		jarated[args[1]] = true
	end
	T.eq(jarated[s.players[2]], true, "the one in sight within 750")
	T.eq(jarated[s.players[1]], nil, "not out of sight")
	T.eq(jarated[s.players[3]], nil, "not beyond 750")
	local vortex = s.me:Called("SpawnEntity")[1]
	T.eq(vortex[1], "teleport_vortex", "vortex")
	T.eq(vortex[2].death, true, "a loot vortex")
	T.eq(s.npc:IsEmpty(), true, "over")
end)

T.test("a falling eyeball gives up after 10 s and pops anyway", function()
	local s = Scene({})
	Arrived(s, V(0, 0, 400))
	s.me.alive = false
	s.me.ground = nil
	s.npc:Event("OnKilled", { amount = 1 })
	Tick(s, 9.9)
	T.eq(s.me.removed, false, "still falling")
	Tick(s, 0.3)
	T.eq(s.me.removed, true, "popped")
end)

-- A spell's eyeball (the MONOCULUS spell)
T.test("a spell's eyeball is immune, always enraged, and escapes after 8 s", function()
	local s = Scene({ team = Teams.BLUE })
	local red = s.world:AddPlayer({
		team = Teams.RED,
		origin = V(0, 0, 5000),
		visible = false,
	})
	T.eq(s.npc:FilterDamage({
		attacker = red,
		amount = 100,
	}), false, "immune")
	T.eq(Eyeball.IsEnraged(s.npc:State(), s.me), true, "enraged")
	s.npc:Update(TICK)
	s.me:FinishSequence()
	Tick(s, TICK)
	Tick(s, TICK)
	local skins = s.me:Called("SetSkin")
	T.eq(skins[#skins][1], Eyeball.SKIN_TEAM_BLUE, "its team's skin")
	Tick(s, 7.5)
	T.eq(s.npc:Describe(), "BossBehavior/Idle", "idle")
	Tick(s, 0.6)
	T.eq(s.npc:Describe(), "BossBehavior/Escape", "escapes at 8 s")
	s.me:FinishSequence()
	Tick(s, TICK)
	T.eq(SoundCount(s.me, "Halloween.spell_spawn_boss_disappear"), 1, "disappears")
	T.eq(s.me.removed, true, "gone")
end)

T.test("a spell's rockets are not crits and it does not circle", function()
	local s = Scene({
		team = Teams.RED,
		players = {
			{
				team = Teams.BLUE,
				origin = V(500, 0, 0),
			},
		},
	})
	s.npc:Update(TICK)
	s.me:FinishSequence()
	Tick(s, 1)
	local rocket = Rockets(s.me)[1][2]
	T.eq(rocket.crit, false, "no crit")
	T.eq(rocket.team, Teams.RED, "its team")
	T.eq(Count(s.me, "Approach"), 0, "no circling")
end)

T.test("an owned eyeball credits its rockets to its owner", function()
	local s = Scene({
		team = Teams.RED,
		owner = "caster",
		players = {
			{
				team = Teams.BLUE,
				origin = V(500, 0, 0),
			},
		},
	})
	s.npc:Update(TICK)
	s.me:FinishSequence()
	Tick(s, 1)
	T.eq(Rockets(s.me)[1][2].attacker, "caster", "the caster")
end)

-------------------------------------------------------------------------------
-- The teleport vortex (CTeleportVortex, SendPlayerToTheUnderworld)

local function VortexPort(world)
	local port = FakeCombatant.Actor({})
	local asker = FakeCombatant.Combatant({ world = world })
	function port:CollectPlayers(team) return asker:CollectPlayers(team) end
	function port:TeamOf(p) return p.team end
	function port:SpawnPoints(name) return world.spawnPoints[name] or {} end
	function port:IsLookingTowards(p, v, tolerance) return p.looking == true end
	function port:IsLineOfSightClear(p, v) return p.visible end
	function port:Teleport(p, v)
		p.origin = v
		self:Record("Teleport", p, v)
	end
	return port
end

T.test("a vortex lives 5 s", function()
	local port = VortexPort(FakeCombatant.World())
	local vortex = Eyeball.Vortex.New(false, port)
	vortex:Think()
	T.eq(port.removed, false, "alive")
	port.clock:Advance(5.1)
	vortex:Think()
	T.eq(port.removed, true, "gone")
end)

T.test("it pulls airborne players within 500 who look at it and see it", function()
	local world = FakeCombatant.World()
	local pulled = world:AddPlayer({
		team = Teams.RED,
		origin = V(300, 0, 0),
		onGround = false,
		looking = true,
	})
	world:AddPlayer({
		team = Teams.RED,
		origin = V(300, 0, 0),
		looking = true,
	})
	world:AddPlayer({
		team = Teams.RED,
		origin = V(600, 0, 0),
		onGround = false,
		looking = true,
	})
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(0, 300, 0),
		onGround = false,
		looking = false,
	})
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(0, -300, 0),
		onGround = false,
		looking = true,
		visible = false,
	})
	local port = VortexPort(world)
	Eyeball.Vortex.New(false, port):Think()
	local pulls = port:Called("ApplyImpulse")
	T.eq(#pulls, 1, "one pulled")
	T.eq(pulls[1][1], pulled, "the airborne one looking")
	T.eq(pulls[1][2], V(-30, 0, 0), "30 towards the vortex")
end)

T.test("touching a purgatory vortex sends a player to an open spawn_purgatory spot", function()
	local world = FakeCombatant.World()
	world:SetSpawnPoints(Eyeball.VORTEX_PURGATORY, { V(100, 0, 0), V(200, 0, 0) })
	local red = world:AddPlayer({ team = Teams.RED })
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(110, 0, 0),
	})
	world:AddPlayer({
		team = Teams.RED,
		origin = V(200, 0, 0),
	})
	local port = VortexPort(world)
	Eyeball.Vortex.New(false, port):Touch(red)
	T.eq(red.origin, V(200, 0, 0), "the spot no enemy stands on")
	T.eq(Count(port, "DealDamage"), 0, "nobody telefragged")
end)

T.test("a loot vortex sends a player to spawn_loot, telefragging enemies when every spot is taken", function()
	local world = FakeCombatant.World()
	world:SetSpawnPoints(Eyeball.VORTEX_LOOT, { V(100, 0, 0) })
	local red = world:AddPlayer({ team = Teams.RED })
	local camper = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(110, 0, 0),
	})
	local port = VortexPort(world)
	Eyeball.Vortex.New(true, port):Touch(red)
	T.eq(red.origin, V(100, 0, 0), "the only spot")
	local frag = port:Called("DealDamage")[1]
	T.eq(frag[1], camper, "the camper")
	T.eq(frag[2], 1000, "telefrag")
	T.eq(frag[3], Actor.DMG_CRUSH, "crush")
	T.eq(frag[4], red, "by the teleporter")
end)

T.test("with no spots, nobody moves", function()
	local world = FakeCombatant.World()
	local red = world:AddPlayer({ team = Teams.RED })
	local port = VortexPort(world)
	Eyeball.Vortex.New(true, port):Touch(red)
	T.eq(red.origin, V(0, 0, 0), "stays")
end)

T.test("a loot vortex's book rings in, then out", function()
	local world = FakeCombatant.World()
	local port = VortexPort(world)
	local vortex = Eyeball.Vortex.New(true, port)
	vortex:Think()
	T.eq(port:Called("EmitSound")[1][1], "Halloween.TeleportVortex.BookSpawn", "in")
	port.clock:Advance(4.6)
	vortex:Think()
	T.eq(port:Called("EmitSound")[2][1], "Halloween.TeleportVortex.BookExit", "out")
	vortex:Think()
	T.eq(#port:Called("EmitSound"), 2, "once each")
	local plain = VortexPort(world)
	Eyeball.Vortex.New(false, plain):Think()
	T.eq(#plain:Called("EmitSound"), 0, "no book in a purgatory vortex")
end)

T.test("the fake vortex port implements every vortex method", function()
	local port = VortexPort(FakeCombatant.World())
	for _, name in ipairs(Eyeball.VORTEX_METHODS) do
		T.eq(type(port[name]), "function", "fake " .. name)
	end
end)

-- The bindings (read as text) define their ports as function ENT:<Name>(.
local function Defines(file, name)
	local f = assert(io.open("addon/gamemodes/sandcastle/entities/entities/" .. file, "r"))
	local text = f:read("*a")
	f:close()
	return text:find("function ENT:" .. name .. "(", 1, true) ~= nil
end

T.test("the eyeball_boss binding defines the eyeball's port", function()
	for _, name in ipairs(Eyeball.METHODS) do
		T.eq(Defines("eyeball_boss.lua", name), true, "eyeball_boss " .. name)
		T.eq(Actor.ENGINE[name], nil, "not an engine method: " .. name)
	end
end)

-- The engine's Remove, EmitSound and WorldSpaceCenter already mean what the
-- vortex port says, so the binding must not redefine them.
T.test("the teleport_vortex binding defines the vortex port the engine does not", function()
	for _, name in ipairs(Eyeball.VORTEX_METHODS) do
		T.eq(Defines("teleport_vortex.lua", name), Actor.ENGINE[name] == nil, "teleport_vortex " .. name)
	end
end)

T.finish()
