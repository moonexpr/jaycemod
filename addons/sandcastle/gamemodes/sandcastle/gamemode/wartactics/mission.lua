-- A squad's mission from the tactics engine (docs/squad-missions-plan.md),
-- the wait for its members, and when the squad must regroup.
--
-- New{ kind, way, size, wait, issued, alpha, target } -> a mission,
--   unchangeable: the kind (ADVANCE, or a special mission: AMBUSH, ASSAULT,
--   TOPPLE), the way it goes (a lane of wartactics.lanes), how many soldiers
--   the squad should be, how long its leader waits for them (seconds from
--   issued), whether the squad is its team's alpha (the squad on the
--   objective directly, before any other), and a special mission's target
--   ({ room, pos, door }); a kind it does not know, a way without points, a
--   size under 1, a negative wait or a special mission with no target is
--   our bug
-- Choose{ rooms, size, defending, taken, enemyFrom, ourFrom[, kinds] } ->
--   the special mission worth most, and its target, or nil: rooms are the
--   candidates with what the team knows of each ({ id, center, doors,
--   guarded, traffic, support (a base's strength), ours, theirs (on our
--   lanes, on the enemy's) }). An ambush where AMBUSH_TRAFFIC or more came
--   by on the enemy's way and none holds it, at the door toward the enemy
--   (enemyFrom); an assault on a room held on our way, at the door toward
--   us (ourFrom); a topple of a support base; each held no more strongly
--   than ASSAULT_ODDS times the squad's size; a side's own kind
--   (defenders' ambushes, attackers' assaults) counts FAVOURED times; never
--   a room taken (room id -> true), only the kinds given (kind -> true; all
--   when nil), the lower room on a tie
-- Issue{ fireTeam, fireTeams, lanes, now, nextWave, travel, missing, size,
--   regrouped[, special] } -> the mission a squad leader asked for; a squad
--   other than the alpha is given Choose's special mission when one is worth
--   it (special: Choose's spec; rooms other squads of the team hold missions
--   in are taken), else it advances. The squad is its
--   team's alpha, on the direct lane (else the first), when its job comes at
--   the objective directly (its lane kinds hold DIRECT: never raiders) and
--   no other squad
--   of its team holds the alpha's mission out on the objective (one
--   regrouping does not); any other squad takes the least taken lane of
--   its job's kinds (wartactics.lanes' Choices) among the missions out. Its
--   wait: Wait, with no wave after a regroup. Declined NO_LANES while its
--   team has none; a squad of a job that takes no lanes is our bug.
--   fireTeam: { team, role, mission, regrouping }; lanes: its team's
-- Promote(fireTeams, team) -> with no alpha of team out (none, or it
--   regroups), the first of its squads out on another mission (missionLed),
--   not regrouping, whose job may be the alpha: asked again, it is made the
--   alpha, so a special mission never outlasts the objective's squad
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
local error, ipairs, pairs, setmetatable, max, min, tostring = error, ipairs, pairs, setmetatable, math.max, math.min, tostring
local Distance = math.geometry.Distance
local Lanes = wartactics.lanes
local Transaction = transaction
module(...)

ADVANCE = "advance"
-- The special missions (docs/special-missions-plan.md), each on a target
-- room: an ambush at its door on the enemy's way, an assault through its
-- door on ours, toppling the enemy's support base in it.
AMBUSH, ASSAULT, TOPPLE = "ambush", "assault", "topple"
local KINDS = { [ADVANCE] = true, [AMBUSH] = true, [ASSAULT] = true, [TOPPLE] = true }
local SPECIAL = { [AMBUSH] = true, [ASSAULT] = true, [TOPPLE] = true }

-- An ambush is laid where AMBUSH_TRAFFIC or more enemies came lately; a
-- room is assaulted, or a base toppled, held no more strongly than
-- ASSAULT_ODDS times the squad's size; a base weighs TOPPLE_WEIGHT times its
-- strength; a side's own kind (defenders' ambush, attackers' assault)
-- counts FAVOURED times.
AMBUSH_TRAFFIC, ASSAULT_ODDS, TOPPLE_WEIGHT, FAVOURED = 2, 2, 2, 2

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
	if SPECIAL[spec.kind] and not (spec.target and spec.target.room and spec.target.door) then
		error("a " .. spec.kind .. " needs its target room and door", 2)
	end
	local fields = { kind = spec.kind, way = spec.way, size = spec.size, wait = spec.wait, issued = spec.issued,
		alpha = spec.alpha == true, target = spec.target }
	return setmetatable({}, { __index = fields, __newindex = Frozen })
end

-- Whether a squad of team other than except holds the alpha's mission and
-- is not regrouping.
local function AlphaOut(fireTeams, team, except)
	for _, other in ipairs(fireTeams) do
		if other ~= except and other.team == team and other.mission and other.mission.alpha and not other.regrouping then
			return true
		end
	end
	return false
end

-- Whether a squad of job role may be an alpha: its lanes hold the direct one.
local function MayLead(role)
	return Lanes.JOB_KINDS[role] ~= nil and Lanes.JOB_KINDS[role][Lanes.DIRECT] == true
end

-- With no alpha out, the first squad of team out on another mission, not
-- regrouping, that may be an alpha: it asks again, to be the alpha.
function Promote(fireTeams, team)
	if AlphaOut(fireTeams, team, nil) then return nil end
	for _, squad in ipairs(fireTeams) do
		if squad.team == team and squad.missionLed and squad.mission and not squad.regrouping and MayLead(squad.role) then
			return squad
		end
	end
	return nil
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

-- The room's door nearest a point.
local function DoorToward(room, p)
	local best, bestDistance
	for _, door in ipairs(room.doors) do
		local d = Distance(door.pos, p)
		if not best or d < bestDistance then best, bestDistance = door, d end
	end
	return best
end

-- Each kind's worth in a room, 0 when it is none of it.
local function Worth(room, spec)
	local odds = spec.size * ASSAULT_ODDS
	local ambush = room.theirs and room.guarded == 0 and room.traffic >= AMBUSH_TRAFFIC and room.traffic or 0
	local assault = room.ours and room.guarded > 0 and room.guarded <= odds and room.guarded or 0
	local topple = room.support > 0 and room.guarded <= odds and room.support * TOPPLE_WEIGHT or 0
	if spec.defending then ambush = ambush * FAVOURED else assault = assault * FAVOURED end
	return { [AMBUSH] = ambush, [ASSAULT] = assault, [TOPPLE] = topple }
end

function Choose(spec)
	local bestKind, bestRoom, bestWorth
	for _, room in ipairs(spec.rooms) do
		if not spec.taken[room.id] and room.doors[1] then
			for _, kind in ipairs({ TOPPLE, ASSAULT, AMBUSH }) do
				local worth = (not spec.kinds or spec.kinds[kind]) and Worth(room, spec)[kind] or 0
				if worth > 0 and (not bestWorth or worth > bestWorth or (worth == bestWorth and room.id < bestRoom.id)) then
					bestKind, bestRoom, bestWorth = kind, room, worth
				end
			end
		end
	end
	if not bestKind then return nil end
	local from = bestKind == AMBUSH and spec.enemyFrom or spec.ourFrom
	return bestKind, { room = bestRoom.id, pos = bestRoom.center, door = DoorToward(bestRoom, from) }
end

-- The rooms other squads of the team hold missions in, beside those given.
local function Taken(fireTeams, fireTeam, given)
	local taken = {}
	for room in pairs(given or {}) do taken[room] = true end
	for _, other in ipairs(fireTeams) do
		local target = other ~= fireTeam and other.team == fireTeam.team and other.mission and other.mission.target
		if target then taken[target.room] = true end
	end
	return taken
end

function Issue(spec)
	local fireTeam, lanes = spec.fireTeam, spec.lanes
	if not Lanes.JOBS[fireTeam.role] then error("a squad of job " .. tostring(fireTeam.role) .. " asks for no mission", 2) end
	if not (lanes and lanes[1]) then Transaction.Refuse(NO_LANES, "its team has no lanes planned yet") end
	local alpha = MayLead(fireTeam.role) and not AlphaOut(spec.fireTeams, fireTeam.team, fireTeam)
	local kind, target = ADVANCE, nil
	if not alpha and spec.special then
		local special = {}
		for k, v in pairs(spec.special) do special[k] = v end
		special.taken = Taken(spec.fireTeams, fireTeam, spec.special.taken)
		local chosen, at = Choose(special)
		if chosen then kind, target = chosen, at end
	end
	return New({
		kind = kind,
		way = alpha and Direct(lanes) or LeastTaken(spec.fireTeams, fireTeam, lanes),
		size = spec.size,
		wait = Wait({ missing = spec.missing, nextWave = not spec.regrouped and spec.nextWave or nil, now = spec.now,
			travel = spec.travel }),
		issued = spec.now,
		alpha = alpha,
		target = target,
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

-- A squad whose mission is done (an ambush sprung and fought, or never
-- sprung): it lets the mission go and asks afresh, mustering where it
-- stands (its leader past the muster).
function Finish(fireTeam)
	Recall(fireTeam, nil)
	fireTeam.mission, fireTeam.sprung, fireTeam.ambushSetAt, fireTeam.halted = nil, nil, nil, nil
	fireTeam.stackedAt, fireTeam.breachAt, fireTeam.clearSince = nil, nil, nil
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
