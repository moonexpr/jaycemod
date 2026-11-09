-- The clocks of a game: the round's and each team's, any other by a name. The
-- server keeps them and thinks them; either realm reads what they network.
--
-- A clock given an outcome closes the round with it when it runs out
-- (round_manager.RoundOutcome); any clock tells the GameTimerExpired hook.
local CurTime, GetGlobal2Float, SetGlobal2Float = CurTime, GetGlobal2Float, SetGlobal2Float
local hook, math, pairs = hook, math, pairs

module("game_timer", package.seeall)

ROUND = "round"

-- The id of a team's clock.
function TeamClock(team)
	return "team_" .. team
end

local END, LEFT = "game_timer.end.", "game_timer.left."
-- What LEFT holds of a clock that is not paused.
local NOT_PAUSED = -1

-- Reading ------------------------------------------------------------------------------

-- When a running clock reaches zero; 0 for one paused or not started.
function EndTime(id)
	return GetGlobal2Float(END .. id, 0)
end

function Paused(id)
	return GetGlobal2Float(LEFT .. id, NOT_PAUSED) >= 0
end

-- Whether the clock is started and has not run out, paused or not.
function Running(id)
	return Paused(id) or EndTime(id) > 0
end

function Remaining(id)
	if Paused(id) then return GetGlobal2Float(LEFT .. id) end
	local ends = EndTime(id)
	if ends == 0 then return 0 end
	return math.max(0, ends - CurTime())
end

-- On the server ------------------------------------------------------------------------

local clocks = {}

local function Publish(id, clock)
	SetGlobal2Float(END .. id, clock.paused and 0 or clock.endsAt)
	SetGlobal2Float(LEFT .. id, clock.paused and clock.left or NOT_PAUSED)
end

-- options: outcome (given to round_manager.RoundOutcome when it runs out),
-- paused (starts held at its full time).
function Start(id, seconds, options)
	options = options or {}
	local clock = { outcome = options.outcome, paused = options.paused or false }
	if clock.paused then clock.left = seconds else clock.endsAt = CurTime() + seconds end
	clocks[id] = clock
	Publish(id, clock)
end

function Stop(id)
	clocks[id] = nil
	SetGlobal2Float(END .. id, 0)
	SetGlobal2Float(LEFT .. id, NOT_PAUSED)
end

function StopAll()
	for id in pairs(clocks) do Stop(id) end
end

function Pause(id)
	local clock = clocks[id]
	if not clock or clock.paused then return end
	clock.paused, clock.left = true, math.max(0, clock.endsAt - CurTime())
	Publish(id, clock)
end

function Resume(id)
	local clock = clocks[id]
	if not clock or not clock.paused then return end
	clock.paused, clock.endsAt = false, CurTime() + clock.left
	Publish(id, clock)
end

function AddTime(id, seconds)
	local clock = clocks[id]
	if not clock then return end
	if clock.paused then
		clock.left = math.max(0, clock.left + seconds)
	else
		clock.endsAt = clock.endsAt + seconds
	end
	Publish(id, clock)
end

function SetTime(id, seconds)
	local clock = clocks[id]
	if not clock then return end
	if clock.paused then clock.left = seconds else clock.endsAt = CurTime() + seconds end
	Publish(id, clock)
end

-- Each Think.
function Think()
	local now = CurTime()
	local expired = {}
	for id, clock in pairs(clocks) do
		if not clock.paused and now >= clock.endsAt then expired[id] = clock end
	end
	for id, clock in pairs(expired) do
		Stop(id)
		hook.Run("GameTimerExpired", id)
		if clock.outcome then round_manager.RoundOutcome(clock.outcome) end
	end
end
