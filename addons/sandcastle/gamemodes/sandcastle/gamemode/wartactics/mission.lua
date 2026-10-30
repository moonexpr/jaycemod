-- A squad's mission from the tactics engine (docs/squad-missions-plan.md),
-- the wait for its members, and when the squad must regroup.
--
-- New{ kind, way, size, wait, issued } -> a mission, unchangeable: the kind
--   (ADVANCE), the way it goes (waypoints, { x, y, z }), how many soldiers
--   the squad should be, how long its leader waits for them (seconds from
--   issued); a kind it does not know, an empty way, a size under 1 or a
--   negative wait is our bug
-- Waited(mission, now) -> whether the leader's wait is over
-- Wait{ missing, nextWave, now, travel } -> seconds to wait: none with no
--   one missing; after spawning, until the team's next wave (nextWave, a
--   time; one due counts as now) and the walk from spawn (travel, seconds);
--   after a regroup (no nextWave), only the walk of the living; held to
--   WAIT_MAX
-- Casualties(mission, alive) -> whether the squad, alive strong, is down to
--   CASUALTY_SHARE of the mission's size or fewer
-- Track(remaining, now) -> a record of the squad's best distance left along
--   its way: Stuck(remaining, now) -> whether it has come no PROGRESS_STEP
--   nearer in STUCK_TIME
local error, setmetatable, max, min, tostring = error, setmetatable, math.max, math.min, tostring
module(...)

ADVANCE = "advance"
local KINDS = { [ADVANCE] = true }

WAIT_MAX = 45
CASUALTY_SHARE = 0.5
STUCK_TIME, PROGRESS_STEP = 20, 128

local function Frozen(_, key) error("a mission is not changed: " .. tostring(key), 2) end

function New(spec)
	if not KINDS[spec.kind] then error("no mission kind " .. tostring(spec.kind), 2) end
	if not (spec.way and spec.way[1]) then error("a mission needs a way", 2) end
	if not (spec.size and spec.size >= 1) then error("a mission needs a size of 1 or more", 2) end
	if not (spec.wait and spec.wait >= 0) then error("a mission's wait is never negative", 2) end
	local fields = { kind = spec.kind, way = spec.way, size = spec.size, wait = spec.wait, issued = spec.issued }
	return setmetatable({}, { __index = fields, __newindex = Frozen })
end

function Waited(mission, now)
	return now >= mission.issued + mission.wait
end

function Wait(spec)
	if spec.missing <= 0 then return 0 end
	local wave = spec.nextWave and max(0, spec.nextWave - spec.now) or 0
	return min(WAIT_MAX, wave + spec.travel)
end

function Casualties(mission, alive)
	return alive <= mission.size * CASUALTY_SHARE
end

local Track_ = {}
Track_.__index = Track_

function Track(remaining, now)
	return setmetatable({ best = remaining, at = now }, Track_)
end

function Track_:Stuck(remaining, now)
	if remaining <= self.best - PROGRESS_STEP then
		self.best, self.at = remaining, now
		return false
	end
	return now - self.at >= STUCK_TIME
end
