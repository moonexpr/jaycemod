-- A trigger_ignite (CTriggerIgnite, tf_triggers.cpp): a player who walks in
-- catches fire for burnDuration, and while anyone is inside, every
-- BURN_INTERVAL each of them takes damagePercentPerSecond of his max health
-- per second as burn damage, and is set alight again once his fire has gone
-- out. Not a Hazards variant: the trigger_ignite binding owns this model and
-- carries out its events.
--
-- New({ burnDuration, damagePercentPerSecond }, players): players is the
-- port on the players' conditions, :InCond(target, cond) -> bool and
-- :MaxHealth(target) -> n. Targets are opaque handles. Then:
--   :StartTouch(now, target) -> events; :EndTouch(target);
--   :Think(now) -> events (nothing before NextBurn()); :NextBurn() (nil while
--   nobody is inside).
-- Events, in order:
--   { kind = IGNITE, target, duration }: IgniteEntity, the particle and
--     sound at the target; with a duration (nil when he is invulnerable or
--     already burning) he also catches fire for that long (SelfBurn);
--   { kind = DAMAGE, target, amount }: DMG_BURN from the trigger.
-- Only players touch it here, so CTriggerIgnite's removal of any other
-- entity that walks in is left out.
local ipairs, remove, setmetatable = ipairs, table.remove, setmetatable
local Players = require("foundation.players")
module(...)

-- The CTriggerIgnite constructor and BURN_INTERVAL.
BURN_DURATION_DEFAULT = 1
DAMAGE_PERCENT_DEFAULT = 10
BURN_INTERVAL = 0.1

IGNITE, DAMAGE = "ignite", "damage"

local PERCENT = 0.01
local C = Players.COND

-- CTFPlayerShared::IsInvulnerable
local INVULNERABLE_CONDS = {
	C.INVULNERABLE,
	C.INVULNERABLE_USER_BUFF,
	C.INVULNERABLE_HIDE_UNLESS_DAMAGED,
	C.INVULNERABLE_CARD_EFFECT,
}

local IgniteModel = {}
IgniteModel.__index = IgniteModel

-- nextBurn is when BurnThink runs next (nil: no think); lastBurn is
-- m_flLastBurnTime.
function New(config, players)
	return setmetatable({
		burnDuration = config.burnDuration or BURN_DURATION_DEFAULT,
		damagePercent = config.damagePercentPerSecond or DAMAGE_PERCENT_DEFAULT,
		players = players,
		touching = {},
		nextBurn = nil,
		lastBurn = 0,
	}, IgniteModel)
end

function IgniteModel:NextBurn() return self.nextBurn end

local function Invulnerable(players, target)
	for _, cond in ipairs(INVULNERABLE_CONDS) do
		if players:InCond(target, cond) then return true end
	end
	return false
end

-- Neither invulnerable nor already burning.
local function MayCatchFire(self, target)
	return not Invulnerable(self.players, target) and not self.players:InCond(target, C.BURNING)
end

-- IgniteEntity
local function Ignition(self, target)
	return {
		kind = IGNITE,
		target = target,
		duration = MayCatchFire(self, target) and self.burnDuration or nil,
	}
end

-- CTriggerIgnite::StartTouch: the ignition, and the burn think if none runs.
function IgniteModel:StartTouch(now, target)
	self.touching[#self.touching + 1] = target
	if self.nextBurn == nil then
		self.lastBurn = now
		self.nextBurn = now + BURN_INTERVAL
	end
	return { Ignition(self, target) }
end

-- The last one out stops the burn think, which in TF2 stops at its next
-- run for want of anyone to burn.
function IgniteModel:EndTouch(target)
	for i, t in ipairs(self.touching) do
		if t == target then
			remove(self.touching, i)
			break
		end
	end
	if #self.touching == 0 then self.nextBurn = nil end
end

-- BurnThink / BurnEntities: the damage is for the time since the last burn.
function IgniteModel:Think(now)
	if self.nextBurn == nil or now < self.nextBurn then return {} end
	local dt = now - self.lastBurn
	self.lastBurn = now
	self.nextBurn = now + BURN_INTERVAL
	local events = {}
	for _, target in ipairs(self.touching) do
		if MayCatchFire(self, target) then events[#events + 1] = Ignition(self, target) end
		events[#events + 1] = {
			kind = DAMAGE,
			target = target,
			amount = dt * self.damagePercent * PERCENT * self.players:MaxHealth(target),
		}
	end
	return events
end
