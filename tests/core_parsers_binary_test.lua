-- foundation.core.parsers.binary: little-endian values read back from what
-- foundation.core.encoding writes.
local T = dofile("tests/harness.lua")
local Encoding = T.require("foundation.core.encoding")
local BinaryParser = T.require("foundation.core.parsers.binary")

T.test("a reader reads back what was written, in order", function()
	local data = Encoding.Int32(-5) .. Encoding.Int16(-3) .. Encoding.Int16(65535) .. Encoding.Byte(7)
		.. Encoding.Float32(1.5) .. Encoding.Float32(-0.25) .. Encoding.Float32(2 ^ -140)
	local r = BinaryParser.Reader(data)
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
	local data = Encoding.Varint(0) .. Encoding.Varint(300) .. Encoding.Varint(2 ^ 40) .. Encoding.String("héllo") .. Encoding.String("")
	local r = BinaryParser.Reader(data)
	T.eq(r:Varint(), 0, "zero")
	T.eq(r:Varint(), 300, "300")
	T.eq(r:Varint(), 2 ^ 40, "past 32 bits")
	T.eq(r:String(), "héllo", "a string")
	T.eq(r:String(), "", "an empty one")
	T.eq(r:Consumed(), #data, "every byte")
end)

T.test("a subnormal that rounds up becomes the least normal single", function()
	local least = 2 ^ -126
	local r = BinaryParser.Reader(Encoding.Float32(least - 2 ^ -151))
	T.eq(r:Float32(), least, "carried into the exponent")
end)

T.test("a single rounds to the nearest representable value", function()
	local r = BinaryParser.Reader(Encoding.Float32(0.1))
	T.near(r:Float32(), 0.1, 1e-8, "0.1, nearly")
end)

T.finish()
