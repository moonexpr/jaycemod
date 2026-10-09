-- Which doors close the nav mesh, which GMod's nav mesh does not know:
-- a door shut and locked (map logic locks a door a capture closes for
-- good) blocks every route through the areas it overlaps. Any other door
-- is left to open as a soldier reaches it: TF2's own rule
-- (CTFNavMesh::ComputeBlockedAreas) also walls off a shut door no trigger
-- opens, and a team's spawn door to the other team, which shut soldiers
-- in their own spawn. That rule still marks the walls of setup: a shut
-- door no trigger opens (a setup gate) bounds the ground the attackers
-- wander in setup, though routes may pass it.
local ipairs, lower, sub = ipairs, string.lower, string.sub
module(...)

-- CBaseToggle's m_toggle_state
TS_AT_TOP, TS_AT_BOTTOM, TS_GOING_UP, TS_GOING_DOWN = 0, 1, 2, 3

ANY = "any"

function IsClosed(toggleState)
	return toggleState == TS_AT_BOTTOM or toggleState == TS_GOING_DOWN
end

-- door = { closed, locked, controlled (an enabled trigger overlaps it),
-- owner (the team its trigger's filter admits, or nil) }. Returns the team
-- the door blocks routes for (ANY for everyone), or nil.
function BlockedTeam(door)
	if door.closed and door.locked then return ANY end
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

-- The inputs that open a door.
local OPENING = {
	open = true,
	toggle = true,
	unlock = true,
}

-- Whether a trigger with these outputs ({ name, target, input }, as
-- WETSAND.ParseOutput gives them) opens the door named doorName: one of
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
