-- ws.sound_paths: TF2 turned its voice lines from .wav into .mp3,
-- so a map's ambient_generic naming vo/<line>.wav plays nothing in GMod
-- (pl_bloodwater: 18 of them); it plays the .mp3 that replaced it.
local T = dofile("tests/harness.lua")
local SoundPaths = T.require("ws.sound_paths")

local function Files(list)
	local set = {}
	for _, path in ipairs(list) do set[path] = true end
	return function(path) return set[path] == true end
end

T.test("a .wav that is gone plays the .mp3 that replaced it", function()
	local exists = Files({ "sound/vo/halloween_merasmus/sf12_found01.mp3" })
	T.eq(SoundPaths.Replacement("vo/halloween_merasmus/sf12_found01.wav", exists), "vo/halloween_merasmus/sf12_found01.mp3")
end)

T.test("a sound that exists, or has no .mp3 to take its place, is left as it is", function()
	local exists = Files({ "sound/ambient/wind.wav", "sound/ambient/wind.mp3" })
	T.eq(SoundPaths.Replacement("ambient/wind.wav", exists), nil, "the .wav is there")
	T.eq(SoundPaths.Replacement("vo/gone.wav", exists), nil, "no .mp3 either")
	T.eq(SoundPaths.Replacement("Cart.Roll", exists), nil, "a sound script's name")
end)

T.test("the extension is matched whatever its case, and a leading ) or ^ (a sound's channel mark) is kept", function()
	local exists = Files({ "sound/vo/line.mp3" })
	T.eq(SoundPaths.Replacement("vo/line.WAV", exists), "vo/line.mp3")
	T.eq(SoundPaths.Replacement(")vo/line.wav", exists), ")vo/line.mp3")
end)

-- Sound names GMod's HL2 defines too: TF2's own sounds of surfaces and
-- doors win; any other keeps GMod's (HL2's weapons and NPCs share names
-- with TF2's).
T.test("TF2's surface and door sounds take the place of HL2's of the same name", function()
	T.eq(SoundPaths.TF2Wins("Water.StepLeft", "scripts/game_sounds_physics.txt"), true, "a surface's step")
	T.eq(SoundPaths.TF2Wins("Flesh.ImpactHard", "scripts/game_sounds_physics.txt"), true, "an impact")
	T.eq(SoundPaths.TF2Wins("DoorSound.DefaultMove", "scripts/game_sounds.txt"), true, "a door")
	T.eq(SoundPaths.TF2Wins("RotDoorSound.DefaultArrive", "scripts/game_sounds.txt"), true, "a rotating door")
	T.eq(SoundPaths.TF2Wins("NPC_CombineS.ElectrocuteScream", "scripts/game_sounds.txt"), false, "an NPC")
	T.eq(SoundPaths.TF2Wins("Weapon_Shotgun.Single", "scripts/game_sounds_weapons.txt"), false, "HL2's shotgun")
end)

-- A TF2 sound whose file HL2 also has under the same path plays HL2's
-- (GMod searches HL2's content first): its own copy goes under RELOCATED.
T.test("a TF2 sound file HL2 hides plays from its relocated copy; any other stays", function()
	local hidden = Files({ "player/footsteps/concrete1.wav" })
	T.eq(SoundPaths.Relocated("player/footsteps/concrete1.wav", hidden), SoundPaths.RELOCATED .. "player/footsteps/concrete1.wav", "hidden")
	T.eq(SoundPaths.Relocated(")player/footsteps/concrete1.wav", hidden), ")" .. SoundPaths.RELOCATED .. "player/footsteps/concrete1.wav", "its sound character kept")
	T.eq(SoundPaths.Relocated("doors/door_metal_rusty_move1.wav", hidden), "doors/door_metal_rusty_move1.wav", "TF2's own file")
end)

T.test("a sound's file is its path past the sound characters", function()
	T.eq(SoundPaths.File(")player/x.wav"), "player/x.wav", "spatial")
	T.eq(SoundPaths.File("^#player/x.wav"), "player/x.wav", "two")
	T.eq(SoundPaths.File("player/x.wav"), "player/x.wav", "none")
end)

T.finish()
