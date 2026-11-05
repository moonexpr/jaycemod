-- Part of the AI war controller (sv.lua): what the Tactical Behavior Tool tells the war by hand
-- (features.aiwar.marks), each through the war's own inputs: posts are the field's posts for
-- the team, rallies where its recalled squads regroup (both read by the orders from the field),
-- an area to avoid closed as a disabled hazard is, an enemy seen a contact reported to the
-- team's squads; and a squad's next mission, the room and kind it is issued for.
local Controller = ...
local Marks = WS.require("features.aiwar.marks")
local Tactics = wartactics.fireteam
local Mission = wartactics.mission
local Rooms = wartactics.rooms
local Teams = gameplay.teams

-- The areas this near an AVOID mark are closed.
local AVOID_REACH, AVOID_HEIGHT = 128, 64
-- An ENEMY mark is reported this often, well within a contact's memory.
local ENEMY_EVERY = 2
local MARKS_GLOBAL = "ns_marks"

function Controller:MarksOf()
	self.marks = self.marks or Marks.New()
	return self.marks
end

-- Clients are told, and the areas to avoid are closed now; posts and rallies reach the next field.
function Controller:MarksChanged()
	SetGlobal2String(MARKS_GLOBAL, self:MarksOf():Encode())
	self:ApplyHazards()
end

function Controller:Mark(kind, team, pos)
	self:MarksOf():Add(kind, team, pos)
	self:MarksChanged()
end

-- How many marks near pos were taken.
function Controller:Unmark(pos, reach)
	local removed = self:MarksOf():RemoveNear(pos, reach)
	if removed > 0 then self:MarksChanged() end
	return removed
end

-- The nav areas the AVOID marks close, id -> true.
function Controller:MarkedAvoid()
	local set = {}
	for _, mark in ipairs(self:MarksOf():All()) do
		if mark.kind == Marks.AVOID then
			local at = Vector(mark.pos.x, mark.pos.y, mark.pos.z)
			for _, area in ipairs(navmesh.Find(at, AVOID_REACH, AVOID_HEIGHT, AVOID_HEIGHT)) do set[area:GetID()] = true end
		end
	end
	return set
end

-- Each think: the ENEMY marks reported to their team's squads.
function Controller:MarksThink(now)
	if now < (self.nextMarkReport or 0) then return end
	self.nextMarkReport = now + ENEMY_EVERY
	for _, mark in ipairs(self:MarksOf():All()) do
		if mark.kind == Marks.ENEMY then
			for _, fireTeam in ipairs(self.war.fireTeams) do
				if fireTeam.team == mark.team then Tactics.Report(fireTeam, mark.pos, now) end
			end
		end
	end
end

-- A squad's next mission by hand: kind (a wartactics.mission kind) in the room at pos, or
-- ADVANCE for none; the squad lets its mission go and asks afresh. Returns true, or false and why.
function Controller:GiveMission(fireTeam, kind, pos)
	local room
	if kind ~= Mission.ADVANCE then
		local area = navmesh.GetNearestNavArea(Vector(pos.x, pos.y, pos.z))
		room = IsValid(area) and self.rooms and Rooms.RoomOf(self.rooms, area:GetID())
		if not room or room.outdoor or not room.doors or not room.doors[1] then
			return false, "no room indoors with a door there (or the map's rooms are not found yet)"
		end
	end
	fireTeam.missionGiven = { kind = kind, room = room }
	fireTeam.missionsOff = nil
	Mission.Finish(fireTeam)
	return true
end

-- What MissionSpec gives Issue for a squad's mission by hand, or nil: its target's door toward
-- where the squad comes from, its team's lanes' start (the enemy's, for an ambush).
function Controller:GivenMission(fireTeam, lanes)
	local given = fireTeam.missionGiven
	if not given then return nil end
	if not given.room then return { kind = given.kind } end
	local field = self.war:Field()
	local from = lanes and lanes[1] and lanes[1].points[1]
	if given.kind == Mission.AMBUSH then
		local theirs = field and field.lanes and field.lanes[Teams.EnemyOf(fireTeam.team)]
		from = theirs and theirs[1] and theirs[1].points[1] or from
	end
	return { kind = given.kind, target = Mission.Target(given.room, from or given.room.center) }
end
