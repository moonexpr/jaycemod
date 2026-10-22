-- foundation.file.buffer: values as the bytes files and the wire carry,
-- written and read back.
local T = dofile("tests/harness.lua")
local Buffer = T.require("foundation.file.buffer")

local function Bytes(s)
	local out = {}
	for i = 1, #s do out[i] = string.byte(s, i) end
	return table.concat(out, " ")
end

T.test("integers are written low byte first", function()
	T.eq(Bytes(Buffer.Int32(0x01020304)), "4 3 2 1", "int32")
	T.eq(Bytes(Buffer.Int32(-1)), "255 255 255 255", "negative int32")
	T.eq(Bytes(Buffer.Int16(0x0102)), "2 1", "int16")
	T.eq(Bytes(Buffer.Int16(-2)), "254 255", "negative int16")
	T.eq(Bytes(Buffer.Byte(200)), "200", "byte")
end)

T.test("singles are IEEE 754", function()
	T.eq(Bytes(Buffer.Float32(1)), "0 0 128 63", "1.0")
	T.eq(Bytes(Buffer.Float32(-2)), "0 0 0 192", "-2.0")
	T.eq(Bytes(Buffer.Float32(0)), "0 0 0 0", "0")
end)

T.test("code points as UTF-8, one to four bytes", function()
	T.eq(Bytes(Buffer.Utf8(0x41)), "65", "ASCII")
	T.eq(Bytes(Buffer.Utf8(0xE9)), "195 169", "two bytes")
	T.eq(Bytes(Buffer.Utf8(0x20AC)), "226 130 172", "three")
	T.eq(Bytes(Buffer.Utf8(0x1F600)), "240 159 152 128", "four")
end)

T.test("varints are seven bits a byte, low group first, zero as one byte", function()
	T.eq(Bytes(Buffer.Varint(0)), "0", "zero")
	T.eq(Bytes(Buffer.Varint(127)), "127", "one byte")
	T.eq(Bytes(Buffer.Varint(128)), "128 1", "two bytes")
	T.eq(Bytes(Buffer.Varint(300)), "172 2", "300")
	T.eq(pcall(Buffer.Varint, -1), false, "a negative is refused")
	T.eq(pcall(Buffer.Varint, 1.5), false, "a fraction is refused")
end)

T.test("a string is its length as a varint, then its bytes", function()
	T.eq(Bytes(Buffer.String("hi")), "2 104 105", "hi")
	T.eq(Bytes(Buffer.String("")), "0", "empty")
end)

T.test("a writer gathers values in order", function()
	local w = Buffer.Writer()
	w:Byte(1)
	w:Int16(2)
	w:String("a")
	T.eq(Bytes(w:Bytes()), "1 2 0 1 97", "byte, int16, string")
	T.eq(w:Size(), 5, "five bytes")
end)

T.test("CRC32 is the standard one (zlib's, GMod's util.CRC)", function()
	T.eq(Buffer.Crc32("The quick brown fox jumps over the lazy dog"), 0x414FA339, "check value")
	T.eq(Buffer.Crc32(""), 0, "empty")
end)

-- Reading ------------------------------------------------------------------------

T.test("a reader reads back what was written, in order", function()
	local data = Buffer.Int32(-5) .. Buffer.Int16(-3) .. Buffer.Int16(65535) .. Buffer.Byte(7)
		.. Buffer.Float32(1.5) .. Buffer.Float32(-0.25) .. Buffer.Float32(2 ^ -140)
	local r = Buffer.Reader(data)
	T.eq(r:Int32(), -5, "int32")
	T.eq(r:Int16(), -3, "signed int16")
	T.eq(r:UInt16(), 65535, "unsigned int16")
	T.eq(r:Byte(), 7, "byte")
	T.eq(r:Float32(), 1.5, "float")
	T.eq(r:Float32(), -0.25, "negative float")
	T.eq(r:Float32(), 2 ^ -140, "a subnormal float")
	T.eq(r:Consumed(), #data, "every byte")
end)

T.test("varints and strings read back", function()
	local data = Buffer.Varint(0) .. Buffer.Varint(300) .. Buffer.Varint(2 ^ 40) .. Buffer.String("héllo") .. Buffer.String("")
	local r = Buffer.Reader(data)
	T.eq(r:Varint(), 0, "zero")
	T.eq(r:Varint(), 300, "300")
	T.eq(r:Varint(), 2 ^ 40, "past 32 bits")
	T.eq(r:String(), "héllo", "a string")
	T.eq(r:String(), "", "an empty one")
	T.eq(r:Consumed(), #data, "every byte")
end)

T.test("a subnormal that rounds up becomes the least normal single", function()
	local least = 2 ^ -126
	local r = Buffer.Reader(Buffer.Float32(least - 2 ^ -151))
	T.eq(r:Float32(), least, "carried into the exponent")
end)

T.test("a single rounds to the nearest representable value", function()
	local r = Buffer.Reader(Buffer.Float32(0.1))
	T.near(r:Float32(), 0.1, 1e-8, "0.1, nearly")
end)

T.finish()
