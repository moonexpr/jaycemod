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
local byte, char, concat, floor, lower, sub = string.byte, string.char, table.concat, math.floor, string.lower, string.sub
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

-- UTF-16LE -----------------------------------------------------------------------

local BOM = 0xFEFF
local HIGH_SURROGATE, LOW_SURROGATE, SURROGATE_END = 0xD800, 0xDC00, 0xE000

local function Utf8(code)
	if code < 0x80 then return char(code) end
	if code < 0x800 then return char(0xC0 + floor(code / 0x40), 0x80 + code % 0x40) end
	if code < 0x10000 then
		return char(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return char(0xF0 + floor(code / 0x40000), 0x80 + floor(code / 0x1000) % 0x40,
		0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

-- The file's text as UTF-8, its byte-order mark dropped.
local function Decode(raw)
	local out, n = {}, 0
	local i = 1
	local length = #raw - 1
	while i <= length do
		local a, b = byte(raw, i, i + 1)
		local unit = a + b * 0x100
		i = i + 2
		if unit >= HIGH_SURROGATE and unit < LOW_SURROGATE and i <= length then
			local c, d = byte(raw, i, i + 1)
			local low = c + d * 0x100
			unit = 0x10000 + (unit - HIGH_SURROGATE) * 0x400 + (low - LOW_SURROGATE)
			i = i + 2
		end
		if unit ~= BOM then
			n = n + 1
			out[n] = unit < 0x80 and char(unit) or Utf8(unit)
		end
	end
	return concat(out)
end

-- KeyValues ------------------------------------------------------------------------

local ESCAPES = {
	n = "\n",
	t = "\t",
	['"'] = '"',
	["\\"] = "\\",
}

local QUOTE, BACKSLASH, SLASH, OPEN, CLOSE = 34, 92, 47, 123, 125

-- The next item from position i: "{", "}", or a string (quoted, with its
-- escapes, or bare); nil at the end. Returns the item and the position after.
local function NextItem(text, i)
	local length = #text
	while i <= length do
		local c = byte(text, i)
		if c == SLASH and byte(text, i + 1) == SLASH then
			while i <= length and byte(text, i) ~= 10 do i = i + 1 end
		elseif c <= 32 then
			i = i + 1
		else
			break
		end
	end
	if i > length then return nil, i end
	local c = byte(text, i)
	if c == OPEN then return "{", i + 1 end
	if c == CLOSE then return "}", i + 1 end
	if c == QUOTE then
		local parts, start = {}, i + 1
		i = start
		while i <= length do
			local d = byte(text, i)
			if d == QUOTE then
				parts[#parts + 1] = sub(text, start, i - 1)
				return concat(parts), i + 1
			end
			if d == BACKSLASH then
				parts[#parts + 1] = sub(text, start, i - 1)
				local e = sub(text, i + 1, i + 1)
				parts[#parts + 1] = ESCAPES[e] or e
				i = i + 2
				start = i
			else
				i = i + 1
			end
		end
		parts[#parts + 1] = sub(text, start)
		return concat(parts), i
	end
	local start = i
	while i <= length do
		local d = byte(text, i)
		if d <= 32 or d == QUOTE or d == OPEN or d == CLOSE then break end
		i = i + 1
	end
	return sub(text, start, i - 1), i
end

local TOKENS_BLOCK = "tokens"

-- A language file's tokens, lower-case name to UTF-8 text, and each
-- token's name as TF2 writes it (lower-case name to it), for language.Add.
function Parse(raw)
	local text = Decode(raw):gsub("\r\n", "\n")
	local tokens, names = {}, {}
	local blocks = {}
	local key
	local item, i = NextItem(text, 1)
	while item do
		if item == "{" then
			blocks[#blocks + 1] = key and lower(key) or ""
			key = nil
		elseif item == "}" then
			blocks[#blocks] = nil
			key = nil
		elseif key == nil then
			key = item
		else
			if blocks[#blocks] == TOKENS_BLOCK then
				local name = lower(key)
				tokens[name], names[name] = item, key
			end
			key = nil
		end
		item, i = NextItem(text, i)
	end
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
