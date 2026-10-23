-- foundation.encoding.keyvalues: Valve's KeyValues text, read pair by pair.
local T = dofile("tests/harness.lua")
local KeyValues = encoding.keyvalues

local function Pairs(text)
	local out = {}
	KeyValues.Read(text, function(path, key, value)
		out[#out + 1] = table.concat(path, "/") .. ":" .. key .. "=" .. value
	end)
	return table.concat(out, " | ")
end

T.test("each pair comes with the keys of the blocks it is in, as written", function()
	local text = '"lang" { "Language" "English" "Tokens" { "Cap_1" "Checkpoint 1" } }'
	T.eq(Pairs(text), "lang:Language=English | lang/Tokens:Cap_1=Checkpoint 1", "nested")
end)

T.test("a block with no key before it has an empty key", function()
	T.eq(Pairs('{ "a" "b" }'), ":a=b", "unnamed")
end)

T.test("bare words, comments and blank space", function()
	local text = "// a comment\nroot\n{\n\tkey value // trailing\n\t\"q\" \"v\"\n}\n"
	T.eq(Pairs(text), "root:key=value | root:q=v", "read alike")
end)

T.test("quoted strings take the escapes and may span lines", function()
	T.eq(Pairs('{ "k" "a\\nb\\t\\"c\\"\\\\" }'), ':k=a\nb\t"c"\\', "escapes")
	T.eq(Pairs('{ "k" "two\nlines" }'), ":k=two\nlines", "spanning lines")
	T.eq(Pairs('{ "k" "\\q" }'), ":k=q", "an unknown escape is its character")
end)

T.test("an unterminated string runs to the end", function()
	T.eq(Pairs('"k" "open'), ":k=open", "to the end")
end)

T.finish()
