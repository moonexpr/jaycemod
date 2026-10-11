-- MERASMUS! (CMerasmus, halloween/merasmus/merasmus.cpp and
-- merasmus_behavior/*.cpp): a boss variant of foundation.npc.halloween_boss.
-- He appears in a puff of smoke and chases the nearest player, whacking
-- them with his staff, throwing bombs and zapping everyone near with fire.
-- Every 16 s one player of each team gets a bomb head: whoever carries it
-- to him stuns him, and three stuns send him into the air over the first
-- control point, raining bombs. Hurt badly, he hides among props the
-- players must smash to find him, healing past his first level. After
-- 120 s he goes home. Killed, he leaves a vortex to each team's loot, and
-- the next Merasmus is a level tougher. His announcements reach the clients
-- as foundation.npc.boss_events' game events.
--
-- Its port adds METHODS to the boss port (the merasmus binding implements
-- it; vectors are Vecs, attachments the model's names):
--   ControlPoints() -> the master's points in order, as the Horsemann's;
--   PlayHighPrioritySound(name) (everyone hears), PlayLowPrioritySound(name)
--     (those near, never over a line he is saying), BroadcastGameSound(name)
--     (TFGameRules()->BroadcastSound);
--   AddTimedGesture(act) -> the gesture's length in seconds; SetStaff(n),
--     the staff bodygroup; AttachmentPosition(name) -> Vec;
--   DispatchParticleAttached(name, attachment), DispatchBeam(name,
--     attachment, to);
--   SetHidden(hidden), SetCollidable(on), NetworkState(revealed,
--     aoeAttack, stunned) for the clients' effects (C_Merasmus);
--   StartFlying(), StopFlying(), SetDesiredAltitude(h) (the binding flies
--     him with foundation.npc.hover and FLYING);
--   TriggerRelay(name) -> the logic_relay's origin | nil;
--   PreferredAreas(minSize) -> the centres of the nav areas inside a
--     func_nav_prefer, at least minSize on each side, with no RED or BLU
--     player in them; AreasAround(pos, range) -> the centres of the areas
--     around the one at pos; IsInPreferredArea(t);
--   RemoveGrenades(origin, radius), EndStun(t), RemoveCond(t, cond),
--     RemoveEntity(t);
--   StartBossTimer(seconds, variation) (TFGameRules()->
--     StartHalloweenBossTimer: features.boss_timer.model's Start);
--   PlayScriptedScene(name) (InstancedScriptedScene, multiplayer).
-- The binding forwards the props' events to the Behavior: OnPropKilled(prop,
-- attacker) and OnPropTouched(prop, toucher), and calls Removed(state, me)
-- when he is removed (CMerasmus::UpdateOnRemove).
--
-- His death's rewards, as far as they show here: merasmus_killed carries
-- his level (TF2's only field), and each player who hit him in his last 5 s
-- is named in the chat (merasmus_killer, TF2's SayText2 of
-- TF_Halloween_Merasmus_Killers), unless cheats spawned him. What else TF2
-- does has no counterpart here: the Steam econ hat levels the GC awards
-- (CMsgUpdateHalloweenMerasmusLootLevel), Valve's achievements
-- (ACHIEVEMENT_TF_HALLOWEEN_MERASMUS_KILL), Valve's gamestats (the boss
-- stats SW_ReportMerasmusStats uploads, CTF_GameStats' boss events), the
-- soul packs and halloween_boss_killed, which only feed those; and TF2's
-- scoreboard gives no points for him either.
--
-- His Wheel of Fate is foundation.holiday.wheel (wheel_of_doom). Left out
-- besides: the critical flag on hits while stunned or raining bombs (only
-- TF2's hit numbers and sounds show it; ModifyDamage maps the per-weapon multipliers
-- to damage types), and the holiday ammo pack's health (the props drop a
-- plain medium pack). The prop separation and the area around the control
-- point are measured straight, where TF2 walks the mesh. TF2's boss timer
-- (features.boss_timer.model) brings the next one.
local require = require
local NpcSystem = require("foundation.npc")
local HalloweenBoss = require("foundation.npc.halloween_boss")
local BossEvents = require("foundation.npc.boss_events")
local Actor = require("foundation.npc.actor")
local Combat = require("foundation.combat")
local Players = require("foundation.players")
local Teams = require("foundation.teams")
local atan2, cos, deg, floor, huge, max, min, rad, sin = math.atan2, math.cos, math.deg, math.floor, math.huge, math.max, math.min, math.rad, math.sin
local ipairs = ipairs
local band = bit.band
local format = string.format
module(...)

BOSS_TYPE = HalloweenBoss.BOSS_MERASMUS
PATH = "foundation.npc.path.ground"
-- CMerasmusLocomotion
LOCOMOTION = {
	runSpeed = 600, -- tf_merasmus_speed
	stepHeight = 18,
	jumpHeight = 18,
	deathDropHeight = 200, -- NextBotGroundLocomotion's
	maxYawRate = 200,
	acceleration = 500,
	deceleration = 500,
}
-- CMerasmusFlyingLocomotion: foundation.npc.hover's config.
FLYING = {
	hoverHeight = 50,
	acceleration = 250, -- MERASMUS_ACCELERATION
	horizontalDamping = 1,
	verticalDamping = 1,
}
FLYING_MAX_YAW_RATE = 100
-- CMerasmusLocomotion::ShouldCollideWith and the flying one's: players are
-- no obstacle to him, on foot or aloft.
PLAYERS_PASS_THROUGH = true

-- TF2's convars (merasmus.cpp, merasmus_trick_or_treat_prop.cpp; the boss
-- timer's from tf_gamerules.cpp and headless_hatman.cpp), with their
-- defaults. tf_merasmus_speed_recovery_rate is never read.
CONVARS = {
	tf_merasmus_health_base = 33750,
	tf_merasmus_health_per_player = 2500,
	tf_merasmus_min_player_count = 10,
	tf_merasmus_lifetime = 120,
	tf_merasmus_speed = 600,
	tf_merasmus_chase_duration = 7,
	tf_merasmus_chase_range = 2000,
	tf_merasmus_should_disguise_threshold = 0.45,
	tf_merasmus_min_props_to_reveal = 0.7,
	tf_merasmus_attack_range = 200,
	tf_merasmus_health_regen_rate = 0.001,
	tf_merasmus_bomb_head_duration = 15,
	tf_merasmus_bomb_head_per_team = 1,
	tf_merasmus_stun_duration = 2,
	tf_merasmus_prop_health = 150,
	tf_merasmus_spawn_interval = 180,
	tf_merasmus_spawn_interval_variation = 30,
	tf_halloween_bot_min_player_count = 10,
}

METHODS = {
	"ControlPoints",
	"PlayHighPrioritySound",
	"PlayLowPrioritySound",
	"BroadcastGameSound",
	"AddTimedGesture",
	"SetStaff",
	"AttachmentPosition",
	"DispatchParticleAttached",
	"DispatchBeam",
	"SetHidden",
	"SetCollidable",
	"NetworkState",
	"StartFlying",
	"StopFlying",
	"SetDesiredAltitude",
	"TriggerRelay",
	"PreferredAreas",
	"AreasAround",
	"IsInPreferredArea",
	"RemoveGrenades",
	"EndStun",
	"RemoveCond",
	"RemoveEntity",
	"StartBossTimer",
	"PlayScriptedScene",
}

MODEL = "models/bots/merasmus/merasmus.mdl"
BOMB_MODEL = "models/props_lakeside_event/bomb_temp.mdl"
GRENADE_CLASS = "tf_projectile_pipe"
VORTEX_CLASS = "teleport_vortex"
PROP_CLASS = "tf_merasmus_trick_or_treat_prop"

-- s_pszDisguiseProps, as TF2 lists them (the palm tree twice).
PROP_MODELS = {
	"models/props_halloween/pumpkin_02.mdl",
	"models/props_halloween/pumpkin_03.mdl",
	"models/egypt/palm_tree/palm_tree.mdl",
	"models/props_spytech/control_room_console01.mdl",
	"models/props_spytech/work_table001.mdl",
	"models/props_coalmines/boulder1.mdl",
	"models/props_coalmines/boulder2.mdl",
	"models/props_farm/concrete_block001.mdl",
	"models/props_farm/welding_machine01.mdl",
	"models/props_medieval/medieval_resupply.mdl",
	"models/props_medieval/target/target.mdl",
	"models/props_swamp/picnic_table.mdl",
	"models/props_manor/baby_grand_01.mdl",
	"models/props_manor/bookcase_132_02.mdl",
	"models/props_manor/chair_01.mdl",
	"models/props_manor/couch_01.mdl",
	"models/props_manor/grandfather_clock_01.mdl",
	"models/props_viaduct_event/coffin_simple_closed.mdl",
	"models/props_2fort/miningcrate001.mdl",
	"models/props_gameplay/resupply_locker.mdl",
	"models/props_2fort/oildrum.mdl",
	"models/props_lakeside/wood_crate_01.mdl",
	"models/props_well/hand_truck01.mdl",
	"models/props_vehicles/mining_car_metal.mdl",
	"models/props_2fort/tire002.mdl",
	"models/props_well/computer_cart01.mdl",
	"models/egypt/palm_tree/palm_tree.mdl",
}

-- The logic_relays he triggers by name (CMerasmus::TriggerLogicRelay); the
-- entering one also moves him to it.
ENTER_RELAY = "boss_enter_relay"
DEAD_RELAY = "boss_dead_relay"
EXIT_RELAY = "boss_exit_relay"

-- His particle systems (halloween.pcf, and cinefx.pcf's debris), and the
-- list the npc controller precaches (the files: features/npc/sh.lua).
SPAWN_PARTICLE = "merasmus_spawn"
TELEPORT_PARTICLE = "merasmus_tp"
BLOOD_PARTICLE = "merasmus_blood"
BLOOD_BITS_PARTICLE = "merasmus_blood_bits"
AMBIENT_PARTICLE = "merasmus_ambient_body"
SHOOT_PARTICLE = "merasmus_shoot"
BOOK_PARTICLE = "merasmus_book_attack"
PROP_PARTICLE = "merasmus_object_spawn"
ZAP_PARTICLE = "merasmus_zap"
DAZED_PARTICLE = "merasmus_dazed"
BOMB_PARTICLE = "merasmus_dazed_explosion"
BOMB_HEAD_PARTICLE = "bombinomicon_burningdebris"
PARTICLES = {
	SPAWN_PARTICLE,
	TELEPORT_PARTICLE,
	BLOOD_PARTICLE,
	BLOOD_BITS_PARTICLE,
	AMBIENT_PARTICLE,
	SHOOT_PARTICLE,
	BOOK_PARTICLE,
	PROP_PARTICLE,
	ZAP_PARTICLE,
	DAZED_PARTICLE,
	BOMB_PARTICLE,
	BOMB_HEAD_PARTICLE,
}

-- The sound he floats with (a loop the binding plays), and a prop's when
-- it bursts.
FLOAT_SOUND = "Halloween.Merasmus_Float"
PROP_SOUND = "Halloween.Merasmus_Hiding_Explode"
PROP_LOOT_MODEL_SCALE = 1.4

-- The bomb rain's scripted scene, one of nine (CMerasmusAOEAttack: only
-- for its sound, as the animation does not work with the VCD). Each speaks
-- Halloween.BombSuperMove<n>, then Halloween.BombinomiconBombs at 4.2 s and
-- Halloween.MerasmusBombTaunt at 6 s (.devtools/bin/tf2_scene.py reads them
-- from TF2's scenes.image).
AOE_SCENE = "scenes/bot/merasmus/low/bomb_attack_00%d.vcd"
AOE_SCENE_COUNT = 9

STAFF_ATTACHMENT = "effect_staff"
HAND_ATTACHMENT = "effect_hand_R"
ROBE_ATTACHMENT = "effect_robe"
-- The staff bodygroup: shown, hidden for a taunt, away while throwing.
STAFF_SHOWN, STAFF_HIDDEN, STAFF_THROWING = 0, 1, 2
-- C_Merasmus::GetSkin: his plain skin while stunned or raining bombs.
SKIN_VULNERABLE, SKIN_NORMAL = 0, 1

FIRST_LEVEL = BossEvents.FIRST_LEVEL -- CMerasmus::m_level starts here
local FULL_TURN = 360
local PERCENT_ROLL_MAX = 100

-- Attack
LOOKAHEAD = 100
HOME_RECALC = 3
AT_HOME_RANGE = 50
STAND_AND_SWING_RANGE = 100
HOME_REPATH_AGE = 3
CHASE_REPATH_AGE = 1
OFF_MESH_TOLERANCE = 50
ATTACK_INTERVAL = 1
GRENADE_MIN, GRENADE_MAX = 2, 3
ZAP_MIN, ZAP_MAX = 3, 4
BOMB_HEAD_FIRST = 10
BOMB_HEAD_INTERVAL = 16 -- bomb heads last 15 s
STUCK_LIFT = 10

-- StaffAttack
STAFF_HIT_FRACTION = 0.5 -- of the swing
STAFF_CLOSE_RANGE = 100
HIT_ANGLE_SLOPE = 0.27
STAFF_REACH_FRACTION = 0.9 -- of the attack range
STAFF_DAMAGE = 70
STAFF_PUSH = 500
STAFF_LINE_ROLL_MAX = 2 -- a line at RandomInt( 0, 2 ) == 0
STAFF_RARE_ROLL_MAX = 5 -- rare at RandomInt( 1, 5 ) == 1

-- ThrowingGrenade and CreateMerasmusGrenade
RELEASE_DELAY = 0.25
THROW_SPEED_MIN, THROW_SPEED_MAX = 1500, 2000
THROW_LIFT = 200
THROW_SPREAD = 10
THROW_LINE_ROLL_MAX = 6 -- a line at RandomInt( 0, 6 ) == 0
THROW_RARE_ROLL_MAX = 10 -- rare at RandomInt( 1, 10 ) == 1
GRENADE_DAMAGE = 50
GRENADE_RADIUS = 300
GRENADE_FUSE = 2

-- Zap
ZAP_DELAY = 1.3
ZAP_RANGE = 600
ZAP_RANGE_PER_LEVEL = 50
ZAP_TARGETS = 6
ZAP_MAX_DAMAGE = 50
ZAP_MIN_DAMAGE = 20
ZAP_DAMAGE_PER_LEVEL = 5
ZAP_BURN = 5
ZAP_LIFT = 1000
ZAP_NEAR_SQR = 100 -- RemapValClamped's start, in squared units
SPELL_FIRE, SPELL_LAUNCH = 0, 1

-- Bomb heads and stuns
BOMB_HEAD_DAMAGE = 100 -- while Merasmus fights; 40 otherwise in TF2
BOMB_HEAD_RADIUS = 100
BOMB_HEAD_PUSH_RANGE = 150
BOMB_HEAD_PUSH_FORCE = 400
BOMB_SHAKE_AMPLITUDE, BOMB_SHAKE_FREQUENCY, BOMB_SHAKE_DURATION, BOMB_SHAKE_RADIUS = 15, 5, 2, 750
BOMB_REACH = 100 -- from a bomb head's eyes to his centre
STUN_BUFF = 10
STUN_PUSH = 300
HIT_RARE_ROLL = 9 -- rare at RandomInt( 1, 10 ) == 9
HIT_ROLL_MAX = 10
AOE_AFTER_HITS = 3
STUN_FINISH_PAD = 0.5

-- Teleport
TELEPORT_LIFT = 75
TELEPORT_AREA_SIZE = 100

-- AOEAttack
AOE_WARMUP = 4
AOE_FIRST_LAUNCH = 0.5
AOE_LAUNCH_INTERVAL = 2
AOE_RANGE = 400
MAX_BOMBS_PER_TICK = 4
BOMB_SCALE = 1
BOMB_VERTICAL_SPEED = 750
BOMB_START_HEIGHT = 150
BOMB_SPEED_MIN, BOMB_SPEED_MAX = 100, 2000
RING_COUNT = 2
RING_ANGLE_BASE, RING_ANGLE_SPREAD = 20, 30
SPOKE_ANGLE = 45
SPOKE_BOMBS = 4
SPOKES_BELOW = 50 -- spokes at RandomInt( 1, 100 ) < 50
AOE_ALTITUDE, AOE_BOB = 175, 25
WANDER_MIN, WANDER_MAX = 1, 3

-- Disguise and reveal
HIDING_AREA_SIZE = 150
MAX_PROPS = 10
PROP_SEPARATION = 500
FIND_PROPS_TIMEOUT = 3
FIND_RETRY = 1
HIDDEN_TAUNT_MIN, HIDDEN_TAUNT_MAX = 10, 25
HIDDEN_RARE_ROLL_MAX = 10 -- rare at RandomInt( 0, 10 ) == 0
PROP_TAUNT_ROLL_MAX = 3 -- a taunt at RandomInt( 1, 3 ) == 1
PROP_FORCE_KILL_DAMAGE = 99999
PROP_BLAST_MULTIPLE = 2
REVEAL_PUSH_RANGE = 400
REVEAL_PUSH_FORCE = 500
GRENADE_CLEAR_RANGE = 400

-- The boss timer (features.boss_timer.model): past the third level the next
-- Merasmus comes a minute after the last; the spawn reverts the point he
-- takes to neutral (SpawnHalloweenBoss, LAKESIDE).
STEADY_RESPAWN_LEVEL = 3
QUICK_RESPAWN_INTERVAL = 60
NEUTRALIZES_POINT = true
WAITS_FOR_WHEEL = true -- nor does he come while a Wheel of Fate is busy

-- Leaving: the seconds left at which merasmus_escape_warning fires, checked
-- nearest first, as CMerasmus::LeaveWarning does.
ESCAPE_WARNINGS = { 10, 30, 60 }
DEPART_RARE_ROLL_MAX = 10 -- rare at RandomInt( 0, 10 ) == 0

-- Death: who hit him this recently is named his killer (deathTime).
KILLER_WINDOW = 5

-------------------------------------------------------------------------------
-- His own rules

local function Forward(me)
	local yaw = rad(me:GetYaw())
	return me:Vector(cos(yaw), sin(yaw), 0)
end

local function Right(me)
	local yaw = rad(me:GetYaw())
	return me:Vector(sin(yaw), -cos(yaw), 0)
end

local function Up(me) return me:Vector(0, 0, 1) end

-- The nearest of targets by range (INextBot::GetRangeTo), or nil.
local function Nearest(me, targets)
	local nearest, nearestRange = nil, huge
	for _, t in ipairs(targets) do
		local range = me:RangeTo(t)
		if range < nearestRange then nearest, nearestRange = t, range end
	end
	return nearest
end

-- Up and away from `from`: flat towards their eyes, then straight up.
local function Away(me, from, t, force)
	local to = me:TargetEyes(t) - from
	local flat = me:Vector(to.x, to.y, 0):GetNormalized()
	return me:Vector(flat.x, flat.y, 1) * force
end

-- CMerasmus::PushPlayer
local function Push(me, t, force)
	me:ApplyImpulse(t, Away(me, me:GetAbsOrigin(), t, force))
end

-- CTFGameRules::PushAllPlayersAway; team nil means RED and BLU.
local function PushAllPlayersAway(me, from, range, force, team)
	for _, ply in ipairs(me:CollectPlayers(team)) do
		if (me:TargetEyes(ply) - from):Length() < range then me:ApplyImpulse(ply, Away(me, from, ply, force)) end
	end
end

local function RemapValClamped(value, a, b, c, d)
	local t = (value - a) / (b - a)
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	return c + (d - c) * t
end

-- The level every Merasmus shares (CMerasmus::m_level), from the variant's
-- shared table.
function SharedLevel(shared)
	if shared.level == nil then shared.level = FIRST_LEVEL end
	return shared.level
end

function Level(me) return SharedLevel(me:Shared()) end

-- CMerasmus::StartRespawnTimer and SpawnHalloweenBoss's LAKESIDE intervals.
function SpawnInterval(level, convars)
	if level <= STEADY_RESPAWN_LEVEL then
		return convars.tf_merasmus_spawn_interval, convars.tf_merasmus_spawn_interval_variation
	end
	return QUICK_RESPAWN_INTERVAL, 0
end

local function StartRespawnTimer(state, me)
	me:StartBossTimer(SpawnInterval(Level(me), state.convars))
end

local function ShowHealth(me)
	me:SetBossHealth(me:GetHealth() / me:GetMaxHealth())
end

local function HasStunTimer(state) return not state.stunTimer:IsElapsed() end
local function ShouldLeave(state) return state.lifeTimer:IsElapsed() end

-- CMerasmus::ShouldDisguise: he has lost too much since he was revealed.
local function ShouldDisguise(state, me)
	if me:GetHealth() <= 0 then return false end
	local lost = (state.revealedHealth - me:GetHealth()) / me:GetMaxHealth()
	return lost > state.convars.tf_merasmus_should_disguise_threshold
end

local function StartFlying(state, me)
	state.flying = true
	me:StartFlying()
end

local function StopFlying(state, me)
	state.flying = false
	me:StopFlying()
end

-- CMerasmus::LeaveWarning: each warning once, as the time left falls past it.
local function LeaveWarning(state, me)
	local remaining = state.lifeTimer:GetRemainingTime()
	for _, seconds in ipairs(ESCAPE_WARNINGS) do
		if remaining < seconds and state.lastWarnTime > seconds then
			me:FireGameEvent(BossEvents.MERASMUS_ESCAPE_WARNING, {
				level = Level(me),
				time_remaining = seconds,
			})
			break
		end
	end
	state.lastWarnTime = remaining
end

-- CMerasmus::CreateMerasmusGrenade: a bomb, owned by me, on a 2 s fuse.
local function CreateGrenade(state, me, pos, velocity, scale)
	return me:SpawnEntity(GRENADE_CLASS, {
		damage = GRENADE_DAMAGE * scale,
		radius = GRENADE_RADIUS * scale,
		team = state.team,
		attacker = me,
		launcher = me,
		velocity = velocity,
		fuse = GRENADE_FUSE,
		explodeOnTouch = false,
		model = BOMB_MODEL,
		scale = scale,
		particle = BOMB_PARTICLE,
	}, pos)
end

-------------------------------------------------------------------------------
-- Bomb heads (CMerasmus::BombHeadMode, CTFPlayerShared's
-- TF_COND_HALLOWEEN_BOMB_HEAD and CTFPlayer::MerasmusPlayerBombExplode).
-- state.bombHeads lists { player, ends }; the stamps of when each player
-- last had one outlive any one Merasmus, as TF2 keeps them on the player.

local function Stamps(me)
	local shared = me:Shared()
	if shared.bombHeadStamps == nil then shared.bombHeadStamps = {} end
	return shared.bombHeadStamps
end

local function BombHeadIndex(state, t)
	for i, bomb in ipairs(state.bombHeads) do
		if bomb.player == t then return i end
	end
	return nil
end

local function DropBombHead(state, me, index)
	local t = state.bombHeads[index].player
	for i = index, #state.bombHeads do state.bombHeads[i] = state.bombHeads[i + 1] end
	me:FireGameEvent(BossEvents.HALLOWEEN_BOMB_HEAD, {
		player = t,
		duration = 0,
	})
	return t
end

-- MerasmusPlayerBombExplode: a blast at their head, theirs. Unless they
-- are dead (bExcludeMe) it hurts them too; the combat controller spares a
-- blast's own attacker, so their share is dealt here, as the Explosion
-- reckons it.
local function PlayerBombExplode(me, t, hurtsCarrier)
	local eyes = me:TargetEyes(t)
	local blast = {
		origin = eyes,
		radius = BOMB_HEAD_RADIUS,
		damage = BOMB_HEAD_DAMAGE,
		attackerTeam = me:TeamOf(t),
		attacker = t,
		halfFalloff = false,
		forceFriendlyFire = false,
		crit = false,
	}
	me:Explode(blast)
	me:ScreenShake(eyes, BOMB_SHAKE_AMPLITUDE, BOMB_SHAKE_FREQUENCY, BOMB_SHAKE_DURATION, BOMB_SHAKE_RADIUS)
	if not hurtsCarrier then return end
	local explosion = Combat.Explosion.New(blast)
	local own = explosion:DamageTo({
		team = blast.attackerTeam,
		isAttacker = true,
		distance = explosion:DistanceTo(me:TargetCenter(t), me:TargetOrigin(t), false),
		visible = true,
	})
	if own then me:DealDamage(t, own, Actor.DMG_BLAST, t) end
end

-- OnRemoveHalloweenBombHead: the bomb comes off a living player and blows,
-- throwing everyone near it.
local function RemoveBombHead(state, me, index)
	local t = DropBombHead(state, me, index)
	me:RemoveCond(t, Players.COND.HALLOWEEN_BOMB_HEAD)
	if not me:IsTargetAlive(t) then return t end
	PlayerBombExplode(me, t, true)
	local origin = me:TargetOrigin(t)
	PushAllPlayersAway(me, origin, BOMB_HEAD_PUSH_RANGE, BOMB_HEAD_PUSH_FORCE, nil)
	me:DispatchParticleEffect(BOMB_HEAD_PARTICLE, origin)
	return t
end

-- BombHeadForTeam: the living players of the team who have gone longest
-- without a bomb and stand in a preferred area.
local function BombHeadForTeam(state, me, team)
	local players = me:CollectPlayers(team)
	if #players == 0 then return end
	local cv, stamps, now = state.convars, Stamps(me), me:Now()
	local duration = cv.tf_merasmus_bomb_head_duration
	for _ = 1, cv.tf_merasmus_bomb_head_per_team do
		local victim, oldest = nil, -1
		for _, ply in ipairs(players) do
			local since = now - (stamps[ply] or 0)
			if since > oldest and BombHeadIndex(state, ply) == nil and me:IsInPreferredArea(ply) then
				victim, oldest = ply, since
			end
		end
		if victim == nil then return end
		me:StunPlayer(victim, duration, 0, Players.STUN.LOSER_STATE)
		me:AddCond(victim, Players.COND.HALLOWEEN_BOMB_HEAD, duration)
		me:AddCond(victim, Players.COND.SPEED_BOOST, duration)
		stamps[victim] = now
		state.bombHeads[#state.bombHeads + 1] = {
			player = victim,
			ends = now + duration,
		}
		me:FireGameEvent(BossEvents.HALLOWEEN_BOMB_HEAD, {
			player = victim,
			duration = duration,
		})
	end
end

local function BombHeadMode(state, me)
	BombHeadForTeam(state, me, Teams.RED)
	BombHeadForTeam(state, me, Teams.BLUE)
end

-- CMerasmus::AddStun: a bomb head reached me. They are freed and rewarded,
-- the bomb blows on me, and I am stunned (not while raining bombs).
local function AddStun(state, me, index)
	local t = state.bombHeads[index].player
	if not state.stunned then
		local rare = me:RandomInt(1, HIT_ROLL_MAX) == HIT_RARE_ROLL
		me:PlayLowPrioritySound(rare and "Halloween.MerasmusHitByBombRare" or "Halloween.MerasmusHitByBomb")
	end
	me:AddCond(t, Players.COND.CRITBOOSTED_PUMPKIN, STUN_BUFF)
	me:AddCond(t, Players.COND.SPEED_BOOST, STUN_BUFF)
	me:AddCond(t, Players.COND.INVULNERABLE, STUN_BUFF)
	me:EndStun(t)
	RemoveBombHead(state, me, index)
	PlayerBombExplode(me, t, true)
	Push(me, t, STUN_PUSH)
	me:DispatchParticleEffect(BOMB_PARTICLE, me:WorldSpaceCenter())
	if not state.aoe then
		state.bombHitCount = state.bombHitCount + 1
		state.stunTimer:Start(state.convars.tf_merasmus_stun_duration)
	end
end

-- Each tick: a dead bomb head's bomb blows; a bomb whose time is up comes
-- off and blows; one who reaches the revealed Merasmus stuns him.
local function UpdateBombHeads(state, me)
	local now, center = me:Now(), me:WorldSpaceCenter()
	local i = 1
	while i <= #state.bombHeads do
		local bomb = state.bombHeads[i]
		local t = bomb.player
		if not me:IsTargetValid(t) then
			DropBombHead(state, me, i)
		elseif not me:IsTargetAlive(t) then
			DropBombHead(state, me, i)
			PlayerBombExplode(me, t, false)
		elseif now >= bomb.ends then
			RemoveBombHead(state, me, i)
		elseif state.revealed and (me:TargetEyes(t) - center):Length() < BOMB_REACH then
			AddStun(state, me, i)
		else
			i = i + 1
		end
	end
end

-------------------------------------------------------------------------------
-- Props (CTFMerasmusTrickOrTreatProp)

-- OnTakeDamage: a soldier's or demoman's blast (in GMod, any player's
-- blast) destroys a prop at once.
function PropDamage(amount, playerBlast, propHealth)
	if playerBlast then return propHealth * PROP_BLAST_MULTIPLE end
	return amount
end

local function RemoveAllFakeProps(state, me)
	for _, prop in ipairs(state.props) do
		if me:IsTargetValid(prop) then me:RemoveEntity(prop) end
	end
	state.props = {}
	state.killedProps = {}
	state.destroyedProps = 0
end

-- CMerasmus::OnRevealed: out of hiding, solid, the props gone, everyone
-- near thrown back, and whoever found him rewarded.
local function OnRevealed(state, me, playSound)
	state.revealed = true
	state.hiding = false
	state.revealedHealth = me:GetHealth()
	if playSound then me:PlayHighPrioritySound("Halloween.MerasmusDiscovered") end
	me:SetHidden(false)
	me:DispatchParticleEffect(SPAWN_PARTICLE, me:WorldSpaceCenter())
	me:SetCollidable(true)
	RemoveAllFakeProps(state, me)
	local origin = me:GetAbsOrigin()
	PushAllPlayersAway(me, origin, REVEAL_PUSH_RANGE, REVEAL_PUSH_FORCE, Teams.RED)
	PushAllPlayersAway(me, origin, REVEAL_PUSH_RANGE, REVEAL_PUSH_FORCE, Teams.BLUE)
	me:RemoveGrenades(origin, GRENADE_CLEAR_RANGE)
	local finder = state.revealer
	if finder ~= nil then
		me:AddCond(finder, Players.COND.CRITBOOSTED_PUMPKIN, STUN_BUFF)
		me:AddCond(finder, Players.COND.SPEED_BOOST, STUN_BUFF)
		me:AddCond(finder, Players.COND.INVULNERABLE, STUN_BUFF)
	end
	state.revealer = nil
	ShowHealth(me)
	local close = Nearest(me, me:CollectPlayers(nil))
	if close then
		local to = me:TargetOrigin(close) - origin
		me:SetYaw(deg(atan2(to.y, to.x)))
	else
		me:SetYaw(me:RandomFloat(0, FULL_TURN))
	end
end

-- CMerasmus::OnDisguise
local function OnDisguise(state, me)
	state.revealed = false
	state.hiding = true
	state.aoe = false
	me:SetHidden(true)
	me:DispatchParticleEffect(TELEPORT_PARTICLE, me:WorldSpaceCenter())
	me:SetCollidable(false)
	local count = #state.props
	local fewest = max(1, floor(state.convars.tf_merasmus_min_props_to_reveal * count))
	state.toReveal = me:RandomInt(fewest, count)
end

-- SelectSeparatedShuffleSet: shuffled, then each kept unless it is near an
-- area before it in the shuffle (kept or not).
local function SeparatedShuffle(me, areas, maxCount, minSeparation)
	local shuffled = {}
	for i, area in ipairs(areas) do shuffled[i] = area end
	local n = #shuffled
	while n > 1 do
		local k = me:RandomInt(1, n)
		shuffled[n], shuffled[k] = shuffled[k], shuffled[n]
		n = n - 1
	end
	local kept = {}
	for i, area in ipairs(shuffled) do
		local near = false
		for j = 1, i - 1 do
			if (area - shuffled[j]):Length() < minSeparation then near = true end
		end
		if not near then
			kept[#kept + 1] = area
			if #kept >= maxCount then break end
		end
	end
	return kept
end

-------------------------------------------------------------------------------
-- The bomb rain's patterns (QueueBombRingsForLaunch, QueueBombSpokesForLaunch):
-- velocities from his facing.

function BombRings(yaw, vector)
	local velocities = {}
	local deltaSpeed = BOMB_SPEED_MAX - BOMB_SPEED_MIN
	for r = 1, RING_COUNT do
		local u = r / RING_COUNT
		local speed = BOMB_SPEED_MIN + u * deltaSpeed
		local step = RING_ANGLE_BASE + RING_ANGLE_SPREAD * (1 - u)
		local angle = 0
		while angle < FULL_TURN do
			local a = rad(yaw)
			velocities[#velocities + 1] = vector(speed * cos(a), speed * sin(a), BOMB_VERTICAL_SPEED)
			yaw = yaw + step
			angle = angle + step
		end
	end
	return velocities
end

function BombSpokes(yaw, vector)
	local velocities = {}
	local deltaSpeed = BOMB_SPEED_MAX - BOMB_SPEED_MIN
	local angle = 0
	while angle < FULL_TURN do
		local a = rad(yaw)
		for i = 1, SPOKE_BOMBS do
			local speed = BOMB_SPEED_MIN + (i / SPOKE_BOMBS) * deltaSpeed
			velocities[#velocities + 1] = vector(speed * cos(a), speed * sin(a), BOMB_VERTICAL_SPEED)
		end
		yaw = yaw + SPOKE_ANGLE
		angle = angle + SPOKE_ANGLE
	end
	return velocities
end

-- CMerasmus::Update: his wounds show as health falls; the clients get his
-- skin and the state their effects follow; the bomb heads tick (in TF2,
-- the players' own condition think). It runs every tick whatever he does:
-- from the top action, and from the actions that suspend or replace it.
local function Think(state, me)
	me:SetPoseParameter("damage", 1 - me:GetHealth() / me:GetMaxHealth())
	local skin = (state.aoe or state.stunned) and SKIN_VULNERABLE or SKIN_NORMAL
	if skin ~= state.skin then
		state.skin = skin
		me:SetSkin(skin)
	end
	me:NetworkState(state.revealed, state.aoe, state.stunned)
	UpdateBombHeads(state, me)
end


-------------------------------------------------------------------------------
-- Actions

local Reveal = NpcSystem.Action:Extend("Reveal")
local Attack = NpcSystem.Action:Extend("Attack")
local StaffAttack = NpcSystem.Action:Extend("StaffAttack")
local ThrowingGrenade = NpcSystem.Action:Extend("ThrowingGrenade")
local Zap = NpcSystem.Action:Extend("Zap")
local Stunned = NpcSystem.Action:Extend("Stunned")
local Teleport = NpcSystem.Action:Extend("Teleport")
local AOEAttack = NpcSystem.Action:Extend("AOEAttack")
local Disguise = NpcSystem.Action:Extend("Disguise")
local Escape = NpcSystem.Action:Extend("Escape")
local Dying = NpcSystem.Action:Extend("Dying")

local function StateAction(class)
	function class:Init(state) self.state = state end
end

for _, class in ipairs({ Reveal, Attack, Zap, Stunned, AOEAttack, Disguise, Escape, Dying }) do
	StateAction(class)
end

-- Chase t along path when out of reach or out of sight, and face it.
local function Pursue(me, path, t)
	if me:IsRangeGreaterThan(t, STAND_AND_SWING_RANGE) or not me:IsLineOfSightClear(t) then
		if path:GetAge() > CHASE_REPATH_AGE then path:Compute(me:TargetOrigin(t)) end
		path:Update()
	end
	me:FaceTowards(me:TargetCenter(t))
end

-------------------------------------------------------------------------------
-- Reveal (CMerasmusReveal)

function Reveal:OnStart(me, priorAction)
	OnRevealed(self.state, me, false)
	me:StartActivity(me:Activity("ACT_SHIELD_UP"))
	return self:Continue()
end

function Reveal:Update(me, interval)
	if me:IsActivityFinished() then return self:ChangeTo(Attack:New(self.state), "Here I come!") end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- Attack (CMerasmusAttack)

function Attack:OnStart(me, priorAction)
	self.path = me:NewPath()
	self.path:SetMinLookAheadDistance(LOOKAHEAD)
	me:StartActivity(me:Activity("ACT_MP_RUN_ITEM1"))
	me:SetDesiredSpeed(self.state.convars.tf_merasmus_speed)
	self.attackTimer = NpcSystem.CountdownTimer(me)
	self.attackTarget = nil
	self.focusTimer = NpcSystem.CountdownTimer(me)
	self.focusTimer:Start(0)
	self.grenadeTimer = NpcSystem.CountdownTimer(me)
	self.grenadeTimer:Start(me:RandomFloat(GRENADE_MIN, GRENADE_MAX))
	self.zapTimer = NpcSystem.CountdownTimer(me)
	self.zapTimer:Start(me:RandomFloat(ZAP_MIN, ZAP_MAX))
	self.home = me:GetAbsOrigin()
	self.homeRecalcTimer = NpcSystem.CountdownTimer(me)
	self.homeRecalcTimer:Start(HOME_RECALC)
	self.bombHeadTimer = NpcSystem.CountdownTimer(me)
	self.bombHeadTimer:Start(BOMB_HEAD_FIRST)
	return self:Continue()
end

-- IsPotentiallyChaseable: alive, reachable (not in a spawn room; on the
-- mesh while standing), not invulnerable, and not too far from home.
function Attack:IsPotentiallyChaseable(me, victim)
	if victim == nil or not me:IsTargetValid(victim) or not me:IsTargetAlive(victim) then return false end
	if me:InRespawnRoom(victim) then return false end
	local tolerance = me:IsTargetOnGround(victim) and OFF_MESH_TOLERANCE or huge
	if not me:IsOnNavMesh(victim, tolerance) then return false end
	if me:IsInvulnerable(victim) then return false end
	return (self.home - me:TargetOrigin(victim)):Length() <= self.state.convars.tf_merasmus_chase_range
end

-- SelectVictim: keep the victim while the focus lasts; then the nearest.
function Attack:SelectVictim(me)
	if self:IsPotentiallyChaseable(me, self.attackTarget) and not self.focusTimer:IsElapsed() then return end
	local newVictim, victimRange = nil, huge
	for _, ply in ipairs(me:CollectPlayers(nil)) do
		if self:IsPotentiallyChaseable(me, ply) then
			local range = me:RangeTo(ply)
			if range < victimRange then newVictim, victimRange = ply, range end
		end
	end
	if newVictim then self.focusTimer:Start(self.state.convars.tf_merasmus_chase_duration) end
	self.attackTarget = newVictim
end

-- RecomputeHomePosition: the first point of the round that BLU does not
-- own and may capture; failing that, the last point the loop looked at.
function Attack:RecomputeHomePosition(me)
	if not self.homeRecalcTimer:IsElapsed() then return end
	self.homeRecalcTimer:Reset()
	local contested = nil
	for _, point in ipairs(me:ControlPoints()) do
		contested = point
		if point.inRound and point.owner ~= Teams.BLUE and point.blueMayCapture then break end
	end
	if contested then self.home = contested.origin end
end

function Attack:Move(me)
	local path = self.path
	local victim = self.attackTarget
	if victim == nil then
		if me:IsRangeGreaterThan(self.home, AT_HOME_RANGE) then
			if path:GetAge() > HOME_REPATH_AGE then path:Compute(self.home) end
			path:Update()
		end
		return
	end
	if me:IsRangeGreaterThan(victim, STAND_AND_SWING_RANGE) or not me:IsLineOfSightClear(victim) then
		if path:GetAge() > CHASE_REPATH_AGE then path:Compute(me:TargetOrigin(victim)) end
		path:Update()
	end
end

function Attack:Update(me, interval)
	local state = self.state
	if not me:IsAlive() then return self:Done() end
	if HasStunTimer(state) then return self:SuspendFor(Stunned:New(state), "Stunned!") end
	self:SelectVictim(me)
	self:RecomputeHomePosition(me)
	self:Move(me)

	if self.bombHeadTimer:IsElapsed() then
		self.bombHeadTimer:Start(BOMB_HEAD_INTERVAL)
		BombHeadMode(state, me)
	end

	local target = self.attackTarget
	if target ~= nil and me:IsTargetAlive(target) then
		if self.zapTimer:IsElapsed() then
			self.zapTimer:Start(me:RandomFloat(ZAP_MIN, ZAP_MAX))
			return self:SuspendFor(Zap:New(state), "Zap!")
		end
		if me:IsRangeLessThan(target, state.convars.tf_merasmus_attack_range) then
			if self.attackTimer:IsElapsed() then
				self.attackTimer:Start(ATTACK_INTERVAL)
				return self:SuspendFor(StaffAttack:New(state, target), "Whack!")
			end
			me:FaceTowards(me:TargetCenter(target))
		end
		if self.grenadeTimer:IsElapsed() then
			self.grenadeTimer:Start(me:RandomFloat(GRENADE_MIN, GRENADE_MAX))
			return self:SuspendFor(ThrowingGrenade:New(state, target), "Fire in the hole!")
		end
	end

	local run = me:Activity("ACT_MP_RUN_MELEE")
	if not me:IsActivity(run) then me:StartActivity(run) end
	return self:Continue()
end

-- Stuck: warp to where the path was heading.
function Attack:OnStuck(me)
	local goal = self.path:GetCurrentGoalPos()
	if goal then me:SetAbsOrigin(goal + me:Vector(0, 0, STUCK_LIFT)) end
	return self:TryContinue()
end

-- A living player who bumps into him becomes his victim for a while.
function Attack:OnContact(me, other)
	if me:IsTargetValid(other) and HalloweenBoss.IsPlayer(me, other) then
		self.attackTarget = other
		self.focusTimer:Start(self.state.convars.tf_merasmus_chase_duration)
	end
	return self:TryContinue()
end

-------------------------------------------------------------------------------
-- StaffAttack (CMerasmusStaffAttack)

function StaffAttack:Init(state, target)
	self.state = state
	self.target = target
end

function StaffAttack:OnStart(me, priorAction)
	self.path = me:NewPath()
	self.path:SetMinLookAheadDistance(LOOKAHEAD)
	local duration = me:AddTimedGesture(me:Activity("ACT_MP_ATTACK_STAND_MELEE"))
	self.swingTimer = NpcSystem.CountdownTimer(me)
	self.swingTimer:Start(duration)
	self.hitTimer = NpcSystem.CountdownTimer(me)
	self.hitTimer:Start(STAFF_HIT_FRACTION * duration)
	if me:RandomInt(0, STAFF_LINE_ROLL_MAX) == 0 then
		local rare = me:RandomInt(1, STAFF_RARE_ROLL_MAX) == 1
		me:PlayLowPrioritySound(rare and "Halloween.MerasmusStaffAttackRare" or "Halloween.MerasmusStaffAttack")
	end
	return self:Continue()
end

-- The cone widens as the victim comes closer; the reach is 0.9 of the
-- attack range.
function StaffAttack:Hit(me, t)
	local attackRange = self.state.convars.tf_merasmus_attack_range
	local toVictim = (me:TargetCenter(t) - me:WorldSpaceCenter()):GetNormalized()
	local range = me:RangeTo(t)
	local closeness = 0
	if range >= STAFF_CLOSE_RANGE then closeness = (range - STAFF_CLOSE_RANGE) / (attackRange - STAFF_CLOSE_RANGE) end
	if Forward(me):Dot(toVictim) <= closeness * HIT_ANGLE_SLOPE then return end
	if not me:IsRangeLessThan(t, STAFF_REACH_FRACTION * attackRange) then return end
	if not me:IsLineOfSightClear(t) then return end
	me:DealDamage(t, STAFF_DAMAGE, Actor.DMG_CLUB)
	me:PlayLowPrioritySound("Halloween.HeadlessBossAxeHitFlesh")
	Push(me, t, STAFF_PUSH)
end

function StaffAttack:Update(me, interval)
	if HasStunTimer(self.state) then return self:ChangeTo(Stunned:New(self.state), "Stun Interupt!") end
	local t = self.target
	local valid = t ~= nil and me:IsTargetValid(t)
	if self.hitTimer:HasStarted() and self.hitTimer:IsElapsed() then
		self.hitTimer:Invalidate()
		if valid then self:Hit(me, t) end
	end
	if valid then Pursue(me, self.path, t) end
	if self.swingTimer:IsElapsed() then return self:Done() end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- ThrowingGrenade (CMerasmusThrowingGrenade)

function ThrowingGrenade:Init(state, target)
	self.state = state
	self.target = target
end

-- Out of sight, the bomb goes to a random other player in sight, if any.
function ThrowingGrenade:OnStart(me, priorAction)
	local t = self.target
	if t == nil or not me:IsTargetValid(t) then return self:Done("No Target") end
	if not me:IsLineOfSightClear(t) then
		local inSight = {}
		for _, ply in ipairs(me:CollectPlayers(nil)) do
			if ply ~= t and me:IsLineOfSightClear(ply) then inSight[#inSight + 1] = ply end
		end
		t = nil
		if #inSight > 0 then t = inSight[me:RandomInt(1, #inSight)] end
	end
	self.target = t
	if t == nil then return self:Done("No Target") end
	me:FaceTowards(me:TargetCenter(t))
	local duration = me:AddTimedGesture(me:Activity("ACT_MP_ATTACK_STAND_ITEM1"))
	self.throwTimer = NpcSystem.CountdownTimer(me)
	self.throwTimer:Start(duration)
	self.releaseTimer = NpcSystem.CountdownTimer(me)
	self.releaseTimer:Start(RELEASE_DELAY)
	me:SetStaff(STAFF_THROWING)
	self.path = me:NewPath()
	self.path:SetMinLookAheadDistance(LOOKAHEAD)
	return self:Continue()
end

function ThrowingGrenade:Release(me)
	me:DispatchParticleAttached(SHOOT_PARTICLE, HAND_ATTACHMENT)
	local pos = me:AttachmentPosition(HAND_ATTACHMENT)
	local up = Up(me)
	local speed = me:RandomFloat(THROW_SPEED_MIN, THROW_SPEED_MAX)
	local velocity = Forward(me) * speed + up * THROW_LIFT
		+ Right(me) * me:RandomFloat(-THROW_SPREAD, THROW_SPREAD) + up * me:RandomFloat(-THROW_SPREAD, THROW_SPREAD)
	CreateGrenade(self.state, me, pos, velocity, BOMB_SCALE)
	if me:RandomInt(0, THROW_LINE_ROLL_MAX) == 0 then
		local rare = me:RandomInt(1, THROW_RARE_ROLL_MAX) == 1
		me:PlayLowPrioritySound(rare and "Halloween.MerasmusGrenadeThrowRare" or "Halloween.MerasmusGrenadeThrow")
	end
end

function ThrowingGrenade:Update(me, interval)
	if HasStunTimer(self.state) then return self:ChangeTo(Stunned:New(self.state), "Stun Interupt!") end
	if self.releaseTimer:HasStarted() and self.releaseTimer:IsElapsed() then
		self.releaseTimer:Invalidate()
		self:Release(me)
	end
	local t = self.target
	if me:IsTargetValid(t) then Pursue(me, self.path, t) end
	if self.throwTimer:IsElapsed() then return self:Done("Fire in the hole!") end
	return self:Continue()
end

function ThrowingGrenade:OnEnd(me, nextAction)
	me:SetStaff(STAFF_SHOWN)
end

-------------------------------------------------------------------------------
-- Zap (CMerasmusZap, CMerasmus::Zap, CollectTargets, CastSpell)

function Zap:OnStart(me, priorAction)
	me:StartActivity(me:Activity("ACT_RANGE_ATTACK2"))
	self.zapTimer = NpcSystem.CountdownTimer(me)
	self.zapTimer:Start(ZAP_DELAY)
	local spell = me:RandomInt(SPELL_FIRE, SPELL_LAUNCH)
	me:PlayLowPrioritySound(spell == SPELL_FIRE and "Halloween.MerasmusCastFireSpell" or "Halloween.MerasmusLaunchSpell")
	return self:Continue()
end

-- CollectTargets: the living players near my eyes and in sight, picked at
-- random up to the count.
local function CollectTargets(me, range, count)
	local eyes = me:EyePosition()
	local candidates = {}
	for _, ply in ipairs(me:CollectPlayers(nil)) do
		if (eyes - me:TargetCenter(ply)):Length() < range and me:IsLineOfSightClear(ply) then
			candidates[#candidates + 1] = ply
		end
	end
	local targets = {}
	while #candidates > 0 and #targets ~= count do
		local which = me:RandomInt(1, #candidates)
		targets[#targets + 1] = candidates[which]
		candidates[which] = candidates[#candidates]
		candidates[#candidates] = nil
	end
	return targets
end

-- CastSpell: set alight, flung up, hurt more the closer to my eyes, and a
-- zap from the staff to their eyes.
local function CastSpell(me, t, range, minDamage, maxDamage)
	me:AddCond(t, Players.COND.BURNING, ZAP_BURN)
	me:ApplyImpulse(t, me:Vector(0, 0, ZAP_LIFT))
	local to = me:EyePosition() - me:TargetCenter(t)
	local halfRange = 0.5 * range
	local damage = RemapValClamped(to:Dot(to), ZAP_NEAR_SQR, halfRange * halfRange, maxDamage, minDamage)
	me:DealDamage(t, damage, Actor.DMG_BURN)
	me:DispatchBeam(ZAP_PARTICLE, STAFF_ATTACHMENT, me:TargetEyes(t))
end

function Zap:Update(me, interval)
	if HasStunTimer(self.state) then return self:ChangeTo(Stunned:New(self.state), "Stun Interupt!") end
	if self.zapTimer:HasStarted() and self.zapTimer:IsElapsed() then
		self.zapTimer:Invalidate()
		local past = Level(me) - FIRST_LEVEL
		local range = ZAP_RANGE + ZAP_RANGE_PER_LEVEL * past
		local maxDamage = ZAP_MAX_DAMAGE + ZAP_DAMAGE_PER_LEVEL * past
		local minDamage = ZAP_MIN_DAMAGE + ZAP_DAMAGE_PER_LEVEL * past
		local targets = CollectTargets(me, range, ZAP_TARGETS + past)
		for _, t in ipairs(targets) do CastSpell(me, t, range, minDamage, maxDamage) end
		if #targets > 0 then me:EmitSound("Halloween.Merasmus_Spell") end
	end
	if me:IsActivityFinished() then return self:Done("Zapped!") end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- Stunned (CMerasmusStunned): he reels while the stun lasts, then
-- teleports, to the bomb rain after the third hit.

local STUN_BEGIN, STUN_MID, STUN_END = 0, 1, 2

function Stunned:OnStart(me, priorAction)
	self.stage = STUN_BEGIN
	self.animationTimer = NpcSystem.CountdownTimer(me)
	self.animationTimer:Start(me:AddTimedGesture(me:Activity("ACT_MP_STUN_BEGIN")))
	self.finishTimer = NpcSystem.CountdownTimer(me)
	me:EmitSound("Halloween.Merasmus_Stun")
	self.state.stunned = true
	return self:Continue()
end

function Stunned:Update(me, interval)
	local state = self.state
	if self.stage == STUN_END and self.finishTimer:IsElapsed() then
		if ShouldDisguise(state, me) then return self:Done() end
		if state.bombHitCount >= AOE_AFTER_HITS then
			return self:ChangeTo(Teleport:New(state, true, true), "Teleport AOE!")
		end
		return self:ChangeTo(Teleport:New(state, false, false), "Teleport to new area!")
	end
	if self.animationTimer:IsElapsed() then
		local stunned = HasStunTimer(state)
		if stunned then self.stage = STUN_BEGIN end
		if self.stage == STUN_BEGIN then
			self.animationTimer:Start(me:AddTimedGesture(me:Activity("ACT_MP_STUN_MIDDLE")))
			if not stunned then self.stage = STUN_MID end
		elseif self.stage == STUN_MID then
			local duration = me:AddTimedGesture(me:Activity("ACT_MP_STUN_END"))
			self.animationTimer:Start(duration)
			self.stage = STUN_END
			self.finishTimer:Start(duration + STUN_FINISH_PAD)
		end
	end
	return self:Continue()
end

function Stunned:OnEnd(me, nextAction)
	self.state.stunTimer:Invalidate()
	self.state.stunned = false
end

-------------------------------------------------------------------------------
-- Teleport (CMerasmusTeleport)

local TELEPORTING_OUT, TELEPORTING_IN, TELEPORT_DONE = 0, 1, 2

function Teleport:Init(state, aoe, toCap)
	self.state = state
	self.aoe = aoe
	self.toCap = toCap
end

function Teleport:OnStart(me, priorAction)
	self.phase = TELEPORTING_OUT
	me:StartActivity(me:Activity("ACT_SHIELD_DOWN"))
	return self:Continue()
end

-- Home, raised, for the bomb rain; otherwise a random free preferred area.
function Teleport:Destination(me)
	local home = self.state.home + me:Vector(0, 0, TELEPORT_LIFT)
	if self.toCap then return home end
	local areas = me:PreferredAreas(TELEPORT_AREA_SIZE)
	if #areas == 0 then return home end
	return areas[me:RandomInt(1, #areas)]
end

function Teleport:Update(me, interval)
	if not me:IsActivityFinished() then return self:Continue() end
	if self.phase == TELEPORTING_OUT then
		me:DispatchParticleEffect(TELEPORT_PARTICLE, me:WorldSpaceCenter())
		me:SetHidden(true)
		me:SetAbsOrigin(self:Destination(me))
		self.phase = TELEPORTING_IN
	elseif self.phase == TELEPORTING_IN then
		me:SetHidden(false)
		me:DispatchParticleEffect(TELEPORT_PARTICLE, me:WorldSpaceCenter())
		me:StartActivity(me:Activity("ACT_SHIELD_UP"))
		self.phase = TELEPORT_DONE
	else
		if self.aoe then
			self.aoe = false
			return self:SuspendFor(AOEAttack:New(self.state), "AOE Attack!")
		end
		return self:Done()
	end
	return self:Continue()
end

-------------------------------------------------------------------------------
-- AOEAttack (CMerasmusAOEAttack): aloft over the first control point, he
-- rains rings or spokes of bombs every 2 s, a few each tick.

local AOE_BEGIN, AOE_FIRING = 0, 1

function AOEAttack:OnStart(me, priorAction)
	self.startTimer = NpcSystem.CountdownTimer(me)
	self.startTimer:Start(AOE_WARMUP)
	self.launchTimer = NpcSystem.CountdownTimer(me)
	self.wanderTimer = NpcSystem.CountdownTimer(me)
	self.phase = AOE_BEGIN
	self.pending = {}
	self.wanderArea = nil
	StartFlying(self.state, me)
	local point = me:ControlPoints()[1]
	if point == nil then return self:Done("No control point!") end
	self.areas = me:AreasAround(point.origin, AOE_RANGE)
	if #self.areas == 0 then return self:Done("No nav areas near control point!") end
	me:StartActivity(me:Activity("ACT_RANGE_ATTACK1"))
	me:PlayScriptedScene(format(AOE_SCENE, me:RandomInt(1, AOE_SCENE_COUNT)))
	return self:Continue()
end

function AOEAttack:Queue(me)
	local yaw = me:GetYaw()
	local function vector(x, y, z) return me:Vector(x, y, z) end
	if me:RandomInt(1, PERCENT_ROLL_MAX) < SPOKES_BELOW then
		self.pending = BombSpokes(yaw, vector)
	else
		self.pending = BombRings(yaw, vector)
	end
end

function AOEAttack:LaunchPending(me)
	local count = min(#self.pending, MAX_BOMBS_PER_TICK)
	local from = me:WorldSpaceCenter() + me:Vector(0, 0, BOMB_START_HEIGHT)
	for _ = 1, count do
		local velocity = self.pending[1]
		for i = 1, #self.pending do self.pending[i] = self.pending[i + 1] end
		CreateGrenade(self.state, me, from, velocity, BOMB_SCALE)
	end
end

function AOEAttack:Wander(me)
	if self.wanderTimer:IsElapsed() or self.wanderArea == nil then
		self.wanderTimer:Start(me:RandomFloat(WANDER_MIN, WANDER_MAX))
		self.wanderArea = self.areas[me:RandomInt(1, #self.areas)]
	end
	local spot = me:Vector(self.wanderArea.x, self.wanderArea.y, me:GetAbsOrigin().z)
	me:Approach(spot)
	me:FaceTowards(spot)
end

function AOEAttack:Update(me, interval)
	local state = self.state
	if me:IsActivityFinished() then
		state.aoe = false
		return self:Done()
	end
	if self.phase == AOE_BEGIN then
		if self.startTimer:IsElapsed() then
			self.launchTimer:Start(AOE_FIRST_LAUNCH)
			self.phase = AOE_FIRING
		end
		return self:Continue()
	end
	state.aoe = true
	me:SetDesiredAltitude(AOE_ALTITUDE + AOE_BOB * cos(me:Now()))
	if self.launchTimer:IsElapsed() then
		self:Queue(me)
		self.launchTimer:Start(AOE_LAUNCH_INTERVAL)
	end
	self:LaunchPending(me)
	self:Wander(me)
	return self:Continue()
end

function AOEAttack:OnEnd(me, nextAction)
	StopFlying(self.state, me)
	me:SetStaff(STAFF_SHOWN)
	self.state.bombHitCount = 0
end

-------------------------------------------------------------------------------
-- Disguise (CMerasmusDisguise): he hides among props on separated
-- preferred areas until the players smash enough of them, or his time is up.

function Disguise:OnStart(me, priorAction)
	self.spawned = false
	self.findFailTimer = NpcSystem.CountdownTimer(me)
	self.retryTimer = NpcSystem.CountdownTimer(me)
	self:TryToDisguiseSpawn(me)
	self.regenStart = me:Now()
	self.regenHealth = me:GetHealth()
	me:PlayHighPrioritySound("Halloween.MerasmusInitiateHiding")
	self.tauntTimer = NpcSystem.CountdownTimer(me)
	self.tauntTimer:Start(me:RandomFloat(HIDDEN_TAUNT_MIN, HIDDEN_TAUNT_MAX))
	self.findFailTimer:Start(FIND_PROPS_TIMEOUT)
	return self:Continue()
end

-- TryToDisguiseSpawn: a prop on each of up to 10 separated, big, free
-- preferred areas, then into hiding.
function Disguise:TryToDisguiseSpawn(me)
	local state = self.state
	self.retryTimer:Start(FIND_RETRY)
	local candidates = me:PreferredAreas(HIDING_AREA_SIZE)
	if #candidates == 0 then return end
	local spots = SeparatedShuffle(me, candidates, MAX_PROPS, PROP_SEPARATION)
	if #spots == 0 then return end
	for _ = 1, #spots do
		local which = me:RandomInt(1, #spots)
		local prop = me:SpawnEntity(PROP_CLASS, {
			boss = me,
			model = PROP_MODELS[me:RandomInt(1, #PROP_MODELS)],
			yaw = me:RandomFloat(0, FULL_TURN),
			health = state.convars.tf_merasmus_prop_health,
		}, spots[which])
		state.props[#state.props + 1] = prop
		spots[which] = spots[#spots]
		spots[#spots] = nil
	end
	OnDisguise(state, me)
	self.spawned = true
end

-- Past the first level he heals while hidden.
function Disguise:Regenerate(me)
	local maxHealth = me:GetMaxHealth()
	if me:GetHealth() >= maxHealth then return end
	local perSecond = self.state.convars.tf_merasmus_health_regen_rate * maxHealth * (Level(me) - FIRST_LEVEL)
	me:SetHealth(floor(min((me:Now() - self.regenStart) * perSecond + self.regenHealth, maxHealth)))
	ShowHealth(me)
end

function Disguise:Update(me, interval)
	local state = self.state
	Think(state, me)
	if ShouldLeave(state) then return self:Done("Leaving") end
	LeaveWarning(state, me)
	if not self.spawned then
		if self.findFailTimer:HasStarted() and self.findFailTimer:IsElapsed() then return self:Done("No props") end
		if not self.retryTimer:IsElapsed() then return self:Continue() end
		self:TryToDisguiseSpawn(me)
		return self:Continue()
	end
	if self.tauntTimer:IsElapsed() then
		local rare = me:RandomInt(0, HIDDEN_RARE_ROLL_MAX) == 0
		me:PlayHighPrioritySound(rare and "Halloween.MerasmusHiddenRare" or "Halloween.MerasmusHidden")
		self.tauntTimer:Start(me:RandomFloat(HIDDEN_TAUNT_MIN, HIDDEN_TAUNT_MAX))
	end
	self:Regenerate(me)
	if state.destroyedProps >= state.toReveal then return self:Done("Revealed!") end
	return self:Continue()
end

-- Out of time while hidden, he steps out of a random surviving prop.
function Disguise:OnEnd(me, nextAction)
	local state = self.state
	if ShouldLeave(state) then
		local standing = {}
		for _, prop in ipairs(state.props) do
			if me:IsTargetValid(prop) and not state.killedProps[prop] then standing[#standing + 1] = prop end
		end
		if #standing > 0 then me:SetAbsOrigin(me:TargetOrigin(standing[me:RandomInt(1, #standing)])) end
	end
	OnRevealed(state, me, true)
end

-- CTFMerasmusTrickOrTreatProp::Event_Killed: the prop he hid in brings him
-- out where it stood, and its finder is rewarded; a decoy may taunt.
function Disguise:OnPropKilled(me, prop, attacker)
	local state = self.state
	if state.destroyedProps + 1 == state.toReveal then
		me:SetAbsOrigin(me:TargetOrigin(prop))
		if attacker ~= nil and HalloweenBoss.IsPlayer(me, attacker) then state.revealer = attacker end
	elseif me:RandomInt(1, PROP_TAUNT_ROLL_MAX) == 1 then
		me:PlayLowPrioritySound("Halloween.MerasmusTauntFakeProp")
	end
	state.destroyedProps = state.destroyedProps + 1
	state.killedProps[prop] = true
	return self:TryContinue()
end

-- CTFMerasmusTrickOrTreatProp::Touch: a bomb head who touches a prop loses
-- the bomb, which blows, and the prop with it.
function Disguise:OnPropTouched(me, prop, toucher)
	local state = self.state
	local index = BombHeadIndex(state, toucher)
	if index == nil then return self:TryContinue() end
	me:EndStun(toucher)
	RemoveBombHead(state, me, index)
	PlayerBombExplode(me, toucher, true)
	me:DealDamage(prop, PROP_FORCE_KILL_DAMAGE, Actor.DMG_BLAST, toucher)
	return self:TryContinue()
end

-------------------------------------------------------------------------------
-- Escape (CMerasmusEscape)

function Escape:OnStart(me, priorAction)
	me:StartActivity(me:Activity("ACT_FLY"))
	local rare = me:RandomInt(0, DEPART_RARE_ROLL_MAX) == 0
	me:PlayHighPrioritySound(rare and "Halloween.MerasmusDepartRare" or "Halloween.MerasmusDepart")
	return self:Continue()
end

-- Gone home; the next Merasmus starts over at the first level.
function Escape:Update(me, interval)
	Think(self.state, me)
	if not me:IsActivityFinished() then return self:Continue() end
	me:DispatchParticleEffect(TELEPORT_PARTICLE, me:AttachmentPosition(ROBE_ATTACHMENT))
	me:SetBossHealth(0)
	me:FireGameEvent(BossEvents.MERASMUS_ESCAPED, { level = Level(me) })
	me:TriggerRelay(EXIT_RELAY)
	me:Shared().level = FIRST_LEVEL
	StartRespawnTimer(self.state, me)
	me:Remove()
	return self:Done()
end

-------------------------------------------------------------------------------
-- Dying (CMerasmusDying)

-- CMerasmusBehavior::Update as he dies: each player who hit him in his last
-- KILLER_WINDOW seconds is named his killer, unless cheats spawned him.
local function NameKillers(state, me)
	if state.spawnedByCheats then return end
	local now, level = me:Now(), Level(me)
	for _, known in ipairs(state.attackers) do
		if me:IsTargetValid(known.attacker) and now - known.at < KILLER_WINDOW then
			me:FireGameEvent(BossEvents.MERASMUS_KILLER, {
				player = known.attacker,
				level = level,
			})
		end
	end
end

function Dying:OnStart(me, priorAction)
	NameKillers(self.state, me)
	me:StartActivity(me:Activity("ACT_DIESIMPLE"))
	me:PlayHighPrioritySound("Halloween.MerasmusBanish")
	me:BroadcastGameSound("Halloween.Merasmus_Death")
	return self:Continue()
end

-- Burst; a vortex to each team's loot; the next Merasmus is a level up.
function Dying:Update(me, interval)
	Think(self.state, me)
	if not me:IsActivityFinished() then return self:Continue() end
	me:Break()
	me:DispatchParticleEffect(SPAWN_PARTICLE, me:GetAbsOrigin())
	local shared = me:Shared()
	me:FireGameEvent(BossEvents.MERASMUS_KILLED, { level = Level(me) })
	me:TriggerRelay(DEAD_RELAY)
	me:SpawnEntity(VORTEX_CLASS, {
		death = true,
		splitTeam = true,
	}, me:WorldSpaceCenter())
	shared.level = Level(me) + 1
	StartRespawnTimer(self.state, me)
	me:Remove()
	return self:Done()
end

-------------------------------------------------------------------------------
-- The boss hooks

-- CMerasmus::Spawn: scaled by the players beyond the minimum.
function Health(players, level, convars)
	local health = convars.tf_merasmus_health_base
	local minimum = convars.tf_merasmus_min_player_count
	if players > minimum then
		health = health + (players - minimum) * convars.tf_merasmus_health_per_player
	end
	return health
end

-- CMerasmus::Spawn: his line, his life, the summoning event, the map's
-- entering relay, and a puff of smoke. Home is where he spawned.
function Setup(state, config, me)
	state.home = me:GetAbsOrigin()
	state.revealed = false
	state.hiding = false
	state.stunned = false
	state.aoe = false
	state.flying = false
	state.stunTimer = NpcSystem.CountdownTimer(me)
	state.bombHitCount = 0
	state.bombHeads = {}
	state.props = {}
	state.killedProps = {}
	state.destroyedProps = 0
	state.toReveal = 0
	state.revealer = nil
	state.revealedHealth = me:GetHealth()
	state.skin = nil
	state.lifeTimer = NpcSystem.CountdownTimer(me)
	state.lifeTimer:Start(state.convars.tf_merasmus_lifetime)
	state.lastWarnTime = 0
	me:PlayHighPrioritySound("Halloween.MerasmusAppears")
	me:FireGameEvent(BossEvents.MERASMUS_SUMMONED, { level = state.level })
	local relay = me:TriggerRelay(ENTER_RELAY)
	if relay then me:SetAbsOrigin(relay) end
	me:DispatchParticleEffect(SPAWN_PARTICLE, me:GetAbsOrigin())
end

-- MerasmusModifyDamage: TF2 scales the hits of some of its weapons. A RED
-- or BLU player's hit here is scaled as the TF2 weapon its damage type
-- stands for: a sniper round (DMG_SNIPER) as the sniper rifle, a crossbow
-- bolt (DMG_BULLET with DMG_NEVERGIB, HL2's) as the Huntsman and a blade
-- (DMG_SLASH) as the knife, x3; buckshot (DMG_BUCKSHOT) as the scattergun,
-- x2, the first that fits. Plain bullets, clubs, blasts (rockets, grenades,
-- pumpkin bombs, bomb heads) and fire (the spells) are as dealt, as TF2's
-- spellbook and bombs are; no damage type here stands for the minigun or
-- the sentry (x0.5), nor the revolver, Soda Popper, Shortstop or Baby
-- Face's Blaster, whose bullets are plain. What is not a player's weapon
-- (a skeleton's claws, a hazard) is as dealt.
WEAPON_SCALES = {
	{
		bits = Actor.DMG_SNIPER,
		scale = 3,
	},
	{
		bits = Actor.DMG_BULLET + Actor.DMG_NEVERGIB,
		scale = 3,
	},
	{
		bits = Actor.DMG_SLASH,
		scale = 3,
	},
	{
		bits = Actor.DMG_BUCKSHOT,
		scale = 2,
	},
}

function WeaponScale(dmgType)
	for _, weapon in ipairs(WEAPON_SCALES) do
		if band(dmgType, weapon.bits) == weapon.bits then return weapon.scale end
	end
	return 1
end

-- CMerasmus::OnTakeDamage_Alive: hidden, he takes nothing; otherwise he
-- bleeds (more while stunned), takes the weapon's share, and his bar shows
-- what the hit leaves.
function ModifyDamage(state, damageEvent, me)
	if not state.revealed then return 0 end
	me:DispatchParticleEffect(state.stunned and BLOOD_PARTICLE or BLOOD_BITS_PARTICLE, damageEvent.position)
	local amount = damageEvent.amount
	if HalloweenBoss.IsPlayer(me, damageEvent.attacker) then amount = amount * WeaponScale(damageEvent.dmgType) end
	local left = max(0, me:GetHealth() - amount)
	me:SetBossHealth(left / me:GetMaxHealth())
	return amount
end


-- CMerasmusBehavior::Update: the warnings, then home when his time is up,
-- unless stunned or aloft.
function LeaveAction(state, me)
	LeaveWarning(state, me)
	if ShouldLeave(state) and not state.stunned and not state.flying then return Escape:New(state) end
	return nil
end

-- CMerasmusBehavior::OnInjured: badly hurt since he was revealed, he hides
-- (not while stunned or aloft).
function InterruptAction(state, damageEvent, me)
	if ShouldDisguise(state, me) and state.revealed and not state.stunned and not state.flying then
		return Disguise:New(state)
	end
	return nil
end

OnUpdate = Think

function EmergeAction(state) return Reveal:New(state) end
function DyingAction(state) return Dying:New(state) end

-- CMerasmus::UpdateOnRemove: his bar goes, the bomb heads' bombs blow, and
-- his props go with him.
function Removed(state, me)
	me:SetBossHealth(0)
	for i = #state.bombHeads, 1, -1 do RemoveBombHead(state, me, i) end
	RemoveAllFakeProps(state, me)
end

HalloweenBoss.Variant(_M)
