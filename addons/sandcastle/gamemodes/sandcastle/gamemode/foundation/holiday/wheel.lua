-- The Wheel of Fate (wheel_of_doom, CWheelOfDoom in tf_wheel_of_doom.cpp):
-- Merasmus's slot-machine screen. Spin chooses an effect, then the screen
-- shows (with every other wheel_of_doom's) and flicks through the faces,
-- fast and then slower, for 5.75 s, Merasmus calling the spin at 1.6 s; a
-- second after it stops the effect lands on every player: OnEffectApplied,
-- the face, Merasmus naming it, and the HUD's icon and countdown. When it
-- runs out: OnEffectExpired, the screen blanks and hides, the HUD clears.
-- A player who spawns meanwhile gets the effects that reapply.
--
-- The effects are Strategies, one per TF2 class, each with Init, Activate,
-- Update and Deactivate: eight buffs and three whammies (the Jarate rain,
-- the Burn and the Ghosts). No player speaks (the MP_CONCEPT_MAGIC_*
-- responses: GMod players have no class voices).
--
-- New{ duration (effect_duration), hasSpiral (has_spiral) }; the wheel
-- controller calls Spin(world), Think(world) every tick, PlayerSpawned(world,
-- player), ClearAllEffects(world) and IsDoneBroadcastingEffectSound(now).
-- Its world port:
--   Now(), RandomInt(lo, hi), RandomFloat(lo, hi), Vector(x, y, z);
--   Players() (every player), LivingPlayers(), TeamOf(p), IsTargetValid(p);
--   AddCond(p, cond, duration), RemoveCond(p, cond);
--   SetAttribute(p, name, value), RemoveAttribute(p, name)
--     (foundation.players.attributes' names);
--   SetGravityMultiplier(m) (CTFGameRules::SetGravityMultiplier);
--   OtherWheels() -> the other wheel_of_doom entities (opaque);
--   SetSkin(others, n), SetScale(others, s): on this wheel and the others;
--   SetVisible(on): this wheel's screen; GrowSpirals(others) and
--     ShrinkSpirals(others): this wheel's spiral and the others' that have
--     one;
--   BroadcastSound(name) (everyone hears); Announce(name) (Merasmus says it
--     if he is about, else everyone hears it);
--   SetEffectStatus(skin, duration), ClearEffectStatus() (the HUD);
--   FireOutput(name);
--   DanceSpot(teamName, n) -> { pos, yaw } | nil (the dance_teleport_<team><n>
--     entity), Teleport(p, pos, yaw), Taunt(p) (the dance);
--   SpawnDancer(pos, yaw) -> dancer, DancerVanish(dancer),
--     DancerBlastOff(dancer) (merasmus_dancer);
--   CloudBoxes() -> { mins, maxs } of each spawn_cloud brush; DropJar(pos,
--     spin) (a tf_projectile_jar with that angular impulse, nobody's);
--   BeginHaunting(count, minDuration, maxDuration)
--     (CTFGameRules::BeginHaunting: foundation.npc.ghost's Haunt).
local require = require
local Players = require("foundation.players")
local Attributes = require("foundation.players.attributes")
local Teams = require("foundation.teams")
local Class = require("foundation.core.meta.class")
local ipairs, setmetatable = ipairs, setmetatable
local floor, log, max, min = math.floor, math.log, math.max, math.min
local format = string.format
module(...)

METHODS = {
	"Now",
	"RandomInt",
	"RandomFloat",
	"Vector",
	"Players",
	"LivingPlayers",
	"TeamOf",
	"IsTargetValid",
	"AddCond",
	"RemoveCond",
	"SetAttribute",
	"RemoveAttribute",
	"SetGravityMultiplier",
	"OtherWheels",
	"SetSkin",
	"SetScale",
	"SetVisible",
	"GrowSpirals",
	"ShrinkSpirals",
	"BroadcastSound",
	"Announce",
	"SetEffectStatus",
	"ClearEffectStatus",
	"FireOutput",
	"DanceSpot",
	"Teleport",
	"Taunt",
	"SpawnDancer",
	"DancerVanish",
	"DancerBlastOff",
	"CloudBoxes",
	"DropJar",
	"BeginHaunting",
}

MODEL = "models/props_lakeside_event/buff_plane.mdl"
SPIRAL_MODEL = "models/props_lakeside_event/wof_plane2.mdl"
SPIN_SOUND = "Halloween.WheelofFate"
SPIN_LINE = "Halloween.MerasmusWheelSpin"

OUTPUT_APPLIED = "OnEffectApplied"
OUTPUT_EXPIRED = "OnEffectExpired"
INPUT_SPIN = "spin"
INPUT_CLEAR = "clearalleffects"

-- eWheelOfDoomEffectSkinIndex: the screen's faces (0 is blank). The HUD's
-- icons are hud/death_wheel_whammy and hud/death_wheel_<face - 1>.
BLANK = 0
EFFECT_WHAMMY, EFFECT_JUMP_HEIGHT, EFFECT_SMALL_HEAD, EFFECT_SPEED, EFFECT_LOW_GRAVITY = 1, 2, 3, 4, 5
EFFECT_BIG_HEAD, EFFECT_UBER, EFFECT_CRITS, EFFECT_DANCE = 6, 7, 8, 9
EFFECT_COUNT = 16 -- past the faces only the slot machine shows (baseballs to cherries)

SPIN_TIME = 5.75
SPIN_TIME_BIAS = 0.3
FASTEST_SPIN_RATE, SLOWEST_SPIN_RATE = 0.1, 0.55
SPIN_SCALE_MIN, SPIN_SCALE_MAX = 0.3, 0.9
FULL_SCALE = 1
ANNOUNCE_DELAY = 1.6
APPLY_DELAY = 1 -- after the stop
BROADCAST_TAIL = 10 -- the boss timer waits this long past the stop
IDLE_INTERVAL = 0.1

UBER_MAX = 10
BURN_TIME = 10
SPEED_BONUS = 2
JUMP_BONUS = 3
BIG_HEAD, BIG_HEAD_PITCH = 3, 0.85
SMALL_HEAD, SMALL_HEAD_PITCH = 0.5, 1.3
LOW_GRAVITY = 0.25
NORMAL_GRAVITY = 1
DANCE_TIME = 8 -- two dances, whatever the wheel's duration
DANCE_FIRST = 1.5
DANCE_INTERVAL = 3.5
DANCE_SLAM_LEAD = 0.2 -- players are put back on their spots this close to a dance
DANCER_ENDS = 2 -- Merasmus dances at either end of the floor, by turns
DANCER_YAW_LOW, DANCER_YAW_HIGH = 90, -90
DANCE_TEAM_RED, DANCE_TEAM_BLUE = "red", "blue"
DANCE_SPOT_FORMAT = "dance_teleport_%s%d"
PEE_FIRST = 0.25
PEE_INTERVAL_MIN, PEE_INTERVAL_MAX = 0.2, 0.5
PEE_SPIN = 300 -- the jar's angular impulse, each axis
CLOUD_NAME = "spawn_cloud" -- the brushes the Jarate rains from
GHOST_COUNT = 4

-- merasmus_dancer (CMerasmusDancer): Merasmus dancing taunt06, staff away,
-- in a puff of smoke; he vanishes in another, or plays ACT_FLY and goes
-- 0.3 s later.
DANCER_MODEL = "models/bots/merasmus/merasmus.mdl"
DANCER_SEQUENCE = "taunt06"
DANCER_STAFF = 2 -- the staff bodygroup's "away"
DANCER_POOF_PARTICLE = "merasmus_tp"
DANCER_POOF_SOUND = "Halloween.Merasmus_Hiding_Explode"
DANCER_BLAST_OFF_TIME = 0.3

-- The HUD (CTFHudPlayerHealth::UpdateHalloweenStatus): the effect's icon,
-- blinking every quarter second in its last 3 s.
HUD_WHAMMY_ICON = "hud/death_wheel_whammy"
HUD_ICON_FORMAT = "hud/death_wheel_%d"
HUD_WARN_TIME = 3
HUD_BLINK_INTERVAL = 0.25

function HudIcon(skin)
	if skin == EFFECT_WHAMMY then return HUD_WHAMMY_ICON end
	return format(HUD_ICON_FORMAT, skin - 1)
end

function HudVisible(timeLeft)
	if timeLeft >= HUD_WARN_TIME then return true end
	return floor(timeLeft / HUD_BLINK_INTERVAL) % 2 == 1
end

-- Bias( x, amount ): x to the power log(amount) / log(0.5).
local function Bias(x, amount)
	return x ^ (log(amount) / log(0.5))
end

-- CalcNextTickTime's step at a spin progress from 0 to 1.
function TickInterval(progress)
	local b = Bias(progress, SPIN_TIME_BIAS)
	return (1 - b) * FASTEST_SPIN_RATE + b * SLOWEST_SPIN_RATE
end

-- SpinThink's next face: the rolled one, unless it is up already, then the
-- next, wrapping past the last over the blank.
function NextFace(rolled, current)
	local face = rolled
	if face == current then face = face + 1 end
	if face == EFFECT_COUNT then face = EFFECT_WHAMMY end
	return face
end

-------------------------------------------------------------------------------
-- Effects (WOD_BaseEffect and its subclasses)

local Effect = {}
Effect.__index = Effect
Effect.whammy = false
Effect.reapplies = true

function Effect:Init(world, wheel, duration) self.expireTime = world:Now() + duration end
function Effect:Activate(world, wheel, players) end
function Effect:Update(world, players) end
function Effect:Deactivate(world, players) end
function Effect:TimeLeft(world) return self.expireTime - world:Now() end

local function CondEffect(fields, cond)
	local effect = Class.Extend(Effect, fields)
	function effect:Activate(world, wheel, players)
		for _, p in ipairs(players) do world:AddCond(p, cond, self:TimeLeft(world)) end
	end
	return effect
end

-- attrs: { name, value } pairs, given on activation and taken on the end.
local function AttributeEffect(fields, attrs)
	local effect = Class.Extend(Effect, fields)
	function effect:Activate(world, wheel, players)
		for _, p in ipairs(players) do
			for _, attr in ipairs(attrs) do world:SetAttribute(p, attr.name, attr.value) end
		end
	end
	function effect:Deactivate(world, players)
		for _, p in ipairs(players) do
			for _, attr in ipairs(attrs) do world:RemoveAttribute(p, attr.name) end
		end
	end
	return effect
end

local function Attr(name, value)
	return {
		name = name,
		value = value,
	}
end

local Uber = CondEffect({
	name = "Uber",
	skin = EFFECT_UBER,
	sound = "Halloween.MerasmusWheelUber",
}, Players.COND.INVULNERABLE)

function Uber:Init(world, wheel, duration) self.expireTime = world:Now() + min(duration, UBER_MAX) end

local Crits = CondEffect({
	name = "Crits",
	skin = EFFECT_CRITS,
	sound = "Halloween.MerasmusWheelCrits",
}, Players.COND.CRITBOOSTED_PUMPKIN)

local SuperSpeed = AttributeEffect({
	name = "Super Speed",
	skin = EFFECT_SPEED,
	sound = "Halloween.MerasmusWheelSuperSpeed",
}, { Attr(Attributes.MOVE_SPEED_BONUS, SPEED_BONUS) })

local SuperJump = AttributeEffect({
	name = "Super Jump",
	skin = EFFECT_JUMP_HEIGHT,
	sound = "Halloween.MerasmusWheelSuperJump",
}, {
	Attr(Attributes.JUMP_HEIGHT_BONUS, JUMP_BONUS),
	Attr(Attributes.CANCEL_FALL_DAMAGE, 1),
})

local BigHead = AttributeEffect({
	name = "Big Head",
	skin = EFFECT_BIG_HEAD,
	sound = "Halloween.MerasmusWheelBigHead",
}, {
	Attr(Attributes.VOICE_PITCH_SCALE, BIG_HEAD_PITCH),
	Attr(Attributes.HEAD_SCALE, BIG_HEAD),
})

local SmallHead = AttributeEffect({
	name = "Small Head",
	skin = EFFECT_SMALL_HEAD,
	sound = "Halloween.MerasmusWheelShrunkHead",
}, {
	Attr(Attributes.VOICE_PITCH_SCALE, SMALL_HEAD_PITCH),
	Attr(Attributes.HEAD_SCALE, SMALL_HEAD),
})

local LowGravity = Class.Extend(Effect, {
	name = "Low Gravity",
	skin = EFFECT_LOW_GRAVITY,
	sound = "Halloween.MerasmusWheelGravity",
})

function LowGravity:Activate(world, wheel, players) world:SetGravityMultiplier(LOW_GRAVITY) end
function LowGravity:Deactivate(world, players) world:SetGravityMultiplier(NORMAL_GRAVITY) end

local Burn = Class.Extend(Effect, {
	name = "Burn",
	skin = EFFECT_WHAMMY,
	sound = "Halloween.MerasmusWheelBurn",
	whammy = true,
	reapplies = false,
})

function Burn:Init(world, wheel, duration) self.expireTime = world:Now() + BURN_TIME end

-- SelfBurn for the wheel's duration, at most 10 s.
function Burn:Activate(world, wheel, players)
	for _, p in ipairs(players) do world:AddCond(p, Players.COND.BURNING, min(wheel.duration, BURN_TIME)) end
end

-- WOD_Dance: everyone alive to their team's numbered spots, held in the
-- thriller; every 3.5 s they dance (put back on their spots just before)
-- and a Merasmus pops up at one end of the floor, then the other. With no
-- spots TF2 divides by zero for his place; here he does not come.
local Dance = Class.Extend(Effect, {
	name = "Dance",
	skin = EFFECT_DANCE,
	sound = "Halloween.MerasmusWheelDance",
	reapplies = false,
})

local function DanceTeam(team)
	if team == Teams.RED then return DANCE_TEAM_RED end
	return DANCE_TEAM_BLUE
end

function Dance:TeamDancing(world, team)
	local count = 0
	for _, dancer in ipairs(self.dancers) do
		if world:TeamOf(dancer.player) == team then count = count + 1 end
	end
	return count
end

function Dance:Init(world, wheel, duration)
	local now = world:Now()
	self.current = world:RandomInt(0, DANCER_ENDS - 1)
	self.expireTime = now + DANCE_TIME
	self.nextDance = now + DANCE_FIRST
	self.dancers = {}
	self.dancerSpots = {}
	self.dancer = nil
	local lowY, highY, sumX, z = nil, nil, 0, 0
	for _, p in ipairs(world:LivingPlayers()) do
		local team = world:TeamOf(p)
		local spot = world:DanceSpot(DanceTeam(team), self:TeamDancing(world, team))
		if spot then
			local pos = spot.pos
			lowY, highY = min(lowY or pos.y, pos.y), max(highY or pos.y, pos.y)
			sumX, z = sumX + pos.x, pos.z
			world:Teleport(p, pos, spot.yaw)
			world:AddCond(p, Players.COND.HALLOWEEN_THRILLER, Players.PERMANENT)
			self.dancers[#self.dancers + 1] = {
				player = p,
				pos = pos,
				yaw = spot.yaw,
			}
		end
	end
	if #self.dancers == 0 then return end
	local x = sumX / #self.dancers
	self.dancerSpots = {
		{
			pos = world:Vector(x, lowY, z),
			yaw = DANCER_YAW_LOW,
		},
		{
			pos = world:Vector(x, highY, z),
			yaw = DANCER_YAW_HIGH,
		},
	}
end

function Dance:Update(world, players)
	local now = world:Now()
	local slam = self.nextDance - now < DANCE_SLAM_LEAD
	local taunt = now > self.nextDance
	if taunt then self.nextDance = now + DANCE_INTERVAL end
	for i = #self.dancers, 1, -1 do
		local dancer = self.dancers[i]
		if not world:IsTargetValid(dancer.player) then
			for j = i, #self.dancers do self.dancers[j] = self.dancers[j + 1] end
		else
			if taunt then world:Taunt(dancer.player) end
			if slam then world:Teleport(dancer.player, dancer.pos, dancer.yaw) end
		end
	end
	if not taunt or #self.dancerSpots == 0 then return end
	if self.dancer then world:DancerVanish(self.dancer) end
	local spot = self.dancerSpots[self.current % #self.dancerSpots + 1]
	self.dancer = world:SpawnDancer(spot.pos, spot.yaw)
	self.current = (self.current + 1) % #self.dancerSpots
end

function Dance:Deactivate(world, players)
	for _, p in ipairs(players) do world:RemoveCond(p, Players.COND.HALLOWEEN_THRILLER) end
	self.dancers = {}
	self.dancerSpots = {}
	if self.dancer then world:DancerBlastOff(self.dancer) end
	self.dancer = nil
end

-- WOD_Pee: Jarate rains from the map's spawn_cloud brushes, a jar from a
-- random spot in a random one a quarter second in and then every 0.2-0.5
-- s, spinning.
local Pee = Class.Extend(Effect, {
	name = "Pee",
	skin = EFFECT_WHAMMY,
	sound = "Halloween.MerasmusWheelJarate",
	whammy = true,
	reapplies = false,
})

function Pee:Activate(world, wheel, players)
	self.clouds = world:CloudBoxes()
	self.nextPee = world:Now() + PEE_FIRST
end

function Pee:Update(world, players)
	local now = world:Now()
	if now < self.nextPee or #self.clouds == 0 then return end
	self.nextPee = now + world:RandomFloat(PEE_INTERVAL_MIN, PEE_INTERVAL_MAX)
	local cloud = self.clouds[world:RandomInt(1, #self.clouds)]
	local lo, hi = cloud.mins, cloud.maxs
	local pos = world:Vector(world:RandomFloat(lo.x, hi.x), world:RandomFloat(lo.y, hi.y), world:RandomFloat(lo.z, hi.z))
	local spin = world:Vector(world:RandomFloat(-PEE_SPIN, PEE_SPIN), world:RandomFloat(-PEE_SPIN, PEE_SPIN),
		world:RandomFloat(-PEE_SPIN, PEE_SPIN))
	world:DropJar(pos, spin)
end

-- WOD_Ghosts: a haunting of four ghosts, each for half to all the wheel's
-- duration; its end puts out whoever is burning.
local Ghosts = Class.Extend(Effect, {
	name = "Ghosts",
	skin = EFFECT_WHAMMY,
	sound = "Halloween.MerasmusWheelGhosts",
	whammy = true,
	reapplies = false,
})

function Ghosts:Activate(world, wheel, players)
	world:BeginHaunting(GHOST_COUNT, wheel.duration / 2, wheel.duration)
end

function Ghosts:Deactivate(world, players)
	for _, p in ipairs(players) do world:RemoveCond(p, Players.COND.BURNING) end
end

-- In CWheelOfDoom's order of registration.
EFFECTS = {
	Uber,
	Crits,
	SuperSpeed,
	SuperJump,
	BigHead,
	SmallHead,
	LowGravity,
	Dance,
	Pee,
	Burn,
	Ghosts,
}

-------------------------------------------------------------------------------
-- The wheel

local Wheel = {}
Wheel.__index = Wheel

function New(config)
	local effects = {}
	for i, class in ipairs(EFFECTS) do effects[i] = Class.New(class) end
	return setmetatable({
		duration = config.duration,
		hasSpiral = config.hasSpiral,
		effects = effects,
		active = {},
		chosen = nil,
		others = {},
		skin = BLANK,
		spinning = false,
		stopTime = 0,
		nextTickTime = 0,
		nextAnnounceTime = 0,
		announced = false,
		finishBroadcastingTime = 0,
		nextIdle = 0,
	}, Wheel)
end

-- GetRandomEffectWithFlags: the buffs (last registered first), then the
-- whammies; one roll in buffs + 1 is a whammy, rolled again among them.
function Wheel:RandomEffect(world)
	local list, buffs, whammies = {}, 0, 0
	for _, effect in ipairs(self.effects) do
		if effect.whammy then
			whammies = whammies + 1
			list[#list + 1] = effect
		else
			buffs = buffs + 1
			for i = #list, 1, -1 do list[i + 1] = list[i] end
			list[1] = effect
		end
	end
	if whammies == 0 then return list[world:RandomInt(1, buffs)] end
	local roll = world:RandomInt(0, buffs)
	if roll == buffs then roll = buffs + world:RandomInt(0, whammies - 1) end
	return list[roll + 1]
end

local function SetSkin(self, world, skin)
	self.skin = skin
	world:SetSkin(self.others, skin)
end

local function SpinCompletion(self, now)
	return (SPIN_TIME - (self.stopTime - now)) / SPIN_TIME
end

local function NextTickTime(self, now)
	return now + TickInterval(SpinCompletion(self, now))
end

-- Spin: the effect is chosen now and lands when the spin is done.
function Wheel:Spin(world)
	self.chosen = self:RandomEffect(world)
	local now = world:Now()
	world:SetVisible(true)
	self.others = world:OtherWheels()
	world:BroadcastSound(SPIN_SOUND)
	if self.hasSpiral then world:GrowSpirals(self.others) end
	self.stopTime = now + SPIN_TIME
	self.nextTickTime = NextTickTime(self, now)
	self.nextAnnounceTime = now + ANNOUNCE_DELAY
	self.announced = false
	self.finishBroadcastingTime = self.stopTime + BROADCAST_TAIL
	self.spinning = true
end

-- EffectManager::AddEffect: on everyone, named, and on the HUD.
function Wheel:AddEffect(world, effect)
	effect:Init(world, self, self.duration)
	effect:Activate(world, self, world:Players())
	world:Announce(effect.sound)
	world:SetEffectStatus(effect.skin, effect:TimeLeft(world))
	self.active[#self.active + 1] = effect
	return effect.skin
end

-- UpdateAndClearExpiredEffects: whether any ran out.
function Wheel:UpdateEffects(world)
	local now, players, expired = world:Now(), world:Players(), false
	for i = #self.active, 1, -1 do
		local effect = self.active[i]
		if now > effect.expireTime then
			expired = true
			effect:Deactivate(world, players)
			for j = i, #self.active do self.active[j] = self.active[j + 1] end
		else
			effect:Update(world, players)
		end
	end
	return expired
end

function Wheel:SpinThink(world)
	local now = world:Now()
	if self:UpdateEffects(world) then
		world:FireOutput(OUTPUT_EXPIRED)
		world:ClearEffectStatus()
	end
	if now > self.stopTime then
		if now > self.stopTime + APPLY_DELAY then
			world:SetScale(self.others, FULL_SCALE)
			world:FireOutput(OUTPUT_APPLIED)
			SetSkin(self, world, self:AddEffect(world, self.chosen))
			self.spinning = false
			self.nextIdle = now + IDLE_INTERVAL
			self.stopTime, self.nextTickTime, self.chosen = 0, 0, nil
		end
	elseif now > self.nextTickTime then
		SetSkin(self, world, NextFace(world:RandomInt(EFFECT_WHAMMY, EFFECT_COUNT - 1), self.skin))
		local completion = SpinCompletion(self, now)
		world:SetScale(self.others, SPIN_SCALE_MIN + (SPIN_SCALE_MAX - SPIN_SCALE_MIN) * completion)
		self.nextTickTime = NextTickTime(self, now)
	end
	if now > self.nextAnnounceTime and not self.announced then
		self.announced = true
		world:Announce(SPIN_LINE)
	end
end

function Wheel:IdleThink(world)
	if not self:UpdateEffects(world) then return end
	world:SetVisible(false)
	world:FireOutput(OUTPUT_EXPIRED)
	SetSkin(self, world, BLANK)
	world:ClearEffectStatus()
	if self.hasSpiral then world:ShrinkSpirals(self.others) end
end

-- Every tick: the spin's think runs each tick, the idle one every 0.1 s.
function Wheel:Think(world)
	if self.spinning then return self:SpinThink(world) end
	local now = world:Now()
	if now < self.nextIdle then return end
	self.nextIdle = now + IDLE_INTERVAL
	self:IdleThink(world)
end

-- ApplyAllEffectsToPlayer, on player_spawn.
function Wheel:PlayerSpawned(world, player)
	for _, effect in ipairs(self.active) do
		if effect.reapplies then effect:Activate(world, self, { player }) end
	end
end

-- ClearAllEffects: each ends at once; nothing fires and the HUD stays.
function Wheel:ClearAllEffects(world)
	local players = world:Players()
	for _, effect in ipairs(self.active) do effect:Deactivate(world, players) end
	self.active = {}
end

function Wheel:IsDoneBroadcastingEffectSound(now)
	return now > self.finishBroadcastingTime
end
