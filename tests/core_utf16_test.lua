-- foundation.core.utf16: UTF-16LE text as UTF-8.
local T = dofile("tests/harness.lua")
local Utf16 = T.require("foundation.core.utf16")

-- UTF-16LE bytes of the given code units.
local function Le(...)
	local out = {}
	for _, unit in ipairs({ ... }) do out[#out + 1] = string.char(unit % 256, math.floor(unit / 256)) end
	return table.concat(out)
end

T.test("ASCII decodes to itself, the byte-order mark dropped", function()
	T.eq(Utf16.Decode(Le(0xFEFF, 0x41, 0x62)), "Ab", "BOM gone")
	T.eq(Utf16.Decode(""), "", "empty")
end)

T.test("two- and three-byte UTF-8 for the basic plane", function()
	T.eq(Utf16.Decode(Le(0xE9)), "\195\169", "é")
	T.eq(Utf16.Decode(Le(0x20AC)), "\226\130\172", "€")
end)

T.test("a surrogate pair is one four-byte character", function()
	T.eq(Utf16.Decode(Le(0xD83D, 0xDE00)), "\240\159\152\128", "U+1F600")
end)

T.test("a trailing odd byte is ignored", function()
	T.eq(Utf16.Decode(Le(0x41) .. "x"), "A", "half a unit")
end)

T.finish()
