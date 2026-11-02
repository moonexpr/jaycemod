-- nextsoldier.weapons: the soldiers' own guns (issue #8 L3), HL2's fired by
-- a NextBot: each class's stats, and a magazine per weapon held that fires
-- at its pace, empties and reloads.
local T = dofile("tests/harness.lua")
local Weapons = nextsoldier.weapons

local function Definition(class)
	local path = "addons/cstrike_weapons/lua/weapons/" .. class .. ".lua"
	local definition = { SWEP = {}, AddCSLuaFile = function() end, Model = function(path) return path end }
	setmetatable(definition, { __index = _G })
	local chunk = assert(loadfile(path))
	setfenv(chunk, definition)()
	return definition.SWEP
end

local GUN = Weapons.Stats({ damage = 5, bullets = 1, interval = 0.1, clip = 3, reload = 2,
	sound = "Weapon_Test.Single", tracer = "Tracer", hold = "ar2", spread = 3 })

T.test("a full magazine fires at once, then at its interval", function()
	local m = Weapons.Magazine(GUN)
	T.eq(m:Ready(0), true)
	m:Fire(0)
	T.eq(m:Ready(0.05), false, "inside the interval")
	T.eq(m:Ready(0.1), true)
	T.eq(m:Rounds(), 2)
end)

T.test("emptied, it reloads for its reload time and comes back full", function()
	local m = Weapons.Magazine(GUN)
	m:Fire(0)
	m:Fire(0.1)
	m:Fire(0.2)
	T.eq(m:Rounds(), 0)
	T.eq(m:Reloading(0.3), true)
	T.eq(m:Ready(1.0), false, "reloading")
	T.eq(m:Ready(2.2), true, "reloaded at the third shot's time plus the reload")
	T.eq(m:Rounds(), GUN.clip)
	T.eq(m:Reloading(2.2), false)
end)

T.test("firing when not ready is our bug, refused", function()
	local m = Weapons.Magazine(GUN)
	m:Fire(0)
	T.eq(pcall(m.Fire, m, 0.01), false)
end)

T.test("HL2's guns the soldiers carry have stats", function()
	for _, class in ipairs({ "weapon_ar2", "weapon_smg1", "weapon_shotgun", "weapon_pistol", "weapon_357", "weapon_crossbow" }) do
		local stats = Weapons.STATS[class]
		T.eq(stats ~= nil, true, class)
		T.eq(stats.clip > 0 and stats.interval > 0 and stats.bullets > 0, true, class .. " fires")
	end
end)

T.test("CS:S NextSoldier stats live on each terminal weapon", function()
	for _, class in ipairs({ "weapon_ak47", "weapon_m3", "weapon_awp", "weapon_usp" }) do
		local definition = Definition(class)
		T.eq(definition.CStrikeWeapon, true, class)
		T.eq(Weapons.Stat(definition, "damage"), definition.Stats.Ballistics.Damage, class .. " damage")
		T.eq(Weapons.Stat(definition, "bullets"), definition.Stats.Ballistics.BulletCount, class .. " bullets")
		T.eq(Weapons.Stat(definition, "interval"), definition.Stats.Ballistics.CycleTime, class .. " cycle")
		T.eq(Weapons.Stat(definition, "clip"), definition.Primary.ClipSize, class .. " clip")
		T.eq(Weapons.Stat(definition, "sound"), definition.SingleShotSound, class .. " sound")
		T.eq(Weapons.STATS[class], nil, class .. " is not copied into a class map")
		T.eq(definition.NextSoldier, nil, class .. " has no nested stats table")
		T.eq(definition.CSS, nil, class .. " has no CSS stats table")
	end
	T.eq(Definition("weapon_knife").SoldierDamage, nil, "the knife is not a gun")
end)

T.test("the crossbow throws a bolt that flies; the guns fire bullets", function()
	T.eq(Weapons.STATS.weapon_crossbow.projectile ~= nil, true, "a bolt")
	T.eq(Weapons.STATS.weapon_crossbow.projectile.speed > 0, true, "that flies")
	T.eq(Weapons.STATS.weapon_ar2.projectile, nil, "bullets")
end)

T.test("a projectile is aimed where its target will be when it arrives", function()
	local speed = 1000
	local at = Weapons.Lead({ x = 0, y = 0, z = 0 }, { x = 1000, y = 0, z = 0 }, { x = 0, y = 100, z = 0 }, speed)
	T.eq(at.x, 1000)
	T.eq(at.y, 100, "a second of flight: a second of its walk ahead")
	local still = Weapons.Lead({ x = 0, y = 0, z = 0 }, { x = 500, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, speed)
	T.eq(still.y, 0, "a target standing still is aimed at")
end)

T.test("a projectile's speed must be above 0", function()
	T.eq(pcall(Weapons.Stats, { damage = 5, bullets = 1, interval = 0.1, clip = 3, reload = 2,
		sound = "s", tracer = "t", hold = "ar2", spread = 0, projectile = { class = "crossbow_bolt", speed = 0 } }), false)
end)

T.test("stats missing a part are refused", function()
	T.eq(pcall(Weapons.Stats, { damage = 5, bullets = 1, interval = 0.1, clip = 3 }), false)
end)

T.test("a gun's damage is a number of its own, not a convar's name", function()
	local spec = { damage = "sk_npc_dmg_ar2", bullets = 1, interval = 0.1, clip = 3, reload = 2,
		sound = "Weapon_Test.Single", tracer = "Tracer", hold = "ar2", spread = 3 }
	T.eq(pcall(Weapons.Stats, spec), false)
	for class, stats in pairs(Weapons.STATS) do
		T.eq(type(stats.damage) == "number" and stats.damage > 0, true, class .. " hurts")
	end
end)

T.finish()
