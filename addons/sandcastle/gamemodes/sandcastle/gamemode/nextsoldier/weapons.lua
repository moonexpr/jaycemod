-- The soldiers' own guns (issue #8 L3): HL2's, fired by a NextBot as the
-- body fires (base_nextsoldier's RangeAttack), not DrGBase's weapons. A
-- gun's state is its magazine, as TF2 keeps it on the weapon: it fires at
-- its interval, empties, and reloads for its reload time before firing
-- again.
--
-- Stats{ damage (the skill convar of an HL2 NPC's damage with it), bullets
--   (a shot's), interval (between shots), clip, reload (seconds), sound,
--   tracer, hold (its hold type, for the body's acts), spread (degrees across
--   its cone: features.aiwar.arms' cones) } -> stats, made once
-- STATS[class] -> HL2's guns the soldiers carry
-- Magazine(stats) -> magazine: Ready(now), Fire(now) (refused when not
--   ready: our bug), Reloading(now), Rounds()
local error, setmetatable, type = error, setmetatable, type
module(...)

local PARTS = { "damage", "bullets", "interval", "clip", "reload", "sound", "tracer", "hold", "spread" }

function Stats(spec)
	local stats = {}
	for i = 1, #PARTS do
		local key = PARTS[i]
		if spec[key] == nil then error("gun stats need " .. key, 2) end
		stats[key] = spec[key]
	end
	return stats
end

-- HL2's guns: its NPCs' damage convars and fire rates, its clips, reload
-- times near its reload animations, its fire sounds and tracers.
STATS = {
	weapon_ar2 = Stats({ damage = "sk_npc_dmg_ar2", bullets = 1, interval = 0.1, clip = 30, reload = 1.6,
		sound = "Weapon_AR2.Single", tracer = "AR2Tracer", hold = "ar2", spread = 3 }),
	weapon_smg1 = Stats({ damage = "sk_npc_dmg_smg1", bullets = 1, interval = 0.075, clip = 45, reload = 1.5,
		sound = "Weapon_SMG1.Single", tracer = "Tracer", hold = "smg", spread = 5 }),
	weapon_shotgun = Stats({ damage = "sk_npc_dmg_buckshot", bullets = 8, interval = 0.8, clip = 6, reload = 2.5,
		sound = "Weapon_Shotgun.Single", tracer = "Tracer", hold = "shotgun", spread = 10 }),
	weapon_pistol = Stats({ damage = "sk_npc_dmg_pistol", bullets = 1, interval = 0.4, clip = 18, reload = 1.4,
		sound = "Weapon_Pistol.Single", tracer = "Tracer", hold = "pistol", spread = 2 }),
	weapon_357 = Stats({ damage = "sk_npc_dmg_357", bullets = 1, interval = 0.75, clip = 6, reload = 3,
		sound = "Weapon_357.Single", tracer = "Tracer", hold = "revolver", spread = 1 }),
	weapon_crossbow = Stats({ damage = "sk_npc_dmg_crossbow", bullets = 1, interval = 1.9, clip = 1, reload = 1.9,
		sound = "Weapon_Crossbow.Single", tracer = "Tracer", hold = "crossbow", spread = 0 }),
}

local Magazine_ = {}
Magazine_.__index = Magazine_

function Magazine(stats)
	return setmetatable({ stats = stats, rounds = stats.clip, nextShot = nil, reloadedAt = nil }, Magazine_)
end

-- A reload that has run its time fills the magazine.
local function Settle(self, now)
	if self.reloadedAt and now >= self.reloadedAt then
		self.rounds, self.reloadedAt = self.stats.clip, nil
	end
end

function Magazine_:Reloading(now)
	Settle(self, now)
	return self.reloadedAt ~= nil
end

function Magazine_:Ready(now)
	Settle(self, now)
	return self.reloadedAt == nil and self.rounds > 0 and (self.nextShot == nil or now >= self.nextShot)
end

function Magazine_:Fire(now)
	if not self:Ready(now) then error("a gun fired when not ready", 2) end
	self.rounds = self.rounds - 1
	self.nextShot = now + self.stats.interval
	if self.rounds == 0 then self.reloadedAt = now + self.stats.reload end
end

function Magazine_:Rounds() return self.rounds end
