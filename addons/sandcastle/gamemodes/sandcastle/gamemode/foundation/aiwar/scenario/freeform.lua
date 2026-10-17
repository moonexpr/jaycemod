-- The freeform scenario (foundation.aiwar.scenario): the war on a map whose
-- rounds mode is none the war knows (no rounds at all, or no standard
-- objective). Nothing is fought over, so every squad explores
-- (foundation.aiwar.explore), in squads of SQUAD_SIZE: a squad follows the
-- nearest living player of its team (field.players), and without one its
-- leader explores as arena's do, walking its lane toward the enemy's base
-- (Front; none where both teams start in the same place), then the
-- waypoints. A squad in a fight fights first. The war's soldiers respawn at
-- once without gamerules (the controller's WaveLength).
local ipairs = ipairs
local AiWar = require("foundation.aiwar")
local Explore = require("foundation.aiwar.explore")
local Orders = require("foundation.aiwar.orders")
local Teams = require("foundation.teams")
local Base = require("foundation.aiwar.scenario")
local Distance = require("foundation.core.geometry").Distance
module(...)

MODE = "freeform"

-- Bigger squads than the point scenarios' fire teams.
SQUAD_SIZE = 8
-- Bases nearer than this are one place: no lane leads between them.
FRONT_MIN = Explore.SPACING

local TEAMS = { Teams.RED, Teams.BLUE }
local EnemyOf = Teams.EnemyOf
local EXPLORE = AiWar.EXPLORE

-- The nearest of players ({ handle, pos }) to pos, or nil.
local function Nearest(players, pos)
	local best, bestDistance
	for _, p in ipairs(players) do
		local d = Distance(p.pos, pos)
		if not bestDistance or d < bestDistance then best, bestDistance = p, d end
	end
	return best
end

-- The doctrine ---------------------------------------------------------------------

-- An explorer squad fights where it is in a fight, else follows the nearest
-- player of its team, else explores.
local ROLE = {
	name = "Explore",
	chases = "opportunist",
	tactic = "attack",
	squads = true,
	arrive = Orders.ESCORT_ARRIVE,
	leash = Orders.ESCORT_LEASH,
	rushes = false,
	Goal = function(field, member)
		local fight = Explore.Fight(field, member)
		if fight then return fight end
		local player = Nearest(field.players[member.team], member.pos or field.bases[member.team])
		if player then return player.pos end
		return Explore.Goal(field, member)
	end,
	LeavesLane = Explore.LeavesLane,
}

DOCTRINE = {
	NAME = "freeform",
	ROLES = { [EXPLORE] = ROLE },
	-- nobody waits behind gates: there is no attacker
	WaitsForSetup = function(field, member) return false end,
	-- chases go anywhere: there is nothing to keep near
	ChaseAnchor = function(field, member) return nil end,
	SIDES = { attack = "FreeformExplorer" },
	Side = function(field, member) return "attack" end,
	-- the enemy comes from its base
	Threat = function(field, member) return field.bases[EnemyOf(member.team)] end,
	PatrolMark = function(field, member) return {} end,
	PatrolHolds = function(mark, field, member) return true end,
}

-- The scenario ---------------------------------------------------------------------

Scenario = Base.Scenario:Extend(MODE)
Scenario.NEEDS = { Base.BASES, Base.WAYPOINTS }
Scenario.SQUAD_SIZE = SQUAD_SIZE

function Scenario:Brief(field, now)
	self:Explore(field)
	field.doctrine = DOCTRINE
end

local STANCE = { { role = EXPLORE, weight = 1 } }

function Scenario:Stances(field, now)
	local entries, defense = {}, {}
	for _, team in ipairs(TEAMS) do
		entries[team] = { stance = STANCE, key = EXPLORE, critical = false }
		defense[team] = 0
	end
	return entries, defense
end

function Scenario:Front(field, team)
	local own, enemy = field.bases[team], field.bases[EnemyOf(team)]
	if Distance(own, enemy) < FRONT_MIN then return nil end
	return enemy
end

-- No setup gates to come out through.
function Scenario:SetupAttacks(field)
	return {}
end
