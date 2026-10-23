-- ws.localization: TF2's language files (tf/resource/tf_<language>.txt,
-- UTF-16LE KeyValues) read once into a token table, the player's GMod
-- language mapped to TF2's file, and tokens looked up with English behind.
local T = dofile("tests/harness.lua")
local L = T.require("ws.localization")

local BOM = "\255\254"

-- UTF-8 text as the UTF-16LE bytes TF2's files hold (code points up to
-- U+10FFFF, as surrogate pairs above U+FFFF).
local function Utf16(text)
	local out = {}
	local i = 1
	while i <= #text do
		local c = text:byte(i)
		local code, len
		if c < 0x80 then code, len = c, 1
		elseif c < 0xE0 then code, len = (c % 0x20) * 0x40 + text:byte(i + 1) % 0x40, 2
		elseif c < 0xF0 then code, len = ((c % 0x10) * 0x40 + text:byte(i + 1) % 0x40) * 0x40 + text:byte(i + 2) % 0x40, 3
		else code, len = (((c % 0x08) * 0x40 + text:byte(i + 1) % 0x40) * 0x40 + text:byte(i + 2) % 0x40) * 0x40 + text:byte(i + 3) % 0x40, 4 end
		if code >= 0x10000 then
			local v = code - 0x10000
			local high, low = 0xD800 + math.floor(v / 0x400), 0xDC00 + v % 0x400
			out[#out + 1] = string.char(high % 0x100, math.floor(high / 0x100), low % 0x100, math.floor(low / 0x100))
		else
			out[#out + 1] = string.char(code % 0x100, math.floor(code / 0x100))
		end
		i = i + len
	end
	return table.concat(out)
end

local function File(lines)
	return BOM .. Utf16(table.concat(lines, "\r\n"))
end

local ENGLISH = File({
	'"lang"',
	"{",
	'"Language" "English"',
	'"Tokens"',
	"{",
	'// the HUD',
	'"Badwater_cap_1"\t\t"Checkpoint 1"',
	'"TF_Two_Lines"\t"First\\nSecond"',
	'"TF_Quoted"\t"Say \\"hi\\""',
	'"TF_Backslash"\t"a\\\\b"',
	'"TF_Spanning"\t"one',
	'two"',
	'"TF_Only_English"\t"English only"',
	"}",
	"}",
})

T.test("a language file's tokens, read from UTF-16LE, keyed by name whatever its case", function()
	local tokens = L.Parse(ENGLISH)
	T.eq(L.Lookup("#Badwater_cap_1", tokens), "Checkpoint 1", "with #")
	T.eq(L.Lookup("#BADWATER_CAP_1", tokens), "Checkpoint 1", "any case")
	T.eq(L.Lookup("#Language", tokens), nil, "the file's header is not a token")
	T.eq(L.Lookup("#TF_Missing", tokens), nil, "an unknown token")
	T.eq(L.Lookup("Plain text", tokens), "Plain text", "text without # is itself")
end)

T.test("each token keeps the name TF2 gives it, for GMod's language.Add", function()
	local _, names = L.Parse(ENGLISH)
	T.eq(names.badwater_cap_1, "Badwater_cap_1", "TF2's case")
	T.eq(names.tf_two_lines, "TF_Two_Lines", "another")
	T.eq(names.language, nil, "not the header")
end)

T.test("escapes and values spanning lines read as TF2 shows them", function()
	local tokens = L.Parse(ENGLISH)
	T.eq(L.Lookup("#TF_Two_Lines", tokens), "First\nSecond", "\\n")
	T.eq(L.Lookup("#TF_Quoted", tokens), 'Say "hi"', '\\"')
	T.eq(L.Lookup("#TF_Backslash", tokens), "a\\b", "\\\\")
	T.eq(L.Lookup("#TF_Spanning", tokens), "one\ntwo", "a value over two lines keeps its line break")
end)

T.test("characters beyond ASCII become UTF-8, surrogate pairs included", function()
	local tokens = L.Parse(File({ '"lang"', "{", '"Tokens"', "{", '"TF_Zh"\t"检查点"', '"TF_Face"\t"😀"', "}", "}" }))
	T.eq(L.Lookup("#TF_Zh", tokens), "检查点", "Chinese")
	T.eq(L.Lookup("#TF_Face", tokens), "😀", "beyond the BMP")
end)

T.test("a translation's [english] shadow line never stands for the token itself", function()
	local tokens = L.Parse(File({
		'"lang"',
		"{",
		'"Tokens"',
		"{",
		'"[english]Goldrush_blue_setup_goal"\t"Move the cart!"',
		'"Goldrush_blue_setup_goal"\t"Poussez le chariot !"',
		"}",
		"}",
	}))
	T.eq(L.Lookup("#Goldrush_blue_setup_goal", tokens), "Poussez le chariot !", "the translation")
end)

T.test("a token the player's language lacks falls back to English", function()
	local french = L.Parse(File({ '"lang"', "{", '"Tokens"', "{", '"Badwater_cap_1"\t"Point de contrôle 1"', "}", "}" }))
	local english = L.Parse(ENGLISH)
	T.eq(L.Lookup("#Badwater_cap_1", french, english), "Point de contrôle 1", "French first")
	T.eq(L.Lookup("#TF_Only_English", french, english), "English only", "then English")
end)

T.test("GMod's language codes pick TF2's file, English for those TF2 lacks", function()
	T.eq(L.FileFor("fr"), "resource/tf_french.txt", "French")
	T.eq(L.FileFor("zh-CN"), "resource/tf_schinese.txt", "any case")
	T.eq(L.FileFor("zh-tw"), "resource/tf_tchinese.txt", "traditional Chinese")
	T.eq(L.FileFor("pt-br"), "resource/tf_brazilian.txt", "Brazilian Portuguese")
	T.eq(L.FileFor("en-pt"), "resource/tf_pirate.txt", "GMod's pirate English is TF2's")
	T.eq(L.FileFor("ko"), "resource/tf_koreana.txt", "Korean")
	T.eq(L.FileFor("et"), L.ENGLISH_FILE, "Estonian: TF2 has none")
	T.eq(L.FileFor("en"), L.ENGLISH_FILE, "English")
end)

-- A reader that counts the files it was asked for, each with its own tokens.
local function CountingReader()
	local reads = {}
	local function Read(path)
		reads[path] = (reads[path] or 0) + 1
		return { path = path }, { path = path }
	end
	return Read, reads
end

T.test("a language's tables are its own file's tokens over English's", function()
	local Read = CountingReader()
	local french = L.Tables("fr", Read)
	T.eq(french.code, "fr", "the language")
	T.eq(french.own.path, "resource/tf_french.txt", "its own tokens")
	T.eq(french.ownNames.path, "resource/tf_french.txt", "its own names")
	T.eq(french.english.path, L.ENGLISH_FILE, "English behind")
	T.eq(french.englishNames.path, L.ENGLISH_FILE, "English names behind")
	local english = L.Tables("en", Read)
	T.eq(english.own, english.english, "English is its own")
end)

T.test("English is read once, however often the player changes language", function()
	local Read, reads = CountingReader()
	local tables = L.Tables("fr", Read)
	tables = L.Tables("de", Read, tables)
	tables = L.Tables("en", Read, tables)
	tables = L.Tables("fr", Read, tables)
	T.eq(reads[L.ENGLISH_FILE], 1, "English")
	T.eq(reads["resource/tf_german.txt"], 1, "German")
	T.eq(reads["resource/tf_french.txt"], 2, "French, each time it's chosen")
	T.eq(tables.own.path, "resource/tf_french.txt", "the language now")
end)

T.finish()
