-- foundation.core.crc32: the standard CRC32.
local T = dofile("tests/harness.lua")
local Crc32 = T.require("foundation.core.crc32")

T.test("CRC32 is the standard one (zlib's, GMod's util.CRC)", function()
	T.eq(Crc32.Of("The quick brown fox jumps over the lazy dog"), 0x414FA339, "check value")
	T.eq(Crc32.Of(""), 0, "empty")
end)

T.finish()
