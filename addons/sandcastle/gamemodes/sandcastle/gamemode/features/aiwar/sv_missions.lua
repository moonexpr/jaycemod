-- Part of the AI war controller (sv.lua): squads' missions
-- (docs/squad-missions-plan.md). A squad leader that wants a mission says
-- so on its squad (fireTeam.missionWanted, its orders' report up), with the
-- seconds it took to walk to where it waits (fireTeam.musterWalk). Each
-- think, every squad that wants one and has no request in flight asks the
-- tactics engine (wartactics.mission's Issue) as a transaction on the slow
-- lane, with MISSION_TIME to settle in. Committed, the mission is the
-- squad's (fireTeam.mission), which its lane follows (wartactics.lanes'
-- Assign); declined for want of lanes, it asks again after LANE_RETRY; out
-- of time, at the next think. A squad out on its mission is judged each
-- think and recalled to regroup on heavy casualties or no progress
-- (JudgeMission). A request that fails (our bug, logged), or a
-- mission given up (AbandonMission), leaves the squad on its scenario's
-- default behaviour (the lane wartactics.lanes' Assign gives it, its
-- orders), and it asks no more.
local Controller = ...
local Mission = wartactics.mission
local Orders = WS.require("features.aiwar.orders")
local Lanes = wartactics.lanes
local Squad = wartactics.squad
local Tactics = wartactics.fireteam
local Teams = gameplay.teams
local Geometry = math.geometry
local Transaction = transaction

local MISSION_TIME, LANE_RETRY = 2, 5
-- A soldier's walk, for how long members take to come (base_nextsoldier's
-- RunSpeed).
local RUN_SPEED = 220

local function Living(fireTeam)
	local alive, leader = 0, fireTeam.leader
	local farthest = 0
	for _, member in pairs(fireTeam.members) do
		alive = alive + 1
		if leader and leader.pos and member.pos then
			farthest = math.max(farthest, Geometry.Distance(leader.pos, member.pos))
		end
	end
	return alive, farthest
end

-- The rooms a team's lanes pass through (room id -> true), worked out once
-- for each plan of them.
local laneRooms = setmetatable({}, { __mode = "k" })

function Controller:LaneRooms(lanes)
	if not lanes then return {} end
	if laneRooms[lanes] then return laneRooms[lanes] end
	local crossed = {}
	for _, lane in ipairs(lanes) do
		for _, p in ipairs(lane.points) do
			local room = self:RoomAt(Vector(p.x, p.y, p.z))
			if room then crossed[room] = true end
		end
	end
	laneRooms[lanes] = crossed
	return crossed
end

-- The special missions' spec for a squad (wartactics.mission's Choose): the
-- map's rooms with what its team knows of each, whose lanes pass through
-- them, whether its team defends (on payload, the side without a cart),
-- where each side's lanes start, and the kinds its orders can lead
-- (Orders.SPECIAL_KINDS). nil before the rooms are known or with no lanes.
function Controller:SpecialSpec(fireTeam, size, now)
	local partition, field = self.rooms, self.war:Field()
	if not (partition and field and field.lanes) then return nil end
	local team = fireTeam.team
	local enemy = Teams.EnemyOf(team)
	local ourLanes, theirLanes = field.lanes[team], field.lanes[enemy]
	if not (ourLanes and ourLanes[1]) then return nil end
	local ours, theirs = self:LaneRooms(ourLanes), self:LaneRooms(theirLanes)
	local intel = self:Intel(team)
	local bases = {}
	for _, base in ipairs(intel:SupportBases(now)) do bases[base.room] = base.strength end
	local rooms = {}
	for _, room in ipairs(partition.rooms) do
		rooms[#rooms + 1] = { id = room.id, center = room.center, doors = room.doors, guarded = intel:Guarded(room.id, now),
			traffic = intel:Traffic(room.id, now), support = bases[room.id] or 0, ours = ours[room.id] == true,
			theirs = theirs[room.id] == true }
	end
	local ourFrom = ourLanes[1].points[1]
	local carts = field.carts or {}
	return {
		rooms = rooms,
		size = size,
		defending = carts[team] == nil and next(carts) ~= nil,
		taken = {},
		ourFrom = ourFrom,
		enemyFrom = theirLanes and theirLanes[1] and theirLanes[1].points[1] or ourFrom,
		kinds = Orders.SPECIAL_KINDS,
	}
end

-- The request's inputs, read on the slow lane: the squad's strength and how
-- long its members take to come (its leader's own walk to where it waits,
-- after spawning; the farthest living member's walk to it), its team's next
-- wave and lanes.
function Controller:MissionSpec(fireTeam, now)
	local field, war = self.war:Field(), self.war
	local alive, farthest = Living(fireTeam)
	local size = math.max(fireTeam.size or alive, alive)
	return {
		fireTeam = fireTeam,
		fireTeams = war.fireTeams,
		lanes = field and field.lanes and field.lanes[fireTeam.team],
		now = now,
		nextWave = war.nextWave[fireTeam.team],
		travel = math.max(fireTeam.musterWalk or 0, farthest / RUN_SPEED),
		missing = size - alive,
		size = size,
		regrouped = fireTeam.regrouping ~= nil,
		special = self:SpecialSpec(fireTeam, size, now),
	}
end

function Controller:RequestMission(fireTeam)
	local tx = Transaction.Spawn(WS.SlowTransactions, function(work)
		work:CheckYield()
		return Mission.Issue(self:MissionSpec(fireTeam, CurTime()))
	end):Within(WS.Deadline(MISSION_TIME))
	fireTeam.missionRequest = tx
	tx:OnSettle(function(settled)
		fireTeam.missionRequest = nil
		local state = settled:State()
		if fireTeam.missionsOff then return end
		if state == Transaction.COMMITTED then
			fireTeam.mission, fireTeam.missionWanted, fireTeam.regrouping = settled:Value(), nil, nil
			-- a squad out on one when the new came: halt, and on to the new
			if fireTeam.missionLed then fireTeam.halted, fireTeam.missionTrack = true, nil end
		elseif state == Transaction.DECLINED then
			if Transaction.IsRefusal(settled:Refusal(), { [Mission.NO_LANES] = true }) then
				fireTeam.missionRetryAt = CurTime() + LANE_RETRY
			end
		else
			ErrorNoHalt("AI war: a mission request failed: " .. tostring(settled:Error()) .. "\n")
			self:AbandonMission(fireTeam)
		end
	end)
	return tx
end

-- The squad gives its mission up and asks for none: its scenario's
-- default behaviour again.
function Controller:AbandonMission(fireTeam)
	fireTeam.mission, fireTeam.missionWanted, fireTeam.regrouping, fireTeam.missionsOff = nil, nil, nil, true
end

-- A squad out on its mission is judged (wartactics.mission's Regroup):
-- heavy casualties against the strength it led out with, or no progress
-- along its way from its leader's place, and it is recalled to regroup
-- (Recall), which its orders carry out.
function Controller:JudgeMission(fireTeam, now)
	local leader = Squad.Leader(fireTeam)
	if not (leader and leader.pos) then return end
	local alive = Living(fireTeam)
	local remaining = Lanes.Remaining(fireTeam.mission.way, leader.pos)
	fireTeam.missionTrack = fireTeam.missionTrack or Mission.Track(remaining, now)
	local why = Mission.Regroup(fireTeam.missionTrack, fireTeam.ledStrength or alive, alive, remaining, now,
		Tactics.Contact(fireTeam, now) ~= nil)
	if why then Mission.Recall(fireTeam, why) end
end

-- Every squad out on its mission is judged; every squad that wants one and
-- has none on the way asks; and a team with no alpha out has a squad out
-- on another mission ask again, to be made its alpha (Promote), which halts
-- it and sends it on the new.
function Controller:MissionsThink(now)
	for _, fireTeam in ipairs(self.war.fireTeams) do
		if fireTeam.missionLed and fireTeam.mission then self:JudgeMission(fireTeam, now) end
		if fireTeam.missionWanted and not fireTeam.missionRequest and now >= (fireTeam.missionRetryAt or 0) then
			self:RequestMission(fireTeam)
		end
	end
	for _, team in ipairs({ Teams.RED, Teams.BLUE }) do
		local promoted = Mission.Promote(self.war.fireTeams, team)
		if promoted and not promoted.missionRequest then self:RequestMission(promoted) end
	end
end
