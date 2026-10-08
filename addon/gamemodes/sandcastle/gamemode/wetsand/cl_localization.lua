-- TF2's strings in GMod: WETSAND.Localize("#Badwater_cap_1") is the text TF2
-- shows for a token, in the player's GMod language (gmod_language), with
-- English behind it for tokens that language lacks. The text comes from the
-- mounted TF2's own language files (resource/tf_<language>.txt, under the
-- "tf" path), read by foundation.localization the first time a token is
-- needed, and again when the player changes language. Every token is also
-- handed to GMod's language.Add, so language.GetPhrase and VGUI labels that
-- say "#Badwater_cap_1" show it too. The server never localizes: it sends
-- tokens, and each client words them.
local L = WETSAND.require("foundation.localization")

local MOUNT = "tf" -- the mounted TF2's path id
local LANGUAGE_CONVAR = "gmod_language"

local loaded -- { code, own, english } for the language last read

-- A file's tokens, or empty ones when the mounted TF2 has no such file.
local function Read(path)
	local raw = file.Read(path, MOUNT)
	if not raw then return {}, {} end
	return L.Parse(raw)
end

-- English first, then the player's language over it.
local function Register(tokens, names)
	for name, text in pairs(tokens) do language.Add(names[name], text) end
end

local function Load()
	local code = GetConVar(LANGUAGE_CONVAR):GetString()
	if loaded and loaded.code == code then return loaded end
	local english, englishNames = Read(L.ENGLISH_FILE)
	local own, ownNames = english, englishNames
	if L.FileFor(code) ~= L.ENGLISH_FILE then own, ownNames = Read(L.FileFor(code)) end
	Register(english, englishNames)
	if own ~= english then Register(own, ownNames) end
	loaded = {
		code = code,
		own = own,
		english = english,
	}
	return loaded
end

-- The text of a "#Token", or nil when neither the player's language nor
-- English has it; text without a leading "#" is itself.
function WETSAND.Localize(token)
	local tables = Load()
	return L.Lookup(token, tables.own, tables.english)
end

cvars.AddChangeCallback(LANGUAGE_CONVAR, function()
	if loaded then Load() end
end, "wetsand_localization")
