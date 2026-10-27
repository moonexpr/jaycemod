-- TF2's hit sound (tf_dingalingaling): which sound a hit plays
-- (tf_dingalingaling_effect, or tf_dingaling_wav_override's wav), its pitch
-- by the damage dealt (tf_dingaling_pitchmindmg at LOW_DAMAGE or less,
-- tf_dingaling_pitchmaxdmg at HIGH_DAMAGE or more), and the least time
-- between two (tf_dingalingaling_repeat_delay). ws/cl_hits.lua plays it.
local type = type
local Scalar = math.scalar
module(...)

-- tf_dingalingaling_effect's choices, 0 first, as TF2's options list them.
EFFECTS = {
	{ label = "Default", sound = "Player.HitSoundDefaultDing" },
	{ label = "Electro", sound = "Player.HitSoundElectro" },
	{ label = "Notes", sound = "Player.HitSoundNotes" },
	{ label = "Percussion", sound = "Player.HitSoundPercussion" },
	{ label = "Retro", sound = "Player.HitSoundRetro" },
	{ label = "Space", sound = "Player.HitSoundSpace" },
	{ label = "Beepo", sound = "Player.HitSoundBeepo" },
	{ label = "Vortex", sound = "Player.HitSoundVortex" },
	{ label = "Squasher", sound = "Player.HitSoundSquasher" },
}

LOW_DAMAGE, HIGH_DAMAGE = 10, 150

-- The sound for effect (0 to #EFFECTS - 1); a wav override, when not
-- empty, plays instead.
function Sound(effect, override)
	if override ~= "" then return override end
	return EFFECTS[effect + 1].sound
end

-- The files the hit sound plays, one picked a hit: sound's soundscript's
-- (scriptFiles: its one file or its list), or sound itself, a path, when
-- no soundscript has it (nil). Played as files, its pitch and volume are
-- the player's; a soundscript played by name would override them.
function Files(sound, scriptFiles)
	if scriptFiles == nil then return { sound } end
	if type(scriptFiles) == "string" then return { scriptFiles } end
	return scriptFiles
end

-- RemapValClamped(damage, LOW_DAMAGE, HIGH_DAMAGE, minPitch, maxPitch)
function Pitch(damage, minPitch, maxPitch)
	return Scalar.Remap(damage, LOW_DAMAGE, HIGH_DAMAGE, minPitch, maxPitch)
end

-- Whether a hit sound may play now, the last at lastAt (nil for none yet).
function Ready(lastAt, now, delay)
	return lastAt == nil or now - lastAt >= delay
end
