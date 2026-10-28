-- nextsoldier.weapons: the soldiers' own guns (issue #8 L3), HL2's fired by
-- a NextBot: each class's stats, and a magazine per weapon held that fires
-- at its pace, empties and reloads.
local T = dofile("tests/harness.lua")
local Weapons = nextsoldier.weapons

local GUN = Weapons.Stats({ damage = "sk_npc_dmg_test", bullets = 1, interval = 0.1, clip = 3, reload = 2,
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

T.test("stats missing a part are refused", function()
	T.eq(pcall(Weapons.Stats, { damage = "x", bullets = 1, interval = 0.1, clip = 3 }), false)
end)

T.finish()
