-- The fortune teller (halloween_fortune_teller, CTFHalloweenFortuneTeller in
-- tf_logic_halloween_2014.cpp): Merasmus's booth. While its timer runs
-- (after EnableFortuneTelling; it starts without one) it counts to 120 s:
-- OnFortuneWarning 2 s before, then OnFortuneTold and the Wheel of Fate
-- sound for everyone. 6.1 s later it teleports each team to its named spots,
-- and 6 s after that fires OnFortuneCurse; 30 s later OnFortuneEnd, and the
-- count starts over. Disable pauses the count and Enable resumes it.
-- StartFortuneTelling and EndFortuneTelling run a fortune by hand.
--
-- The curses themselves (big heads, melee only, swimming), the dances, the
-- thriller taunts, the screen flash and the sentry and projectile clean-up
-- are left out: they need econ conditions and taunts GMod lacks.
--
-- New{ redTeleport, blueTeleport }, now, then :Input(name, now) and
-- :Tick(now), each returning a list of effects:
--   OUTPUT { name }: fire the output, the teller as activator;
--   BROADCAST { sound }: a game sound every player hears;
--   TELEPORT { team, target }: the team's players to the entities named
--     target (Teleports pairs them).
-- Its timers follow SetContextThink: each runs at its own time, however
-- late the tick that runs it, and one set in the past runs at once.
local require = require
local Teams = require("games.gameplay.teams")
local ipairs, setmetatable = ipairs, setmetatable
local max = math.max
module(...)

MODEL = "models/bots/merasmus/merasmas_misfortune_teller.mdl"
IDLE_SEQUENCE = "ref"
SPIN_SOUND = "Halloween.WheelofFateQuiet"

INTERVAL = 120 -- tf_fortune_teller_interval_time
WARNING_TIME = 2 -- tf_fortune_teller_warning_time
DURATION = 30 -- tf_fortune_teller_fortune_duration
TELL_DELAY = 6.1 -- StartFortuneTell to TellFortune
CURSE_DELAY = 6 -- TellFortune to ApplyFortuneEffect

OUTPUT, BROADCAST, TELEPORT = "output", "broadcast", "teleport"

OUTPUT_WARNING = "OnFortuneWarning"
OUTPUT_TOLD = "OnFortuneTold"
OUTPUT_CURSE = "OnFortuneCurse"
OUTPUT_END = "OnFortuneEnd"

INPUT_ENABLE = "enablefortunetelling"
INPUT_DISABLE = "disablefortunetelling"
INPUT_START = "startfortunetelling"
INPUT_END = "endfortunetelling"

-- The context thinks, in the order they run when due together.
local WARN, TELL, FORTUNE, CURSE, FINISH = "StartFortuneWarning", "StartFortuneTell", "TellFortune",
	"FortuneActivate", "EndFortuneTell"
local THINK_ORDER = { WARN, TELL, FORTUNE, CURSE, FINISH }

local Teller = {}
Teller.__index = Teller

-- Spawn's ResetTimer; the timer itself is off.
function New(config, now)
	return setmetatable({
		redTeleport = config.redTeleport,
		blueTeleport = config.blueTeleport,
		useTimer = false,
		startTime = now,
		pauseTime = now,
		thinks = {},
	}, Teller)
end

-- A think set in the past runs at the next tick, as of then.
local function Schedule(self, name, at, now)
	self.thinks[name] = max(at, now)
end

local function Output(effects, name)
	effects[#effects + 1] = {
		kind = OUTPUT,
		name = name,
	}
end

-- UpdateFortuneTellerTime: unpause, then wait for what is left of the
-- interval.
local function Resume(self, now)
	self.startTime = now - (self.pauseTime - self.startTime)
	local past = now - self.startTime
	local warnAt = INTERVAL - WARNING_TIME
	if past < warnAt then
		Schedule(self, WARN, now + warnAt - past, now)
	else
		Schedule(self, TELL, now + INTERVAL - past, now)
	end
end

-- PauseTimer: the queued curse is not among what it cancels.
local function Pause(self, now)
	self.pauseTime = now
	for _, name in ipairs({ WARN, TELL, FORTUNE, FINISH }) do self.thinks[name] = nil end
end

local function ResetTimer(self, now)
	self.startTime = now
	self.pauseTime = now
end

-- StartFortuneTell
local function Tell(self, now, effects)
	Output(effects, OUTPUT_TOLD)
	effects[#effects + 1] = {
		kind = BROADCAST,
		sound = SPIN_SOUND,
	}
	Schedule(self, FORTUNE, now + TELL_DELAY, now)
end

-- EndFortuneTell
local function Finish(self, now, effects)
	self.thinks[FORTUNE] = nil
	Output(effects, OUTPUT_END)
	if self.useTimer then
		ResetTimer(self, now)
		Resume(self, now)
	end
end

local THINKS = {
	[WARN] = function(self, now, effects)
		Output(effects, OUTPUT_WARNING)
		Schedule(self, TELL, now + WARNING_TIME, now)
	end,
	[TELL] = Tell,
	-- TellFortune: RED first, then BLU.
	[FORTUNE] = function(self, now, effects)
		effects[#effects + 1] = {
			kind = TELEPORT,
			team = Teams.RED,
			target = self.redTeleport,
		}
		effects[#effects + 1] = {
			kind = TELEPORT,
			team = Teams.BLUE,
			target = self.blueTeleport,
		}
		Schedule(self, CURSE, now + CURSE_DELAY, now)
	end,
	-- ApplyFortuneEffect
	[CURSE] = function(self, now, effects)
		Output(effects, OUTPUT_CURSE)
		if self.useTimer then Schedule(self, FINISH, now + DURATION, now) end
	end,
	[FINISH] = Finish,
}

-- The earliest think due by now, if any.
local function Due(self, now)
	local due, dueAt = nil, nil
	for _, name in ipairs(THINK_ORDER) do
		local at = self.thinks[name]
		if at and at <= now and (dueAt == nil or at < dueAt) then due, dueAt = name, at end
	end
	return due, dueAt
end

function Teller:Tick(now)
	local effects = {}
	local name, at = Due(self, now)
	while name do
		self.thinks[name] = nil
		THINKS[name](self, at, effects)
		name, at = Due(self, now)
	end
	return effects
end

local INPUTS = {
	[INPUT_ENABLE] = function(self, now, effects)
		local was = self.useTimer
		self.useTimer = true
		if not was then Resume(self, now) end
	end,
	[INPUT_DISABLE] = function(self, now, effects)
		local was = self.useTimer
		self.useTimer = false
		if was then Pause(self, now) end
	end,
	[INPUT_START] = Tell,
	[INPUT_END] = Finish,
}

-- Kill and AddOutput are the engine's.
function Teller:Accepts(name)
	return INPUTS[name] ~= nil
end

-- name lower-cased.
function Teller:Input(name, now)
	local effects = {}
	INPUTS[name](self, now, effects)
	return effects
end

-- TeleportPlayersToTargetEntities: the team in a random order (randomInt(lo,
-- hi) as RandomInt), taken from the back, each to the next spot; once the
-- spots run out the rest stay. Returns { player, spot } pairs.
function Teleports(players, spots, randomInt)
	local order = {}
	for i, p in ipairs(players) do order[i] = p end
	for i = #order, 2, -1 do
		local j = randomInt(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local moves = {}
	for i = #order, 1, -1 do
		local spot = spots[#moves + 1]
		if spot == nil then break end
		moves[#moves + 1] = {
			player = order[i],
			spot = spot,
		}
	end
	return moves
end
