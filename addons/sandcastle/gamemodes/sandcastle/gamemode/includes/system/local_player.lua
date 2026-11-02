-- The local player's soundscapes: soundscript names (TF2's game_sounds
-- files, sound.Add) precached once, so a line plays the moment it is cued,
-- and played on the local player, where the script's own channel, level
-- and pitch hold (Entity:EmitSound): an announcer line on CHAN_VOICE2 cuts
-- off the one before rather than talking over it. Sound files (a path to
-- a .wav or .mp3) are not soundscapes and are played apart, at the level,
-- pitch and channel the caller gives (ws/sh_announcer.lua).
--
-- The engine is a port: Exists(name) -> whether a soundscript of that name
-- is loaded; Precache(name), its files; Emit(name), on the local player.
--
--   New(engine) -> a library:
--     library:Precache(name) -> name, or nil when no soundscript has it
--     library:Has(name) -> whether it is precached
--     library:Play(name): a soundscript the preload missed is precached as
--       it plays and counted late; a name no soundscript has is refused
--     library:Late() -> the names precached as they played, in order
-- Models and materials a feature brings are preloaded by the feature
-- loader's resource handlers (games.system.features, ws/sh_core.lua).
local error, ipairs, setmetatable, tostring = error, ipairs, setmetatable, tostring
module(...)

local Library = {}
Library.__index = Library

function New(engine)
	return setmetatable({ engine = engine, cached = {}, late = {} }, Library)
end

function Library:Precache(name)
	if self.cached[name] then return name end
	if not self.engine:Exists(name) then return nil end
	self.engine:Precache(name)
	self.cached[name] = true
	return name
end

function Library:Has(name)
	return self.cached[name] == true
end

function Library:Play(name)
	if not self.cached[name] then
		if self:Precache(name) == nil then error("no soundscript is named " .. tostring(name), 2) end
		self.late[#self.late + 1] = name
	end
	self.engine:Emit(name)
end

function Library:Late()
	local copy = {}
	for i, name in ipairs(self.late) do copy[i] = name end
	return copy
end
