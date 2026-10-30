-- Part of the AI war controller (sv.lua): squads' missions
-- (docs/squad-missions-plan.md). A squad leader that wants a mission says
-- so on its squad (fireTeam.missionWanted, its orders' report up), with the
-- seconds it took to walk to where it waits (fireTeam.musterWalk). Each
-- think, every squad that wants one and has no request in flight asks the
-- tactics engine (wartactics.mission's Issue) as a transaction on the slow
-- lane, with MISSION_TIME to settle in. Committed, the mission is the
-- squad's (fireTeam.mission), which its lane follows (wartactics.lanes'
-- Assign); declined for want of lanes, it asks again after LANE_RETRY; out
-- of time, at the next think. A request that fails (our bug, logged), or a
-- mission given up (AbandonMission), leaves the squad on its scenario's
-- default behaviour (the lane wartactics.lanes' Assign gives it, its
-- orders), and it asks no more.
local Controller = ...
local Mission = wartactics.mission
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
		regrouped = fireTeam.regrouping == true,
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

-- Every squad that wants a mission and has none on the way asks.
function Controller:MissionsThink(now)
	for _, fireTeam in ipairs(self.war.fireTeams) do
		if fireTeam.missionWanted and not fireTeam.missionRequest and now >= (fireTeam.missionRetryAt or 0) then
			self:RequestMission(fireTeam)
		end
	end
end
