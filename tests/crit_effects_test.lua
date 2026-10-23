local T = dofile("tests/harness.lua")
local Teams = gameplay.teams
local Crit = T.require("games.gameplay.combat.crit_effects")

-- CTFWeaponBase::GetTracerType and FireBullet: the weapon's tracer, by
-- team, with _crit for a crit; RED's for RED, BLU's for anyone else.
T.test("a crit bullet's tracer is its shooter's team's, BLU's for anyone else", function()
	T.eq(Crit.Tracer(Teams.RED), "bullet_tracer01_red_crit", "RED")
	T.eq(Crit.Tracer(Teams.BLUE), "bullet_tracer01_blue_crit", "BLU")
	T.eq(Crit.Tracer(Teams.UNASSIGNED), "bullet_tracer01_blue_crit", "no team")
end)

-- C_TFProjectile_Rocket and C_TFProjectile_Arrow trail critical_rocket_*,
-- a crit grenade critical_grenade_*.
T.test("a crit projectile trails its kind's crit trail in its team's colour", function()
	T.eq(Crit.Trail("rpg_missile", Teams.RED), "critical_rocket_red", "rocket")
	T.eq(Crit.Trail("crossbow_bolt", Teams.BLUE), "critical_rocket_blue", "bolt")
	T.eq(Crit.Trail("npc_grenade_frag", Teams.RED), "critical_grenade_red", "frag")
	T.eq(Crit.Trail("npc_grenade_frag", Teams.UNASSIGNED), "critical_grenade_blue", "no team")
end)

T.test("a projectile with no crit trail has none", function()
	T.eq(Crit.Trail("prop_combine_ball", Teams.RED), nil, "combine ball")
end)

T.test("every particle named is precached once, from the files listed", function()
	local seen = {}
	for _, name in ipairs(Crit.PARTICLES) do
		T.eq(seen[name], nil, "once: " .. name)
		seen[name] = true
	end
	for _, team in ipairs({ Teams.RED, Teams.BLUE }) do
		T.eq(seen[Crit.Tracer(team)], true, "tracer " .. team)
		for class in pairs(Crit.TRAILS) do T.eq(seen[Crit.Trail(class, team)], true, class .. " " .. team) end
	end
	T.eq(#Crit.FILES > 0, true, "files")
end)

T.finish()
