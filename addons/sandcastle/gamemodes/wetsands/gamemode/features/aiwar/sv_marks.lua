-- Part of the AI war controller (sv.lua): what the Path Follower stool tells the war by hand
-- (features.aiwar.marks), each through the war's own inputs: posts are the field's posts for
-- the team, rallies where its recalled squads regroup (both read by the orders from the field),
-- an area to avoid closed as a disabled hazard is, an enemy seen a contact reported to the
-- team's squads; a camp (a spot an enemy kills its members from again and again) marked as the
-- war goes, a label for what its squads will throw and fire explosives at; a squad's next mission, the room and kind it is issued for; and the ways out of
-- a room, for the legs' panic.
local Controller = ...
local Marks = WS.require ("features.aiwar.marks")
local Camps = WS.require ("features.aiwar.camps")
local Tactics = wartactics.fireteam
local Mission = wartactics.mission
local Rooms = wartactics.rooms
local Teams = gameplay.teams

-- The areas this near an AVOID mark are closed.
local AVOID_REACH, AVOID_HEIGHT = 128, 64
-- An ENEMY mark is reported this often, well within a contact's memory.
local ENEMY_EVERY = 2
local MARKS_GLOBAL = "ns_marks"
-- A DANGER mark this near a squad's point, across the ground, is its to retreat from: about a
-- room's breadth.
local DANGER_REACH = 768

function Controller:MarksOf ()
	self.marks = self.marks or Marks.New ()
	return self.marks
end

-- Clients are told, and the areas to avoid are closed now; posts and rallies reach the next field.
function Controller:MarksChanged ()
	SetGlobal2String (MARKS_GLOBAL, self:MarksOf ():Encode ())
	self:ApplyHazards ()
end

function Controller:Mark (kind, team, pos)
	self:MarksOf ():Add (kind, team, pos)
	self:MarksChanged ()
end

-- The DANGER mark of team's nearest point, within DANGER_REACH, or nil.
function Controller:DangerNear (team, point)
	return self:MarksOf ():DangerNear (team, point, DANGER_REACH)
end

-- How many marks near pos were taken.
function Controller:Unmark (pos, reach)
	local removed = self:MarksOf ():RemoveNear (pos, reach)
	if removed > 0 then self:MarksChanged () end
	return removed
end

-- The nav areas the AVOID marks close, id -> true.
function Controller:MarkedAvoid ()
	local set = {}
	for _, mark in ipairs (self:MarksOf ():All ()) do
		if mark.kind == Marks.AVOID then
			local at = Vector (mark.pos.x, mark.pos.y, mark.pos.z)
			for _, area in ipairs (navmesh.Find (at, AVOID_REACH, AVOID_HEIGHT, AVOID_HEIGHT)) do set [area:GetID ()] = true end
		end
	end
	return set
end

-- Each think: the ENEMY marks reported to their team's squads.
function Controller:MarksThink (now)
	if now < (self.nextMarkReport or 0) then return end
	self.nextMarkReport = now + ENEMY_EVERY
	for _, mark in ipairs (self:MarksOf ():All ()) do
		if mark.kind == Marks.ENEMY then
			for _, fireTeam in ipairs (self.war.fireTeams) do
				if fireTeam.team == mark.team then Tactics.Report (fireTeam, mark.pos, now) end
			end
		end
	end
end

-- A kill while the war is on: an enemy killing again and again from one spot (features.aiwar.camps)
-- makes it a CAMP mark of its victims' team. A building's kills (a sentry's, credited to its
-- builder) are the building's: it is what camps.
function Controller:NoteKill (victim, attacker, inflictor)
	if IsValid (inflictor) and inflictor.GetObjTeam then attacker = inflictor end
	if not (self.war and IsValid (victim) and IsValid (attacker) and attacker ~= victim) then return end
	local killerTeam, victimTeam = WS.TeamNumber (attacker), WS.LastTeamNumber (victim)
	if not (Teams.EnemyOf (victimTeam) and killerTeam == Teams.EnemyOf (victimTeam)) then return end
	self.camps = self.camps or Camps.New ()
	local at = attacker:GetPos ()
	local camp = self.camps:Kill (attacker, killerTeam, victimTeam, { x = at.x, y = at.y, z = at.z }, CurTime ())
	if camp then self:Mark (Marks.CAMP, camp.team, camp.pos) end
end

hook.Add ("PlayerDeath", "ws_aiwar_camps", function (victim, inflictor, attacker) Controller:NoteKill (victim, attacker, inflictor) end)
hook.Add ("OnNPCKilled", "ws_aiwar_camps", function (victim, attacker, inflictor) Controller:NoteKill (victim, attacker, inflictor) end)

-- A squad's next mission by hand: kind (a wartactics.mission kind) in the room at pos, or
-- ADVANCE for none; the squad lets its mission go and asks afresh. Returns true, or false and why.
function Controller:GiveMission (fireTeam, kind, pos)
	local room
	if kind ~= Mission.ADVANCE then
		local area = navmesh.GetNearestNavArea (Vector (pos.x, pos.y, pos.z))
		room = IsValid (area) and self.rooms and Rooms.RoomOf (self.rooms, area:GetID ())
		if not room or room.outdoor or not room.doors or not room.doors [1] then
			return false, "no room indoors with a door there (or the map's rooms are not found yet)"
		end
	end
	fireTeam.missionGiven = { kind = kind, room = room }
	fireTeam.missionsOff = nil
	Mission.Finish (fireTeam)
	return true
end

-- What MissionSpec gives Issue for a squad's mission by hand, or nil: its target's door toward
-- where the squad comes from, its team's lanes' start (the enemy's, for an ambush).
function Controller:GivenMission (fireTeam, lanes)
	local given = fireTeam.missionGiven
	if not given then return nil end
	if not given.room then return { kind = given.kind } end
	local field = self.war:Field ()
	local from = lanes and lanes [1] and lanes [1].points [1]
	if given.kind == Mission.AMBUSH then
		local theirs = field and field.lanes and field.lanes [Teams.EnemyOf (fireTeam.team)]
		from = theirs and theirs [1] and theirs [1].points [1] or from
	end
	return { kind = given.kind, target = Mission.Target (given.room, from or given.room.center) }
end

-- What sees a point from a room: eyes on a lattice EYES across its block, ROOM_EYES_INSET clear of
-- its walls, at a standing eye's height; a point is seen when a line from any of them to its own
-- eye height meets no wall (glass and other breakables are seen through).
local EYES, ROOM_EYES_INSET, EYE_HEIGHT = 3, 48, Vector (0, 0, 64)
-- What a point in a room is worth to fight from: the share of the room's other ways in (its doors
-- and windows but the one the squad comes by) a standing eye there sees, weighed THREAT_WEIGHT;
-- the share of a FLOOR_SAMPLES-square lattice over its floor it sees; and the share of COVER_RAYS
-- directions in which a wall stands within COVER_REACH at the chest, weighed COVER_WEIGHT.
local THREAT_WEIGHT, COVER_WEIGHT = 2, 0.5
-- The classes' names of the teams (sv_classes' TEAMS), by number.
local TEAM_NAMES = { [WS.TEAM_RED] = "RED", [WS.TEAM_BLUE] = "BLU" }
local FLOOR_SAMPLES, COVER_RAYS, COVER_REACH, CHEST = 5, 8, 64, Vector (0, 0, 40)
-- Where one walking up to an entrance looks in from: LOOKOUT_ALONG out from it, LOOKOUT_ACROSS to
-- either side.
local LOOKOUT_ALONG, LOOKOUT_ACROSS = { 96, 192, 384 }, { -128, 0, 128 }

-- The room at point as a squad takes it (the legs' Assault and SetRoom; RoomAt is the war's room at a point): its block and middle, its
-- doors as its ways out and its entrances (each with the team's incursion flow into it there), the
-- doorway nearest from it comes in by, what it sees, what a point in it is worth to fight from, and,
-- given the squad's team, the enemy that team has marked in it nearest its middle (an ENEMY mark); nil where the map's rooms are not found,
-- none is there, or it has no door.
function Controller:RoomForSquad (point, from, team)
	local area = navmesh.GetNearestNavArea (Vector (point.x, point.y, point.z))
	local room = self.rooms and IsValid (area) and Rooms.RoomOf (self.rooms, area:GetID ())
	if not (room and room.doors and room.doors [1]) then return nil end
	local entry
	for _, door in ipairs (room.doors) do
		local d = (door.pos.x - from.x) ^ 2 + (door.pos.y - from.y) ^ 2
		if not entry or d < entry.d then entry = { pos = door.pos, d = d } end
	end
	local eyes = {}
	for i = 0, EYES - 1 do
		for j = 0, EYES - 1 do
			local t, u = i / (EYES - 1), j / (EYES - 1)
			eyes [#eyes + 1] = Vector (room.lo.x + ROOM_EYES_INSET + (room.hi.x - room.lo.x - 2 * ROOM_EYES_INSET) * t,
				room.lo.y + ROOM_EYES_INSET + (room.hi.y - room.lo.y - 2 * ROOM_EYES_INSET) * u, room.center.z) + EYE_HEIGHT
		end
	end
	local function Seen (p)
		local target = Vector (p.x, p.y, p.z) + EYE_HEIGHT
		for _, eye in ipairs (eyes) do
			if not util.TraceLine ({ start = eye, endpos = target, mask = MASK_SOLID_BRUSHONLY }).Hit then return true end
		end
		return false
	end
	local threats = {}
	for _, door in ipairs (room.doors) do
		if door.pos ~= entry.pos then threats [#threats + 1] = Vector (door.pos.x, door.pos.y, door.pos.z) + EYE_HEIGHT end
	end
	for _, window in ipairs (room.windows or {}) do threats [#threats + 1] = Vector (window.pos.x, window.pos.y, window.pos.z) end
	local floor = {}
	for i = 0, FLOOR_SAMPLES - 1 do
		for j = 0, FLOOR_SAMPLES - 1 do
			local t, u = (i + 0.5) / FLOOR_SAMPLES, (j + 0.5) / FLOOR_SAMPLES
			floor [#floor + 1] = Vector (room.lo.x + (room.hi.x - room.lo.x) * t, room.lo.y + (room.hi.y - room.lo.y) * u, room.center.z) + EYE_HEIGHT
		end
	end
	local function Sees (from, targets)
		if #targets == 0 then return 0 end
		local seen = 0
		for _, target in ipairs (targets) do
			if not util.TraceLine ({ start = from, endpos = target, mask = MASK_SOLID_BRUSHONLY }).Hit then seen = seen + 1 end
		end
		return seen / #targets
	end
	local function Score (p)
		local eye, chest = Vector (p.x, p.y, p.z) + EYE_HEIGHT, Vector (p.x, p.y, p.z) + CHEST
		local walls = 0
		for k = 0, COVER_RAYS - 1 do
			local angle = k / COVER_RAYS * 2 * math.pi
			local reach = chest + Vector (math.cos (angle), math.sin (angle), 0) * COVER_REACH
			if util.TraceLine ({ start = chest, endpos = reach, mask = MASK_SOLID_BRUSHONLY }).Hit then walls = walls + 1 end
		end
		return THREAT_WEIGHT * Sees (eye, threats) + Sees (eye, floor) + COVER_WEIGHT * walls / COVER_RAYS
	end
	local at = function (p) return { x = p.x, y = p.y, z = p.z } end
	local enemy
	for _, mark in ipairs (team and self:MarksOf ():Of (team, Marks.ENEMY) or {}) do
		local p = mark.pos
		if p.x >= room.lo.x and p.x <= room.hi.x and p.y >= room.lo.y and p.y <= room.hi.y
			and (not enemy or math.geometry.Distance2D (p, room.center) < math.geometry.Distance2D (enemy, room.center)) then
			enemy = p
		end
	end
	local exits = {}
	for i, door in ipairs (room.doors) do exits [i] = at (door.pos) end
	-- each door with the team's flow into the room by it, and the enemy's: their incursion routes
	-- and breaches entering there (the classes' entrances, once found; none while they are not)
	local entrances = {}
	for i, door in ipairs (room.doors) do entrances [i] = { pos = exits [i], flow = 0, enemyFlow = 0 } end
	local classes = team and self:Classes ()
	if team then
		local ourName = TEAM_NAMES [team]
		local enemyName = TEAM_NAMES [Teams.EnemyOf (team)]
		for _, e in ipairs (classes and classes.entrances or {}) do
			if e.room == room and (e.team == ourName or e.team == enemyName) then
				local nearest
				for _, entrance in ipairs (entrances) do
					if not nearest or math.geometry.Distance2D (entrance.pos, e.via) < math.geometry.Distance2D (nearest.pos, e.via) then
						nearest = entrance
					end
				end
				if e.team == ourName then nearest.flow = nearest.flow + e.paths end
				if e.team == enemyName then nearest.enemyFlow = nearest.enemyFlow + e.paths end
			end
		end
	end
	-- what one walking up to an entrance sees inside through it: a line from any lookout on its
	-- approach (LOOKOUT_ALONG out from it, LOOKOUT_ACROSS either side) to the point, at eye height
	local function Watched (p, entrance)
		local out = math.geometry.Normalize2D (math.geometry.Sub (entrance, room.center))
		local target = Vector (p.x, p.y, p.z) + EYE_HEIGHT
		for _, along in ipairs (LOOKOUT_ALONG) do
			for _, across in ipairs (LOOKOUT_ACROSS) do
				local eye = Vector (entrance.x + out.x * along - out.y * across, entrance.y + out.y * along + out.x * across,
					entrance.z) + EYE_HEIGHT
				if not util.TraceLine ({ start = eye, endpos = target, mask = MASK_SOLID_BRUSHONLY }).Hit then return true end
			end
		end
		return false
	end
	-- its own nav areas, which a squad staging round it keeps out of
	local inside = {}
	for _, id in ipairs (room.areas) do inside [id] = true end
	-- its name, as the map gives it (info_room)
	local hinted = (self:RoomHints () or {}) [room]
	return { center = at (room.center), lo = at (room.lo), hi = at (room.hi), entry = at (entry.pos), exits = exits,
		entrances = entrances, inside = inside, seen = Seen, watched = Watched, score = Score,
		enemy = enemy and at (enemy), label = hinted and hinted.label }
end

-- The doors of the room at point, as the ways out a panicked squad makes for (the legs'
-- SetExits), or nil where the map's rooms are not found or none is there.
function Controller:ExitsAt (point)
	local area = navmesh.GetNearestNavArea (Vector (point.x, point.y, point.z))
	local room = self.rooms and IsValid (area) and Rooms.RoomOf (self.rooms, area:GetID ())
	if not (room and room.doors and room.doors [1]) then return nil end
	local exits = {}
	for i, door in ipairs (room.doors) do exits [i] = door.pos end
	return exits
end
