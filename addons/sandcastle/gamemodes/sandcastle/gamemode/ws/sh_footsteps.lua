-- A player's footsteps play as loud as the soldiers' (Noise.Played: twice
-- Source's volume, at most full), so they carry over the fighting. The
-- engine's step is replaced by the same sound louder, on both realms as the
-- engine's is: the stepping player's own client plays it, and the server to
-- everyone else (filter). The sound is the surface's step (TF2's own,
-- ws/sh_soundscripts.lua).
local Noise = nextsoldier.noise

-- A surface's step is a sound script carrying its own level; a step that
-- names a file (a ladder's, a map's) plays at PlayStepSound's SNDLVL_NORM.
local STEP_LEVEL = 75

hook.Add("PlayerFootstep", "ws_footsteps", function(ply, pos, foot, name, volume, filter)
	if CLIENT and not IsFirstTimePredicted() then return true end
	local script = sound.GetProperties(name)
	ply:EmitSound(name, script and script.level or STEP_LEVEL, 100, Noise.Played(volume), CHAN_BODY, 0, 0, filter)
	return true
end)
