-- The hazards feature's particles, in both realms: the server precaches the
-- names it sends (ParticleEffect, util.ParticleTracerEx) and clients need
-- the files to draw them. The event maps' own names (a generic bomb's
-- explode_particle, a zapper's ParticleEffect) come from these files too:
-- ghost_appearation on plr_hacksaw_event, merasmus_zap and
-- underworld_skull_zap on the zapper maps. The entities precache those.
local Pumpkin = WS.require("features.hazards.pumpkin_bomb")

local FILES = {
	"particles/item_fx.pcf", -- pumpkin_explode
	"particles/halloween.pcf", -- the goop and the zaps
	"particles/scary_ghost.pcf", -- ghost_appearation
}

for _, path in ipairs(FILES) do game.AddParticles(path) end

for _, name in ipairs({ Pumpkin.EXPLODE_PARTICLE, Pumpkin.GOOP_RED, Pumpkin.GOOP_BLUE }) do
	PrecacheParticleSystem(name)
end
