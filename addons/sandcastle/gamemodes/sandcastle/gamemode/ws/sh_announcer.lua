-- The announcer's game events, on every map, rounds or not: sounds the
-- server broadcasts and the announcement line. The server fires them to
-- everyone (ws/sv_world.lua: WS.BroadcastSoundscape,
-- BroadcastSoundscapeToOthers, BroadcastSoundFile, Announce); each client
-- decides whether its player hears a sound (games.gameplay.teams
-- HearsBroadcast) and plays it as its own. The rounds view draws the
-- announcement.
--
-- Sounds come in two kinds, kept apart. A soundscape is a soundscript's
-- name (announcer lines, music, chimes): each client precaches the ones
-- it will hear as it loads (ws.soundscapes) and plays them on its player
-- through system.local_player, the script's own channel, level and pitch
-- holding, so an announcer line on CHAN_VOICE2 cuts off the one before
-- (WS.PlaySoundscape, for the client's own cues too). A sound file is a
-- path, played at the channel the server gives.
local E = WS.Events
local Teams = WS.TeamRules

-- CTeamplayRoundBasedRules::BroadcastSound, TF2's event: team (UNASSIGNED
-- for everyone) and the soundscape; others: every player not on the team.
E.Define("game_teamplay_broadcast_audio", {
	team = E.Team(),
	sound = E.String(),
	others = E.Default(E.Bool(), false),
})

-- A sound file to team, on channel (CHAN_AUTO when not given). Source's
-- channels fit in a byte.
local CHANNEL_BITS = 8
E.Define("game_sound_file", {
	team = E.Team(),
	path = E.String(),
	channel = E.Default(E.UInt(CHANNEL_BITS), CHAN_AUTO),
})

-- A line of text across the top of every screen, in the team's colour; with
-- an icon (a material), TF2's notification card instead (the scramble's:
-- resource/ui/notifications/base_notification.res). audience: who sees it
-- (HearsBroadcast's teams; UNASSIGNED is everyone).
E.Define("game_announcement", {
	text = E.String(),
	team = E.Default(E.Team(), Teams.UNASSIGNED),
	audience = E.Default(E.Team(), Teams.UNASSIGNED),
	icon = E.Default(E.String(), ""),
})

-- Points an admin awarded a team (the Game Rules editor): the rounds view
-- flashes "+points" beside the team's score, as "+time" beside the timer.
local POINTS_BITS = 8
E.Define("game_points_awarded", {
	team = E.Team(),
	points = E.UInt(POINTS_BITS),
})

if CLIENT then
	local Soundscapes = WS.require("ws.soundscapes")

	-- system.local_player's engine: the soundscripts loaded, their files
	-- precached, played on the local player.
	local Engine = {}
	function Engine:Exists(name) return sound.GetProperties(name) ~= nil end
	function Engine:Precache(name)
		local files = sound.GetProperties(name).sound
		if isstring(files) then files = { files } end
		for _, path in ipairs(files) do util.PrecacheSound(path) end
	end
	-- heard as WSSoundscapePlayed(name): the voice panel's announcer note (ws/cl_voice.lua)
	function Engine:Emit(name)
		LocalPlayer():EmitSound(name)
		hook.Run("WSSoundscapePlayed", name)
	end

	local soundscapes = system.local_player.New(Engine)
	local function Preload(names)
		for _, name in ipairs(names) do soundscapes:Precache(name) end
	end
	-- the gamemode's own, then each feature's as it loads (its resources.lua)
	Preload(Soundscapes.PRELOAD)
	WS.FeatureLoader:Handle(system.features.SOUNDSCAPES, Preload)

	function WS.PrecacheSoundscape(name) return soundscapes:Precache(name) end
	function WS.PlaySoundscape(name) soundscapes:Play(name) end

	concommand.Add("ws_soundscapes_late", function()
		local late = soundscapes:Late()
		print(#late .. " soundscapes played before they were precached (ws.soundscapes' PRELOAD should take them):")
		for _, name in ipairs(late) do print("  " .. name) end
	end, nil, "List the soundscapes this client played without having precached them first")

	-- the player's own team, spectators' included: WS.TeamOf counts them
	-- unassigned, so a line to the spectators reached nobody
	local function Hears(ply, team, others)
		return IsValid(ply) and Teams.HearsBroadcast(team, others, ply:Team())
	end

	E.Listen("game_teamplay_broadcast_audio", "ws_announcer", function(fields)
		if Hears(LocalPlayer(), fields.team, fields.others) then WS.PlaySoundscape(fields.sound) end
	end)

	E.Listen("game_sound_file", "ws_announcer", function(fields)
		local ply = LocalPlayer()
		if Hears(ply, fields.team, false) then
			ply:EmitSound(fields.path, SNDLVL_100dB, 100, 1, fields.channel) -- path, level, pitch, volume, channel
		end
	end)
end
