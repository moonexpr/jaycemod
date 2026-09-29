-- Which doors close the nav mesh to whom: TF2's rule
-- (CTFNavMesh::ComputeBlockedAreas, tf_nav_mesh.cpp), which GMod's nav
-- mesh lacks, so routes led through shut doors. A func_door that an
-- enabled trigger_multiple overlaps is opened by that trigger; if the
-- trigger's filter_activator_tfteam admits one team, the door is that
-- team's (a spawn door) and blocks the other team, open or shut. A closed
-- door no trigger opens is a wall until map logic opens it (a setup gate,
-- a door opened by a capture) and blocks everyone. Every nav area the door
-- overlaps is blocked so.
module(...)

-- CBaseToggle's m_toggle_state
TS_AT_TOP, TS_AT_BOTTOM, TS_GOING_UP, TS_GOING_DOWN = 0, 1, 2, 3

ANY = "any"

function IsClosed(toggleState)
	return toggleState == TS_AT_BOTTOM or toggleState == TS_GOING_DOWN
end

-- door = { closed, controlled (an enabled trigger overlaps it), owner (the
-- team its trigger's filter admits, or nil) }; EnemyOf(team) -> the other
-- team. Returns the team the door blocks (ANY for everyone), or nil.
function BlockedTeam(door, EnemyOf)
	if door.owner then return EnemyOf(door.owner) or ANY end
	if door.closed and not door.controlled then return ANY end
	return nil
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
