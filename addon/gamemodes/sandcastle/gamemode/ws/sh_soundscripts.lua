-- TF2's game sounds (Cart.RollStart, Regenerate.Touch, ControlPoint.CaptureWarn,
-- ...) are soundscript entries GMod never loads, so engine entities that name
-- them (func_tracktrain's StartSound, MoveSound, StopSound) play nothing.
-- Read TF2's soundscript manifest from the mounted tf content and register
-- every entry GMod does not already define. This runs before map entities
-- spawn, so they precache the sounds by name as they would in TF2.

local NAMED = {
	VOL_NORM = 1.0,
	PITCH_NORM = 100, PITCH_LOW = 95, PITCH_HIGH = 120,
	SNDLVL_NONE = 0, SNDLVL_IDLE = 60, SNDLVL_TALKING = 60, SNDLVL_STATIC = 66,
	SNDLVL_NORM = 75, SNDLVL_GUNFIRE = 140,
}

-- "95,105" is a random range; names are VOL_/PITCH_/SNDLVL_ constants;
-- SNDLVL_80dB carries its level in the name.
local function Number(text)
	text = string.Trim(text)
	if NAMED[text] then return NAMED[text] end
	local db = string.match(text, "^SNDLVL_(%d+)dB$")
	if db then return tonumber(db) end
	return tonumber(text)
end

local function Range(text)
	local lo, hi = string.match(text, "^%s*([^,]+),%s*([^,]+)%s*$")
	if lo then
		local a, b = Number(lo), Number(hi)
		if a and b then return { a, b } end
	end
	return Number(text)
end

local function Waves(value)
	if isstring(value) then return value end
	local waves = {}
	for _, kv in ipairs(value) do
		if string.lower(kv.Key) == "wave" and isstring(kv.Value) then waves[#waves + 1] = kv.Value end
	end
	return waves
end

-- One soundscript entry, as an ordered key/value list, into sound.Add's table.
local function Entry(name, fields)
	local entry = { name = name, channel = CHAN_AUTO, volume = 1.0, level = 75, pitch = 100 }
	for _, kv in ipairs(fields) do
		local key = string.lower(kv.Key)
		if key == "wave" or key == "rndwave" then
			entry.sound = Waves(kv.Value)
		elseif isstring(kv.Value) then
			if key == "channel" then
				entry.channel = _G[string.upper(kv.Value)] or CHAN_AUTO
			elseif key == "volume" then
				entry.volume = Range(kv.Value) or 1.0
			elseif key == "soundlevel" then
				entry.level = Number(kv.Value) or 75
			elseif key == "pitch" then
				entry.pitch = Range(kv.Value) or 100
			end
		end
	end
	if entry.sound == nil or (istable(entry.sound) and #entry.sound == 0) then return nil end
	return entry
end

-- TF2's scripts by path. Where TF2 is mounted as a game (a client, a listen
-- server) they are under "tf". A dedicated server mounts it through
-- mount.cfg under "GAME", where GMod's own files of the same names hide the
-- manifest and four of the scripts; those are read from the copy extracted
-- into data/ (EXTRACTED: .devtools/bin/server_root.py writes it from TF2's
-- tf2_misc_dir.vpk), the rest from "GAME".
local EXTRACTED = "sandcastle/tf_scripts/"

local function ReadTF(path)
	if file.Exists("scripts/game_sounds_manifest.txt", "tf") then return file.Read(path, "tf") end
	return file.Read(EXTRACTED .. path, "DATA") or file.Read(path, "GAME")
end

local function LoadFile(path)
	local text = ReadTF(path)
	if not text then return 0 end
	local root = util.KeyValuesToTablePreserveOrder('"soundscripts" {' .. text .. "}", false, true)
	local added = 0
	for _, kv in ipairs(root or {}) do
		if istable(kv.Value) and not sound.GetProperties(kv.Key) then
			local entry = Entry(kv.Key, kv.Value)
			if entry then
				sound.Add(entry)
				added = added + 1
			end
		end
	end
	return added
end

function WS.LoadSoundScripts()
	local manifest = ReadTF("scripts/game_sounds_manifest.txt")
	if not manifest then return 0 end
	local files = util.KeyValuesToTablePreserveOrder(manifest, false, true)
	local added = 0
	for _, kv in ipairs(files or {}) do
		local key = string.lower(kv.Key)
		if (key == "precache_file" or key == "preload_file") and isstring(kv.Value) then
			added = added + LoadFile(kv.Value)
		end
	end
	return added
end

WS.SoundScriptsAdded = WS.LoadSoundScripts()
