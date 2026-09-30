-- The announcer's game events, on every map, rounds or not: sounds the
-- server broadcasts (announcer lines, win and lose music) and the
-- announcement line. The server fires them to everyone (wetsand/sv_world.lua:
-- WETSAND.BroadcastSound, BroadcastSoundToOthers, Announce); each client
-- decides whether its player hears a sound (foundation.teams
-- HearsBroadcast) and plays it as its own. The rounds view draws the
-- announcement.
local E = WETSAND.Events
local Teams = WETSAND.TeamRules

-- CTeamplayRoundBasedRules::BroadcastSound: team (UNASSIGNED for
-- everyone) and the game sound; others: every player not on the team.
E.Define("teamplay_broadcast_audio", {
	team = E.Team(),
	sound = E.String(),
	others = E.Default(E.Bool(), false),
})

-- A line of text across the top of every screen, in the team's colour.
E.Define("announcement", {
	text = E.String(),
	team = E.Default(E.Team(), Teams.UNASSIGNED),
})

if CLIENT then
	E.Listen("teamplay_broadcast_audio", "wetsand_announcer", function(fields)
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		if Teams.HearsBroadcast(fields.team, fields.others, WETSAND.TeamOf(ply)) then ply:EmitSound(fields.sound) end
	end)
end
