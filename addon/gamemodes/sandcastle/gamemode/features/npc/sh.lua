-- The npc feature's particle files, in both realms: a mounted game's .pcf
-- must be added where its systems are used, so the server can precache the
-- names its NPCs send (the controller does, per variant, from the variant's
-- PARTICLES) and clients can draw them. The rockets MONOCULUS fires, the
-- vortexes it leaves, and Merasmus's bombs and props use these files too.
local FILES = {
	"particles/scary_ghost.pcf", -- halloween_boss_summon, _axe_hit_world, _death, _injured
	"particles/eyeboss.pcf", -- eyeboss_tp_normal, _tp_escape, _death, _tp_vortex, _aura_angry, _projectile
	"particles/cinefx.pcf", -- bomibomicon_ring (the skeleton king's stomp), bombinomicon_burningdebris
	"particles/halloween.pcf", -- spell_skeleton_goop_green, spell_pumpkin_mirv_goop_red and _blue, merasmus_*
	"particles/rockettrail.pcf", -- rockettrail, critical_rocket_red and _blue
	"particles/explosion.pcf", -- ExplosionCore_Wall, ExplosionCore_MidAir
}

for _, path in ipairs(FILES) do game.AddParticles(path) end

-- The Halloween bosses' game events, with TF2's fields (modevents.res:
-- level a short, time_remaining a byte). Names and cues:
-- foundation.npc.boss_events.
local E = WETSAND.Events
local LEVEL_BITS = 16
local SECONDS_BITS = 8

E.Define("pumpkin_lord_summoned", {})
E.Define("pumpkin_lord_killed", {})
E.Define("eyeball_boss_summoned", { level = E.Int(LEVEL_BITS) })
E.Define("eyeball_boss_killed", { level = E.Int(LEVEL_BITS) })
E.Define("eyeball_boss_escape_imminent", {
	level = E.Int(LEVEL_BITS),
	time_remaining = E.UInt(SECONDS_BITS),
})
E.Define("eyeball_boss_escaped", { level = E.Int(LEVEL_BITS) })
E.Define("merasmus_summoned", { level = E.Int(LEVEL_BITS) })
E.Define("merasmus_killed", { level = E.Int(LEVEL_BITS) })
E.Define("merasmus_escape_warning", {
	level = E.Int(LEVEL_BITS),
	time_remaining = E.UInt(SECONDS_BITS),
})
E.Define("merasmus_escaped", { level = E.Int(LEVEL_BITS) })

-- Sandcastle's own, for the chat line TF2 says for each of Merasmus's
-- killers (TF_Halloween_Merasmus_Killers).
E.Define("merasmus_killer", {
	player = E.Entity(),
	level = E.Int(LEVEL_BITS),
})

-- Sandcastle's own, for what TF2 networks as a player condition: a player
-- became a bomb head for duration seconds (0: no longer one).
E.Define("halloween_bomb_head", {
	player = E.Entity(),
	duration = E.Float(),
})
