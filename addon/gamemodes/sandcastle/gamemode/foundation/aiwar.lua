-- The AI war: a payload round fought by Half-Life 2's engine NPCs, the
-- Combine for RED and the Resistance for BLU. This model holds who fights
-- for whom, what each soldier is for (its role), when each side's dead come
-- back, and what the round state lets soldiers do. The soldiers' orders are
-- foundation.aiwar.orders; the features/aiwar controller spawns, enlists
-- and drives the NPCs.
--
-- Members are opaque handles (the NPC entities). Carts are given as the set
-- of teams with a cart moving on the map.
local floor, ipairs, pairs, setmetatable, sort = math.floor, ipairs, pairs, setmetatable, table.sort
local Teams = require("foundation.teams")
local STATE = require("foundation.rounds.state")
module(...)

local RED, BLUE = Teams.RED, Teams.BLUE
local ENEMY = { [RED] = BLUE, [BLUE] = RED }

function EnemyOf(team)
	return ENEMY[team]
end

-- How a soldier of `team` stands toward someone of `otherTeam`. `losers` is
-- the team that lost the round, while the winners celebrate (TF2's
-- humiliation): its soldiers fear their enemies instead of fighting them.
ALLY, ENEMY_OF, FEAR, NEUTRAL = "ally", "enemy", "fear", "neutral"

function Relation(team, otherTeam, losers)
	if team == otherTeam then return ALLY end
	if ENEMY[team] ~= otherTeam then return NEUTRAL end
	if team == losers then return FEAR end
	return ENEMY_OF
end

-- The team humiliated when `winner` wins: its enemy, or none on a stalemate.
function LosersOf(winner)
	return ENEMY[winner]
end

-- Roles: what a soldier is for. foundation.aiwar.orders gives each its goal.
PUSH, ESCORT, BLOCK, DEFEND = "push", "escort", "block", "defend"

TEAM_SIZE_DEFAULT = 8
TEAM_SIZE_MAX = 32
-- HL2's squads coordinate at most 16 (MAX_SQUAD_MEMBERS); smaller squads
-- fight better.
SQUAD_SIZE = 8

-- npc_citizen spawnflags (npc_citizen17.h)
local SF_CITIZEN_MEDIC = 131072
local SF_CITIZEN_NOT_COMMANDABLE = 1048576
local CT_REBEL = "3" -- citizentype

-- Ground NPCs only: the orders walk them over the nav mesh, which fliers
-- (manhacks, scanners) and gunships do not use.
FACTIONS = {
	[RED] = {
		name = "Combine",
		team = RED,
		classes = { npc_combine_s = true, npc_metropolice = true, npc_hunter = true },
		recruits = {
			{ class = "npc_combine_s", weapon = "weapon_smg1", model = "models/combine_soldier.mdl" },
			{ class = "npc_combine_s", weapon = "weapon_ar2", model = "models/combine_soldier.mdl" },
			{ class = "npc_metropolice", weapon = "weapon_pistol" },
			{ class = "npc_combine_s", weapon = "weapon_shotgun", model = "models/combine_soldier.mdl", skin = 1 },
			{ class = "npc_combine_s", weapon = "weapon_ar2", model = "models/combine_super_soldier.mdl" },
			{ class = "npc_metropolice", weapon = "weapon_smg1" },
		},
	},
	[BLUE] = {
		name = "Resistance",
		team = BLUE,
		classes = {
			npc_citizen = true,
			npc_alyx = true,
			npc_barney = true,
			npc_vortigaunt = true,
			npc_monk = true,
		},
		recruits = {
			{ class = "npc_citizen", weapon = "weapon_smg1", keyvalues = { citizentype = CT_REBEL }, spawnflags = SF_CITIZEN_NOT_COMMANDABLE },
			{ class = "npc_citizen", weapon = "weapon_ar2", keyvalues = { citizentype = CT_REBEL }, spawnflags = SF_CITIZEN_NOT_COMMANDABLE },
			{ class = "npc_citizen", weapon = "weapon_shotgun", keyvalues = { citizentype = CT_REBEL }, spawnflags = SF_CITIZEN_NOT_COMMANDABLE },
			{ class = "npc_citizen", weapon = "weapon_smg1", keyvalues = { citizentype = CT_REBEL }, spawnflags = SF_CITIZEN_NOT_COMMANDABLE + SF_CITIZEN_MEDIC },
			{ class = "npc_citizen", weapon = "weapon_ar2", keyvalues = { citizentype = CT_REBEL }, spawnflags = SF_CITIZEN_NOT_COMMANDABLE },
			{ class = "npc_citizen", weapon = "weapon_pistol", keyvalues = { citizentype = CT_REBEL }, spawnflags = SF_CITIZEN_NOT_COMMANDABLE },
		},
	},
}

-- The team an NPC class fights for, or nil for a class in no faction.
function FactionTeam(class)
	for team, faction in pairs(FACTIONS) do
		if faction.classes[class] then return team end
	end
	return nil
end

-- Stances: how a team splits its soldiers between roles, as integer
-- weights, first role first on a tie. A team with its own cart pushes it;
-- one facing only the enemy's defends; on a race map each does both.
local ATTACK = { { role = PUSH, weight = 5 }, { role = ESCORT, weight = 5 } }
local DEFEND_STANCE = { { role = DEFEND, weight = 7 }, { role = BLOCK, weight = 3 } }
local RACE = { { role = PUSH, weight = 4 }, { role = BLOCK, weight = 3 }, { role = ESCORT, weight = 3 } }

function Stance(team, carts)
	local own, enemy = carts[team], carts[ENEMY[team]]
	if own and enemy then return RACE end
	if own then return ATTACK end
	if enemy then return DEFEND_STANCE end
	return nil
end

-- The role most short of its share once one more soldier joins.
function PickRole(stance, counts)
	local total, sum = 0, 0
	for _, share in ipairs(stance) do
		total = total + (counts[share.role] or 0)
		sum = sum + share.weight
	end
	local best, bestDeficit
	for _, share in ipairs(stance) do
		local deficit = share.weight * (total + 1) - (counts[share.role] or 0) * sum
		if bestDeficit == nil or deficit > bestDeficit then best, bestDeficit = share.role, deficit end
	end
	return best
end

-- Phases: what the round state allows. Pre-round freezes everyone as it
-- freezes players; sudden death has no respawns; a won round ends orders.
PHASES = {
	waiting = { name = "waiting", reinforce = false, orders = false },
	frozen = { name = "frozen", reinforce = true, orders = false },
	running = { name = "running", reinforce = true, orders = true },
	suddenDeath = { name = "suddenDeath", reinforce = false, orders = true },
	over = { name = "over", reinforce = false, orders = false },
}

local PHASE_OF_STATE = {
	[STATE.INIT] = PHASES.waiting,
	[STATE.PREGAME] = PHASES.waiting,
	[STATE.PREROUND] = PHASES.frozen,
	[STATE.RND_RUNNING] = PHASES.running,
	[STATE.STALEMATE] = PHASES.suddenDeath,
}

-- active: the map runs TF2's rounds (tf_gamerules); without them the war
-- simply runs.
function PhaseOf(active, state)
	if not active then return PHASES.running end
	return PHASE_OF_STATE[state] or PHASES.over
end

-------------------------------------------------------------------------------
-- War: the roster and the waves

War = {}
War.__index = War

function War.New()
	return setmetatable({
		members = {}, -- handle -> member
		enlisted = 0, -- members ever enlisted, for their order
		stances = {}, -- team -> stance
		drafts = { [RED] = 0, [BLUE] = 0 },
		nextWave = { [RED] = 0, [BLUE] = 0 },
		field = nil,
	}, War)
end

-- Every member, oldest first.
function War:Members()
	local list = {}
	for _, member in pairs(self.members) do list[#list + 1] = member end
	sort(list, function(a, b) return a.seq < b.seq end)
	return list
end

function War:Member(handle)
	return self.members[handle]
end

-- The lowest slot no other member of the team has in that role.
local function FreeSlot(members, team, role, except)
	local taken = {}
	for _, member in pairs(members) do
		if member ~= except and member.team == team and member.role == role then taken[member.slot] = true end
	end
	local slot = 0
	while taken[slot] do slot = slot + 1 end
	return slot
end

local function RoleCounts(members, team, except)
	local counts = {}
	for _, member in pairs(members) do
		if member ~= except and member.team == team and member.role then
			counts[member.role] = (counts[member.role] or 0) + 1
		end
	end
	return counts
end

function War:AssignRole(member)
	local stance = self.stances[member.team]
	member.role = stance and PickRole(stance, RoleCounts(self.members, member.team, member)) or nil
	member.slot = member.role and FreeSlot(self.members, member.team, member.role, member) or 0
end

-- drafted: spawned by the war (counted against the team's size), rather
-- than added by a player.
function War:Enlist(handle, team, drafted)
	self.enlisted = self.enlisted + 1
	local member = { handle = handle, team = team, drafted = drafted, seq = self.enlisted, role = nil, slot = 0 }
	self.members[handle] = member
	self:AssignRole(member)
	return member
end

function War:Discharge(handle)
	self.members[handle] = nil
end

-- A team whose stance changes (a cart appears or goes) is reassigned
-- from scratch, oldest first.
function War:Assign(carts)
	for _, team in ipairs({ RED, BLUE }) do
		local stance = Stance(team, carts)
		if stance ~= self.stances[team] then
			self.stances[team] = stance
			local list = {}
			for _, member in ipairs(self:Members()) do
				if member.team == team then
					member.role = nil
					list[#list + 1] = member
				end
			end
			for _, member in ipairs(list) do self:AssignRole(member) end
		end
	end
end

-- The next recruit to spawn for a team and the squad it joins.
function War:Draft(team)
	local n = self.drafts[team] + 1
	self.drafts[team] = n
	local recruits = FACTIONS[team].recruits
	return {
		recruit = recruits[(n - 1) % #recruits + 1],
		squad = "wetsand_aiwar_" .. team .. "_" .. floor((n - 1) / SQUAD_SIZE),
	}
end

function War:DraftedCount(team)
	local n = 0
	for _, member in pairs(self.members) do
		if member.team == team and member.drafted then n = n + 1 end
	end
	return n
end

-- TF2's respawn waves for the war's own soldiers: when a team's wave is
-- due, it is topped back up to teamSize drafted soldiers, and the next wave
-- is waveLength(team) seconds away (0: every call). Returns team -> how
-- many to spawn now.
function War:Reinforcements(now, teamSize, waveLength)
	local wave = {}
	for _, team in ipairs({ RED, BLUE }) do
		if now >= self.nextWave[team] then
			self.nextWave[team] = now + waveLength(team)
			local missing = teamSize - self:DraftedCount(team)
			if missing > 0 then wave[team] = missing end
		end
	end
	return wave
end

function War:ResetWaves()
	self.nextWave = { [RED] = 0, [BLUE] = 0 }
end

-- The battlefield the orders read: { phase, setup (the round is in
-- setup), carts = team -> { track (foundation.aiwar.track), distance along
-- it, pos, nextCheckpoint (distance along it) }, gates = team -> list of
-- { pos, dir }: the doors that team must pass to reach the rest of the map,
-- dir the way it passes them, posts = team -> points where its defenders
-- establish their line, forwardPosts = team -> points ahead of its own
-- cart where its escorts do (foundation.aiwar.posts) }.
function War:SetField(field)
	self.field = field
end

function War:Field()
	return self.field
end
