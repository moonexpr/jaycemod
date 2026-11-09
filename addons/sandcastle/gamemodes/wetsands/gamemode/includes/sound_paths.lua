-- Sound paths TF2 has since changed: it turned its voice lines from .wav
-- into .mp3, so a map's ambient_generic naming vo/<line>.wav plays nothing
-- (pl_bloodwater has 18), and plays the .mp3 that replaced it instead (as
-- the TF2 Resource Mounting Fix addon does for vo/). A leading sound
-- character (")" spatial, "^" distance, ...) is kept.
--
-- And which of TF2's sound names take the place of GMod's own of the same
-- name (ws/sh_soundscripts.lua): its surfaces' (steps, impacts, water) and
-- doors', so a TF2 map's doors and floors sound as in TF2. HL2's weapons and
-- NPCs keep theirs, though TF2 names its own alike.
local gsub, ipairs, lower, match, sub = string.gsub, ipairs, string.lower, string.match, string.sub
module(...)

SURFACES = "scripts/game_sounds_physics.txt"
DOOR_PREFIXES = { "DoorSound.", "RotDoorSound." }

-- Whether TF2's entry name, from its script scriptPath, replaces GMod's.
function TF2Wins(name, scriptPath)
	if scriptPath == SURFACES then return true end
	for _, prefix in ipairs(DOOR_PREFIXES) do
		if sub(name, 1, #prefix) == prefix then return true end
	end
	return false
end

local MARKS = "^([%)%^%*%#%@%<%>%!%?%$%%&%(%~%+%{%}]*)(.*)$"

-- A sound's file under sound/: its path past the sound characters.
function File(path)
	local _, file = match(path, MARKS)
	return file
end

-- Where a TF2 sound's own copy of a file HL2 hides goes (GMod searches HL2's
-- content first), under sound/ or materials/: ws/cl_tf_content.lua puts it there.
RELOCATED = "sandcastle/tf/"

-- The path to play for TF2's sound path: its relocated copy when
-- hidden(file) says HL2 has a file there too, else path itself.
function Relocated(path, hidden)
	local mark, file = match(path, MARKS)
	if not hidden(file) then return path end
	return mark .. RELOCATED .. file
end

-- The path to play instead of path, or nil to keep it. exists(path): whether
-- a game file is there, path relative to the game's root ("sound/...").
function Replacement(path, exists)
	if lower(sub(path, -4)) ~= ".wav" then return nil end
	local mark, file = match(path, MARKS)
	if exists("sound/" .. file) then return nil end
	local mp3 = sub(file, 1, -5) .. ".mp3"
	if not exists("sound/" .. mp3) then return nil end
	return mark .. mp3
end

-- A sound file without its extension, lower-cased: TF2's .wav and the .mp3
-- that replaced it are one line.
local function Stem(path)
	return lower(gsub(File(path), "%.%w+$", ""))
end

-- The lines of scripts (soundscript names): each by its name and by each
-- of filesOf(name).
function Lines(scripts, filesOf)
	local lines = {}
	for _, name in ipairs(scripts) do
		lines[lower(name)] = true
		for _, file in ipairs(filesOf(name)) do lines[Stem(file)] = true end
	end
	return lines
end

-- Whether message, a soundscript's name or a file's path, is one of lines.
function Speaks(lines, message)
	return lines[lower(message)] == true or lines[Stem(message)] == true
end
