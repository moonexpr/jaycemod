local T = dofile("tests/harness.lua")
local Balance = T.require("foundation.combat.weapon_balance")

local W = Balance.WEAPONS
local FALLOFF = Balance.FALLOFF
local MEDIUM, SHORT = FALLOFF[Balance.RANGE_MEDIUM], FALLOFF[Balance.RANGE_SHORT]
local CLOSE = Balance.CLOSE_CRITS

local function Bullet(fields)
	local hit = {
		damage = 10,
		bullet = true,
		blast = false,
		distance = 0,
		headshot = false,
		roll = 1,
	}
	for k, v in pairs(fields or {}) do hit[k] = v end
	return hit
end

T.test("the tuning is defined", function()
	T.defined(W.weapon_crossbow.damage, "crossbow damage")
	T.defined(W.weapon_crossbow.knockback, "crossbow knockback")
	T.defined(W.weapon_crossbow.headshotKnockback, "crossbow headshot knockback")
	T.defined(W.weapon_crossbow.lift, "crossbow lift")
	T.defined(W.weapon_pistol.damage, "pistol damage")
	T.defined(W.weapon_pistol.cone, "pistol cone")
	T.defined(W.weapon_pistol.interval, "pistol interval")
	T.defined(W.weapon_357.damage, "magnum damage")
	T.defined(W.weapon_357.interval, "magnum interval")
	for _, range in ipairs({ Balance.RANGE_MEDIUM, Balance.RANGE_SHORT }) do
		T.defined(FALLOFF[range].start, range .. " falloff start")
		T.defined(FALLOFF[range].finish, range .. " falloff finish")
		T.defined(FALLOFF[range].floor, range .. " falloff floor")
	end
	T.defined(CLOSE.far, "close crits far")
	T.defined(CLOSE.near, "close crits near")
	T.defined(CLOSE.chance, "close crits chance")
end)

T.test("a projectile is balanced as the weapon that fired it", function()
	T.eq(Balance.Weapon("crossbow_bolt"), "weapon_crossbow", "a bolt")
	T.eq(Balance.Weapon("rpg_missile"), "weapon_rpg", "a rocket")
	T.eq(Balance.Weapon("npc_grenade_frag"), "weapon_frag", "a frag")
	T.eq(Balance.Weapon("npc_satchel"), "weapon_slam", "a satchel")
	T.eq(Balance.Weapon("weapon_pistol"), "weapon_pistol", "a weapon itself")
	T.eq(Balance.Weapon("weapon_crowbar"), "weapon_crowbar", "a weapon left as HL2 has it")
	T.eq(Balance.Weapon("prop_physics"), nil, "anything else")
end)

T.test("the crossbow hits for its own damage and never crits on a headshot", function()
	local damage, headshot, crit = Balance.Shot("weapon_crossbow", Bullet({ damage = 100, headshot = true }))
	T.eq(damage, W.weapon_crossbow.damage, "its damage, not the bolt's")
	T.eq(headshot, false, "a headshot does not count")
	T.eq(crit, false, "no crit")
end)

T.test("other weapons keep their headshot", function()
	local _, headshot = Balance.Shot("weapon_357", Bullet({ headshot = true }))
	T.eq(headshot, true, "the magnum")
	local _, melee = Balance.Shot("weapon_crowbar", Bullet({ bullet = false, headshot = true }))
	T.eq(melee, true, "the crowbar")
	local _, unknown = Balance.Shot(nil, Bullet({ headshot = true }))
	T.eq(unknown, true, "a weapon the balance does not know")
end)

-- A weapon's range: the long-range guns never fall off; the medium- and
-- short-range ones fall off past their range's FALLOFF.
T.test("the pistol and magnum are long-range and hit for their own damage at any range", function()
	T.eq(W.weapon_pistol.range, Balance.RANGE_LONG, "pistol")
	T.eq(W.weapon_357.range, Balance.RANGE_LONG, "magnum")
	T.eq(FALLOFF[Balance.RANGE_LONG], nil, "no falloff")
	T.eq(Balance.Shot("weapon_pistol", Bullet({ damage = 5 })), W.weapon_pistol.damage, "pistol up close")
	T.eq(Balance.Shot("weapon_pistol", Bullet({ damage = 5, distance = MEDIUM.finish * 2 })), W.weapon_pistol.damage, "pistol far")
	T.eq(Balance.Shot("weapon_357", Bullet({ damage = 40, distance = MEDIUM.finish * 2 })), W.weapon_357.damage, "magnum far")
end)

-- Full damage to the curve's start, its floor at its finish and beyond,
-- halfway between them halfway down; base: the weapon's own damage, or the
-- hit's.
local function FallsOff(class, curve)
	local base = W[class].damage or 10
	T.eq(Balance.Shot(class, Bullet({ distance = curve.start })), base, class .. " at the start")
	T.near(Balance.Shot(class, Bullet({ distance = curve.finish })), base * curve.floor, 1e-9, class .. " at the finish")
	T.near(Balance.Shot(class, Bullet({ distance = curve.finish * 3 })), base * curve.floor, 1e-9, class .. " beyond")
	local middle = (curve.start + curve.finish) / 2
	T.near(Balance.Shot(class, Bullet({ distance = middle })), base * (1 + curve.floor) / 2, 1e-9, class .. " halfway")
end

T.test("the automatics and the crossbow are medium-range and fall off past it", function()
	for _, class in ipairs({ "weapon_smg1", "weapon_ar2", "weapon_crossbow" }) do
		T.eq(W[class].range, Balance.RANGE_MEDIUM, class)
		FallsOff(class, MEDIUM)
	end
end)

T.test("the shotgun is short-range and falls off past it", function()
	T.eq(W.weapon_shotgun.range, Balance.RANGE_SHORT, "shotgun")
	FallsOff("weapon_shotgun", SHORT)
end)

T.test("every weapon that fires bullets has a range", function()
	for _, class in ipairs({ "weapon_pistol", "weapon_357", "weapon_smg1", "weapon_ar2", "weapon_crossbow", "weapon_shotgun" }) do
		T.eq(FALLOFF[W[class].range] ~= nil or W[class].range == Balance.RANGE_LONG, true, class)
	end
end)

T.test("an automatic's grenade or ball is not a bullet and does not fall off", function()
	T.eq(Balance.Shot("weapon_smg1", Bullet({ damage = 100, bullet = false, distance = MEDIUM.finish })), 100, "smg grenade")
end)

T.test("the shotgun crits more the closer it is", function()
	local function Crit(distance, roll)
		local _, _, crit = Balance.Shot("weapon_shotgun", Bullet({ distance = distance, roll = roll }))
		return crit
	end
	T.eq(Crit(CLOSE.far, 0), false, "never at the far edge")
	T.eq(Crit(CLOSE.far * 2, 0), false, "never beyond it")
	T.eq(Crit(CLOSE.near, CLOSE.chance - 0.01), true, "up close, under the chance")
	T.eq(Crit(0, CLOSE.chance - 0.01), true, "point blank")
	T.eq(Crit(CLOSE.near, CLOSE.chance), false, "up close, at the chance")
	local middle = (CLOSE.near + CLOSE.far) / 2
	T.eq(Crit(middle, CLOSE.chance / 2 - 0.01), true, "halfway, under half the chance")
	T.eq(Crit(middle, CLOSE.chance / 2 + 0.01), false, "halfway, over half the chance")
end)

T.test("only the shotgun crits by distance", function()
	local _, _, crit = Balance.Shot("weapon_smg1", Bullet({ roll = 0 }))
	T.eq(crit, false, "the smg")
end)

T.test("explosives hit harder by the same falloff", function()
	for class, inflictor in pairs({ weapon_frag = "npc_grenade_frag", weapon_rpg = "rpg_missile", weapon_slam = "npc_satchel" }) do
		local base = Balance.HL2_BLAST[class]
		local full = Balance.Shot(Balance.Weapon(inflictor), Bullet({ bullet = false, blast = true, damage = base }))
		T.near(full, W[class].blast, 1e-9, class .. " at the centre")
		local edge = Balance.Shot(Balance.Weapon(inflictor), Bullet({ bullet = false, blast = true, damage = base / 2 }))
		T.near(edge, W[class].blast / 2, 1e-9, class .. " further out")
	end
end)

T.test("melee keeps its damage", function()
	T.eq(Balance.Shot("weapon_crowbar", Bullet({ bullet = false, damage = 10 })), 10, "crowbar")
	T.eq(Balance.Shot("weapon_stunstick", Bullet({ bullet = false, damage = 10 })), 10, "stunstick")
end)

T.test("the crossbow knocks back, harder on a headshot", function()
	local bolt = W.weapon_crossbow
	local push = Balance.Knockback("weapon_crossbow", false)
	T.eq(push.speed, bolt.knockback, "a body shot")
	T.eq(push.lift, bolt.knockback * bolt.lift, "lifted off the ground")
	T.eq(push.stagger, bolt.stagger, "its stagger")
	T.eq(push.slow, bolt.staggerSlow, "its slow")
	local head = Balance.Knockback("weapon_crossbow", true)
	T.eq(head.speed, bolt.knockback * bolt.headshotKnockback, "a headshot")
	T.eq(head.lift, head.speed * bolt.lift, "lifted by its own speed")
	T.eq(Balance.Knockback("weapon_357", false), nil, "no other weapon")
end)

T.test("the pistol and magnum fire no faster than their interval", function()
	T.eq(Balance.CanFire("weapon_pistol", nil, 0), true, "never fired")
	T.eq(Balance.CanFire("weapon_pistol", 10, 10 + W.weapon_pistol.interval / 2), false, "too soon")
	T.eq(Balance.CanFire("weapon_pistol", 10, 10 + W.weapon_pistol.interval), true, "on time")
	T.eq(Balance.CanFire("weapon_357", 10, 10 + W.weapon_357.interval / 2), false, "the magnum too soon")
	T.eq(Balance.CanFire("weapon_smg1", 10, 10), true, "an automatic is the engine's")
	T.eq(Balance.NextShot("weapon_357", 10), 10 + W.weapon_357.interval, "the magnum's next shot")
	T.eq(Balance.NextShot("weapon_smg1", 10), nil, "an automatic has none")
end)

T.test("the pistol and magnum shoot within their cone", function()
	T.near(Balance.Spread("weapon_pistol"), math.sin(math.rad(W.weapon_pistol.cone / 2)), 1e-12, "the pistol's")
	T.eq(Balance.Spread("weapon_357"), 0, "the magnum is exact")
	T.eq(Balance.Spread("weapon_smg1"), nil, "an automatic's is the engine's")
end)

T.test("the Store shows the damage a weapon deals", function()
	T.eq(Balance.Damage("weapon_crossbow", 100), W.weapon_crossbow.damage, "crossbow")
	T.eq(Balance.Damage("weapon_rpg", 100), W.weapon_rpg.blast, "rpg")
	T.eq(Balance.Damage("weapon_smg1", 4), 4, "smg, the skill's")
end)

T.finish()
