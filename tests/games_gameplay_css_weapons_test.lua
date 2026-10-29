-- games.gameplay.css_weapons: CS:S's weapons, made from the game's own
-- scripts (css_weapons/scripts.lua): their teams, damage by range and hit
-- group, the accuracy model (a penalty each shot adds and time takes away,
-- movement, the air), the spray a shot's bullets make, recoil, second modes
-- (silencer, burst, scope) and the knife's backstab.
local T = dofile("tests/harness.lua")
local Css = gameplay.css_weapons
local Scripts = T.require("games.gameplay.css_weapons.scripts")

local AK, M4, AWP, GLOCK, M3 = "weapon_ak47", "weapon_m4a1", "weapon_awp", "weapon_glock", "weapon_m3"

T.test("every script but C4's is a weapon, and every weapon listed has a script", function()
	local listed = {}
	for _, class in ipairs(Css.CLASSES) do
		listed[class] = true
		T.eq(Css.WEAPONS[class] ~= nil, true, class)
	end
	for class in pairs(Scripts.SCRIPTS) do T.eq(listed[class], true, class .. " listed") end
	T.eq(Css.WEAPONS.weapon_c4, nil, "no C4")
end)

T.test("a weapon is shown by GMod's c_ model of it, held in the player's own hands", function()
	for class, w in pairs(Css.WEAPONS) do
		T.eq(w.viewModel:find("^models/weapons/cstrike/c_") ~= nil, true, class .. " " .. w.viewModel)
		T.eq(w.worldModel:find("^models/weapons/w_") ~= nil, true, class)
	end
	T.eq(Css.WEAPONS[AK].viewModel, "models/weapons/cstrike/c_rif_ak47.mdl", "the AK's")
end)

T.test("the knife and the grenades are their own kinds; every gun has an accuracy model", function()
	T.eq(Css.WEAPONS.weapon_knife.kind, Css.KNIFE, "knife")
	for _, g in ipairs({ "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade" }) do
		T.eq(Css.WEAPONS[g].kind, Css.GRENADE, g)
	end
	for class, w in pairs(Css.WEAPONS) do
		if w.kind == Css.GUN then
			T.eq(type(w.accuracy.spread), "number", class .. " spread")
			T.eq(type(w.kick), "table", class .. " kick")
			T.eq(Css.AMMO[w.ammo] ~= nil, true, class .. " ammo " .. tostring(w.ammo))
		end
	end
end)

T.test("a team may use its own weapons and either team's, never the other team's", function()
	local t, ct = Css.Set(Css.For(Css.TERRORIST)), Css.Set(Css.For(Css.CT))
	T.eq(t[AK], true, "T: AK")
	T.eq(t[M4], nil, "T: no M4")
	T.eq(ct[M4], true, "CT: M4")
	T.eq(ct[AK], nil, "CT: no AK")
	T.eq(t[AWP] and ct[AWP], true, "both: AWP")
end)

T.test("a bullet's damage falls off by the range modifier every 500 units and stops at its range", function()
	local ak = Css.WEAPONS[AK]
	T.near(Css.Damage(ak, 0, Css.HITGROUP_CHEST), ak.damage, 1e-9, "point blank")
	T.near(Css.Damage(ak, Css.FALLOFF_STEP, Css.HITGROUP_CHEST), ak.damage * ak.rangeModifier, 1e-9, "one step")
	T.near(Css.Damage(ak, 0, Css.HITGROUP_HEAD), ak.damage * Css.HITGROUPS[Css.HITGROUP_HEAD], 1e-9, "head")
	T.eq(Css.HITGROUPS[Css.HITGROUP_HEAD] > Css.HITGROUPS[Css.HITGROUP_STOMACH], true, "head over stomach")
	T.eq(Css.HITGROUPS[Css.HITGROUP_LEFTLEG] < 1, true, "legs under 1")
	T.eq(Css.Damage(ak, ak.range + 1, Css.HITGROUP_CHEST), 0, "past its range")
	T.near(Css.Damage(ak, 0, 99), ak.damage, 1e-9, "an unknown group as generic")
end)

local function Still(penalty) return { penalty = penalty, speed = 0, onGround = true } end

T.test("inaccuracy: the penalty standing still, plus movement past a third of the weapon's speed, plus the air", function()
	local ak = Css.WEAPONS[AK]
	local acc = Css.Accuracy(ak, false)
	local base = Css.Base(acc, false)
	T.near(Css.Inaccuracy(ak, acc, Still(base)), base, 1e-9, "still")
	T.near(Css.Inaccuracy(ak, acc, { penalty = base, speed = ak.maxSpeed * Css.MOVE_FROM * 0.9, onGround = true }), base, 1e-9,
		"walking slowly")
	T.near(Css.Inaccuracy(ak, acc, { penalty = base, speed = ak.maxSpeed, onGround = true }), base + acc.move, 1e-9, "running")
	T.near(Css.Inaccuracy(ak, acc, { penalty = base, speed = 0, onGround = false }), base + acc.jump, 1e-9, "in the air")
	T.eq(Css.Inaccuracy(ak, acc, { penalty = 5, speed = ak.maxSpeed, onGround = false, ladder = true }), Css.MAX_INACCURACY, "held")
end)

T.test("each shot adds its fire penalty, and its recovery time takes nine tenths of what is over the base away", function()
	local acc = Css.Accuracy(Css.WEAPONS[AK], false)
	local base = Css.Base(acc, false)
	local fired = Css.Fired(acc, base)
	T.near(fired, base + acc.fire, 1e-9, "fired")
	T.near(Css.Recover(acc, fired, false, acc.recoveryStand), base + acc.fire / 10, 1e-9, "recovered")
	T.near(Css.Recover(acc, fired, false, 0), fired, 1e-9, "no time")
	T.eq(Css.Base(acc, true) < Css.Base(acc, false), true, "crouching is steadier")
	T.near(Css.Recover(acc, base, true, 1e6), Css.Base(acc, true), 1e-9, "settles to the crouch's base")
	T.near(Css.Landed(acc, base), base + acc.land, 1e-9, "landing")
end)

T.test("a shot's spray: one offset a bullet, within its inaccuracy and spread, all centred with no randomness", function()
	local m3 = Css.WEAPONS[M3]
	local zero = function() return 0 end
	local spray = Css.Spray(0.05, m3.accuracy.spread, m3.bullets, zero)
	T.eq(#spray, m3.bullets, "pellets")
	for _, o in ipairs(spray) do
		T.eq(o.x, 0, "x")
		T.eq(o.y, 0, "y")
	end
	local n = 0
	local wobbly = function() n = n + 1; return (n * 0.37) % 1 end
	for _, o in ipairs(Css.Spray(0.05, m3.accuracy.spread, m3.bullets, wobbly)) do
		T.eq(math.sqrt(o.x * o.x + o.y * o.y) <= 0.05 + m3.accuracy.spread + 1e-9, true, "within the cone")
	end
end)

T.test("recoil: an automatic gun climbs with each shot to its most, and swings aside, changing side on a roll of 0", function()
	local ak = Css.WEAPONS[AK]
	local k = ak.kick
	T.eq(k.upBase ~= nil, true, "a KickBack")
	local punch, left = Css.Kick(ak, Css.STAND, 1, { pitch = 0, yaw = 0 }, true, 1)
	T.near(punch.pitch, -k.upBase, 1e-9, "first shot up")
	T.near(punch.yaw, k.lateralBase, 1e-9, "aside")
	T.eq(left, true, "no change on a roll above 0")
	local _, flipped = Css.Kick(ak, Css.STAND, 1, { pitch = 0, yaw = 0 }, true, 0)
	T.eq(flipped, false, "changes side on 0")
	local climbed = Css.Kick(ak, Css.STAND, 200, { pitch = 0, yaw = 0 }, true, 1)
	T.near(climbed.pitch, -k.upMax, 1e-9, "held at its most")
	local air = Css.Kick(ak, Css.AIR, 1, { pitch = 0, yaw = 0 }, true, 1)
	T.eq(air.pitch < punch.pitch, true, "more in the air")
end)

T.test("recoil: a gun of one punch a shot kicks up within its range, whatever came before", function()
	local deagle = Css.WEAPONS.weapon_deagle
	T.eq(deagle.kick.punch ~= nil, true, "a punch")
	local low = Css.Kick(deagle, Css.STAND, 1, { pitch = 0, yaw = 0 }, true, 0)
	local high = Css.Kick(deagle, Css.STAND, 1, { pitch = 0, yaw = 0 }, true, 1)
	T.near(low.pitch, -deagle.kick.punch[1], 1e-9, "the least")
	T.near(high.pitch, -deagle.kick.punch[2], 1e-9, "the most")
end)

T.test("second modes: the M4A1's silencer and the AWP's scope use the script's second accuracy; the Glock bursts", function()
	local m4, awp, glock = Css.WEAPONS[M4], Css.WEAPONS[AWP], Css.WEAPONS[GLOCK]
	T.eq(m4.second.mode, Css.SILENCER, "M4A1")
	T.eq(Css.Accuracy(m4, true), m4.alt, "silenced")
	T.eq(Css.Accuracy(m4, false), m4.accuracy, "bare")
	T.eq(awp.second.mode, Css.SCOPE, "AWP")
	T.eq(Css.Accuracy(awp, true).stand < Css.Accuracy(awp, false).stand, true, "steadier scoped")
	for i = 2, #awp.second.fov do T.eq(awp.second.fov[i] < awp.second.fov[i - 1], true, "zooms in") end
	T.eq(glock.second.mode, Css.BURST, "Glock")
	T.eq(glock.second.rounds > 1, true, "a burst")
	T.eq(Css.WEAPONS[AK].second, nil, "the AK has none")
end)

T.test("the knife: a stab hits harder than a slash, and either hits harder from behind", function()
	local knife = Css.KNIFE_STATS
	T.eq(knife.stab.damage > knife.slash.damage, true, "stab")
	T.eq(knife.stab.reach < knife.slash.reach, true, "a stab reaches less")
	T.eq(Css.Backstab({ x = 1, y = 0 }, { x = 1, y = 0 }), true, "behind")
	T.eq(Css.Backstab({ x = 1, y = 0 }, { x = -1, y = 0 }), false, "face to face")
	T.eq(Css.Backstab({ x = 1, y = 0 }, { x = 0, y = 1 }), false, "beside")
	T.eq(Css.KnifeDamage(knife.stab, true), knife.stab.damage * Css.BACKSTAB, "a backstab")
end)

T.test("a gun script without its accuracy model is refused", function()
	local ok, err = pcall(Css.Weapon, "weapon_broken", { type = "Rifle", team = "ANY" })
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("weapon_broken") ~= nil, true, "named")
end)

T.test("the tuning the scripts lack is defined", function()
	T.defined(Css.FALLOFF_STEP, "falloff step")
	T.defined(Css.MOVE_FROM, "movement from")
	T.defined(Css.GRENADES.weapon_hegrenade.damage, "HE damage")
	T.defined(Css.GRENADES.weapon_hegrenade.radius, "HE radius")
	T.defined(Css.GRENADES.weapon_flashbang.blind, "flash")
	T.defined(Css.GRENADES.weapon_smokegrenade.duration, "smoke")
	for class, w in pairs(Css.WEAPONS) do
		if w.kind == Css.GUN then T.defined(w.reload, class .. " reload") end
	end
end)

T.finish()
