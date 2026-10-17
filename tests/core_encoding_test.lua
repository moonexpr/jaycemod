-- foundation.core.encoding: values as the bytes files and the wire carry.
local T = dofile("tests/harness.lua")
local Encoding = T.require("foundation.core.encoding")

local function Bytes(s)
	local out = {}
	for i = 1, #s do out[i] = string.byte(s, i) end
	return table.concat(out, " ")
end

T.test("integers are written low byte first", function()
	T.eq(Bytes(Encoding.Int32(0x01020304)), "4 3 2 1", "int32")
	T.eq(Bytes(Encoding.Int32(-1)), "255 255 255 255", "negative int32")
	T.eq(Bytes(Encoding.Int16(0x0102)), "2 1", "int16")
	T.eq(Bytes(Encoding.Int16(-2)), "254 255", "negative int16")
	T.eq(Bytes(Encoding.Byte(200)), "200", "byte")
end)

T.test("singles are IEEE 754", function()
	T.eq(Bytes(Encoding.Float32(1)), "0 0 128 63", "1.0")
	T.eq(Bytes(Encoding.Float32(-2)), "0 0 0 192", "-2.0")
	T.eq(Bytes(Encoding.Float32(0)), "0 0 0 0", "0")
end)

T.test("code points as UTF-8, one to four bytes", function()
	T.eq(Bytes(Encoding.Utf8(0x41)), "65", "ASCII")
	T.eq(Bytes(Encoding.Utf8(0xE9)), "195 169", "two bytes")
	T.eq(Bytes(Encoding.Utf8(0x20AC)), "226 130 172", "three")
	T.eq(Bytes(Encoding.Utf8(0x1F600)), "240 159 152 128", "four")
end)

T.test("CRC32 is the standard one (zlib's, GMod's util.CRC)", function()
	T.eq(Encoding.Crc32("The quick brown fox jumps over the lazy dog"), 0x414FA339, "check value")
	T.eq(Encoding.Crc32(""), 0, "empty")
end)

T.finish()
