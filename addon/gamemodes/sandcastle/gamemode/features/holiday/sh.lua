-- The holiday feature's particles, in both realms: the server precaches the
-- name it sends and clients need the file to draw it. Only a taken
-- Halloween gift plays one (foundation.holiday.gift).
local Gift = WETSAND.require("foundation.holiday.gift")

local FILES = {
	"particles/halloween.pcf", -- duck_collect_green
}

for _, path in ipairs(FILES) do game.AddParticles(path) end

PrecacheParticleSystem(Gift.TAKE_PARTICLE)
