-- The npc feature's particle files, in both realms: a mounted game's .pcf
-- must be added where its systems are used, so the server can precache the
-- names its NPCs send (the controller does, per variant, from the variant's
-- PARTICLES) and clients can draw them. The rockets MONOCULUS fires and the
-- vortexes it leaves use these files too.
local FILES = {
	"particles/scary_ghost.pcf", -- halloween_boss_summon, _axe_hit_world, _death, _injured
	"particles/eyeboss.pcf", -- eyeboss_tp_normal, _tp_escape, _death, _tp_vortex, _aura_angry, _projectile
	"particles/cinefx.pcf", -- bomibomicon_ring (the skeleton king's stomp)
	"particles/halloween.pcf", -- spell_skeleton_goop_green, spell_pumpkin_mirv_goop_red and _blue
	"particles/rockettrail.pcf", -- rockettrail, critical_rocket_red and _blue
	"particles/explosion.pcf", -- ExplosionCore_Wall, ExplosionCore_MidAir
}

for _, path in ipairs(FILES) do game.AddParticles(path) end
