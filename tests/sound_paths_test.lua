-- foundation.sound_paths: TF2 turned its voice lines from .wav into .mp3,
-- so a map's ambient_generic naming vo/<line>.wav plays nothing in GMod
-- (pl_bloodwater: 18 of them); it plays the .mp3 that replaced it.
local T = dofile("tests/harness.lua")
local SoundPaths = T.require("foundation.sound_paths")

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

T.finish()
