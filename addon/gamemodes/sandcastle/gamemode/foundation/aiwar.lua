-- The AI war: a payload round fought by Half-Life 2's engine NPCs, the
-- Combine for RED and the Resistance for BLU. This model holds who fights
-- for whom, what each soldier is for (its role), when each side's dead come
-- back, and what the round state lets soldiers do. The soldiers' orders are
-- foundation.aiwar.orders; the features/aiwar controller spawns, enlists
-- and drives the NPCs.
--
-- Members are opaque handles (the NPC entities). Carts are given as the set
-- of teams with a cart moving on the map.
local floor, max, min, ipairs, next, pairs, setmetatable, sort, table, type = math.floor, math.max, math.min, ipairs, next, pairs, setmetatable, table.sort, table, type
local Teams = require("foundation.teams")
local STATE = require("foundation.rounds.state")
local Squad = require("foundation.aiwar.squad")
local Lanes = require("foundation.aiwar.lanes")
local Hunt = require("foundation.aiwar.hunt")
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
-- Raiders, on either side, go round the enemy's line and break it up;
-- support stands behind its own line and hits hard from there (the
-- Combine's metrocops with manhacks and turrets, the Resistance's heroes).
RAID, SUPPORT = "raid", "support"
-- Medics heal their side: a job apart from the stance's shares. Each side
-- keeps MedicsFor(its size) of them, drafted as medics (a class that is only
-- ever one, as the vortigaunt, or its side's soldier given the job) and never
-- rebalanced into another job.
MEDIC = "medic"
-- The point jobs (foundation.aiwar.scenario.control_points' doctrine):
-- capture stands on the point to take it, assault fights its way to it in
-- squads, and hold stands on its own point against a capture.
CAPTURE, ASSAULT, HOLD = "capture", "assault", "hold"

function MedicsFor(teamSize)
	if (teamSize or 0) < 4 then return 0 end
	return max(1, floor(teamSize / 8 + 0.5))
end

TEAM_SIZE_DEFAULT = 8
TEAM_SIZE_MAX = 32
-- Fire teams: a side's soldiers fight in teams of at most FIRE_TEAM_SIZE,
-- each with one role, so teammates are soldiers fighting together.
FIRE_TEAM_SIZE = 4

-- The sides' soldiers: DrGBase NextBots (the entities ws_drg_combine
-- and ws_drg_rebel), each drafting its own model and weapons.
FACTIONS = {
	[RED] = {
		name = "Combine",
		team = RED,
		classes = { ws_drg_combine = true },
		recruits = { { class = "ws_drg_combine" } },
		medic = { class = "ws_drg_combine" }, -- in a metrocop's kit
	},
	[BLUE] = {
		name = "Resistance",
		team = BLUE,
		-- a class whose value is a job only ever does that job
		classes = { ws_drg_rebel = true, ws_drg_vortigaunt = MEDIC },
		recruits = { { class = "ws_drg_rebel" } },
		medic = { class = "ws_drg_vortigaunt" },
	},
}

-- The job a class only ever does (the vortigaunt heals), or nil.
function FixedRole(class)
	for _, faction in pairs(FACTIONS) do
		local value = faction.classes[class]
		if type(value) == "string" then return value end
	end
	return nil
end

-- The team an NPC class fights for, or nil for a class in no faction.
function FactionTeam(class)
	for team, faction in pairs(FACTIONS) do
		if faction.classes[class] then return team end
	end
	return nil
end

-- Whether winner won the round as its defender: it held until the time
-- limit (defendedTimeLimit: WINREASON.DEFEND_UNTIL_TIME_LIMIT), or, on
-- payload, it had no cart and the losers had one. carts: team -> cart.
function DefenderWon(winner, defendedTimeLimit, carts)
	local loser = ENEMY[winner]
	if not loser then return false end
	if defendedTimeLimit then return true end
	return carts[winner] == nil and carts[loser] ~= nil
end

-- Stances: how a team splits its soldiers between roles, as integer
-- weights, first role first on a tie. No team is the attacker or the
-- defender: each has a defense share (DefenseShare), the part of its cart
-- work that goes against the enemy's cart (defending its line, blocking
-- it) rather than to its own (pushing, escorting). With only its own cart
-- a team is all offense, with only the enemy's all defense; on a race it
-- leans on whichever cart matters more. Its blockers outnumber its
-- defenders while the enemy's cart is close to its checkpoint. Every team
-- keeps a fifth of its soldiers raiding and a tenth in support, whose
-- focus follows the share too (foundation.aiwar.orders' Focus).
--
-- carts: team -> true, or { close = the cart is near its next checkpoint
-- (CartClose), progress = how far along its track, 0 to 1 }, for each team
-- with a cart.

-- A race: the share starts even, grows DEFENSE_LEAD per whole track the
-- enemy's cart is ahead of the team's, and by DEFENSE_CLOSE while the
-- enemy's is close to its checkpoint (shrinks the same while the team's
-- own is), kept within DEFENSE_MIN..DEFENSE_MAX, in tenths.
DEFENSE_EVEN, DEFENSE_LEAD, DEFENSE_CLOSE = 0.5, 1.5, 0.2
DEFENSE_MIN, DEFENSE_MAX = 0.2, 0.8

local function Info(cart) return type(cart) == "table" and cart or {} end

-- The team's defense share, in tenths (0 to 10), or nil with no cart at all.
function DefenseTenths(team, carts)
	local own, enemy = carts[team], carts[ENEMY[team]]
	if not own and not enemy then return nil end
	if not enemy then return 0 end
	if not own then return 10 end
	own, enemy = Info(own), Info(enemy)
	local share = DEFENSE_EVEN + ((enemy.progress or 0) - (own.progress or 0)) * DEFENSE_LEAD
	if enemy.close then share = share + DEFENSE_CLOSE end
	if own.close then share = share - DEFENSE_CLOSE end
	share = min(DEFENSE_MAX, max(DEFENSE_MIN, share))
	return floor(share * 10 + 0.5)
end

function DefenseShare(team, carts)
	local tenths = DefenseTenths(team, carts)
	return tenths and tenths / 10 or nil
end

-- Per tenth of offense, pushers and escorts 4:3; per tenth of defense,
-- defenders and blockers 5:2, or 2:5 with the enemy's cart close; raiders
-- and support as two and one tenths of the whole.
local PUSH_W, ESCORT_W = 4, 3
local DEFEND_W, BLOCK_W = 5, 2
local RAID_W, SUPPORT_W = 20, 10

local stances = {} -- key -> stance: the same situation, the same table

function Stance(team, carts)
	local tenths = DefenseTenths(team, carts)
	if not tenths then return nil end
	local close = tenths > 0 and Info(carts[ENEMY[team]]).close == true
	local key = tenths .. (close and "c" or "")
	if stances[key] then return stances[key] end
	local offense, defense = 10 - tenths, tenths
	local defendW, blockW = DEFEND_W, BLOCK_W
	if close then defendW, blockW = BLOCK_W, DEFEND_W end
	local cartWork = {
		offense = { { role = PUSH, weight = offense * PUSH_W }, { role = ESCORT, weight = offense * ESCORT_W } },
		defense = { { role = DEFEND, weight = defense * defendW }, { role = BLOCK, weight = defense * blockW } },
	}
	local order = tenths >= 5 and { "defense", "offense" } or { "offense", "defense" }
	local stance = {}
	for _, side in ipairs(order) do
		for _, share in ipairs(cartWork[side]) do
			if share.weight > 0 then stance[#stance + 1] = share end
		end
	end
	stance[#stance + 1] = { role = RAID, weight = RAID_W }
	stance[#stance + 1] = { role = SUPPORT, weight = SUPPORT_W }
	stances[key] = stance
	return stance
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
-- freezes players; sudden death has no respawns, and both sides hunt each
-- other down (everyoneHunts), every live enemy on their boards (sightAll);
-- a round won by a team is its humiliation of the losers, when the winners
-- hunt them down knowing what they saw (hunt: foundation.aiwar.hunt, TF2's
-- CTFBotTacticalMonitor "Get the losers!"); a round over with no winner
-- ends orders.
PHASES = {
	waiting = {
		name = "waiting",
		reinforce = false,
		orders = false,
		hunt = false,
		everyoneHunts = false,
		sightAll = false,
	},
	frozen = {
		name = "frozen",
		reinforce = true,
		orders = false,
		hunt = false,
		everyoneHunts = false,
		sightAll = false,
	},
	running = {
		name = "running",
		reinforce = true,
		orders = true,
		hunt = false,
		everyoneHunts = false,
		sightAll = false,
	},
	suddenDeath = {
		name = "suddenDeath",
		reinforce = false,
		orders = true,
		hunt = true,
		everyoneHunts = true,
		sightAll = true,
	},
	humiliation = {
		name = "humiliation",
		reinforce = false,
		orders = true,
		hunt = true,
		everyoneHunts = false,
		sightAll = false,
	},
	over = {
		name = "over",
		reinforce = false,
		orders = false,
		hunt = false,
		everyoneHunts = false,
		sightAll = false,
	},
}

local PHASE_OF_STATE = {
	[STATE.INIT] = PHASES.waiting,
	[STATE.PREGAME] = PHASES.waiting,
	[STATE.PREROUND] = PHASES.frozen,
	[STATE.RND_RUNNING] = PHASES.running,
	[STATE.STALEMATE] = PHASES.suddenDeath,
}

-- active: the map runs TF2's rounds (tf_gamerules); without them the war
-- simply runs. winner: the team that won the round (TEAM_WIN) or the match
-- (GAME_OVER, whose winners hunt to its music), or nil.
function PhaseOf(active, state, winner)
	if not active then return PHASES.running end
	if (state == STATE.TEAM_WIN or state == STATE.GAME_OVER) and ENEMY[winner] then return PHASES.humiliation end
	return PHASE_OF_STATE[state] or PHASES.over
end

-------------------------------------------------------------------------------
-- War: the roster and the waves

War = {}
War.__index = War

function War.New()
	return setmetatable({
		members = {}, -- handle -> member
		fireTeams = {}, -- every fire team: { team, role, index (per team and role), squad, members = place -> member,
		-- manual (formed or changed by hand: any size, the war leaves it be), chosen (the leader it was formed for) }
		autoSquads = true, -- whether the war groups soldiers into fire teams itself (SetAutoSquads)
		enlisted = 0, -- members ever enlisted, for their order
		claims = Squad.Claims.New(), -- spots soldiers hold (foundation.aiwar.squad)
		hunt = Hunt.Board.New(), -- the winners' sightings of the losers (foundation.aiwar.hunt)
		stances = {}, -- team -> stance
		defense = {}, -- team -> its defense share (DefenseShare), or nil
		drafts = { [RED] = 0, [BLUE] = 0 },
		sizes = { [RED] = 0, [BLUE] = 0 }, -- team -> its size, as Reinforcements was last given it
		nextWave = { [RED] = 0, [BLUE] = 0 },
		factions = { [RED] = FACTIONS[RED], [BLUE] = FACTIONS[BLUE] }, -- team -> the faction fighting for it
		field = nil,
	}, War)
end

-- The faction fighting for team: FACTIONS' to begin with, swapped when the
-- defenders win (SwapFactions).
function War:Faction(team)
	return self.factions[team]
end

-- The team a class fights for in this war, or nil for a class in no faction.
function War:FactionTeam(class)
	for team, faction in pairs(self.factions) do
		if faction.classes[class] then return team end
	end
	return nil
end

-- The defenders won (DefenderWon): the factions trade sides, so the side
-- that defended attacks next.
function War:SwapFactions()
	self.factions[RED], self.factions[BLUE] = self.factions[BLUE], self.factions[RED]
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
	if fireTeam.leader == member then fireTeam.leader = nil end
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

-- The lowest free place; a fire team the war formed holds FIRE_TEAM_SIZE,
-- one formed by hand any number.
local function FreePlace(fireTeam)
	local place = 0
	while fireTeam.members[place] do place = place + 1 end
	if not fireTeam.manual and place >= FIRE_TEAM_SIZE then return nil end
	return place
end

-- The lowest index no fire team of the team and role has.
local function FreeIndex(fireTeams, team, role, except)
	local used = {}
	for _, fireTeam in ipairs(fireTeams) do
		if fireTeam ~= except and fireTeam.team == team and fireTeam.role == role then used[fireTeam.index] = true end
	end
	local index = 0
	while used[index] do index = index + 1 end
	return index
end

-- Names the fire team for its team, role and index (its squad).
local function Index(fireTeams, fireTeam)
	fireTeam.index = FreeIndex(fireTeams, fireTeam.team, fireTeam.role, fireTeam)
	fireTeam.squad = "ws_aiwar_" .. fireTeam.team .. "_" .. fireTeam.role .. "_" .. fireTeam.index
end

local function NewFireTeam(war, team, role, manual)
	local fireTeam = {
		team = team,
		role = role,
		members = {},
		manual = manual,
	}
	Index(war.fireTeams, fireTeam)
	war.fireTeams[#war.fireTeams + 1] = fireTeam
	return fireTeam
end

local function Seat(member, fireTeam)
	member.place = FreePlace(fireTeam)
	member.fireTeam = fireTeam
	fireTeam.members[member.place] = member
end

-- Joins an open fire team the war formed of the member's team and role,
-- the lowest indexed first, or starts one at the lowest free index.
function War:JoinFireTeam(member)
	local open = nil
	for _, fireTeam in ipairs(self.fireTeams) do
		if fireTeam.team == member.team and fireTeam.role == member.role and not fireTeam.manual
			and FreePlace(fireTeam) and (not open or fireTeam.index < open.index) then
			open = fireTeam
		end
	end
	Seat(member, open or NewFireTeam(self, member.team, member.role, false))
end

local function ByPlace(a, b)
	return a.place < b.place
end

-- The member's fire team's members in place order.
function War:FireTeamMembers(fireTeam)
	local list = {}
	for _, member in pairs(fireTeam.members) do list[#list + 1] = member end
	sort(list, ByPlace)
	return list
end

-- Whether the war leaves the member's job and squad be: given by hand, or
-- in a squad formed or changed by hand.
local function Held(member)
	return member.roleByHand == true or (member.fireTeam ~= nil and member.fireTeam.manual == true)
end

-- In a fire team of the war's, when the war groups soldiers itself.
local function Regroup(war, member)
	if war.autoSquads and member.role and not member.fireTeam then war:JoinFireTeam(member) end
end

function War:AssignRole(member)
	self:LeaveFireTeam(member)
	local stance = self.stances[member.team]
	if member.fixed then
		member.role = member.fixed
	else
		member.role = stance and PickRole(stance, RoleCounts(self.members, member.team, member)) or nil
	end
	member.slot = member.role and FreeSlot(self.members, member.team, member.role, member) or 0
	Regroup(self, member)
end

-- drafted: spawned by the war (counted against the team's size), rather
-- than added by a player. fixed: the job it only ever does (MEDIC), or nil.
function War:Enlist(handle, team, drafted, fixed)
	self.enlisted = self.enlisted + 1
	local member = { handle = handle, team = team, drafted = drafted, seq = self.enlisted, role = nil, slot = 0, fixed = fixed }
	self.members[handle] = member
	self:AssignRole(member)
	return member
end

function War:Discharge(handle)
	local member = self.members[handle]
	if member then
		self:LeaveFireTeam(member)
		self.claims:ReleaseAll(member)
	end
	self.members[handle] = nil
end

-- The member takes another role, in its own fire team of that role.
function War:ChangeRole(member, role)
	self:LeaveFireTeam(member)
	member.role = role
	member.slot = FreeSlot(self.members, member.team, role, member)
	Regroup(self, member)
end

-- Rebalances a team to its stance's shares with as few role changes as
-- possible: the newest members of the roles over their share take the
-- roles under theirs.
function War:Rebalance(team, stance)
	local list = {}
	for _, member in ipairs(self:Members()) do
		if member.team == team and member.role and not member.fixed and not Held(member) then list[#list + 1] = member end
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

-- The team's roles given out again under its stance, from scratch, oldest
-- first.
function War:Reassign(team, stance)
	self.stances[team] = stance
	local list = {}
	for _, member in ipairs(self:Members()) do
		if member.team == team and not Held(member) then
			self:LeaveFireTeam(member)
			member.role = nil
			list[#list + 1] = member
		end
	end
	for _, member in ipairs(list) do self:AssignRole(member) end
end

-- A team whose stance changes is reassigned: rebalanced when the new
-- stance has the same roles (a cart nearing its checkpoint), otherwise (a
-- cart appears or goes) from scratch, oldest first.
function War:Assign(carts)
	for _, team in ipairs({ RED, BLUE }) do
		self.defense[team] = DefenseShare(team, carts)
		local stance = Stance(team, carts)
		local old = self.stances[team]
		if stance ~= old and stance and old and SameRoles(stance, old) then
			self.stances[team] = stance
			self:Rebalance(team, stance)
		elseif stance ~= old then
			self:Reassign(team, stance)
		end
	end
end

-- A scenario's allocation (foundation.aiwar.scenario): stances = team ->
-- stance, defense = team -> its defense share. A team given a stance while
-- it has one is rebalanced to it with the fewest moves, even when roles
-- leave the stance (Rebalance moves their members to the roles short of
-- their share); a team without one is assigned from scratch, oldest first.
-- A team with no entry is left as it is.
function War:AssignStances(stances, defense)
	for _, team in ipairs({ RED, BLUE }) do
		local stance = stances[team]
		if stance then
			self.defense[team] = defense[team]
			local old = self.stances[team]
			if old and stance ~= old then
				self.stances[team] = stance
				self:Rebalance(team, stance)
			elseif not old then
				self:Reassign(team, stance)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Squads and jobs by hand (ns_squads_*, ns_soldiers_job)

-- on: the war groups soldiers into fire teams itself, and groups those in
-- none now; off: soldiers out of a squad stay out until put in one by hand.
function War:SetAutoSquads(on)
	self.autoSquads = on
	for _, member in ipairs(self:Members()) do Regroup(self, member) end
end

-- Every soldier out of its squad; with automatic squads, grouped afresh.
function War:DissolveSquads()
	for _, member in pairs(self.members) do self:LeaveFireTeam(member) end
	for _, member in ipairs(self:Members()) do Regroup(self, member) end
end

-- A squad by hand, led by `leader`, which leaves its own; returns it.
function War:FormSquad(leader)
	self:LeaveFireTeam(leader)
	local fireTeam = NewFireTeam(self, leader.team, leader.role, true)
	fireTeam.chosen = leader
	Seat(leader, fireTeam)
	return fireTeam
end

-- The member joins the squad and takes its job (a medic keeps healing);
-- the squad is one by hand from now on. Returns true, or false and why.
function War:JoinSquad(member, fireTeam)
	if member.team ~= fireTeam.team then return false, member.handle .. " fights for the other side" end
	fireTeam.manual = true
	if member.fireTeam == fireTeam then return true end
	self:LeaveFireTeam(member)
	if not member.fixed then
		member.role = fireTeam.role
		member.slot = FreeSlot(self.members, member.team, fireTeam.role, member)
	end
	Seat(member, fireTeam)
	return true
end

-- Out of its squad: solo, or in one of the war's with automatic squads.
function War:LeaveSquad(member)
	self:LeaveFireTeam(member)
	Regroup(self, member)
end

-- The member's job, by hand; in a squad by hand, the whole squad's. The war
-- leaves it be until ReleaseRole. Returns true, or false and why.
function War:SetRole(member, role)
	if member.fixed then return false, member.handle .. " only ever does " .. member.fixed end
	local fireTeam = member.fireTeam
	if fireTeam and fireTeam.manual then
		fireTeam.role = role
		Index(self.fireTeams, fireTeam)
		for _, mate in pairs(fireTeam.members) do
			if not mate.fixed then
				mate.role = role
				mate.slot = FreeSlot(self.members, mate.team, role, mate)
			end
		end
		return true
	end
	member.roleByHand = true
	self:ChangeRole(member, role)
	return true
end

-- The member's job is the war's again: given now from the team's stance.
function War:ReleaseRole(member)
	member.roleByHand = nil
	if not Held(member) then self:AssignRole(member) end
end

-- The next recruit to spawn for a team (its squad is its fire team's,
-- given once it is enlisted).
-- A medic comes first while the side has fewer than MedicsFor its size:
-- { recruit, role = MEDIC }.
function War:Draft(team)
	local faction = self:Faction(team)
	local medics = 0
	for _, member in pairs(self.members) do
		if member.team == team and member.role == MEDIC then medics = medics + 1 end
	end
	if faction.medic and medics < MedicsFor(self.sizes[team]) then return { recruit = faction.medic, role = MEDIC } end
	local n = self.drafts[team] + 1
	self.drafts[team] = n
	local recruits = faction.recruits
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
-- due, it is topped back up to its size (sizes = team -> how many drafted
-- soldiers it keeps: its faction's slots, foundation.aiwar.slots), and the
-- next wave is waveLength(team) seconds away (0: every call). Returns team
-- -> how many to spawn now.
function War:Reinforcements(now, sizes, waveLength)
	self.sizes = sizes
	local wave = {}
	for _, team in ipairs({ RED, BLUE }) do
		if now >= self.nextWave[team] then
			self.nextWave[team] = now + waveLength(team)
			local missing = sizes[team] - self:DraftedCount(team)
			if missing > 0 then wave[team] = missing end
		end
	end
	return wave
end

function War:ResetWaves()
	self.nextWave = { [RED] = 0, [BLUE] = 0 }
end

-- The team's next wave comes at the next Reinforcements (a slot was added).
function War:CallWave(team)
	self.nextWave[team] = 0
end

-- The battlefield the orders read: { phase, setup (the round is in
-- setup), carts = team -> { track (foundation.aiwar.track), distance along
-- it, pos, nextCheckpoint (distance along it) }, gates = team -> list of
-- { pos, dir }: the doors that team must pass to reach the rest of the map,
-- dir the way it passes them, posts = team -> points where its defenders
-- establish their line, forwardPosts = team -> points ahead of its own
-- cart where its escorts do (foundation.aiwar.posts) }. The war adds
-- defense = team -> its defense share (DefenseShare).
function War:SetField(field)
	field.defense = self.defense
	-- each offensive squad holds one of its team's lanes (field.lanes)
	Lanes.Assign(self.fireTeams, field.lanes or {})
	self.field = field
end

function War:Field()
	return self.field
end
