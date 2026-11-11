-- An assisted kill's assister (ws/sv_kill_credit.lua), told to everyone
-- just after the kill's death notice, for the kill feed to name beside its
-- killer, "killer + assister" (ws/cl_kill_feed.lua); and a building destroyed.
local E = WS.Events

local TEAM_BITS = 16 -- Sandbox's TEAM_UNASSIGNED is 1001

-- victim and assister: named as GMod's death notices name them (a player's
-- name, "#<class>" for an NPC); team: the assister's, features.aiwar.kill_feed's
-- NPC_TEAM for an NPC.
E.Define ("game_kill_assist",
	{
		victim = E.String (),
		assister = E.String (),
		team = E.Int (TEAM_BITS)
	}
)

-- A building destroyed (base_obj's WSObjectDestroyed), told to everyone for the kill feed's row,
-- TF2's object_destroyed: object, its name (a TF2 token, "#TF_Object_Sentry", worded by each
-- client); builder, its builder's name ("" for none); team, its team; killer and killerTeam, as
-- game_kill_assist names and teams its assister ("" and NPC_TEAM for none); inflictor, the class
-- that struck, for its icon.
E.Define ("game_object_destroyed",
	{
		object = E.String (),
		builder = E.String (),
		team = E.Int (TEAM_BITS),
		killer = E.String (),
		killerTeam = E.Int (TEAM_BITS),
		inflictor = E.String ()
	}
)
