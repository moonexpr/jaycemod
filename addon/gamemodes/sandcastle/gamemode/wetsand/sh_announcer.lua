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
-- The sound channel it plays on: CHAN_VOICE2 for the announcer
-- (WETSAND.BroadcastPA), so a new line cuts off the last instead of talking
-- over it; CHAN_AUTO otherwise. Source's channels fit in a byte.
local CHANNEL_BITS = 8

E.Define("teamplay_broadcast_audio", {
	team = E.Team(),
	sound = E.String(),
	channel = E.Default(E.UInt(CHANNEL_BITS), CHAN_AUTO),
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
		if Teams.HearsBroadcast(fields.team, fields.others, WETSAND.TeamOf(ply)) then 
			ply:EmitSound(fields.sound, SNDLVL_100dB, 100, 1, fields.channel) -- name, level, pitch, volume, channel
		end
	end)
end
