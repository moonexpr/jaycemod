-- An NPC spawner (CZombieSpawner, as a model). New{ class, team, maxActive,
-- infinite, npcConfig, teamOf }: `class` and `npcConfig` describe what it
-- spawns, `team` is the spawner's own, and `teamOf(team)` is the variant's
-- team strategy, giving the team of what it spawns. The controller calls
-- Think(now, random) as often as it likes; when a request comes back it
-- spawns the NPC and reports it with Spawned(handle), and reports removal
-- with Died(handle). `random(lo, hi)` draws a float.
local pairs, setmetatable = pairs, setmetatable
module(...)

IDLE_THINK = 0.2
SPAWN_THINK_MIN, SPAWN_THINK_MAX = 1.5, 3 -- after a spawn

local Spawner = {}
Spawner.__index = Spawner

function New(cfg)
	return setmetatable({
		class = cfg.class,
		team = cfg.team,
		maxActive = cfg.maxActive,
		infinite = cfg.infinite,
		npcConfig = cfg.npcConfig,
		teamOf = cfg.teamOf,
		enabled = false,
		spawned = 0,
		active = {},
		activeCount = 0,
		nextThink = 0, -- CZombieSpawner::Spawn thinks at once
	}, Spawner)
end

-- CZombieSpawner::InputEnable
function Spawner:Enable(now)
	self.enabled = true
	self.nextThink = now
end

-- CZombieSpawner::InputDisable: the NPCs already out are forgotten.
function Spawner:Disable()
	self.enabled = false
	self.spawned = 0
	self.active = {}
	self.activeCount = 0
end

function Spawner:SetMaxActive(n)
	self.maxActive = n
end

function Spawner:Spawned(handle)
	self.spawned = self.spawned + 1
	self.active[handle] = true
	self.activeCount = self.activeCount + 1
end

function Spawner:Died(handle)
	if self.active[handle] then
		self.active[handle] = nil
		self.activeCount = self.activeCount - 1
	end
end

-- An infinite spawner keeps `maxActive` alive; a finite one spawns
-- `maxActive` in all until it is disabled.
function Spawner:HasRoom()
	if self.infinite then return self.activeCount < self.maxActive end
	return self.spawned < self.maxActive
end

function Spawner:Request()
	local config = {}
	for k, v in pairs(self.npcConfig) do config[k] = v end
	config.team = self.teamOf(self.team)
	return {
		class = self.class,
		config = config,
	}
end

-- CZombieSpawner::Think. Returns a spawn request or nil, and when it next
-- wants to think.
function Spawner:Think(now, random)
	if now < self.nextThink then return nil, self.nextThink end
	if self.enabled and self:HasRoom() then
		self.nextThink = now + random(SPAWN_THINK_MIN, SPAWN_THINK_MAX)
		return self:Request(), self.nextThink
	end
	self.nextThink = now + IDLE_THINK
	return nil, self.nextThink
end
