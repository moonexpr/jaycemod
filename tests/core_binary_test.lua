-- foundation.core.binary: little-endian integers and IEEE 754 singles,
-- written to strings and read back.
local T = dofile("tests/harness.lua")
local Binary = T.require("foundation.core.binary")

local function Bytes(s)
	local out = {}
	for i = 1, #s do out[i] = string.byte(s, i) end
	return table.concat(out, " ")
end

T.test("integers are written low byte first", function()
	T.eq(Bytes(Binary.Int32(0x01020304)), "4 3 2 1", "int32")
	T.eq(Bytes(Binary.Int32(-1)), "255 255 255 255", "negative int32")
	T.eq(Bytes(Binary.Int16(0x0102)), "2 1", "int16")
	T.eq(Bytes(Binary.Int16(-2)), "254 255", "negative int16")
	T.eq(Bytes(Binary.Byte(200)), "200", "byte")
end)

T.test("singles are IEEE 754", function()
	T.eq(Bytes(Binary.Float32(1)), "0 0 128 63", "1.0")
	T.eq(Bytes(Binary.Float32(-2)), "0 0 0 192", "-2.0")
	T.eq(Bytes(Binary.Float32(0)), "0 0 0 0", "0")
end)

T.test("a reader reads back what was written, in order", function()
	local data = Binary.Int32(-5) .. Binary.Int16(-3) .. Binary.Int16(65535) .. Binary.Byte(7)
		.. Binary.Float32(1.5) .. Binary.Float32(-0.25) .. Binary.Float32(2 ^ -140)
	local r = Binary.Reader(data)
	T.eq(r:Int32(), -5, "int32")
	T.eq(r:Int16(), -3, "signed int16")
	T.eq(r:UInt16(), 65535, "unsigned int16")
	T.eq(r:Byte(), 7, "byte")
	T.eq(r:Float32(), 1.5, "float")
	T.eq(r:Float32(), -0.25, "negative float")
	T.eq(r:Float32(), 2 ^ -140, "a subnormal float")
	T.eq(r:Consumed(), #data, "every byte")
end)

T.test("a subnormal that rounds up becomes the least normal single", function()
	local least = 2 ^ -126
	local r = Binary.Reader(Binary.Float32(least - 2 ^ -151))
	T.eq(r:Float32(), least, "carried into the exponent")
end)

T.test("a single rounds to the nearest representable value", function()
	local r = Binary.Reader(Binary.Float32(0.1))
	T.near(r:Float32(), 0.1, 1e-8, "0.1, nearly")
end)

T.finish()
