-- HL2's voices for whoever wears its models (foundation.npc.voices): the AI
-- war's soldiers and the players alike. A death plays where it happened, its
-- cry loud (a rebel's scream layered) and then its confirmation (the
-- Combine's radio and flatline beeps), so the radio still sounds after the
-- soldier's body is gone. A player grunts
-- or cries out on a hit, as a soldier does (ws/sh_drg_soldier.lua), and
-- dies as one: in its model's voice, or in a model of none, its side's (the
-- faction fighting for its team, Voices.ForAffiliation); a spectator keeps
-- the engine's.
local Voices = WS.require("foundation.npc.voices")

-- The factions by name (foundation.aiwar's FACTIONS), and the sides they
-- start on, which hold while no war is on to trade them.
local AFFILIATION = { Combine = Voices.COMBINE, Resistance = Voices.REBEL }
local STARTING = { [WS.TEAM_RED] = Voices.COMBINE, [WS.TEAM_BLUE] = Voices.REBEL }

local function PlayerVoice(ply)
	local voice = Voices.For(ply:GetModel())
	if voice then return voice end
	local team = ply:Team()
	if WS.AiWarActive() then return Voices.ForAffiliation(AFFILIATION[WS.Feature("aiwar"):FactionName(team)]) end
	return STARTING[team] and Voices.ForAffiliation(STARTING[team])
end

-- A hit's grunt or cry: a soldier's level (SNDLVL_NORM).
local VOICE_LEVEL = 75

-- Plays voice's death at pos (Voices.Death); a voice without death lines
-- (the soldiers' silent one) plays none.
function WS.PlayDeath(pos, voice)
	if #voice.death == 0 then return end
	for _, s in ipairs(Voices.Death(voice, math.random)) do
		if s.delay == 0 then
			sound.Play(s.sound, pos, s.level, s.pitch)
		else
			timer.Simple(s.delay, function() sound.Play(s.sound, pos, s.level, s.pitch) end)
		end
	end
end

hook.Add("PlayerHurt", "ws_voices", function(ply, _, healthRemaining, damageTaken)
	local voice = PlayerVoice(ply)
	local now = CurTime()
	if not voice or healthRemaining <= 0 or damageTaken <= 0 or now < (ply.WSNextVoice or 0) then return end
	ply.WSNextVoice = now + Voices.FEEDBACK_COOLDOWN
	local lines = voice[Voices.Feedback(damageTaken, ply:GetMaxHealth())]
	ply:EmitSound(lines[math.random(#lines)], VOICE_LEVEL)
end)

-- GM:PlayerDeathSound: true silences the engine's own.
hook.Add("PlayerDeathSound", "ws_voices", function(ply)
	local voice = PlayerVoice(ply)
	if not voice then return end
	WS.PlayDeath(ply:GetPos(), voice)
	return true
end)
