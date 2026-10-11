-- foundation.npc.zombie: TF2's skeletons (CZombie and its actions), their
-- spawner's keyvalues, and the skull grenade that hatches them, driven as
-- whole scenarios against tests/fake_combatant.lua.
local T = dofile("tests/harness.lua")
local FC = dofile("tests/fake_combatant.lua")
local N = T.require("foundation.npc")
local Zombie = T.require("foundation.npc.zombie")
local Actor = T.require("foundation.npc.actor")
local Spawner = T.require("features.npc.spawner")
local Players = T.require("foundation.players")
local Teams = T.require("foundation.teams")

local V = FC.Vector
local C = Players.COND

local START = 1
local TICK = 0.1
local MID = 0.5 -- every random draw lands mid-range unless a test scripts it
local EPSILON = 0.01 -- a step past a timer's end

-- A skeleton bound to a fake combatant, as the npc controller binds one.
local function Skeleton(t)
	local me = FC.Combatant({
		world = t.world or FC.World(),
		variant = Zombie,
		team = t.team or Teams.UNASSIGNED,
		clock = FC.Clock(START),
		random = FC.Random(t.fractions or { MID }),
		origin = t.origin or V(0, 0, 0),
		owner = t.owner,
	})
	local npc = N.Npc.New(Zombie, {
		lifetime = t.lifetime or 0,
		owner = t.owner,
		skeletonType = t.skeletonType or Zombie.SKELETON_NORMAL,
		maxActive = t.maxActive or Zombie.MAX_ACTIVE_DEFAULT,
	}, me)
	return me, npc
end

-- Start the Behavior and finish the rise, so the skeleton is attacking.
local function Rise(me, npc)
	npc:Update(TICK)
	me:FinishActivity()
	npc:Update(TICK)
	T.eq(npc:Describe(), "ZombieBehavior/Attack", "risen")
end

local function Advance(me, npc, dt)
	me.clock:Advance(dt)
	npc:Update(TICK)
end

-- The damage event ws_nextbot builds, from an attacker that is a
-- player or NPC unless said otherwise.
local function Kill(attacker, isCharacter)
	return {
		attacker = attacker,
		inflictor = attacker,
		amount = 1000,
		dmgType = Actor.DMG_GENERIC,
		position = V(0, 0, 36),
		crit = false,
		attackerIsCharacter = isCharacter ~= false,
	}
end

local function Count(calls, first)
	local n = 0
	for _, args in ipairs(calls) do
		if args[1] == first then n = n + 1 end
	end
	return n
end

-- 1. A HALLOWEEN NORMAL skeleton, from rising to breaking apart.

T.test("a Halloween skeleton rises, chases the nearest player, swings, hits, and breaks into three mini skulls", function()
	local world = FC.World()
	local red = world:AddPlayer({
		team = Teams.RED,
		origin = V(300, 0, 0),
	})
	local blue = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(200, 0, 0),
	})
	local me, npc = Skeleton({ world = world })
	T.eq(npc:State().team, Teams.HALLOWEEN, "an unassigned skeleton joins HALLOWEEN")
	T.eq(me:Called("SetSkin")[1][1], Zombie.SKIN_HALLOWEEN, "the Halloween skin")
	T.eq(me:GetHealth(), 50, "health")
	T.eq(me:GetMaxHealth(), 50, "max health")
	T.eq(me:GetYaw(), 180, "a random yaw")
	T.eq(#me:Called("SetModelScale"), 0, "a normal skeleton keeps its scale")

	npc:Update(TICK)
	T.eq(npc:Describe(), "ZombieBehavior/Spawn", "rising")
	T.eq(me.activity, "ACT_TRANSITION", "the spawn activity")
	npc:Update(TICK)
	T.eq(npc:Describe(), "ZombieBehavior/Spawn", "rising until the activity finishes")
	me:FinishActivity()
	npc:Update(TICK)
	T.eq(npc:Describe(), "ZombieBehavior/Attack", "attacking")
	T.eq(me.activity, "ACT_MP_RUN_MELEE", "running")

	npc:Update(TICK)
	local path = me.paths[1]
	T.eq(path.lookAhead, 100, "look-ahead")
	T.eq(path.goal, blue.origin, "chases the nearer of RED and BLU")
	T.eq(path.computes, 1, "one path")
	T.eq(path.updates, 1, "follows it")
	T.eq(#me:Called("FaceTowards"), 0, "no swing beyond 150")

	Advance(me, npc, 0.4)
	T.eq(path.computes, 1, "no repath before 0.5 s")
	T.eq(path.updates, 2, "still follows")
	Advance(me, npc, 0.2)
	T.eq(path.computes, 2, "repaths after 0.5 s")

	blue.origin = V(100, 0, 0)
	npc:Update(TICK)
	npc:Update(TICK)
	T.eq(#me:Called("FaceTowards"), 2, "faces between 50 and 150")
	T.eq(me:Called("FaceTowards")[1][1], blue.origin + V(0, 0, 36), "towards the victim's centre")
	T.eq(Count(me:Called("AddGesture"), "ACT_MP_ATTACK_STAND_MELEE"), 1, "one swing gesture while it plays")
	T.eq(#me:Called("DealDamage"), 0, "no hit outside 50")

	blue.origin = V(40, 0, 0)
	local updates = path.updates
	npc:Update(TICK)
	local hits = me:Called("DealDamage")
	T.eq(#hits, 1, "hits inside 50")
	T.eq(hits[1][1], blue, "the victim")
	T.eq(hits[1][2], 30, "for 30")
	T.eq(hits[1][3], Actor.DMG_SLASH, "slashing")
	T.eq(hits[1][4], nil, "as itself, having no owner")
	T.eq(path.updates, updates, "stands still inside 50 with a clear line")
	Advance(me, npc, 0.9)
	T.eq(#me:Called("DealDamage"), 1, "not again within 0.8-1.2 s")
	Advance(me, npc, 0.2)
	T.eq(#me:Called("DealDamage"), 2, "again after it")

	npc:Event("OnKilled", Kill(red))
	npc:Update(TICK)
	local skulls = me:Called("SpawnEntity")
	T.eq(#skulls, Zombie.MINIS_ON_DEATH, "three skull grenades")
	for _, skull in ipairs(skulls) do
		T.eq(skull[1], Zombie.SKULL_CLASS, "a skull grenade")
		T.eq(skull[2].thrower, me, "thrown by itself, having no owner")
		T.eq(skull[2].team, Teams.HALLOWEEN, "its team")
		T.eq(skull[2].skeletonType, Zombie.SKELETON_MINI, "hatching a mini")
		T.eq(skull[3], me.origin, "from where it fell")
	end
	local outputs = me:Called("FireOutput")
	T.eq(#outputs, 1, "OnDeath once")
	T.eq(outputs[1][1], "OnDeath", "OnDeath")
	T.eq(outputs[1][2], red, "with the inflictor as activator")
	T.eq(Count(me:Called("EmitSound"), Zombie.BREAK_SOUND), 1, "it breaks")
	T.eq(me.removed, true, "removed")
	T.eq(npc:IsEmpty(), true, "its Behavior is done")
end)

-- 2. Whom a team skeleton chooses.

T.test("a RED skeleton skips teammates and unchaseable or hidden players, but sees a burning spy", function()
	local world = FC.World()
	world:AddPlayer({
		team = Teams.RED,
		origin = V(50, 0, 0),
	})
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(100, 0, 0),
		inRespawnRoom = true,
	})
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(110, 0, 0),
		onMesh = false,
	})
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(120, 0, 0),
		alive = false,
	})
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(130, 0, 0),
		conds = { C.STEALTHED },
	})
	world:AddPlayer({
		team = Teams.BLUE,
		origin = V(140, 0, 0),
		conds = { C.HALLOWEEN_GHOST_MODE },
	})
	local burning = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(400, 0, 0),
		conds = { C.STEALTHED, C.BURNING },
	})
	local me, npc = Skeleton({
		world = world,
		team = Teams.RED,
	})
	T.eq(npc:State().team, Teams.RED, "a RED skeleton stays RED")
	T.eq(me:Called("SetSkin")[1][1], Zombie.SKIN_RED, "the RED skin")
	Rise(me, npc)
	npc:Update(TICK)
	T.eq(me.paths[1].goal, burning.origin, "the burning spy")
end)

T.test("a RED skeleton fights a nearer BLU skeleton, keeping each victim for 3 s", function()
	local world = FC.World()
	local blue = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(400, 0, 0),
	})
	world:AddNPC(Zombie.KIND, FC.Target({
		team = Teams.RED,
		origin = V(60, 0, 0),
	}))
	local me, npc = Skeleton({
		world = world,
		team = Teams.RED,
	})
	Rise(me, npc)
	npc:Update(TICK)
	local path = me.paths[1]
	T.eq(path.goal, blue.origin, "the player, not a RED skeleton")

	local enemy = world:AddNPC(Zombie.KIND, FC.Target({
		team = Teams.BLUE,
		origin = V(300, 0, 0),
	}))
	Advance(me, npc, 0.6)
	T.eq(path.computes, 2, "repathed")
	T.eq(path.goal, blue.origin, "keeps its victim for 3 s")
	Advance(me, npc, 2.5)
	T.eq(path.goal, enemy.origin, "then takes the nearer BLU skeleton")
end)

T.test("a skeleton chases the AI war's soldiers of an enemy team, not its own", function()
	local world = FC.World()
	world:AddPlayer({ team = Teams.BLUE, origin = V(600, 0, 0) })
	world:AddMember({ team = Teams.RED, origin = V(50, 0, 0) })
	local soldier = world:AddMember({ team = Teams.BLUE, origin = V(200, 0, 0) })
	local me, npc = Skeleton({ world = world, team = Teams.RED })
	Rise(me, npc)
	npc:Update(TICK)
	T.eq(me.paths[1].goal, soldier.origin, "the nearer BLU soldier, not the RED one")
end)

T.test("a Halloween skeleton chases soldiers of either team", function()
	local world = FC.World()
	local soldier = world:AddMember({ team = Teams.RED, origin = V(200, 0, 0) })
	local me, npc = Skeleton({ world = world, team = Teams.HALLOWEEN })
	Rise(me, npc)
	npc:Update(TICK)
	T.eq(me.paths[1].goal, soldier.origin, "a RED soldier")
end)

T.test("a team skeleton locks onto an enemy player it touches for 3 s", function()
	local world = FC.World()
	local teammate = world:AddPlayer({
		team = Teams.RED,
		origin = V(20, 0, 0),
	})
	local near = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(200, 0, 0),
	})
	local toucher = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(500, 0, 0),
	})
	local me, npc = Skeleton({
		world = world,
		team = Teams.RED,
	})
	Rise(me, npc)
	npc:Update(TICK)
	local path = me.paths[1]
	T.eq(path.goal, near.origin, "the nearest")

	me.clock:Advance(3.1)
	npc:Event("OnContact", teammate)
	npc:Event("OnContact", toucher)
	Advance(me, npc, 0.1)
	T.eq(path.goal, toucher.origin, "the enemy that touched it")
	Advance(me, npc, 2.8)
	T.eq(path.goal, toucher.origin, "held for 3 s")
	Advance(me, npc, 0.6)
	T.eq(path.goal, near.origin, "then the nearest again")
end)

-- 3. The skeleton king.

T.test("a king stomps when its special timer has elapsed inside 100, then resumes, and drops a rare spell on death", function()
	local world = FC.World()
	local teammate = world:AddPlayer({
		team = Teams.RED,
		origin = V(60, 0, 0),
	})
	local victim = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(80, 0, 0),
	})
	local near = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(150, 0, 0),
	})
	local far = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(250, 0, 0),
	})
	local me, npc = Skeleton({
		world = world,
		team = Teams.RED,
		skeletonType = Zombie.SKELETON_KING,
	})
	T.eq(me:Called("SetModelScale")[1][1], 2, "twice the size")
	T.eq(me:GetHealth(), 1000, "health")
	T.eq(me:GetMaxHealth(), 1000, "max health")
	local crown = me:Called("AttachProp")[1]
	T.eq(crown[1], Zombie.CROWN_MODEL, "a crown")
	T.eq(crown[2], Zombie.HEAD_BONE, "on its head")

	Rise(me, npc)
	npc:Update(TICK)
	local hits = me:Called("DealDamage")
	T.eq(#hits, 1, "a king hits inside 100")
	T.eq(hits[1][1], victim, "its victim")
	T.eq(hits[1][2], 100, "for 100")

	Advance(me, npc, 7.4)
	T.eq(npc:Describe(), "ZombieBehavior/Attack", "no stomp before the special timer (5-10 s)")
	Advance(me, npc, 0.2)
	T.eq(npc:Describe(), "ZombieBehavior/SpecialAttack", "stomps")
	T.eq(me.activity, "ACT_SPECIAL_ATTACK1", "the stomp activity")
	local before = #me:Called("DealDamage")

	Advance(me, npc, 0.9)
	T.eq(#me:Called("ApplyImpulse"), 0, "nothing before 1 s")
	Advance(me, npc, 0.2)
	local ring = me:Called("DispatchParticleEffect")
	T.eq(ring[#ring][1], Zombie.STOMP_PARTICLE, "the ring")
	T.eq(ring[#ring][2], me.origin, "at its feet")
	local pushes = me:Called("ApplyImpulse")
	T.eq(#pushes, 2, "the two BLU players whose eyes are within 200")
	T.eq(pushes[1][1], victim, "the victim")
	T.eq(pushes[1][2], V(500, 0, 500), "pushed up and away")
	T.eq(pushes[2][1], near, "the other")
	local stomped = {}
	for i = before + 1, #me:Called("DealDamage") do
		local hit = me:Called("DealDamage")[i]
		T.eq(hit[2], 100, "attack damage")
		T.eq(hit[3], Actor.DMG_SLASH, "slashing")
		stomped[hit[1]] = true
	end
	T.eq(stomped[victim] and stomped[near], true, "both hit")
	T.eq(stomped[far] or stomped[teammate], nil, "not the far one or a teammate")

	me:FinishActivity()
	npc:Update(TICK)
	T.eq(npc:Describe(), "ZombieBehavior/Attack", "attack resumes")
	T.eq(#me:Called("ApplyImpulse"), 2, "one stomp")

	npc:Event("OnKilled", Kill(victim))
	npc:Update(TICK)
	local drops = me:Called("DropSpellPickup")
	T.eq(#drops, 1, "a spell drop")
	T.eq(drops[1][1], me.origin, "where it fell")
	T.eq(drops[1][2], Zombie.SPELL_TIER_RARE, "rare")
	T.eq(#me:Called("SpawnEntity"), 0, "no skulls")
	T.eq(me.removed, true, "removed")
end)

-- 4. Minis, lifetimes and owners.

T.test("a skull grenade hatches a 30 s mini owned only by a player thrower", function()
	local thrower = FC.Target({ team = Teams.RED })
	local skull = {
		thrower = thrower,
		team = Teams.RED,
		skeletonType = Zombie.SKELETON_MINI,
	}
	local owned = Zombie.HatchConfig(skull, true)
	T.eq(owned.team, Teams.RED, "team")
	T.eq(owned.lifetime, Zombie.MINI_LIFETIME, "lifetime")
	T.eq(owned.owner, thrower, "the player owns it")
	T.eq(owned.skeletonType, Zombie.SKELETON_MINI, "a mini")
	T.eq(Zombie.HatchConfig(skull, false).owner, nil, "a thrower that is not a player owns nothing")
end)

T.test("a mini lives 30 s, then fires OnDeath once and is removed", function()
	local me, npc = Skeleton({
		skeletonType = Zombie.SKELETON_MINI,
		lifetime = Zombie.MINI_LIFETIME,
	})
	T.eq(me:Called("SetModelScale")[1][1], 0.5, "half size")
	local head = me:Called("SetBoneScale")[1]
	T.eq(head[1], Zombie.HEAD_BONE, "a big head")
	T.eq(head[2], 3, "three times")
	T.eq(me:GetHealth(), 50, "health")
	Rise(me, npc)
	Advance(me, npc, 29.9)
	T.eq(me.removed, false, "alive at 29.9 s")
	Advance(me, npc, 0.1 + EPSILON)
	local outputs = me:Called("FireOutput")
	T.eq(#outputs, 1, "OnDeath once")
	T.eq(outputs[1][2], me, "with itself as activator")
	T.eq(me.removed, true, "removed")
	T.eq(npc:IsEmpty(), true, "done")
	T.eq(#me:Called("SpawnEntity"), 0, "a suicide throws nothing")
	npc:Event("OnKilled", Kill(FC.Target({})))
	npc:Update(TICK)
	T.eq(#me:Called("FireOutput"), 1, "a kill before removal fires no second OnDeath")
	T.eq(#me:Called("SpawnEntity"), 0, "and throws nothing")
end)

T.test("a skeleton whose owner changes team suicides", function()
	local owner = FC.Target({ team = Teams.RED })
	local me, npc = Skeleton({
		team = Teams.RED,
		owner = owner,
		skeletonType = Zombie.SKELETON_MINI,
		lifetime = Zombie.MINI_LIFETIME,
	})
	Rise(me, npc)
	Advance(me, npc, 1)
	T.eq(me.removed, false, "alive while the owner is a teammate")
	owner.team = Teams.BLUE
	Advance(me, npc, TICK)
	T.eq(#me:Called("FireOutput"), 1, "OnDeath once")
	T.eq(me.removed, true, "removed")
end)

T.test("an owned skeleton hits as its owner", function()
	local world = FC.World()
	local owner = world:AddPlayer({ team = Teams.RED })
	local victim = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(30, 0, 0),
	})
	local me, npc = Skeleton({
		world = world,
		team = Teams.RED,
		owner = owner,
		skeletonType = Zombie.SKELETON_MINI,
	})
	Rise(me, npc)
	npc:Update(TICK)
	local hit = me:Called("DealDamage")[1]
	T.eq(hit[1], victim, "the victim")
	T.eq(hit[2], 20, "a mini hits for 20")
	T.eq(hit[4], owner, "as its owner")
end)

-- 5. Laughs, getting stuck, contact, own-team damage, and deaths that throw nothing.

T.test("each type laughs on its own cadence", function()
	local cases = {
		{
			skeletonType = Zombie.SKELETON_NORMAL,
			wait = 4.5,
			sound = "Halloween.skeleton_laugh_medium",
		},
		{
			skeletonType = Zombie.SKELETON_KING,
			wait = 6.5,
			sound = "Halloween.skeleton_laugh_giant",
		},
		{
			skeletonType = Zombie.SKELETON_MINI,
			wait = 2.5,
			sound = "Halloween.skeleton_laugh_small",
		},
	}
	for _, case in ipairs(cases) do
		local me, npc = Skeleton({ skeletonType = case.skeletonType })
		npc:Update(TICK)
		npc:Update(TICK)
		Advance(me, npc, case.wait - EPSILON)
		T.eq(Count(me:Called("EmitSound"), case.sound), 0, case.sound .. " not yet")
		Advance(me, npc, 2 * EPSILON)
		T.eq(Count(me:Called("EmitSound"), case.sound), 1, case.sound)
		Advance(me, npc, 0)
		Advance(me, npc, case.wait - EPSILON)
		T.eq(Count(me:Called("EmitSound"), case.sound), 1, case.sound .. " restarts after a laugh")
		Advance(me, npc, 2 * EPSILON)
		T.eq(Count(me:Called("EmitSound"), case.sound), 2, case.sound .. " again")
	end
end)

T.test("a stuck skeleton deals itself a fatal slash", function()
	local me, npc = Skeleton({})
	Rise(me, npc)
	npc:Event("OnStuck")
	local hit = me:Called("DealDamage")[1]
	T.eq(hit[1], me, "itself")
	T.eq(hit[2], Zombie.STUCK_DAMAGE, "fatal")
	T.eq(hit[3], Actor.DMG_SLASH, "slashing")
end)

T.test("a Halloween skeleton ignores who touches it", function()
	local world = FC.World()
	local near = world:AddPlayer({
		team = Teams.BLUE,
		origin = V(200, 0, 0),
	})
	local toucher = world:AddPlayer({
		team = Teams.RED,
		origin = V(500, 0, 0),
	})
	local me, npc = Skeleton({ world = world })
	Rise(me, npc)
	npc:Update(TICK)
	me.clock:Advance(3.1)
	npc:Event("OnContact", toucher)
	Advance(me, npc, 0.1)
	T.eq(me.paths[1].goal, near.origin, "still the nearest")
end)

T.test("a skeleton takes no damage from its own team, and flinches and splashes from anyone else", function()
	local world = FC.World()
	local teammate = world:AddPlayer({ team = Teams.RED })
	local enemy = world:AddPlayer({ team = Teams.BLUE })
	local me, npc = Skeleton({
		world = world,
		team = Teams.RED,
	})
	local hitAt = V(1, 2, 3)
	T.eq(npc:FilterDamage({
		attacker = teammate,
		position = hitAt,
	}), false, "a teammate's hit is refused")
	T.eq(#me:Called("AddGesture"), 0, "no flinch")
	T.eq(#me:Called("DispatchParticleEffect"), 0, "no goop")
	T.eq(npc:FilterDamage({
		attacker = enemy,
		position = hitAt,
	}), true, "an enemy's hit is taken")
	T.eq(Count(me:Called("AddGesture"), "ACT_MP_GESTURE_FLINCH_CHEST"), 1, "flinch")
	T.eq(npc:FilterDamage({
		attacker = nil,
		position = hitAt,
	}), true, "damage with no attacker is taken")
	T.eq(Count(me:Called("AddGesture"), "ACT_MP_GESTURE_FLINCH_CHEST"), 1, "no second flinch while one plays")
	local goop = me:Called("DispatchParticleEffect")[1]
	T.eq(goop[1], "spell_pumpkin_mirv_goop_red", "RED goop")
	T.eq(goop[2], hitAt, "where it was hit")
end)

T.test("goop matches the team: green for Halloween, red for RED, blue otherwise", function()
	T.eq(Zombie.GoopParticle(Teams.HALLOWEEN), "spell_skeleton_goop_green", "halloween")
	T.eq(Zombie.GoopParticle(Teams.RED), "spell_pumpkin_mirv_goop_red", "red")
	T.eq(Zombie.GoopParticle(Teams.BLUE), "spell_pumpkin_mirv_goop_blue", "blue")
end)

T.test("a partial config overrides only the placed skeleton's defaults it names, and binds", function()
	local typed = Zombie.BindingConfig({ skeletonType = Zombie.SKELETON_MINI }, {}, Zombie.MAX_ACTIVE_DEFAULT)
	T.eq(typed.skeletonType, Zombie.SKELETON_MINI, "the given type")
	T.eq(typed.lifetime, 0, "no lifetime, as placed")
	local timed = Zombie.BindingConfig({ lifetime = Zombie.MINI_LIFETIME }, {}, Zombie.MAX_ACTIVE_DEFAULT)
	T.eq(timed.lifetime, Zombie.MINI_LIFETIME, "the given lifetime")
	T.eq(timed.skeletonType, Zombie.SKELETON_NORMAL, "normal, as placed")
	local empty = Zombie.BindingConfig({}, {}, Zombie.MAX_ACTIVE_DEFAULT)
	T.eq(empty.lifetime, 0, "an empty config: no lifetime")
	T.eq(empty.skeletonType, Zombie.SKELETON_NORMAL, "an empty config: normal")
	local me = FC.Combatant({
		world = FC.World(),
		variant = Zombie,
	})
	local npc = N.Npc.New(Zombie, Zombie.BindingConfig({ skeletonType = Zombie.SKELETON_NORMAL }, {}, Zombie.MAX_ACTIVE_DEFAULT), me)
	npc:Update(TICK)
	T.eq(npc.state.skeletonType, Zombie.SKELETON_NORMAL, "bound and running")
end)

T.test("a skeleton of each team, hit, splashes its team's goop, a system its variant declares", function()
	local cases = {
		{
			team = Teams.HALLOWEEN,
			enemy = Teams.RED,
			goop = Zombie.GOOP_HALLOWEEN,
		},
		{
			team = Teams.RED,
			enemy = Teams.BLUE,
			goop = Zombie.GOOP_RED,
		},
		{
			team = Teams.BLUE,
			enemy = Teams.RED,
			goop = Zombie.GOOP_BLUE,
		},
	}
	for _, case in ipairs(cases) do
		local world = FC.World()
		local enemy = world:AddPlayer({ team = case.enemy })
		local me, npc = Skeleton({
			world = world,
			team = case.team,
		})
		T.eq(npc:FilterDamage({
			attacker = enemy,
			position = V(0, 0, 0),
		}), true, "the hit is taken")
		T.eq(me:Called("DispatchParticleEffect")[1][1], case.goop, "team " .. case.team)
	end
end)

T.test("a skeleton killed by no player or NPC throws nothing, but still fires OnDeath once and breaks", function()
	local world = FC.World()
	local me, npc = Skeleton({ world = world })
	Rise(me, npc)
	local trap = FC.Target({})
	npc:Event("OnKilled", Kill(trap, false))
	npc:Update(TICK)
	npc:Update(TICK)
	T.eq(#me:Called("SpawnEntity"), 0, "no skulls")
	T.eq(#me:Called("FireOutput"), 1, "OnDeath once")
	T.eq(Count(me:Called("EmitSound"), Zombie.BREAK_SOUND), 1, "it breaks")
	T.eq(me.removed, true, "removed")
end)

T.test("a king killed by no player or NPC drops nothing", function()
	local me, npc = Skeleton({ skeletonType = Zombie.SKELETON_KING })
	Rise(me, npc)
	npc:Event("OnKilled", Kill(FC.Target({}), false))
	npc:Update(TICK)
	T.eq(#me:Called("DropSpellPickup"), 0, "no spell")
end)

-- 6. Culling over tf_max_active_zombie.

T.test("Cull picks the oldest non-kings above the cap and never a king", function()
	local types = {
		Zombie.SKELETON_KING,
		Zombie.SKELETON_NORMAL,
		Zombie.SKELETON_MINI,
		Zombie.SKELETON_NORMAL,
		Zombie.SKELETON_NORMAL,
	}
	local npcs = {}
	for i, skeletonType in ipairs(types) do
		local _, npc = Skeleton({
			skeletonType = skeletonType,
			maxActive = 3,
		})
		npcs[i] = npc
	end
	local culled = N.Cull(Zombie, npcs)
	T.eq(#culled, 2, "two over the cap")
	T.eq(culled[1], npcs[2]:State(), "the oldest non-king")
	T.eq(culled[2], npcs[3]:State(), "the next")
	T.eq(npcs[1]:State().culled, false, "the king is spared")

	local me, npc = Skeleton({ maxActive = 1 })
	Rise(me, npc)
	N.Cull(Zombie, { npc })
	T.eq(me.removed, false, "at the cap nothing is culled")
	npc:State().culled = true
	npc:Update(TICK)
	T.eq(#me:Called("FireOutput"), 1, "a culled skeleton fires OnDeath")
	T.eq(me.removed, true, "and suicides")
end)

T.test("a king placed over the cap by kings alone culls nothing", function()
	local npcs = {}
	for i = 1, 3 do
		local _, npc = Skeleton({
			skeletonType = Zombie.SKELETON_KING,
			maxActive = 1,
		})
		npcs[i] = npc
	end
	T.eq(#N.Cull(Zombie, npcs), 0, "kings are never culled")
end)

-- The spawner and the bindings' configs.

local function Draw(lo, hi) return lo + MID * (hi - lo) end

T.test("a spawner's keyvalues make a finite spawner of HALLOWEEN skeletons", function()
	local spawner = Spawner.New(Zombie.SpawnerConfig({
		teamnum = tostring(Teams.UNASSIGNED),
		zombie_lifetime = "240",
		max_zombies = "2",
		infinite_zombies = "0",
		zombie_type = tostring(Zombie.SKELETON_KING),
		zombie_scale = "2",
	}))
	local now = START
	T.eq((spawner:Think(now, Draw)), nil, "disabled")
	spawner:Enable(now)
	local request = spawner:Think(now, Draw)
	T.eq(request.class, Zombie.ZOMBIE_CLASS, "a tf_zombie")
	T.eq(request.config.team, Teams.HALLOWEEN, "HALLOWEEN")
	T.eq(request.config.lifetime, 240, "lifetime")
	T.eq(request.config.skeletonType, Zombie.SKELETON_KING, "type")
	spawner:Spawned("first")
	now = now + 3
	spawner:Spawned((spawner:Think(now, Draw)) and "second")
	spawner:Died("first")
	now = now + 3
	T.eq((spawner:Think(now, Draw)), nil, "a finite spawner stops at max_zombies, deaths or not")
	spawner:SetMaxActive(3)
	now = now + 3
	T.eq((spawner:Think(now, Draw)) ~= nil, true, "SetMaxActiveZombies raises the cap")
	spawner:Disable()
	now = now + 3
	T.eq((spawner:Think(now, Draw)), nil, "Disable stops it")
end)

T.test("an infinite spawner refills, a team spawner keeps its team, and missing keyvalues take TF2's defaults", function()
	local spawner = Spawner.New(Zombie.SpawnerConfig({
		teamnum = tostring(Teams.RED),
		infinite_zombies = "1",
	}))
	spawner:Enable(START)
	local request = spawner:Think(START, Draw)
	T.eq(request.config.team, Teams.RED, "RED stays RED")
	T.eq(request.config.lifetime, 0, "no lifetime")
	T.eq(request.config.skeletonType, Zombie.SKELETON_NORMAL, "normal")
	spawner:Spawned("first")
	T.eq((spawner:Think(START + 3, Draw)), nil, "one active at a time by default")
	spawner:Died("first")
	T.eq((spawner:Think(START + 6, Draw)) ~= nil, true, "refills after a death")

	local defaults = Zombie.SpawnerConfig({})
	T.eq(defaults.team, Teams.UNASSIGNED, "no team")
	T.eq(defaults.maxActive, 1, "one")
	T.eq(defaults.infinite, false, "finite")
	T.eq(Zombie.SpawnerTeam(Teams.BLUE), Teams.BLUE, "BLU stays BLU")
	T.eq(Zombie.SpawnerTeam(Teams.SPECTATOR), Teams.HALLOWEEN, "any other team is HALLOWEEN")
end)

T.test("a tf_zombie's config: what its spawner or skull gave, or a placed normal skeleton", function()
	local owner = FC.Target({})
	local given = {
		team = Teams.RED,
		lifetime = Zombie.MINI_LIFETIME,
		owner = owner,
		skeletonType = Zombie.SKELETON_MINI,
	}
	local config = Zombie.BindingConfig(given, {}, 7)
	T.eq(config.team, Teams.RED, "team")
	T.eq(config.lifetime, Zombie.MINI_LIFETIME, "lifetime")
	T.eq(config.owner, owner, "owner")
	T.eq(config.skeletonType, Zombie.SKELETON_MINI, "type")
	T.eq(config.maxActive, 7, "tf_max_active_zombie")
	T.eq(config.modelScale, nil, "no scale keyvalue")

	local placed = Zombie.BindingConfig(nil, { modelscale = "2.25" }, 30)
	T.eq(placed.team, nil, "the TeamNum keyvalue decides")
	T.eq(placed.lifetime, 0, "no lifetime")
	T.eq(placed.owner, nil, "no owner")
	T.eq(placed.skeletonType, Zombie.SKELETON_NORMAL, "normal")
	T.eq(placed.modelScale, 2.25, "the map's scale")

	local big = FC.Combatant({
		world = FC.World(),
		variant = Zombie,
	})
	N.Npc.New(Zombie, placed, big)
	T.eq(big:Called("SetModelScale")[1][1], 2.25, "a placed skeleton takes the map's scale")
	local king = FC.Combatant({
		world = FC.World(),
		variant = Zombie,
	})
	N.Npc.New(Zombie, Zombie.BindingConfig({
		lifetime = 0,
		skeletonType = Zombie.SKELETON_KING,
	}, { modelscale = "2.25" }, 30), king)
	local scales = king:Called("SetModelScale")
	T.eq(scales[#scales][1], 2, "a king's own scale wins over the map's")
	T.eq(Zombie.Model(Zombie.SKELETON_KING), "models/bots/skeleton_sniper_boss/skeleton_sniper_boss.mdl", "king model")
	T.eq(Zombie.Model(Zombie.SKELETON_MINI), "models/bots/skeleton_sniper/skeleton_sniper.mdl", "mini model")
end)

T.test("a skull is thrown up and out from beside the thrower, with a 2-2.5 s fuse", function()
	-- offset x, offset y; direction x, y, z; lift; speed; fuse
	local rnd = FC.Random({ 1, 0, 1, MID, MID, 1, 0, 0 })
	local throw = Zombie.SkullThrow(function(lo, hi) return rnd:Float(lo, hi) end, V)
	T.eq(throw.offset, V(32, -32, 16), "beside and above")
	T.eq(throw.velocity, V(250, 0, 400), "a unit direction lifted to 1.6, at 250")
	T.eq(throw.fuse, 2, "fuse")
	T.eq(throw.spin, V(300, 300, 100), "spin")
	T.eq(throw.model, Zombie.SKULL_MODEL, "the skull")
end)

-- The bindings

local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

local function LoadsAtTopLevel(line)
	if line:match("^%s") or line:match("^function ") then return false end
	return line:find("WS.require", 1, true) ~= nil or line:find("WS.Feature", 1, true) ~= nil
end

T.test("the skeleton bindings load nothing at top level and shadow no engine method", function()
	for _, file in ipairs({ "tf_zombie.lua", "tf_zombie_spawner.lua", "tf_projectile_spellspawnzombie.lua" }) do
		local text = ReadFile(ENTITIES .. file)
		for line in text:gmatch("[^\n]+") do
			T.eq(LoadsAtTopLevel(line), false, file .. ": " .. line)
		end
		for name in text:gmatch("function ENT:(%w+)%(") do
			T.eq(Actor.ENGINE[name], nil, file .. " defines engine method " .. name)
		end
	end
end)

T.finish()
