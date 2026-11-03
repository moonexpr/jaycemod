-- What a soldier's body says without words: the gesture an occasion plays
-- (GMod's player-model acts, by name, so this needs no GMod), how fast,
-- and how long before the same occasion moves the soldier again; the
-- celebration a squad wiped out earns; whether a grenade is rolled or
-- thrown; and the canned death a crit plays.
--
-- GESTURES[occasion] -> { acts = { act name, ... }, rate, cooldown }
-- Memory() -> a soldier's own:
--   Play(occasion, now, randomInt) -> an act name drawn from the
--     occasion's and its rate, or nil while the occasion cools down; an
--     unknown occasion is our bug. randomInt(low, high) is the caller's.
--   Killed(now): a kill in the fight it is in
--   Calm(now) -> whether, out of the fight DOWNTIME after its last kill,
--     it killed SQUAD_KILLS or more in it; the fight's count ends either way
-- Still(act name) -> whether the act is a taunt (GMod's ACT_GMOD_TAUNT_*,
--   the whole body's), played standing still, not a gesture on the move
-- Throw(distance) -> GRENADE_ROLL within ROLL_RANGE, else GRENADE_THROW
-- DEATHS, Death(critical, randomInt) -> a crit's canned death (a player
--   model's sequence name), or nil for any other death
-- Name(act name) -> the gesture's own name, for the response rules'
--   gesture criterion: lower case, the player model's prefixes left off
--   (ACT_GMOD_TAUNT_DANCE: dance; ACT_GMOD_GESTURE_TAUNT_ZOMBIE: zombie)
local error, setmetatable, tostring, sub, lower, ipairs = error, setmetatable, tostring, string.sub, string.lower, ipairs
module(...)

-- Witnessing a teammate's kill or capture; a squad wiped out with time to
-- spare; greeting a teammate player or lining up in a battle stance; a
-- grenade rolled near or thrown far; a squad commander's signals.
AGREE, CELEBRATE, GREET = "agree", "celebrate", "greet"
GRENADE_ROLL, GRENADE_THROW = "grenade_roll", "grenade_throw"
SIGNAL_FORWARD, SIGNAL_GROUP, SIGNAL_HALT = "signal_forward", "signal_group", "signal_halt"

FAST = 2
MODERATE_COOLDOWN, LONG_COOLDOWN = 20, 60

GESTURES = {
	[AGREE] = { acts = { "ACT_GMOD_GESTURE_AGREE" }, rate = FAST, cooldown = MODERATE_COOLDOWN },
	[CELEBRATE] = {
		acts = { "ACT_GMOD_GESTURE_BOW", "ACT_GMOD_TAUNT_DANCE", "ACT_GMOD_TAUNT_LAUGH", "ACT_GMOD_GESTURE_TAUNT_ZOMBIE" },
		rate = FAST, cooldown = MODERATE_COOLDOWN,
	},
	[GREET] = {
		acts = { "ACT_GMOD_GESTURE_WAVE", "ACT_GMOD_TAUNT_ROBOT", "ACT_GMOD_TAUNT_DANCE", "ACT_GMOD_TAUNT_MUSCLE" },
		rate = FAST, cooldown = LONG_COOLDOWN,
	},
	[GRENADE_ROLL] = { acts = { "ACT_GMOD_GESTURE_ITEM_DROP" }, rate = FAST, cooldown = 0 },
	[GRENADE_THROW] = { acts = { "ACT_GMOD_GESTURE_ITEM_THROW" }, rate = FAST, cooldown = 0 },
	[SIGNAL_FORWARD] = { acts = { "ACT_SIGNAL_FORWARD" }, rate = FAST, cooldown = 0 },
	[SIGNAL_GROUP] = { acts = { "ACT_SIGNAL_GROUP" }, rate = FAST, cooldown = 0 },
	[SIGNAL_HALT] = { acts = { "ACT_SIGNAL_HALT" }, rate = 1, cooldown = 0 },
}

-- A squad is SQUAD_KILLS kills in one fight; DOWNTIME of calm after the
-- last ends the fight.
SQUAD_KILLS, DOWNTIME = 3, 4

local Memory_ = {}
Memory_.__index = Memory_

function Memory()
	return setmetatable({ readyAt = {}, kills = 0, lastKill = nil }, Memory_)
end

function Memory_:Play(occasion, now, randomInt)
	local gesture = GESTURES[occasion]
	if not gesture then error("no gesture for the occasion " .. tostring(occasion), 2) end
	if now < (self.readyAt[occasion] or now) then return nil end
	self.readyAt[occasion] = now + gesture.cooldown
	return gesture.acts[randomInt(1, #gesture.acts)], gesture.rate
end

function Memory_:Killed(now)
	self.kills, self.lastKill = self.kills + 1, now
end

function Memory_:Calm(now)
	if not self.lastKill or now - self.lastKill < DOWNTIME then return false end
	local wiped = self.kills >= SQUAD_KILLS
	self.kills, self.lastKill = 0, nil
	return wiped
end

local TAUNT_PREFIX = "ACT_GMOD_TAUNT_"

function Still(act)
	return sub(act, 1, #TAUNT_PREFIX) == TAUNT_PREFIX
end

-- the longest first
local NAME_PREFIXES = { "ACT_GMOD_GESTURE_TAUNT_", "ACT_GMOD_GESTURE_", TAUNT_PREFIX, "ACT_" }

function Name(act)
	for _, prefix in ipairs(NAME_PREFIXES) do
		if sub(act, 1, #prefix) == prefix then return lower(sub(act, #prefix + 1)) end
	end
	return lower(act)
end

-- Grenades within ROLL_RANGE are rolled underhand, farther ones thrown.
ROLL_RANGE = 400

function Throw(distance)
	return distance <= ROLL_RANGE and GRENADE_ROLL or GRENADE_THROW
end

DEATHS = { "death_01", "death_02", "death_03", "death_04" }

function Death(critical, randomInt)
	if not critical then return nil end
	return DEATHS[randomInt(1, #DEATHS)]
end
