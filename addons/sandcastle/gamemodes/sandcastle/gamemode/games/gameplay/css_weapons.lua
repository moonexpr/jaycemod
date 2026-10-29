-- CS:S's weapons, for hostage rescue and the other CS:S modes: each made
-- from the game's own script (css_weapons/scripts.lua, written by
-- .devtools/bin/css_weapons.py), with what CS:S keeps in code instead (its
-- recoil, second modes, ammo, the knife and the grenades) as tuning here.
-- Players hold them as SWEPs (entities/weapons/weapon_css_base.lua), bot
-- soldiers through the same SWEPs, and NPC soldiers through their stats
-- (nextsoldier.weapons).
--
-- The accuracy model is the scripts' ("New accuracy model parameters"), as
-- CS:S's successor plays it: a shot's inaccuracy is the weapon's penalty,
-- plus movement past MOVE_FROM of its speed, plus the air or a ladder,
-- held to MAX_INACCURACY. Each shot adds its fire penalty, landing adds
-- its land penalty, and the penalty falls back to its base (crouching's or
-- standing's) by nine tenths over the recovery time. A shot's bullets
-- spray about one offset drawn from the inaccuracy, each its own within the
-- spread. Damage falls by the range modifier every FALLOFF_STEP units, to
-- nothing past the weapon's range, times its hit group's multiplier.
--
-- CLASSES: the weapons in the buy menu's order; WEAPONS[class]: each, a
-- value: { class, name, kind (GUN, KNIFE, GRENADE), type, team, price,
-- damage, bullets, cycle, range, rangeModifier, penetration, clip, ammo,
-- maxSpeed, fullAuto, slot, slotPos, viewModel (GMod's c_ model),
-- worldModel, hold, sounds, accuracy, alt (the second mode's accuracy),
-- second ({ mode, ... } or nil), kick, reload (seconds, for NPC soldiers) }.
-- For(team) -> the classes a team may use; Set(list) -> class -> true.
-- Accuracy(weapon, second) -> the model in use; Base(acc, crouching);
-- Inaccuracy(weapon, acc, { penalty, speed, onGround, ladder });
-- Fired(acc, penalty); Landed(acc, penalty); Recover(acc, penalty,
-- crouching, seconds); Spray(inaccuracy, spread, bullets, random) ->
-- { x, y } offsets (random() in [0, 1), the caller's); Damage(weapon,
-- distance, hitgroup); Kick(weapon, stance, shots, punch, left, roll) ->
-- punch, left (roll: random 0..kick.flip, or a 0..1 fraction of a punch's
-- range); Backstab(fromAttacker, victimFacing); KnifeDamage(strike, back).
local error, ipairs, setmetatable, tostring, type = error, ipairs, setmetatable, tostring, type
local cos, sin, exp, log, pi, min = math.cos, math.sin, math.exp, math.log, math.pi, math.min
local Scalar = math.scalar
local Scripts = require("games.gameplay.css_weapons.scripts")
module(...)

GUN, KNIFE, GRENADE = "gun", "knife", "grenade"
TERRORIST, CT, ANY = "TERRORIST", "CT", "ANY"
SILENCER, BURST, SCOPE = "silencer", "burst", "scope"
STAND, CROUCH, MOVE, AIR = "stand", "crouch", "move", "air"

-- Source's hit groups (HITGROUP_*), and what CS:S multiplies a hit in each by.
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH = 0, 1, 2, 3
HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG, HITGROUP_GEAR = 4, 5, 6, 7, 10
HITGROUPS = {
	[HITGROUP_GENERIC] = 1,
	[HITGROUP_HEAD] = 4,
	[HITGROUP_CHEST] = 1,
	[HITGROUP_STOMACH] = 1.25,
	[HITGROUP_LEFTARM] = 1,
	[HITGROUP_RIGHTARM] = 1,
	[HITGROUP_LEFTLEG] = 0.75,
	[HITGROUP_RIGHTLEG] = 0.75,
	[HITGROUP_GEAR] = 1,
}

FALLOFF_STEP = 500
MOVE_FROM, MOVE_FULL = 0.34, 0.95 -- of the weapon's speed: movement's inaccuracy starts, and is whole
MOVE_CURVE = 0.25 -- its fraction is raised to this: most of it comes early
MAX_INACCURACY = 1

-- CS:S's ammo (its cs_ammodef): the most a player carries of each.
AMMO = {
	BULLET_PLAYER_50AE = { max = 35 },
	BULLET_PLAYER_762MM = { max = 90 },
	BULLET_PLAYER_556MM = { max = 90 },
	BULLET_PLAYER_556MM_BOX = { max = 200 },
	BULLET_PLAYER_338MAG = { max = 30 },
	BULLET_PLAYER_9MM = { max = 120 },
	BULLET_PLAYER_BUCKSHOT = { max = 32 },
	BULLET_PLAYER_45ACP = { max = 100 },
	BULLET_PLAYER_357SIG = { max = 52 },
	BULLET_PLAYER_57MM = { max = 100 },
}

-- The buy menu's order: pistols, shotguns, SMGs, rifles, machine gun, then
-- the knife and the grenades.
CLASSES = {
	"weapon_glock", "weapon_usp", "weapon_p228", "weapon_deagle", "weapon_elite", "weapon_fiveseven",
	"weapon_m3", "weapon_xm1014",
	"weapon_mac10", "weapon_tmp", "weapon_mp5navy", "weapon_ump45", "weapon_p90",
	"weapon_galil", "weapon_famas", "weapon_ak47", "weapon_m4a1", "weapon_sg552", "weapon_aug",
	"weapon_scout", "weapon_awp", "weapon_g3sg1", "weapon_sg550",
	"weapon_m249",
	"weapon_knife",
	"weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade",
}

-- Tuning: what CS:S keeps in code, not in its scripts. Not read from the
-- game; near CS:S's as it plays.

-- Second modes: the M4A1's and USP's silencer; the Glock's and FAMAS's
-- burst (rounds, seconds between them, and before the next burst); the
-- scopes' fields of view, one a press, and the speed a scoped player moves.
SECOND = {
	weapon_m4a1 = { mode = SILENCER },
	weapon_usp = { mode = SILENCER },
	weapon_glock = { mode = BURST, rounds = 3, gap = 0.05, after = 0.5 },
	weapon_famas = { mode = BURST, rounds = 3, gap = 0.075, after = 0.55 },
	weapon_aug = { mode = SCOPE, fov = { 55 }, speed = 221 },
	weapon_sg552 = { mode = SCOPE, fov = { 55 }, speed = 235 },
	weapon_scout = { mode = SCOPE, fov = { 40, 15 }, speed = 220 },
	weapon_awp = { mode = SCOPE, fov = { 40, 10 }, speed = 150 },
	weapon_g3sg1 = { mode = SCOPE, fov = { 40, 15 }, speed = 150 },
	weapon_sg550 = { mode = SCOPE, fov = { 40, 15 }, speed = 150 },
}

-- Recoil (CS:S's KickBack): an automatic gun's view climbs upBase, plus
-- upModifier a shot after the first, to upMax, and swings aside likewise
-- to lateralMax, changing side one roll in flip + 1; the rest punch up
-- once a shot, between punch[1] and punch[2] degrees. STANCES scales it.
local KICK_BY_TYPE = {
	Rifle = { upBase = 1.0, lateralBase = 0.375, upModifier = 0.175, lateralModifier = 0.0375, upMax = 5.75, lateralMax = 1.75, flip = 8 },
	SubMachinegun = { upBase = 0.45, lateralBase = 0.3, upModifier = 0.2, lateralModifier = 0.03, upMax = 3.0, lateralMax = 2.5, flip = 10 },
	Machinegun = { upBase = 0.8, lateralBase = 0.65, upModifier = 0.45, lateralModifier = 0.125, upMax = 5.0, lateralMax = 3.5, flip = 8 },
	Pistol = { punch = { 2, 2 } },
	SniperRifle = { punch = { 2, 2 } },
	Shotgun = { punch = { 4, 6 } },
}
KICK = {
	weapon_m4a1 = { upBase = 0.65, lateralBase = 0.35, upModifier = 0.25, lateralModifier = 0.015, upMax = 3.5, lateralMax = 2.25, flip = 7 },
	weapon_famas = { upBase = 0.65, lateralBase = 0.35, upModifier = 0.25, lateralModifier = 0.015, upMax = 3.5, lateralMax = 2.25, flip = 7 },
	weapon_aug = { upBase = 0.65, lateralBase = 0.325, upModifier = 0.175, lateralModifier = 0.0325, upMax = 3.5, lateralMax = 2.0, flip = 8 },
	weapon_g3sg1 = { punch = { 0.75, 1.75 } },
	weapon_sg550 = { punch = { 0.75, 1.75 } },
	weapon_xm1014 = { punch = { 3, 5 } },
	weapon_glock = { punch = { 1, 1 } },
	weapon_elite = { punch = { 1.5, 1.5 } },
}
STANCES = { [STAND] = 1, [CROUCH] = 0.9, [MOVE] = 1.5, [AIR] = 2 }

-- Seconds an NPC soldier's reload takes, by type (near the view models'
-- reload animations, which a player's reload plays out).
RELOAD = {
	Pistol = 2.2,
	SubMachinegun = 2.6,
	Rifle = 2.5,
	SniperRifle = 3.5,
	Shotgun = 3.5,
	Machinegun = 4.7,
}

-- GMod's hold types, by type; the dual Elites' own.
local HOLD = {
	Pistol = "pistol",
	SubMachinegun = "smg",
	Rifle = "ar2",
	SniperRifle = "ar2",
	Shotgun = "shotgun",
	Machinegun = "ar2",
	Knife = "knife",
	Grenade = "grenade",
}
local HOLD_BY_CLASS = { weapon_elite = "duel" }

-- The knife: a slash (primary) and a stab (secondary), each { damage,
-- reach, interval (seconds to the next strike) }; a slash a while after the
-- last (fresh seconds) hits for firstDamage. From behind, BACKSTAB times;
-- behind is the victim facing away from its attacker within BACKSTAB_DOT.
KNIFE_STATS = {
	slash = { damage = 15, firstDamage = 20, fresh = 0.4, reach = 48, interval = 0.4 },
	stab = { damage = 65, reach = 32, interval = 1.0 },
}
BACKSTAB, BACKSTAB_DOT = 3, 0.8

-- The grenades: fuse (seconds from the throw), throw speed; HE: damage at
-- its centre, falling to none at radius; the flashbang: blind (the most
-- seconds a flash blinds, facing it at its centre), radius; smoke: duration
-- (seconds the cloud stands), radius.
GRENADES = {
	weapon_hegrenade = { fuse = 1.5, speed = 750, damage = 100, radius = 350, projectile = "hegrenade_projectile" },
	weapon_flashbang = { fuse = 1.5, speed = 750, blind = 4.9, radius = 1500, projectile = "flashbang_projectile" },
	weapon_smokegrenade = { fuse = 1.5, speed = 750, duration = 15, radius = 150, projectile = "smokegrenade_projectile" },
}

local function Refuse(class, what)
	error("css_weapons: " .. class .. " " .. what, 3)
end

local function KindOf(type)
	if type == "Knife" then return KNIFE end
	if type == "Grenade" then return GRENADE end
	return GUN
end

-- GMod's c_ model of a CS:S v_ model: models/weapons/cstrike/c_*.
local function CModel(class, view)
	local name = type(view) == "string" and view:match("^models/weapons/v_(.+)%.mdl$")
	if not name then Refuse(class, "has no v_ model") end
	return "models/weapons/cstrike/c_" .. name .. ".mdl"
end

-- Read through, never written: a weapon is read by its fields, never walked.
local function Frozen(t)
	return setmetatable({}, {
		__index = t,
		__newindex = function(_, key) error("css_weapons: a weapon is not changed (" .. tostring(key) .. ")", 2) end,
	})
end

-- A weapon from its script (a SCRIPTS entry); refused when the script lacks
-- what its kind needs: our content's mistake.
function Weapon(class, script)
	local kind = KindOf(script.type)
	if script.team ~= TERRORIST and script.team ~= CT and script.team ~= ANY then Refuse(class, "has no team") end
	local w = {
		class = class,
		name = script.name or class,
		kind = kind,
		type = script.type,
		team = script.team,
		price = script.price,
		maxSpeed = script.maxSpeed,
		slot = script.slot,
		slotPos = script.slotPos,
		viewModel = CModel(class, script.viewModel),
		worldModel = script.worldModel,
		hold = HOLD_BY_CLASS[class] or HOLD[script.type],
		sounds = script.sounds or {},
	}
	if kind == GUN then
		if not script.accuracy then Refuse(class, "has no accuracy model") end
		if not AMMO[script.ammo] then Refuse(class, "fires no ammo CS:S knows: " .. tostring(script.ammo)) end
		w.damage, w.bullets, w.cycle = script.damage, script.bullets, script.cycle
		w.range, w.rangeModifier, w.penetration = script.range, script.rangeModifier, script.penetration
		w.clip, w.ammo, w.fullAuto = script.clip, script.ammo, script.fullAuto == true
		w.accuracy, w.alt = Frozen(script.accuracy), Frozen(script.alt or script.accuracy)
		w.second = SECOND[class] and Frozen(SECOND[class]) or nil
		w.kick = Frozen(KICK[class] or KICK_BY_TYPE[script.type])
		w.reload = RELOAD[script.type]
	elseif kind == GRENADE then
		w.grenade = Frozen(GRENADES[class])
	end
	return Frozen(w)
end

WEAPONS = {}
for _, class in ipairs(CLASSES) do
	local script = Scripts.SCRIPTS[class]
	if not script then Refuse(class, "has no script") end
	WEAPONS[class] = Weapon(class, script)
end

-- The classes a team may use: its own and either team's, in CLASSES' order.
function For(team)
	local list = {}
	for _, class in ipairs(CLASSES) do
		local t = WEAPONS[class].team
		if t == ANY or t == team then list[#list + 1] = class end
	end
	return list
end

function Set(list)
	local set = {}
	for _, v in ipairs(list) do set[v] = true end
	return set
end

-- The accuracy model in use: the second mode's (silencer on, scoped) or the
-- weapon's.
function Accuracy(weapon, second)
	if second then return weapon.alt end
	return weapon.accuracy
end

function Base(acc, crouching)
	return crouching and acc.crouch or acc.stand
end

function Inaccuracy(weapon, acc, state)
	local inaccuracy = state.penalty
	local speed = weapon.maxSpeed
	local moving = Scalar.InverseLerp(speed * MOVE_FROM, speed * MOVE_FULL, state.speed)
	if moving > 0 then inaccuracy = inaccuracy + moving ^ MOVE_CURVE * acc.move end
	if not state.onGround then inaccuracy = inaccuracy + acc.jump end
	if state.ladder then inaccuracy = inaccuracy + acc.ladder end
	return min(inaccuracy, MAX_INACCURACY)
end

function Fired(acc, penalty) return penalty + acc.fire end
function Landed(acc, penalty) return penalty + acc.land end

local TENTH = log(10)

function Recover(acc, penalty, crouching, seconds)
	local base = Base(acc, crouching)
	local time = crouching and acc.recoveryCrouch or acc.recoveryStand
	return base + (penalty - base) * exp(-seconds * TENTH / time)
end

function Spray(inaccuracy, spread, bullets, random)
	local theta, radius = random() * 2 * pi, random() * inaccuracy
	local x0, y0 = radius * cos(theta), radius * sin(theta)
	local offsets = {}
	for i = 1, bullets do
		local t, r = random() * 2 * pi, random() * spread
		offsets[i] = { x = x0 + r * cos(t), y = y0 + r * sin(t) }
	end
	return offsets
end

function Damage(weapon, distance, hitgroup)
	if distance > weapon.range then return 0 end
	return weapon.damage * weapon.rangeModifier ^ (distance / FALLOFF_STEP) * (HITGROUPS[hitgroup] or 1)
end

function Kick(weapon, stance, shots, punch, left, roll)
	local k, scale = weapon.kick, STANCES[stance]
	if k.punch then
		local low, high = k.punch[1], k.punch[2]
		return { pitch = punch.pitch - (low + (high - low) * roll) * scale, yaw = punch.yaw }, left
	end
	local extra = shots > 1 and shots or 0
	local up = (k.upBase + extra * k.upModifier) * scale
	local lateral = (k.lateralBase + extra * k.lateralModifier) * scale
	local pitch = punch.pitch - up
	if pitch < -k.upMax * scale then pitch = -k.upMax * scale end
	local yaw = punch.yaw + (left and lateral or -lateral)
	local most = k.lateralMax * scale
	if yaw > most then yaw = most elseif yaw < -most then yaw = -most end
	if roll == 0 then left = not left end
	return { pitch = pitch, yaw = yaw }, left
end

-- fromAttacker: the way from attacker to victim, victimFacing: the way the
-- victim faces, both across the ground and of length 1.
function Backstab(fromAttacker, victimFacing)
	return fromAttacker.x * victimFacing.x + fromAttacker.y * victimFacing.y > BACKSTAB_DOT
end

function KnifeDamage(strike, back)
	return strike.damage * (back and BACKSTAB or 1)
end
