-- The spells feature's particles, in both realms: the server precaches the
-- names the spells and their projectiles play (CTFSpellBook::Precache) and
-- clients need the files to draw them.
local FILES = {
	"particles/halloween.pcf", -- the spells' own: wheels, bats, goop, orbs, trails
	"particles/cinefx.pcf", -- bombinomicon_burningdebris, bomibomicon_ring
	"particles/class_fx.pcf", -- heavy_ring_of_fire
	"particles/rocketjumptrail.pcf", -- rocketjump_smoke
	"particles/explosion.pcf", -- ExplosionCore_MidAir
	"particles/eyeboss.pcf", -- eyeboss_tp_player, eyeboss_death
	"particles/drg_cowmangler.pcf", -- the lightning orb's end
	"particles/item_fx.pcf", -- unusual_bubbles_green_fumes
}

local NAMES = {
	"spell_cast_wheel_red",
	"spell_cast_wheel_blue",
	"bombinomicon_burningdebris",
	"heavy_ring_of_fire",
	"rocketjump_smoke",
	"spell_overheal_red",
	"spell_overheal_blue",
	"ExplosionCore_MidAir",
	"spell_batball_impact_red",
	"spell_batball_impact_blue",
	"spell_batball_red",
	"spell_batball_blue",
	"spell_batball_throw_red",
	"spell_batball_throw_blue",
	"spell_pumpkin_mirv_goop_red",
	"spell_pumpkin_mirv_goop_blue",
	"eyeboss_tp_player",
	"eyeboss_death",
	"drg_cow_explosioncore_charged",
	"drg_cow_explosioncore_charged_blue",
	"spell_lightningball_hit_red",
	"spell_lightningball_hit_blue",
	"spell_lightningball_parent_red",
	"spell_lightningball_parent_blue",
	"bomibomicon_ring",
	"spell_fireball_tendril_parent_red",
	"spell_fireball_tendril_parent_blue",
	"spell_fireball_small_red",
	"spell_fireball_small_blue",
	"spell_teleport_red",
	"spell_teleport_blue",
	"unusual_bubbles_green_fumes",
}

for _, path in ipairs(FILES) do game.AddParticles(path) end
for _, name in ipairs(NAMES) do PrecacheParticleSystem(name) end
