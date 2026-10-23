-- The twelve TF2 spell strategies on fake_caster: each self spell's effects,
-- and each thrown spell's launch and impact, with TF2's numbers
-- (sdk/shared/tf/halloween/tf_weapon_spellbook.cpp).
local T = dofile("tests/harness.lua")
local Fake = dofile("tests/fake_caster.lua")
local Spells = T.require("features.spells.model")
local SpellSet = T.require("features.spells.halloween")
local CasterPort = T.require("features.spells.caster")
local Teams = T.require("games.gameplay.teams")
local Players = T.require("games.gameplay.players")
local Zombie = T.require("foundation.npc.zombie")
local HalloweenBoss = T.require("foundation.npc.halloween_boss")
local EyeballBoss = T.require("foundation.npc.eyeball_boss")

local Fireball = T.require("features.spells.fireball")
local Bats = T.require("features.spells.bats")
local Overheal = T.require("features.spells.overheal")
local Mirv = T.require("features.spells.mirv")
local Blastjump = T.require("features.spells.blastjump")
local Stealth = T.require("features.spells.stealth")
local Teleport = T.require("features.spells.teleport")
local Lightning = T.require("features.spells.lightning")
local Athletic = T.require("features.spells.athletic")
local Meteor = T.require("features.spells.meteor")
local SpawnBoss = T.require("features.spells.spawn_boss")
local Horde = T.require("features.spells.skeleton_horde")

local V = Fake.Vector
local C = Players.COND
local RED, BLUE = Teams.RED, Teams.BLUE
local EPSILON = 1e-6

local function Near(actual, expected, what)
	T.near(actual.x, expected.x, 1e-3, what .. ".x")
	T.near(actual.y, expected.y, 1e-3, what .. ".y")
	T.near(actual.z, expected.z, 1e-3, what .. ".z")
end

local function Owner(t)
	t = t or {}
	return Fake.Target({
		name = "owner",
		team = t.team or RED,
		origin = t.origin or V(0, 0, 0),
		alive = t.alive,
		velocity = t.velocity,
	})
end

-- The owner stands at the origin looking along +x; every spread draw lands
-- mid-range (0).
local function NewCaster(t)
	t = t or {}
	t.owner = t.owner or Owner()
	return Fake.Caster(t)
end

local function Impact(t)
	return {
		position = t.position or V(0, 0, 1),
		hitPosition = t.hitPosition or V(0, 0, 0),
		normal = t.normal or V(0, 0, 1),
		team = t.team or RED,
		projectile = t.projectile or { name = "projectile" },
	}
end

local function Shot(strategy, class, config, now)
	return Spells.Shot.New(strategy, class, config or {}, now or 0)
end

local function Names(entries)
	local names = {}
	for i, entry in ipairs(entries) do names[i] = entry.name end
	return table.concat(names, ",")
end

local function For(entries, target)
	local found = {}
	for _, entry in ipairs(entries) do
		if entry.target == target then found[#found + 1] = entry end
	end
	return found
end

local function CondOf(caster, target, cond)
	for _, entry in ipairs(For(caster:Calls("AddCond"), target)) do
		if entry.cond == cond then return entry.duration end
	end
	return nil
end

local EYE = V(0, 0, 64)
local HAND = V(3, -7, 55) -- eye + up * -9 + right * 7 + forward * 3
local JAR_VELOCITY = V(1000, 0, 200)

T.test("fake_caster implements the whole caster port", function()
	local caster = NewCaster()
	for _, name in ipairs(CasterPort.METHODS) do
		T.eq(type(caster[name]), "function", name)
	end
end)

-------------------------------------------------------------------------------
-- Throwing

T.test("a fireball flies from the hand along the eyes at the toss's speed", function()
	local caster = NewCaster()
	T.eq(Fireball.Cast(caster), true, "thrown")
	local wheel = caster:Calls("Particle")[1]
	T.eq(wheel.name, "spell_cast_wheel_red", "RED's cast wheel")
	Near(wheel.pos, V(0, 0, SpellSet.CAST_WHEEL_HEIGHT), "the wheel 100 above")
	local trace = caster:Calls("TraceHull")[1]
	Near(trace.from, EYE, "the hull starts at the eyes")
	Near(trace.to, HAND, "and ends at the hand")
	Near(trace.maxs, V(8, 8, 8), "an 8-unit hull")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_fireball_cast", "cast sound")
	local launch = caster:Calls("LaunchProjectile")[1]
	T.eq(launch.class, "tf_projectile_spellfireball", "class")
	T.eq(launch.config.spell, SpellSet.SPELL_FIREBALL, "spell index")
	T.eq(launch.config.team, RED, "team")
	Near(launch.config.position, HAND, "from the hand")
	Near(launch.config.velocity, V(JAR_VELOCITY:Length(), 0, 0), "straight along the eyes")
end)

T.test("the toss's spread: 200 up, then +-10 right and up", function()
	local caster = NewCaster({ random = Fake.Random({ 1, 0 }) })
	Bats.Cast(caster)
	local launch = caster:Calls("LaunchProjectile")[1]
	Near(launch.config.velocity, V(1000, -10, 190), "right +10 (right is -y), up -10")
	T.eq(launch.class, "tf_projectile_spellbats", "class")
	T.eq(launch.config.fuse, SpellSet.JAR_FUSE, "a jar's fuse")
end)

T.test("a jar flies with the toss's velocity; lightning at 0.4 of the speed with a 5 s fuse", function()
	local caster = NewCaster()
	Mirv.Cast(caster)
	Near(caster:Calls("LaunchProjectile")[1].config.velocity, JAR_VELOCITY, "mirv")
	caster = NewCaster()
	Lightning.Cast(caster)
	local launch = caster:Calls("LaunchProjectile")[1]
	T.eq(launch.class, "tf_projectile_lightningorb", "class")
	Near(launch.config.velocity, V(JAR_VELOCITY:Length() * 0.4, 0, 0), "slow and straight")
	T.eq(launch.config.fuse, Lightning.LIFETIME, "5 s")
end)

T.test("no room at the hand: nothing is thrown and no sound plays", function()
	local caster = NewCaster({
		hull = function(from)
			return {
				startSolid = true,
				endPos = from,
			}
		end,
	})
	T.eq(Teleport.Cast(caster), false, "not thrown")
	T.eq(#caster:Calls("LaunchProjectile"), 0, "no projectile")
	T.eq(#caster:Calls("EmitSound"), 0, "no sound")
end)

T.test("the toss launches from where the hull stopped", function()
	local caster = NewCaster({
		hull = function(from, to)
			return {
				startSolid = false,
				endPos = V(1, 0, 60),
			}
		end,
	})
	Horde.Cast(caster)
	Near(caster:Calls("LaunchProjectile")[1].config.position, V(1, 0, 60), "the hull's end")
end)

-------------------------------------------------------------------------------
-- Self spells

T.test("overheal: teammates in sight within 250 heal and turn invulnerable, enemies are pushed", function()
	local mate = Fake.Target({
		name = "mate",
		team = RED,
		origin = V(100, 0, 0),
		health = 100,
	})
	local far = Fake.Target({
		name = "far",
		team = RED,
		origin = V(300, 0, 0),
	})
	local walled = Fake.Target({
		name = "walled",
		team = RED,
		origin = V(0, 200, 0),
	})
	local enemy = Fake.Target({
		name = "enemy",
		team = BLUE,
		origin = V(0, -100, 0),
	})
	local npc = Fake.Target({
		name = "npc",
		team = BLUE,
		origin = V(-50, 0, 0),
		player = false,
	})
	local caster = NewCaster({
		targets = { mate, far, walled, enemy, npc },
		wall = function(from, to) return to.y == 200 end,
	})
	T.eq(Overheal.Cast(caster), true, "cast")
	T.eq(caster:Calls("Particle")[1].name, "spell_cast_wheel_red", "cast wheel")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_overheal", "sound")
	T.eq(caster:Calls("AttachParticle")[1].name, "spell_overheal_red", "the overheal ring")
	T.eq(#For(caster:Calls("Heal"), mate), 1, "mate healed")
	T.eq(For(caster:Calls("Heal"), mate)[1].amount, 50, "by 50")
	T.eq(CondOf(caster, mate, C.INVULNERABLE_USER_BUFF), 1, "1 s invulnerable")
	T.eq(CondOf(caster, mate, C.HALLOWEEN_QUICK_HEAL), 3, "3 s quick heal")
	T.eq(#For(caster:Calls("Heal"), caster.owner), 1, "the caster too")
	T.eq(#For(caster:Calls("Heal"), far), 0, "out of range")
	T.eq(#For(caster:Calls("Heal"), walled), 0, "behind a wall")
	local push = For(caster:Calls("Push"), enemy)[1]
	Near(push.impulse, V(0, -100, 36):GetNormalized() * 300, "enemy pushed 300 away from the caster")
	T.eq(#For(caster:Calls("Push"), npc), 0, "NPCs untouched")
end)

T.test("blast jump: no falling, 800 up, 25 health; enemies within 100 flung, then a blast of 20", function()
	local owner = Owner({ velocity = V(50, 0, -300) })
	local enemy = Fake.Target({
		name = "enemy",
		team = BLUE,
		origin = V(80, 0, 0),
	})
	local mate = Fake.Target({
		name = "mate",
		team = RED,
		origin = V(-80, 0, 0),
	})
	local caster = NewCaster({
		owner = owner,
		targets = { enemy, mate },
	})
	Blastjump.Cast(caster)
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_blastjump", "sound")
	Near(caster:Calls("SetVelocity")[1].velocity, V(50, 0, 0), "the fall stopped")
	Near(For(caster:Calls("Push"), owner)[1].impulse, V(0, 0, 800), "800 up")
	Near(owner.velocity, V(50, 0, 800), "and keeps its run")
	T.eq(For(caster:Calls("Heal"), owner)[1].amount, 25, "25 health")
	local fling = For(caster:Calls("Push"), enemy)[1]
	T.near(fling.impulse:Length(), 800, EPSILON, "enemy flung 800")
	T.eq(#For(caster:Calls("Push"), mate), 0, "teammates stay")
	local blast = caster:Calls("Explode")[1].config
	T.eq(blast.radius, 100, "radius")
	T.eq(blast.damage, 20, "damage")
	T.eq(blast.attacker, owner, "the caster's")
	T.eq(blast.inflictor, owner, "which spares the caster")
	T.eq(blast.attackerTeam, RED, "RED's")
	local names = Names(caster:Calls("Particle"))
	T.eq(names, "spell_cast_wheel_red,bombinomicon_burningdebris,heavy_ring_of_fire", "effects")
end)

T.test("athletic: 100 health, tiny and fast for 20 s", function()
	local caster = NewCaster()
	Athletic.Cast(caster)
	local owner = caster.owner
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_athletic", "sound")
	T.eq(For(caster:Calls("Heal"), owner)[1].amount, 100, "100 health")
	T.eq(CondOf(caster, owner, C.HALLOWEEN_TINY), 20, "tiny")
	T.eq(CondOf(caster, owner, C.HALLOWEEN_SPEED_BOOST), 20, "halloween speed boost")
	T.eq(CondOf(caster, owner, C.SPEED_BOOST), 20, "which is a speed boost")
end)

T.test("stealth: 40 health and 8 s unseen, with no cast wheel", function()
	local caster = NewCaster()
	Stealth.Cast(caster)
	local owner = caster.owner
	T.eq(#caster:Calls("Particle"), 0, "no cast wheel")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_stealth", "sound")
	T.eq(For(caster:Calls("Heal"), owner)[1].amount, 40, "40 health")
	T.eq(CondOf(caster, owner, C.STEALTHED_USER_BUFF), 8, "stealthed")
end)

-------------------------------------------------------------------------------
-- Impacts

local function Field()
	local enemy = Fake.Target({
		name = "enemy",
		team = BLUE,
		origin = V(100, 0, 0),
	})
	local mate = Fake.Target({
		name = "mate",
		team = RED,
		origin = V(-100, 0, 0),
	})
	local shielded = Fake.Target({
		name = "shielded",
		team = BLUE,
		origin = V(0, 100, 0),
		invulnerable = true,
	})
	local npc = Fake.Target({
		name = "npc",
		team = BLUE,
		origin = V(0, -100, 0),
		player = false,
	})
	local far = Fake.Target({
		name = "far",
		team = BLUE,
		origin = V(240, 0, 0),
	})
	return {
		enemy = enemy,
		mate = mate,
		shielded = shielded,
		npc = npc,
		far = far,
		list = { enemy, mate, shielded, npc, far },
	}
end

T.test("fireball: enemy players within 200 burn 5 s and take 100 burn damage, then a blast of 10", function()
	local field = Field()
	local caster = NewCaster({
		owner = Owner({ origin = V(-1000, 0, 0) }),
		targets = field.list,
	})
	local impact = Impact({ position = V(0, 0, 0) })
	Shot(Fireball, Fireball.PROJECTILE):Impact(caster, impact)
	T.eq(Names(caster:Calls("Particle")), "bombinomicon_burningdebris", "particle")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_fireball_impact", "sound")
	T.eq(CondOf(caster, field.enemy, C.BURNING), 5, "enemy burns")
	local hit = For(caster:Calls("Damage"), field.enemy)[1]
	T.eq(hit.amount, 100, "100")
	T.eq(hit.dmgType, CasterPort.DMG_BURN, "burn")
	T.eq(hit.inflictor, impact.projectile, "by the fireball")
	T.eq(#For(caster:Calls("Damage"), field.mate), 0, "teammates spared")
	T.eq(#For(caster:Calls("Damage"), field.shielded), 0, "the invulnerable spared")
	T.eq(#For(caster:Calls("Damage"), field.npc), 0, "NPCs only take the blast")
	T.eq(#For(caster:Calls("Damage"), field.far), 0, "out of range")
	local blast = caster:Calls("Explode")[1].config
	T.eq(blast.radius, 200, "radius")
	T.eq(blast.damage, 10, "damage")
	T.eq(blast.attacker, caster.owner, "credited to the caster")
end)

T.test("bats: enemies within 250 are stunned, flung, bleed and take 40; NPCs are flung harder", function()
	local field = Field()
	local caster = NewCaster({
		owner = Owner({ origin = V(-1000, 0, 0) }),
		targets = field.list,
	})
	Shot(Bats, Bats.PROJECTILE):Impact(caster, Impact({ position = V(0, 0, 0) }))
	T.eq(Names(caster:Calls("Particle")), "ExplosionCore_MidAir,spell_batball_impact_red", "particles")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_bat_impact", "sound")
	local stun = For(caster:Calls("Stun"), field.enemy)[1]
	T.eq(stun.duration, 0.5, "stunned 0.5 s")
	T.eq(stun.reduction, 0.5, "at half speed")
	local enemyCenter = V(100, 0, 36)
	Near(For(caster:Calls("Push"), field.enemy)[1].impulse, enemyCenter:GetNormalized() * 200 + V(0, 0, 800), "flung")
	T.eq(For(caster:Calls("AttachParticle"), field.enemy)[1].name, "spell_batball_red", "bats on the enemy")
	T.eq(CondOf(caster, field.enemy, C.BLEEDING), 3, "bleeds 3 s")
	T.eq(For(caster:Calls("Damage"), field.enemy)[1].amount, 40, "40")
	local npcCenter = V(0, -100, 36)
	Near(For(caster:Calls("Push"), field.npc)[1].impulse, npcCenter:GetNormalized() * 1000, "NPC flung 1000")
	T.eq(For(caster:Calls("Damage"), field.npc)[1].amount, 40, "NPC takes 40")
	T.eq(#For(caster:Calls("Damage"), field.mate), 0, "teammates spared")
	T.eq(#For(caster:Calls("Damage"), field.shielded), 0, "the invulnerable spared")
	T.eq(#For(caster:Calls("Damage"), field.far), 1, "250 reaches further than 200")
	T.eq(caster:Calls("Explode")[1].config.radius, 250, "blast radius")
end)

T.test("a thrown spell whose thrower cannot use it plays the deny sound", function()
	local caster = NewCaster({ owner = Owner({ alive = false }) })
	Shot(Teleport, Teleport.PROJECTILE):Impact(caster, Impact({}))
	T.eq(Names(caster:Calls("EmitSound")), SpellSet.DENY_SOUND, "deny")
	T.eq(#caster:Calls("Heal"), 0, "no heal")
	T.eq(#caster:Calls("Teleport"), 0, "no teleport")
end)

T.test("mirv: six pumpkin bomblets at the fixed offsets with staggered fuses", function()
	local caster = NewCaster()
	Shot(Mirv, Mirv.PROJECTILE):Impact(caster, Impact({ position = V(10, 20, 1) }))
	local launches = caster:Calls("LaunchProjectile")
	T.eq(#launches, 6, "six")
	local offsets = {
		V(75, 110, 400),
		V(75, -110, 400),
		V(-75, 110, 400),
		V(-75, -110, 400),
		V(135, 0, 400),
		V(-135, 0, 400),
	}
	for i, launch in ipairs(launches) do
		T.eq(launch.class, "tf_projectile_spellpumpkin", "bomblet class")
		T.eq(launch.config.spell, SpellSet.SPELL_MIRV, "still the mirv's")
		Near(launch.config.velocity, offsets[i], "offset " .. i)
		Near(launch.config.position, V(10, 20, 1), "from the impact")
		T.near(launch.config.fuse, 2 + 0.05 * (i - 1), EPSILON, "fuse " .. i)
		T.eq(launch.config.armDelay, Mirv.BOMBLET_ARM_DELAY, "ignores touches for 1 s")
		T.eq(launch.config.team, RED, "team")
	end
	T.eq(caster:Calls("Particle")[1].name, "spell_pumpkin_mirv_goop_red", "goop")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_mirv_explode_primary", "sound")
	T.eq(caster:Calls("Explode")[1].config.radius, 1, "a radius-1 blast")
end)

T.test("a mirv bomblet leaves a spell pumpkin bomb", function()
	local caster = NewCaster({ random = Fake.Random({ 0.25 }) })
	Shot(Mirv, Mirv.BOMBLET):Impact(caster, Impact({
		position = V(5, 5, 5),
		team = BLUE,
	}))
	local pumpkin = caster:Calls("Spawn")[1]
	T.eq(pumpkin.class, "tf_pumpkin_bomb", "a pumpkin")
	Near(pumpkin.pos, V(5, 5, 5), "where it landed")
	T.eq(pumpkin.config.scale, 0.6, "scale")
	T.eq(pumpkin.config.damage, 80, "damage")
	T.eq(pumpkin.config.radius, 200, "radius")
	T.eq(pumpkin.config.team, BLUE, "the bomblet's team")
	T.near(pumpkin.config.lifetime, 40.25, EPSILON, "40 s plus up to 1")
	T.eq(pumpkin.config.isSpell, true, "a spell's")
	T.eq(caster:Calls("Particle")[1].name, "spell_pumpkin_mirv_goop_blue", "goop")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_mirv_explode_secondary", "sound")
	T.eq(#caster:Calls("Explode"), 0, "no blast of its own")
end)

T.test("teleport: the trail keeps the last 5 positions every 0.05 s", function()
	local shot = Shot(Teleport, Teleport.PROJECTILE, {}, 0)
	local caster = NewCaster()
	for step = 1, 8 do
		shot:Tick(caster, {
			position = V(step, 0, 0),
			team = RED,
		}, 0.06 * step - 0.02)
		shot:Tick(caster, {
			position = V(step, 0, 0),
			team = RED,
		}, 0.06 * step)
	end
	local trail = shot.state.trail
	T.eq(#trail, 5, "five kept")
	T.eq(trail[1].x, 4, "oldest")
	T.eq(trail[5].x, 8, "newest")
end)

T.test("teleport: to the newest spot the caster fits, starting 50 off the surface", function()
	local owner = Owner({ origin = V(-500, 0, 0) })
	local caster = NewCaster({
		owner = owner,
		fits = function(pos) return pos.x == 7 end,
	})
	local shot = Shot(Teleport, Teleport.PROJECTILE, {}, 0)
	shot.state.trail = {
		V(6, 0, 0),
		V(7, 0, 0),
		V(8, 0, 0),
	}
	shot:Impact(caster, Impact({
		hitPosition = V(9, 0, 0),
		normal = V(-1, 0, 0),
	}))
	T.eq(For(caster:Calls("Heal"), owner)[1].amount, 30, "30 health")
	local particle = caster:Calls("Particle")[1]
	T.eq(particle.name, "eyeboss_tp_player", "a flash where the caster was")
	Near(particle.pos, V(-500, 0, 0), "at the old spot")
	Near(caster:Calls("Teleport")[1].pos, V(7, 0, 0), "moved to the newest fitting spot")
	T.eq(#caster:Calls("ScreenFade"), 1, "screen flash")
	T.eq(caster:Calls("EmitSound")[1].name, "Building_Teleporter.Ready", "sound")
	T.eq(caster:Calls("Explode")[1].config.radius, 5, "a radius-5 blast")

	local cramped = NewCaster({ fits = function() return false end })
	Shot(Teleport, Teleport.PROJECTILE, {}, 0):Impact(cramped, Impact({}))
	T.eq(#cramped:Calls("Teleport"), 0, "nowhere fits: no teleport")
	T.eq(Names(cramped:Calls("EmitSound")), SpellSet.DENY_SOUND, "deny")
	T.eq(#cramped:Calls("Heal"), 1, "the heal came first")
end)

local function Crowd(n, team, x)
	local list = {}
	for i = 1, n do
		list[i] = Fake.Target({
			name = "t" .. i,
			team = team,
			origin = V(x or 50, i, 0),
		})
	end
	return list
end

T.test("lightning: pulls enemies in every 0.2 s and zaps 2 every 0.25-0.35 s", function()
	local enemies = Crowd(3, BLUE)
	local mate = Fake.Target({
		name = "mate",
		team = RED,
		origin = V(-50, 0, 0),
	})
	local airborne = Fake.Target({
		name = "air",
		team = BLUE,
		origin = V(0, -50, 0),
		onGround = false,
	})
	local targets = { mate, airborne }
	for _, e in ipairs(enemies) do targets[#targets + 1] = e end
	local caster = NewCaster({
		owner = Owner({ origin = V(-1000, 0, 0) }),
		targets = targets,
	})
	local shot = Shot(Lightning, Lightning.PROJECTILE, {}, 0)
	local where = {
		position = V(0, 0, 0),
		team = RED,
		projectile = { name = "orb" },
	}

	shot:Tick(caster, where, 0.1)
	T.eq(#caster.log, 0, "nothing before 0.2 s")
	shot:Tick(caster, where, 0.2)
	local pulls = caster:Calls("SetVelocity")
	T.eq(#pulls, 4, "every enemy in range pulled, not the teammate")
	Near(For(pulls, airborne)[1].velocity, V(0, 100, 50), "twice the gap, 50 up")
	Near(For(pulls, enemies[1])[1].velocity, V(-100, -2, 200), "grounded: 150 more up")

	shot:Tick(caster, where, 0.25)
	local zaps = caster:Calls("Damage")
	T.eq(#zaps, 2, "two zapped")
	T.eq(zaps[1].amount, 20, "20")
	T.eq(zaps[1].dmgType, CasterPort.DMG_BURN, "burn")
	T.eq(zaps[1].inflictor, where.projectile, "by the orb")
	T.eq(#caster:Calls("Tracer"), 2, "a beam each")
	T.eq(caster:Calls("Tracer")[1].name, "spell_lightningball_hit_red", "RED's beam")
	T.eq(Names(caster:Calls("EmitSound")), "TFPlayer.MedicChargedDeath", "a sound when anyone is zapped")

	shot:Tick(caster, where, 0.3)
	T.eq(#caster:Calls("Damage"), 2, "the next zap waits 0.25-0.35 s")
	shot:Tick(caster, where, 0.55)
	T.eq(#caster:Calls("Damage"), 4, "and comes")
end)

T.test("lightning's end: zaps up to 16, of the first 5 found", function()
	local enemies = Crowd(7, BLUE, 10)
	local caster = NewCaster({
		owner = Owner({ origin = V(-1000, 0, 0) }),
		targets = enemies,
	})
	Shot(Lightning, Lightning.PROJECTILE, {}, 0):Impact(caster, Impact({ position = V(0, 0, 0) }))
	T.eq(#caster:Calls("Damage"), 5, "UTIL_EntitiesInSphere keeps 5")
	T.eq(caster:Calls("Particle")[1].name, "drg_cow_explosioncore_charged", "RED's burst")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_lightning_impact", "sound")
end)

T.test("meteor shower: lands a spawner that drops 1-2 meteors every 0.2 s for 4 s", function()
	local caster = NewCaster()
	Shot(Meteor, Meteor.PROJECTILE):Impact(caster, Impact({
		position = V(0, 0, 1),
		normal = V(0, 0, 1),
	}))
	T.eq(caster:Calls("Particle")[1].name, "bomibomicon_ring", "ring")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_meteor_impact", "sound")
	local spawner = caster:Calls("Spawn")[1]
	T.eq(spawner.class, Meteor.SPAWNER, "the spawner")
	T.eq(spawner.config.spell, SpellSet.SPELL_METEOR, "the meteor's")
	Near(spawner.config.normal, V(0, 0, 1), "with the surface's normal")

	local rain = NewCaster({ random = Fake.Random({ 0.99 }) })
	local shot = Shot(Meteor, Meteor.SPAWNER, spawner.config, 10)
	local where = {
		position = V(0, 0, 1),
		team = RED,
	}
	T.eq(shot:Tick(rain, where, 10), nil, "raining")
	local meteors = rain:Calls("LaunchProjectile")
	T.eq(#meteors, 2, "two this time")
	T.eq(meteors[1].class, Meteor.METEOR, "fireballs")
	T.eq(meteors[1].config.spell, SpellSet.SPELL_METEOR, "the meteor's")
	T.eq(meteors[1].config.velocity.z, -700, "falling at 700")
	T.eq(meteors[1].config.velocity.x <= 75, true, "sideways at most 75")
	T.eq(meteors[1].config.position.z >= 1 + 400 and meteors[1].config.position.z <= 1 + 500, true, "400-500 up")
	local dx, dy = meteors[1].config.position.x, meteors[1].config.position.y
	T.eq(math.sqrt(dx * dx + dy * dy) <= 200, true, "within 200")
	shot:Tick(rain, where, 10.1)
	T.eq(#rain:Calls("LaunchProjectile"), 2, "every 0.2 s")
	shot:Tick(rain, where, 10.25)
	T.eq(#rain:Calls("LaunchProjectile"), 4, "the next pair")
	T.eq(shot:Tick(rain, where, 14), Spells.DONE, "over after 4 s")
end)

T.test("meteor shower under a ceiling drops from 45-60 below it", function()
	local caster = NewCaster({ random = Fake.Random({ 0 }) })
	local shot = Shot(Meteor, Meteor.SPAWNER, {
		spell = SpellSet.SPELL_METEOR,
		normal = V(0, 0, -1),
		team = RED,
	}, 0)
	shot:Tick(caster, {
		position = V(0, 0, 500),
		team = RED,
	}, 0)
	local meteor = caster:Calls("LaunchProjectile")[1]
	T.eq(meteor.config.position.z, 500 - 45, "45 below")
end)

T.test("meteor shower: a blocked drop point is pulled back off the surface", function()
	local caster = NewCaster({
		line = function(from, to)
			return {
				hit = true,
				endPos = V(0, 0, 100),
				normal = V(0, 0, -1),
			}
		end,
	})
	local shot = Shot(Meteor, Meteor.SPAWNER, {
		spell = SpellSet.SPELL_METEOR,
		normal = V(0, 0, 1),
		team = RED,
	}, 0)
	shot:Tick(caster, {
		position = V(0, 0, 0),
		team = RED,
	}, 0)
	Near(caster:Calls("LaunchProjectile")[1].config.position, V(0, 0, 99), "1 off the ceiling")
end)

T.test("meteor shower stops when its caster changes team", function()
	local caster = NewCaster({ owner = Owner({ team = BLUE }) })
	local shot = Shot(Meteor, Meteor.SPAWNER, {
		spell = SpellSet.SPELL_METEOR,
		normal = V(0, 0, 1),
		team = RED,
	}, 0)
	T.eq(shot:Tick(caster, {
		position = V(0, 0, 0),
		team = RED,
	}, 0), Spells.DONE, "done")
	T.eq(#caster:Calls("LaunchProjectile"), 0, "no meteors")
end)

T.test("a meteor burns like a fireball, with the tendril burst", function()
	local enemy = Fake.Target({
		name = "enemy",
		team = BLUE,
		origin = V(50, 0, 0),
	})
	local caster = NewCaster({
		owner = Owner({ origin = V(-1000, 0, 0) }),
		targets = { enemy },
	})
	Shot(Meteor, Meteor.METEOR):Impact(caster, Impact({ position = V(0, 0, 0) }))
	T.eq(caster:Calls("Particle")[1].name, "spell_fireball_tendril_parent_red", "tendrils")
	T.eq(CondOf(caster, enemy, C.BURNING), 5, "burns")
	T.eq(For(caster:Calls("Damage"), enemy)[1].amount, 100, "100")
end)

T.test("spawn boss: an eyeball of the caster's team where a hull fits, up to the hover height", function()
	local owner = Owner({ team = BLUE })
	local tries = 0
	local caster = NewCaster({
		owner = owner,
		hull = function(from, to)
			tries = tries + 1
			return {
				startSolid = tries == 1,
				endPos = to - V(0, 0, 20),
			}
		end,
	})
	Shot(SpawnBoss, SpawnBoss.PROJECTILE):Impact(caster, Impact({
		hitPosition = V(100, 0, 0),
		normal = V(0, 0, 1),
		team = BLUE,
	}))
	local traces = caster:Calls("TraceHull")
	T.eq(#traces, 2, "tried until one fit")
	local half, height = EyeballBoss.HULL_HALF_WIDTH, 2 * EyeballBoss.HULL_HALF_WIDTH
	Near(traces[1].from, V(100, 0, height + 30), "straight above, 30 off the surface")
	Near(traces[1].to, V(100, 0, height + 30 + EyeballBoss.HOVER.hoverHeight), "up to the hover height")
	Near(traces[2].from, V(100 + half, half, height + 30), "then a corner")
	Near(traces[1].mins, V(-half - 5, -half - 5, -half), "bloated 5 sideways")
	Near(traces[1].maxs, V(half + 5, half + 5, half + 5), "and 5 up")
	local spawn = caster:Calls("SpawnNPC")[1]
	local class, config = HalloweenBoss.SpawnAt(HalloweenBoss.BOSS_MONOCULUS, V(0, 0, 0), BLUE, owner, V)
	T.eq(spawn.class, class, "MONOCULUS")
	T.eq(spawn.config.team, config.team, "the caster's team")
	T.eq(spawn.config.owner, owner, "owned by the caster")
	Near(spawn.pos, traces[2].to - V(0, 0, 20), "where the hull stopped")
	T.eq(caster:Calls("Particle")[1].name, "eyeboss_death", "particle")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_spawn_boss", "sound")
end)

T.test("spawn boss with no room: refunded, with the deny sound", function()
	local caster = NewCaster({
		hull = function(from)
			return {
				startSolid = true,
				endPos = from,
			}
		end,
	})
	local outcome = Shot(SpawnBoss, SpawnBoss.PROJECTILE):Impact(caster, Impact({}))
	T.eq(outcome, Spells.REFUND, "refund")
	T.eq(#caster:Calls("TraceHull"), 5, "five spots tried")
	T.eq(Names(caster:Calls("EmitSound")), SpellSet.DENY_SOUND, "deny")
end)

T.test("skeleton horde: three skull grenades of the caster's team", function()
	local caster = NewCaster()
	Shot(Horde, Horde.PROJECTILE):Impact(caster, Impact({ position = V(1, 2, 3) }))
	local skulls = caster:Calls("SpawnNPC")
	T.eq(#skulls, 3, "three")
	for _, skull in ipairs(skulls) do
		T.eq(skull.class, Zombie.SKULL_CLASS, "skull grenade")
		T.eq(skull.config.thrower, caster.owner, "thrown by the caster")
		T.eq(skull.config.team, RED, "team")
		T.eq(skull.config.skeletonType, Zombie.SKELETON_NORMAL, "normal skeletons")
		Near(skull.pos, V(1, 2, 3), "from the impact")
	end
	T.eq(caster:Calls("Particle")[1].name, "spell_pumpkin_mirv_goop_red", "goop")
	T.eq(caster:Calls("EmitSound")[1].name, "Halloween.spell_skeleton_horde_rise", "sound")
end)

T.finish()
