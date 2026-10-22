-- An assisted kill's assister (ws/sv_kill_credit.lua), told to everyone
-- just after the kill's death notice, for the kill feed to name beside its
-- killer, "killer + assister" (ws/cl_kill_feed.lua).
local E = WS.Events

local TEAM_BITS = 16 -- Sandbox's TEAM_UNASSIGNED is 1001

-- victim and assister: named as GMod's death notices name them (a player's
-- name, "#<class>" for an NPC); team: the assister's, foundation.kill_feed's
-- NPC_TEAM for an NPC.
E.Define("game_kill_assist", {
	victim = E.String(),
	assister = E.String(),
	team = E.Int(TEAM_BITS),
})
