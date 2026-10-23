-- The arena scenario (features.aiwar.scenario): the control point
-- scenario (features.aiwar.scenario.control_points) over arena's one
-- point, which no team may capture before the round's cap-enable time
-- (field.capEnableAt, features.arena.round). The arena round is no
-- sudden death for the soldiers (features.aiwar.model's PHASES.arena: no hunt,
-- no sight of every enemy). Until the point opens every squad explores
-- (EXPLORE, games.ns.explore): it keeps together, its leader
-- walking its lane from the spawn to the point (Front; the enemy's base on
-- a map without one), then making for the nearest waypoint the squad has
-- not been near. A squad that sees the enemy (its fire team's contact,
-- games.ns.tactics) is engaged: it leaves its lane to fight, and
-- hunts where the enemy was, before it goes on to the objective. Once
-- open, the point is a target to the team without it and guarded by its
-- owner, as in King of the Hill, and the stances split, a share still
-- exploring. Keyed:
--   "shut"     before the cap-enable time: all explore
--   "open"     open and neutral
--   "held"     ours
--   "capped"   ours, the enemy capping it (critical from CRITICAL_PROGRESS)
--   "lost"     theirs
local ipairs, pairs, setmetatable = ipairs, pairs, setmetatable
local AiWar = require("features.aiwar.model")
local Orders = require("features.aiwar.orders")
local Teams = require("games.gameplay.teams")
local Base = require("features.aiwar.scenario")
local CP = require("features.aiwar.scenario.control_points")
module(...)

MODE = "arena"

SHUT, OPEN, HELD, CAPPED, LOST = "shut", "open", "held", "capped", "lost"

local TEAMS = { Teams.RED, Teams.BLUE }
local EnemyOf = Teams.EnemyOf
local CAPTURE, ASSAULT, HOLD, DEFEND, EXPLORE = AiWar.CAPTURE, AiWar.ASSAULT, AiWar.HOLD, AiWar.DEFEND, AiWar.EXPLORE

-- Whether the point may be captured now: the round has its cap-enable time
-- and it has passed.
local function Open(field, now)
	return field.capEnableAt ~= nil and now >= field.capEnableAt
end

-- The point: the round's one a team can fight over, or nil.
local function ThePoint(field)
	for _, point in ipairs(field.points) do
		if CP.Eligible(point) then return point end
	end
	return nil
end

-- The doctrine ---------------------------------------------------------------------

-- The point doctrine's jobs, explore among them (features.aiwar.orders'
-- EXPLORE_ROLE): an explorer squad goes for where it fights, else its
-- lane's end, else its waypoint (the scenario's board, field.explore).
DOCTRINE = {}
for k, v in pairs(CP.DOCTRINE) do DOCTRINE[k] = v end
DOCTRINE.NAME = "arena"

-- The scenario ---------------------------------------------------------------------

Scenario = CP.Scenario:Extend(MODE)
-- Its Brief reads the points, both bases and the waypoints to explore.
Scenario.NEEDS = { Base.BASES, Base.POINTS, Base.WAYPOINTS }

-- The point is a target to the team without it once open, whatever
-- mayCapture says, as King of the Hill's hill always is.
function Scenario:Attack(field, team)
	local point = ThePoint(field)
	if point and Open(field, field.now) and point.owner ~= team then return { point } end
	return {}
end

function Scenario:Defend(field, team)
	local point = ThePoint(field)
	if point and Open(field, field.now) and point.owner == team then return { point } end
	return {}
end

-- Nobody waits by a shut point: they explore.
function Scenario:Staging(field, team, attack)
	return nil
end

-- The lanes lead to the point, shut or open, so the squads come at it by
-- several ways once it opens; on a map without one, to the enemy's base.
function Scenario:Front(field, team)
	local point = ThePoint(field)
	if point then return point.zone.center end
	return field.bases[EnemyOf(team)]
end

function Scenario:Brief(field, now)
	CP.Scenario.Brief(self, field, now)
	field.doctrine = DOCTRINE
end

-- Stances ---------------------------------------------------------------------

SHARES = {
	[SHUT] = {
		roles = { EXPLORE },
		weights = { 1 },
	},
	[OPEN] = {
		roles = { CAPTURE, ASSAULT, EXPLORE },
		weights = { 4, 3, 3 },
	},
	[HELD] = {
		roles = { HOLD, DEFEND, EXPLORE },
		weights = { 3, 4, 3 },
	},
	[CAPPED] = {
		roles = { HOLD, DEFEND, EXPLORE },
		weights = { 6, 3, 1 },
	},
	[LOST] = {
		roles = { CAPTURE, ASSAULT, EXPLORE },
		weights = { 5, 3, 2 },
	},
}

local stances = {} -- key -> stance: the same situation, the same table

local function Entry(key, critical)
	if not stances[key] then
		local stance, shares = {}, SHARES[key]
		for i, role in ipairs(shares.roles) do
			stance[i] = {
				role = role,
				weight = shares.weights[i],
			}
		end
		stances[key] = stance
	end
	return {
		stance = stances[key],
		key = key,
		critical = critical,
	}
end

local function TeamEntry(field, team, now)
	local point = ThePoint(field)
	if not point or not Open(field, now) then return Entry(SHUT, false) end
	local enemy = EnemyOf(team)
	if point.owner == team then
		if point.capping == enemy then return Entry(CAPPED, point.progress >= CP.CRITICAL_PROGRESS) end
		return Entry(HELD, false)
	end
	if point.owner == enemy then return Entry(LOST, false) end
	return Entry(OPEN, false)
end

-- The point's holder is all defense, the rest all offense.
function Scenario:Stances(field, now)
	local entries, defense = {}, {}
	local point = ThePoint(field)
	for _, team in ipairs(TEAMS) do
		entries[team] = TeamEntry(field, team, now)
		defense[team] = point and Open(field, now) and point.owner == team and 1 or 0
	end
	return entries, defense
end
