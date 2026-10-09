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

-- A line of text across the top of every screen, in the team's colour; with
-- an icon (a material), TF2's notification card instead (the scramble's:
-- resource/ui/notifications/base_notification.res). audience: who sees it
-- (HearsBroadcast's teams; UNASSIGNED is everyone).
E.Define("announcement", {
	text = E.String(),
	team = E.Default(E.Team(), Teams.UNASSIGNED),
	audience = E.Default(E.Team(), Teams.UNASSIGNED),
	icon = E.Default(E.String(), ""),
})

if CLIENT then
	E.Listen("teamplay_broadcast_audio", "wetsand_announcer", function(fields)
		local ply = LocalPlayer()
		if not IsValid(ply) then return end
		-- the player's own team, spectators' included: WETSAND.TeamOf counts
		-- them unassigned, so a line to the spectators reached nobody
		if Teams.HearsBroadcast(fields.team, fields.others, ply:Team()) then 
			ply:EmitSound(fields.sound, SNDLVL_100dB, 100, 1, fields.channel) -- name, level, pitch, volume, channel
		end
	end)
end
