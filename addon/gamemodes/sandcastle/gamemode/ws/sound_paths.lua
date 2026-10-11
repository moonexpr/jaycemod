-- Sound paths TF2 has since changed: it turned its voice lines from .wav
-- into .mp3, so a map's ambient_generic naming vo/<line>.wav plays nothing
-- (pl_bloodwater has 18), and plays the .mp3 that replaced it instead (as
-- the TF2 Resource Mounting Fix addon does for vo/). A leading sound
-- character (")" spatial, "^" distance, ...) is kept.
local lower, match, sub = string.lower, string.match, string.sub
module(...)

-- The path to play instead of path, or nil to keep it. exists(path): whether
-- a game file is there, path relative to the game's root ("sound/...").
function Replacement(path, exists)
	if lower(sub(path, -4)) ~= ".wav" then return nil end
	local mark, file = match(path, "^([%)%^%*%#%@%<%>%!%?%$%%&%(%~%+%{%}]*)(.*)$")
	if exists("sound/" .. file) then return nil end
	local mp3 = sub(file, 1, -5) .. ".mp3"
	if not exists("sound/" .. mp3) then return nil end
	return mark .. mp3
end
