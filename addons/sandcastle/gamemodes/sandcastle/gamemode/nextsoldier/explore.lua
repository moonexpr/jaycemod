-- Exploring: arena's squads search the map (features.aiwar.scenario.arena).
-- The waypoints are the nav mesh's area centres thinned to one per SPACING
-- cell (Sample). A Board keeps, per squad, the waypoints its own soldiers
-- have been near (Visit): each squad knows only where it has been. Next
-- gives a squad the nearest waypoint it has not visited, keeping it until
-- visited; a team's squads claim theirs, so no two of a team make for the
-- same one (the enemy's claims are its own). A waypoint not reached within
-- GIVE_UP is given up as visited (unreachable, or the way is long); a squad
-- that has been everywhere starts over.
--
-- Before the waypoints, a squad walks its lane (nextsoldier.lanes,
-- fireTeam.lane) to the objective, until one of its soldiers stands within
-- VISIT_RADIUS of the lane's end (Board:Walk). A squad in a fight is engaged
-- (Board:Engage): it leaves its lane and hunts where it last saw the enemy for
-- ENGAGED_FOR after that, the fight before the objective; then it goes back
-- to its lane. The board is the round's: a new round walks the lanes again.
--
-- Positions are { x, y, z } tables; a squad is any key.
local ipairs, pairs, setmetatable = ipairs, pairs, setmetatable
local Lease = world.lease
local Grid = world.grid
local Tactics = nextsoldier.tactics
local Distance = math.geometry.Distance
local Select = list.select
module(...)

-- A waypoint per cell this wide, a waypoint counts as visited by a soldier
-- this close, and is given up after this long.
SPACING = 512
VISIT_RADIUS = 256
GIVE_UP = 30
-- A squad stays engaged this long after it last saw the enemy.
ENGAGED_FOR = 20

-------------------------------------------------------------------------------
-- An explorer's goal (field.explore: the scenario's Board, which keeps each
-- squad's lane walked and fights for the round)

-- Where the member's squad fights: its contact, else, engaged, where it last
-- saw the enemy, else nil.
function Fight(field, member)
	local fireTeam = member.fireTeam
	if not fireTeam then return nil end
	local contact = Tactics.Contact(fireTeam, field.now)
	if contact then return contact.pos end
	return field.explore:Engaged(fireTeam, field.now)
end

-- Where its squad fights, else its lane's end, else its waypoint.
function Goal(field, member)
	local fireTeam = member.fireTeam
	local goal = Fight(field, member) or (fireTeam and field.explore:LaneEnd(fireTeam))
	if goal then return goal end
	local squad = fireTeam and fireTeam.squad or member.handle
	return field.explore:Next(squad, member.team, member.pos or field.bases[member.team], field.now)
end

-- Whether an explorer's squad keeps off its lane: while it is engaged.
function LeavesLane(field, member)
	return member.fireTeam ~= nil and field.explore:Engaged(member.fireTeam, field.now) ~= nil
end

-- The first of points in each spacing cube, in points' order.
function Sample(points, spacing)
	return Grid.Thin(points, spacing)
end

-------------------------------------------------------------------------------
-- Board

Board = {}
Board.__index = Board

function Board.New(waypoints)
	return setmetatable({
		waypoints = waypoints,
		visited = {}, -- squad -> waypoint index -> true
		targets = {}, -- squad -> { index, since }
		claims = {}, -- team -> leases (foundation.world.lease) of waypoint indexes
		walked = {}, -- squad -> the lane it walked to its end
		engaged = {}, -- squad -> { pos, time }: where and when it last saw the enemy
	}, Board)
end

-- A squad's lane and fights (fireTeam: features.aiwar.model's) -------------------

-- The squad's contact (nextsoldier.tactics' { pos, time }) engages it.
function Board:Engage(fireTeam, contact)
	self.engaged[fireTeam.squad] = {
		pos = contact.pos,
		time = contact.time,
	}
end

-- Where the engaged squad last saw the enemy, or nil once it is not engaged.
function Board:Engaged(fireTeam, now)
	local engaged = self.engaged[fireTeam.squad]
	if engaged and now - engaged.time <= ENGAGED_FOR then return engaged.pos end
	return nil
end

-- A soldier of the squad is at pos: at its lane's end, the lane is walked.
function Board:Walk(fireTeam, pos)
	local lane = fireTeam.lane
	if lane and Distance(lane.points[#lane.points], pos) <= VISIT_RADIUS then self.walked[fireTeam.squad] = lane end
end

-- The end of the squad's lane while it is still to walk, or nil.
function Board:LaneEnd(fireTeam)
	local lane = fireTeam.lane
	if lane and self.walked[fireTeam.squad] ~= lane then return lane.points[#lane.points] end
	return nil
end

local function Visited(self, squad)
	local visited = self.visited[squad]
	if not visited then
		visited = {}
		self.visited[squad] = visited
	end
	return visited
end

local function ClaimsOf(self, team)
	local claims = self.claims[team]
	if not claims then
		claims = Lease.New()
		self.claims[team] = claims
	end
	return claims
end

-- The war's members this think (features.aiwar.model's): each squad's soldiers
-- mark where they have been and how far along its lane, and a squad in
-- contact is engaged.
function Board:Survey(members, now)
	for _, member in ipairs(members) do
		local fireTeam = member.fireTeam
		if fireTeam and member.pos then
			self:Visit(fireTeam.squad, member.pos)
			self:Walk(fireTeam, member.pos)
		end
		local contact = fireTeam and Tactics.Contact(fireTeam, now)
		if contact then self:Engage(fireTeam, contact) end
	end
end

-- A soldier of the squad is at pos.
function Board:Visit(squad, pos)
	local visited = Visited(self, squad)
	for i, w in ipairs(self.waypoints) do
		if Distance(w, pos) <= VISIT_RADIUS then visited[i] = true end
	end
end

-- The nearest waypoint the squad has not visited and its team has not
-- claimed for another squad, or nil.
local function Nearest(self, squad, team, here, now)
	local visited, claims = Visited(self, squad), ClaimsOf(self, team)
	local _, _, index = Select.Nearest(self.waypoints, here, nil, function(_, i)
		return not visited[i] and claims:FreeFor(i, squad, now)
	end)
	return index
end

-- The squad's waypoint, from here (where it is), or nil without waypoints.
function Board:Next(squad, team, here, now)
	local visited, claims = Visited(self, squad), ClaimsOf(self, team)
	local target = self.targets[squad]
	if target and now - target.since > GIVE_UP then visited[target.index] = true end
	if target and not visited[target.index] then return self.waypoints[target.index] end
	if target then claims:Release(target.index, squad) end
	local index = Nearest(self, squad, team, here, now)
	if not index then
		-- everywhere visited: start over
		for i in pairs(visited) do visited[i] = nil end
		index = Nearest(self, squad, team, here, now)
	end
	if not index then
		self.targets[squad] = nil
		return nil
	end
	claims:Take(index, squad, now, GIVE_UP)
	self.targets[squad] = {
		index = index,
		since = now,
	}
	return self.waypoints[index]
end
