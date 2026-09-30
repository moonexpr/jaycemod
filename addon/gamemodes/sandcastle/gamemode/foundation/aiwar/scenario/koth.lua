-- The King of the Hill scenario (foundation.aiwar.scenario): the control
-- point scenario (foundation.aiwar.scenario.control_points) over one hill,
-- as foundation.rounds.koth's Mode extends control points'. It overrides:
--   the hill is always a target to the team that does not own it, even
--   while it is locked (TF2's special case in CollectCapturePoints), its
--   owner defends it, and it is where both stage while it is locked;
--   the time left is the enemy's clock (CTFBot::GetTimeLeftToCapture);
--   the stances follow the hill's state and the clocks (field.clocks: team
--   -> { left, running }), keyed:
--     "locked"       the hill locked
--     "open"         unlocked and neutral
--     "held"         ours
--     "held:turtle"  ours, with our clock at KOTH_TURTLE_TIME or less
--     "held:capped"  ours, the enemy capping it (critical from
--                    CRITICAL_PROGRESS)
--     "lost:<a>"     theirs; a, the aggression in tenths, rises as their
--                    clock falls under MUST_PUSH_TIME
--     "laststand"    theirs, in overtime or with their clock at
--                    KOTH_LAST_STAND or less (critical)
local floor, max, min = math.floor, math.max, math.min
local ipairs = ipairs
local AiWar = require("foundation.aiwar")
local Teams = require("foundation.teams")
local Base = require("foundation.aiwar.scenario")
local CP = require("foundation.aiwar.scenario.control_points")
module(...)

MODE = "koth"

KOTH_LAST_STAND, KOTH_TURTLE_TIME = 30, 30
-- TF2 skips the defenders' incursion limit in King of the Hill.
GUARDS_ALL_ROUND = true

LOCKED, OPEN = "locked", "open"
HELD, TURTLE, CAPPED = "held", "held:turtle", "held:capped"
LOST, LAST_STAND = "lost:", "laststand"

local TEAMS = { Teams.RED, Teams.BLUE }
local EnemyOf = AiWar.EnemyOf
local CAPTURE, ASSAULT, HOLD, DEFEND = AiWar.CAPTURE, AiWar.ASSAULT, AiWar.HOLD, AiWar.DEFEND
local RAID, SUPPORT = AiWar.RAID, AiWar.SUPPORT

Scenario = CP.Scenario:Extend(MODE)
Scenario.GUARDS_ALL_ROUND = GUARDS_ALL_ROUND
-- The team clocks exist only once a KOTH round has spawned (not in Sandbox
-- mode): the war waits for them.
Scenario.AWAITS = { Base.CLOCKS }

-- The hill: the round's one point a team can fight over, or nil.
local function Hill(field)
	for _, point in ipairs(field.points) do
		if CP.Eligible(point) then return point end
	end
	return nil
end

function Scenario:Attack(field, team)
	local hill = Hill(field)
	if hill and hill.owner ~= team then return { hill } end
	return {}
end

function Scenario:Defend(field, team)
	local hill = Hill(field)
	if hill and hill.owner == team then return { hill } end
	return {}
end

function Scenario:Staging(field, team, attack)
	local hill = Hill(field)
	return hill and hill.locked and hill or nil
end

function Scenario:TimeLeft(field, team)
	return field.clocks[EnemyOf(team)].left
end

-- Stances ---------------------------------------------------------------------

-- Each state's roles and weights (docs/aiwar-koth-cp.md §2.6). While lost,
-- the weights are LOST's plus `a` times LOST_STEP's.
SHARES = {
	[LOCKED] = {
		roles = { CAPTURE, ASSAULT, RAID, SUPPORT },
		weights = { 4, 3, 2, 1 },
	},
	[OPEN] = {
		roles = { CAPTURE, ASSAULT, RAID, SUPPORT },
		weights = { 5, 3, 1, 1 },
	},
	[HELD] = {
		roles = { HOLD, DEFEND, RAID, SUPPORT },
		weights = { 3, 4, 2, 1 },
	},
	[TURTLE] = {
		roles = { HOLD, DEFEND, SUPPORT },
		weights = { 4, 5, 1 },
	},
	[CAPPED] = {
		roles = { HOLD, DEFEND, SUPPORT },
		weights = { 6, 3, 1 },
	},
	[LOST] = {
		roles = { CAPTURE, ASSAULT, RAID, SUPPORT },
		weights = { 30, 40, 20, 10 },
	},
	[LAST_STAND] = {
		roles = { CAPTURE, ASSAULT, SUPPORT },
		weights = { 8, 1, 1 },
	},
}
LOST_STEP = { 4, -2, -2, 0 }

local stances = {} -- key -> stance: the same situation, the same table

-- The stance of roles weighted by weights, those of weight 0 left out.
local function Stance(key, roles, weights)
	if stances[key] then return stances[key] end
	local stance = {}
	for i, role in ipairs(roles) do
		if weights[i] > 0 then
			stance[#stance + 1] = {
				role = role,
				weight = weights[i],
			}
		end
	end
	stances[key] = stance
	return stance
end

-- The state's entry; a, while lost.
local function Entry(state, critical, a)
	local shares = SHARES[state]
	local key, weights = state, shares.weights
	if state == LOST then
		key, weights = LOST .. a, {}
		for i, weight in ipairs(shares.weights) do weights[i] = weight + a * LOST_STEP[i] end
	end
	return {
		stance = Stance(key, shares.roles, weights),
		key = key,
		critical = critical,
	}
end

-- The team without the hill leans in, in tenths, as the holder's clock
-- runs down under MUST_PUSH_TIME.
local function Aggression(clock)
	local tenths = floor((CP.MUST_PUSH_TIME - clock) / CP.MUST_PUSH_TIME * 10 + 0.5)
	return min(10, max(0, tenths))
end

function Scenario:HillEntry(field, team, hill)
	local enemy = EnemyOf(team)
	local own, theirs = field.clocks[team].left, field.clocks[enemy].left
	if hill.owner == team then
		if hill.capping == enemy then return Entry(CAPPED, hill.progress >= CP.CRITICAL_PROGRESS) end
		if own <= KOTH_TURTLE_TIME then return Entry(TURTLE, false) end
		return Entry(HELD, false)
	end
	if hill.owner == enemy then
		if field.overtime or theirs <= KOTH_LAST_STAND then return Entry(LAST_STAND, true) end
		return Entry(LOST, false, Aggression(theirs))
	end
	if hill.locked then return Entry(LOCKED, false) end
	return Entry(OPEN, false)
end

-- The hill's holder is all defense, the other side all offense.
function Scenario:Stances(field, now)
	local entries, defense = {}, {}
	local hill = Hill(field)
	if not hill then return entries, defense end
	for _, team in ipairs(TEAMS) do
		entries[team] = self:HillEntry(field, team, hill)
		defense[team] = hill.owner == team and 1 or 0
	end
	return entries, defense
end
