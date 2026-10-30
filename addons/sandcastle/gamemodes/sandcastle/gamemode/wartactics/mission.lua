-- A squad's mission from the tactics engine (docs/squad-missions-plan.md),
-- the wait for its members, and when the squad must regroup.
--
-- New{ kind, way, size, wait, issued, alpha } -> a mission, unchangeable:
--   the kind (ADVANCE), the way it goes (a lane of wartactics.lanes), how
--   many soldiers the squad should be, how long its leader waits for them
--   (seconds from issued), and whether the squad is its team's alpha (the
--   squad on the objective directly, before any other); a kind it does not
--   know, a way without points, a size under 1 or a negative wait is our bug
-- Issue{ fireTeam, fireTeams, lanes, now, nextWave, travel, missing, size,
--   regrouped } -> the mission a squad leader asked for: the squad is its
--   team's alpha, on the direct lane (else the first), when its job comes at
--   the objective directly (its lane kinds hold DIRECT: never raiders) and
--   no other squad
--   of its team holds the alpha's mission out on the objective (one
--   regrouping does not); any other squad takes the least taken lane of
--   its job's kinds (wartactics.lanes' Choices) among the missions out. Its
--   wait: Wait, with no wave after a regroup. Declined NO_LANES while its
--   team has none; a squad of a job that takes no lanes is our bug.
--   fireTeam: { team, role, mission, regrouping }; lanes: its team's
-- Waited(mission, now) -> whether the leader's wait is over
-- Wait{ missing, nextWave, now, travel } -> seconds to wait: none with no
--   one missing; after spawning, until the team's next wave (nextWave, a
--   time; one due counts as now) and the walk from spawn (travel, seconds);
--   after a regroup (no nextWave), only the walk of the living; held to
--   WAIT_MAX
-- Casualties(strength, alive) -> whether the squad, alive strong, is down to
--   CASUALTY_SHARE of the strength it led out with, or fewer
-- Track(remaining, now) -> a record of the squad's best distance left along
--   its way: Stuck(remaining, now) -> whether it has come no PROGRESS_STEP
--   nearer in STUCK_TIME; Reset(remaining, now) starts it again from there
-- Regroup(track, strength, alive, remaining, now, fighting) -> why a squad
--   out on its mission (strength: as it led out) must regroup, or nil:
--   CASUALTIES (heavy, even in a
--   fight), else STUCK (no progress along its way, remaining, not counting
--   time in a fight, nor within ARRIVED of its end, where there is none to
--   make)
local error, ipairs, setmetatable, max, min, tostring = error, ipairs, setmetatable, math.max, math.min, tostring
local Lanes = wartactics.lanes
local Transaction = transaction
module(...)

ADVANCE = "advance"
local KINDS = { [ADVANCE] = true }

-- A request declined while the asking squad's team has no lanes planned.
NO_LANES = "no lanes"

WAIT_MAX = 45
CASUALTY_SHARE = 0.5
STUCK_TIME, PROGRESS_STEP = 20, 128

local function Frozen(_, key) error("a mission is not changed: " .. tostring(key), 2) end

function New(spec)
	if not KINDS[spec.kind] then error("no mission kind " .. tostring(spec.kind), 2) end
	if not (spec.size and spec.size >= 1) then error("a mission needs a size of 1 or more", 2) end
	if not (spec.wait and spec.wait >= 0) then error("a mission's wait is never negative", 2) end
	if not (spec.way and spec.way.points and spec.way.points[1]) then error("a mission needs a way", 2) end
	local fields = { kind = spec.kind, way = spec.way, size = spec.size, wait = spec.wait, issued = spec.issued,
		alpha = spec.alpha == true }
	return setmetatable({}, { __index = fields, __newindex = Frozen })
end

-- Whether a squad of team other than fireTeam holds the alpha's mission and
-- is out on it.
local function AlphaOut(fireTeams, fireTeam)
	for _, other in ipairs(fireTeams) do
		if other ~= fireTeam and other.team == fireTeam.team and other.mission and other.mission.alpha
			and not other.regrouping then
			return true
		end
	end
	return false
end

local function Direct(lanes)
	for _, lane in ipairs(lanes) do
		if lane.kind == Lanes.DIRECT then return lane end
	end
	return lanes[1]
end

-- Of the lanes the job takes, the one fewest other squads' missions are on;
-- the first planned on a tie.
local function LeastTaken(fireTeams, fireTeam, lanes)
	local best, bestCount
	for _, i in ipairs(Lanes.Choices(lanes, fireTeam.role)) do
		local count = 0
		for _, other in ipairs(fireTeams) do
			if other ~= fireTeam and other.team == fireTeam.team and other.mission and other.mission.way == lanes[i] then
				count = count + 1
			end
		end
		if best == nil or count < bestCount then best, bestCount = lanes[i], count end
	end
	return best
end

function Issue(spec)
	local fireTeam, lanes = spec.fireTeam, spec.lanes
	if not Lanes.JOBS[fireTeam.role] then error("a squad of job " .. tostring(fireTeam.role) .. " asks for no mission", 2) end
	if not (lanes and lanes[1]) then Transaction.Refuse(NO_LANES, "its team has no lanes planned yet") end
	local alpha = Lanes.JOB_KINDS[fireTeam.role][Lanes.DIRECT] == true and not AlphaOut(spec.fireTeams, fireTeam)
	return New({
		kind = ADVANCE,
		way = alpha and Direct(lanes) or LeastTaken(spec.fireTeams, fireTeam, lanes),
		size = spec.size,
		wait = Wait({ missing = spec.missing, nextWave = not spec.regrouped and spec.nextWave or nil, now = spec.now,
			travel = spec.travel }),
		issued = spec.now,
		alpha = alpha,
	})
end

function Waited(mission, now)
	return now >= mission.issued + mission.wait
end

function Wait(spec)
	if spec.missing <= 0 then return 0 end
	local wave = spec.nextWave and max(0, spec.nextWave - spec.now) or 0
	return min(WAIT_MAX, wave + spec.travel)
end

function Casualties(strength, alive)
	return alive <= strength * CASUALTY_SHARE
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

function Track_:Reset(remaining, now)
	self.best, self.at = remaining, now
end

CASUALTIES, STUCK = "heavy casualties", "no progress"
ARRIVED = 400

-- A squad recalled to regroup (why: CASUALTIES or STUCK): it leads its
-- mission no more and musters afresh, at a hiding spot its leader finds,
-- keeping its mission until a new one comes. fireTeam: the squad's
-- blackboard (missionLed, regrouping, musterAt, musterArrived,
-- missionWanted, regroupCalled, missionTrack).
function Recall(fireTeam, why)
	fireTeam.regrouping, fireTeam.missionLed = why, nil
	fireTeam.musterAt, fireTeam.musterArrived, fireTeam.missionWanted = nil, nil, nil
	fireTeam.regroupCalled, fireTeam.missionTrack = nil, nil
end

function Regroup(track, strength, alive, remaining, now, fighting)
	if Casualties(strength, alive) then return CASUALTIES end
	if fighting or remaining <= ARRIVED then
		track:Reset(remaining, now)
		return nil
	end
	if track:Stuck(remaining, now) then return STUCK end
	return nil
end
