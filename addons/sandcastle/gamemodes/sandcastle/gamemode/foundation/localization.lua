-- TF2's localization: the text of "#Token" strings (map point names, HUD
-- goals, capture reasons, boss lines) from TF2's own language files,
-- tf/resource/tf_<language>.txt, which the mounted TF2 provides. A file is
-- UTF-16LE KeyValues:
--
--   "lang" { "Language" "English" "Tokens" { "Badwater_cap_1" "Checkpoint 1" ... } }
--
-- with `//` comments, the escapes \n, \t, \" and \\, and values that may
-- span lines. Parse reads one into a table, token name (lower case) to its
-- UTF-8 text; Lookup finds a token in the player's language, then in
-- English. FileFor maps GMod's language (gmod_language) to TF2's file.
local KeyValues = require("foundation.core.parsers.keyvalues")
local Utf16 = require("foundation.core.parsers.utf16")
local lower, sub = string.lower, string.sub
module(...)

ENGLISH_FILE = "resource/tf_english.txt"

-- GMod's language codes to the names of the language files TF2 ships; a
-- language without a file reads English.
local FILE_LANGUAGE = {
	["bg"] = "bulgarian",
	["cs"] = "czech",
	["da"] = "danish",
	["de"] = "german",
	["el"] = "greek",
	["en"] = "english",
	["en-pt"] = "pirate",
	["es-es"] = "spanish",
	["fi"] = "finnish",
	["fr"] = "french",
	["hu"] = "hungarian",
	["it"] = "italian",
	["ja"] = "japanese",
	["ko"] = "koreana",
	["nl"] = "dutch",
	["no"] = "norwegian",
	["pl"] = "polish",
	["pt-br"] = "brazilian",
	["pt-pt"] = "portuguese",
	["ru"] = "russian",
	["sv-se"] = "swedish",
	["th"] = "thai",
	["tr"] = "turkish",
	["uk"] = "ukrainian",
	["zh-cn"] = "schinese",
	["zh-tw"] = "tchinese",
}

function FileFor(code)
	local name = FILE_LANGUAGE[lower(code)]
	return name and ("resource/tf_" .. name .. ".txt") or ENGLISH_FILE
end

-- The tables for a language: { code, own, ownNames, english, englishNames },
-- the player's own tokens over English's. read(path) returns a file's tokens
-- and names, as Parse does. English never changes, so it comes from the
-- previous tables when there are some, and a change of language reads only
-- the new language's file.
function Tables(code, read, previous)
	local english, englishNames
	if previous then
		english, englishNames = previous.english, previous.englishNames
	else
		english, englishNames = read(ENGLISH_FILE)
	end
	local own, ownNames = english, englishNames
	if FileFor(code) ~= ENGLISH_FILE then own, ownNames = read(FileFor(code)) end
	return {
		code = code,
		own = own,
		ownNames = ownNames,
		english = english,
		englishNames = englishNames,
	}
end

local TOKENS_BLOCK = "tokens"

-- A language file's tokens, lower-case name to UTF-8 text, and each
-- token's name as TF2 writes it (lower-case name to it), for language.Add.
function Parse(raw)
	local text = Utf16.Decode(raw):gsub("\r\n", "\n")
	local tokens, names = {}, {}
	KeyValues.Read(text, function(path, key, value)
		if lower(path[#path] or "") == TOKENS_BLOCK then
			local name = lower(key)
			tokens[name], names[name] = value, key
		end
	end)
	return tokens, names
end

-- The text of a "#Token" in the first table that has it (the player's
-- language, then English), matched whatever its case; text without a
-- leading "#" is itself; an unknown token is nil.
function Lookup(token, ...)
	if sub(token, 1, 1) ~= "#" then return token end
	local name = lower(sub(token, 2))
	local tables = { ... }
	for t = 1, #tables do
		local text = tables[t][name]
		if text then return text end
	end
	return nil
end
