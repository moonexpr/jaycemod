-- Which doors close the nav mesh, which GMod's nav mesh does not know:
-- a door shut and locked (map logic locks a door a capture closes for
-- good) blocks every route through the areas it overlaps, and so, as in
-- TF2's own rule (CTFNavMesh::ComputeBlockedAreas), does a shut door that
-- nothing a soldier does opens: no trigger opens it and its spawnflags open
-- it to neither touch nor use (TouchOpens), so only the map's logic will
-- (cp_steel's point_a_brushdoor, at BLU's spawn exit). Any other door is
-- left to open as a soldier reaches it; TF2 also walls a team's spawn door
-- to the other team, which shut soldiers in their own spawn. A shut door no
-- trigger opens (a setup gate) also bounds the ground the attackers wander
-- in setup.
-- A door that is a floor (IsFloor: flat and wide, cp_steel's bridges) is
-- the other way round: closed is laid out, and open (drawn back) it blocks
-- everyone from its span, the areas where it lies closed.
local band, ipairs, lower, min, pairs, sub = bit.band, ipairs, string.lower, math.min, pairs, string.sub
module(...)

-- CBaseToggle's m_toggle_state
TS_AT_TOP, TS_AT_BOTTOM, TS_GOING_UP, TS_GOING_DOWN = 0, 1, 2, 3

ANY = "any"

-- a door this thin, and at least this wide both ways, is a floor
FLOOR_THICKNESS, FLOOR_WIDTH = 16, 48

-- size: the door's brush, { x, y, z } extents.
function IsFloor(size)
	return size.z <= FLOOR_THICKNESS and min(size.x, size.y) >= FLOOR_WIDTH
end

-- func_door's spawnflags: Use Opens, NPCs Can't, Touch Opens
SF_USE_OPENS, SF_NO_NPCS, SF_TOUCH_OPENS = 256, 512, 1024

-- Whether a soldier opens the door by touching or using it.
function TouchOpens(spawnflags)
	return band(spawnflags, SF_USE_OPENS + SF_TOUCH_OPENS) ~= 0 and band(spawnflags, SF_NO_NPCS) == 0
end

function IsClosed(toggleState)
	return toggleState == TS_AT_BOTTOM or toggleState == TS_GOING_DOWN
end

-- door = { floor, closed, locked, touchOpens (TouchOpens), controlled (an
-- enabled trigger overlaps it), owner (the team its trigger's filter admits,
-- or nil) }. Returns the team the door blocks routes for (ANY for
-- everyone), or nil.
function BlockedTeam(door)
	if door.floor then return not door.closed and ANY or nil end
	if door.closed and door.locked then return ANY end
	if door.closed and not door.controlled and not door.touchOpens then return ANY end
	return nil
end

-- Whether the door walls in setup's ground: shut, and no trigger opens it.
function IsWall(door)
	return door.closed and not door.controlled
end

-- blockedTeams: the teams an area's doors block (a list, or nil).
function Blocks(blockedTeams, team)
	if not blockedTeams then return false end
	for i = 1, #blockedTeams do
		local blocked = blockedTeams[i]
		if blocked == ANY or blocked == team then return true end
	end
	return false
end

-- Whether two lists of blocked teams close an area to the same teams, in
-- any order; nil and an empty list both close it to no one.
local function SameTeams(a, b)
	a, b = a or {}, b or {}
	for i = 1, #a do
		local found = false
		for j = 1, #b do
			if b[j] == a[i] then found = true end
		end
		if not found then return false end
	end
	for j = 1, #b do
		local found = false
		for i = 1, #a do
			if a[i] == b[j] then found = true end
		end
		if not found then return false end
	end
	return true
end

-- The areas whose blocking differs between two blocked maps (area id ->
-- its blocked teams): id -> true.
function Changed(before, after)
	local changed = {}
	for id, teams in pairs(before) do
		if not SameTeams(teams, after[id]) then changed[id] = true end
	end
	for id, teams in pairs(after) do
		if before[id] == nil and not SameTeams(nil, teams) then changed[id] = true end
	end
	return changed
end

-- The inputs that open a door.
local OPENING = {
	open = true,
	toggle = true,
	unlock = true,
}

-- Whether a trigger with these outputs ({ name, target, input }, as
-- WS.ParseOutput gives them) opens the door named doorName: one of
-- them sends that door (by name or wildcard) Open, Toggle or Unlock. An
-- unnamed door ("") is one no output names.
-- Whether an output's target names the door: the same name, or a prefix of
-- it ending in "*" (Source's wildcard: blue_spawn_door_1* is 1a and 1b).
local function Names(target, name)
	if sub(target, -1) == "*" then
		local prefix = sub(target, 1, -2)
		return sub(name, 1, #prefix) == prefix
	end
	return target == name
end

function Opens(outputs, doorName)
	if doorName == "" then return false end
	local name = lower(doorName)
	for _, output in ipairs(outputs) do
		if Names(lower(output.target), name) and OPENING[lower(output.input)] then return true end
	end
	return false
end
