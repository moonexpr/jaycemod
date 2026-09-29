-- The AI war: a payload round fought by Half-Life 2's engine NPCs, the
-- Combine for RED and the Resistance for BLU. This model holds who fights
-- for whom, what each soldier is for (its role), when each side's dead come
-- back, and what the round state lets soldiers do. The soldiers' orders are
-- foundation.aiwar.orders; the features/aiwar controller spawns, enlists
-- and drives the NPCs.
--
-- Members are opaque handles (the NPC entities). Carts are given as the set
-- of teams with a cart moving on the map.
local floor, ipairs, next, pairs, setmetatable, sort, table, type = math.floor, ipairs, next, pairs, setmetatable, table.sort, table, type
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
-- Fire teams: a side's soldiers fight in teams of at most FIRE_TEAM_SIZE,
-- each with one role, so teammates are soldiers fighting together.
FIRE_TEAM_SIZE = 4

-- The sides' soldiers: DrGBase NextBots (the entities wetsand_drg_combine
-- and wetsand_drg_rebel), each drafting its own model and weapons.
FACTIONS = {
	[RED] = {
		name = "Combine",
		team = RED,
		classes = { wetsand_drg_combine = true },
		recruits = { { class = "wetsand_drg_combine" } },
	},
	[BLUE] = {
		name = "Resistance",
		team = BLUE,
		classes = { wetsand_drg_rebel = true },
		recruits = { { class = "wetsand_drg_rebel" } },
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
-- one facing only the enemy's defends, and throws more blockers at the
-- cart once it is close to its checkpoint; on a race map each does both.
local ATTACK = { { role = PUSH, weight = 5 }, { role = ESCORT, weight = 5 } }
local DEFEND_STANCE = { { role = DEFEND, weight = 7 }, { role = BLOCK, weight = 3 } }
local DEFEND_CLOSE = { { role = DEFEND, weight = 4 }, { role = BLOCK, weight = 6 } }
local RACE = { { role = PUSH, weight = 4 }, { role = BLOCK, weight = 3 }, { role = ESCORT, weight = 3 } }

-- carts: team -> true, or { close = the cart is near its next checkpoint
-- (CartClose) }, for each team with a cart.
function Stance(team, carts)
	local own, enemy = carts[team], carts[ENEMY[team]]
	if own and enemy then return RACE end
	if own then return ATTACK end
	if enemy then return (type(enemy) == "table" and enemy.close) and DEFEND_CLOSE or DEFEND_STANCE end
	return nil
end

-- A cart is close to its checkpoint within CLOSE_RANGE along the track,
-- and stays close until it is CLOSE_RANGE + CLOSE_HYSTERESIS away, so a
-- cart rocking at the edge does not swap the defenders' roles back and forth.
CLOSE_RANGE, CLOSE_HYSTERESIS = 1024, 384

function CartClose(wasClose, remaining)
	if remaining <= CLOSE_RANGE then return true end
	return wasClose and remaining <= CLOSE_RANGE + CLOSE_HYSTERESIS or false
end

-- Whether two stances share their roles (weights aside): a team moving
-- between them keeps its members' roles where it can.
local function SameRoles(a, b)
	if #a ~= #b then return false end
	local roles = {}
	for _, share in ipairs(a) do roles[share.role] = true end
	for _, share in ipairs(b) do
		if not roles[share.role] then return false end
	end
	return true
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
		fireTeams = {}, -- every fire team: { team, role, index (per team and role), squad, members = place -> member }
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

-- Leaves the member's fire team, which goes when empty.
function War:LeaveFireTeam(member)
	local fireTeam = member.fireTeam
	if not fireTeam then return end
	fireTeam.members[member.place] = nil
	member.fireTeam, member.place = nil, nil
	if next(fireTeam.members) == nil then
		for i, other in ipairs(self.fireTeams) do
			if other == fireTeam then
				table.remove(self.fireTeams, i)
				break
			end
		end
	end
end

local function FreePlace(fireTeam)
	for place = 0, FIRE_TEAM_SIZE - 1 do
		if not fireTeam.members[place] then return place end
	end
	return nil
end

-- Joins an open fire team of the member's team and role, the lowest
-- indexed first, or starts one at the lowest free index.
function War:JoinFireTeam(member)
	local open, used = nil, {}
	for _, fireTeam in ipairs(self.fireTeams) do
		if fireTeam.team == member.team and fireTeam.role == member.role then
			used[fireTeam.index] = true
			if FreePlace(fireTeam) and (not open or fireTeam.index < open.index) then open = fireTeam end
		end
	end
	if not open then
		local index = 0
		while used[index] do index = index + 1 end
		open = {
			team = member.team, role = member.role, index = index, members = {},
			squad = "wetsand_aiwar_" .. member.team .. "_" .. member.role .. "_" .. index,
		}
		self.fireTeams[#self.fireTeams + 1] = open
	end
	member.place = FreePlace(open)
	member.fireTeam = open
	open.members[member.place] = member
end

-- The member's fire team's members in place order.
function War:FireTeamMembers(fireTeam)
	local list = {}
	for place = 0, FIRE_TEAM_SIZE - 1 do
		if fireTeam.members[place] then list[#list + 1] = fireTeam.members[place] end
	end
	return list
end

function War:AssignRole(member)
	self:LeaveFireTeam(member)
	local stance = self.stances[member.team]
	member.role = stance and PickRole(stance, RoleCounts(self.members, member.team, member)) or nil
	member.slot = member.role and FreeSlot(self.members, member.team, member.role, member) or 0
	if member.role then self:JoinFireTeam(member) end
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
	local member = self.members[handle]
	if member then self:LeaveFireTeam(member) end
	self.members[handle] = nil
end

-- The member takes another role, in its own fire team of that role.
function War:ChangeRole(member, role)
	self:LeaveFireTeam(member)
	member.role = role
	member.slot = FreeSlot(self.members, member.team, role, member)
	self:JoinFireTeam(member)
end

-- Rebalances a team to its stance's shares with as few role changes as
-- possible: the newest members of the roles over their share take the
-- roles under theirs.
function War:Rebalance(team, stance)
	local list = {}
	for _, member in ipairs(self:Members()) do
		if member.team == team and member.role then list[#list + 1] = member end
	end
	local target = {}
	for _ = 1, #list do
		local role = PickRole(stance, target)
		target[role] = (target[role] or 0) + 1
	end
	local counts = RoleCounts(self.members, team)
	for i = #list, 1, -1 do
		local member = list[i]
		if (counts[member.role] or 0) > (target[member.role] or 0) then
			for _, share in ipairs(stance) do
				if (counts[share.role] or 0) < (target[share.role] or 0) then
					counts[member.role] = counts[member.role] - 1
					counts[share.role] = (counts[share.role] or 0) + 1
					self:ChangeRole(member, share.role)
					break
				end
			end
		end
	end
end

-- A team whose stance changes is reassigned: rebalanced when the new
-- stance has the same roles (a cart nearing its checkpoint), otherwise (a
-- cart appears or goes) from scratch, oldest first.
function War:Assign(carts)
	for _, team in ipairs({ RED, BLUE }) do
		local stance = Stance(team, carts)
		local old = self.stances[team]
		if stance ~= old and stance and old and SameRoles(stance, old) then
			self.stances[team] = stance
			self:Rebalance(team, stance)
		elseif stance ~= old then
			self.stances[team] = stance
			local list = {}
			for _, member in ipairs(self:Members()) do
				if member.team == team then
					self:LeaveFireTeam(member)
					member.role = nil
					list[#list + 1] = member
				end
			end
			for _, member in ipairs(list) do self:AssignRole(member) end
		end
	end
end

-- The next recruit to spawn for a team (its squad is its fire team's,
-- given once it is enlisted).
function War:Draft(team)
	local n = self.drafts[team] + 1
	self.drafts[team] = n
	local recruits = FACTIONS[team].recruits
	return { recruit = recruits[(n - 1) % #recruits + 1] }
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
