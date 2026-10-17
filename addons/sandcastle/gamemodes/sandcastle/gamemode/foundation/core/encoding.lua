-- Binary encodings: values as the bytes Source's files and GMod's wire
-- carry them. Each returns a string; foundation.core.parsers reads them back.
--   Byte(n), Int16(n), Int32(n): little-endian integers, written modulo their
--     width, so signed and unsigned alike
--   Float32(x): an IEEE 754 single, little-endian, rounded to nearest
--   Utf8(code): a Unicode code point as UTF-8
--   Crc32(s): CRC32 (IEEE 802.3, as zlib and GMod's util.CRC compute it) of
--     string s, a whole number below 2^32
--   Varint(n): a whole number n >= 0 as ULEB128, seven bits a byte, low
--     group first, the high bit set on every byte but the last
--   String(s): its length as a Varint, then its bytes
--   Writer() -> w: w:Byte, w:Int16, w:Int32, w:Float32, w:Varint, w:String
--     append in order; w:Bytes() is all of it, w:Size() its length
local bit, byte, char, floor, frexp, ldexp = bit, string.byte, string.char, math.floor, math.frexp, math.ldexp
local concat, error, setmetatable, tostring, type = table.concat, error, setmetatable, tostring, type
module(...)

local TWO_16, TWO_32 = 65536, 4294967296
local MANTISSA_BITS_VALUE = 8388608 -- 2^23
local EXPONENT_BIAS = 126

function Byte(n)
	return char(n)
end

function Int16(n)
	n = n % TWO_16
	return char(n % 256, floor(n / 256) % 256)
end

function Int32(n)
	n = n % TWO_32
	return char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

function Float32(x)
	if x == 0 then return char(0, 0, 0, 0) end
	local sign = 0
	if x < 0 then
		sign = 128
		x = -x
	end
	local mantissa, exponent = frexp(x) -- x = mantissa * 2^exponent, mantissa in [0.5, 1)
	exponent = exponent + EXPONENT_BIAS
	if exponent <= 0 then
		-- subnormal: the value is mantissa * 2^-149
		mantissa = floor(ldexp(mantissa, 23 + exponent) + 0.5)
		exponent = 0
	else
		mantissa = floor((mantissa * 2 - 1) * MANTISSA_BITS_VALUE + 0.5)
	end
	if mantissa == MANTISSA_BITS_VALUE then
		-- rounded up into the next power of two
		mantissa = 0
		exponent = exponent + 1
	end
	return char(mantissa % 256, floor(mantissa / 256) % 256,
		(exponent % 2) * 128 + floor(mantissa / 65536) % 128, sign + floor(exponent / 2))
end

function Utf8(code)
	if code < 0x80 then return char(code) end
	if code < 0x800 then return char(0xC0 + floor(code / 0x40), 0x80 + code % 0x40) end
	if code < 0x10000 then
		return char(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return char(0xF0 + floor(code / 0x40000), 0x80 + floor(code / 0x1000) % 0x40,
		0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local CRC_POLYNOMIAL = 0xEDB88320
local CRC_TABLE = {}
for i = 0, 255 do
	local c = i
	for _ = 1, 8 do
		if bit.band(c, 1) == 1 then
			c = bit.bxor(bit.rshift(c, 1), CRC_POLYNOMIAL)
		else
			c = bit.rshift(c, 1)
		end
	end
	CRC_TABLE[i] = c
end

function Crc32(s)
	local crc = bit.bnot(0)
	for i = 1, #s do
		crc = bit.bxor(bit.rshift(crc, 8), CRC_TABLE[bit.band(bit.bxor(crc, byte(s, i)), 0xFF)])
	end
	return bit.bnot(crc) % 2 ^ 32
end

local VARINT_GROUP = 128

function Varint(n)
	if type(n) ~= "number" or n < 0 or floor(n) ~= n then error("a varint is a whole number >= 0, not " .. tostring(n), 2) end
	local out = {}
	repeat
		local group = n % VARINT_GROUP
		n = floor(n / VARINT_GROUP)
		out[#out + 1] = char(n > 0 and group + VARINT_GROUP or group)
	until n == 0
	return concat(out)
end

function String(s)
	return Varint(#s) .. s
end

local WriterClass = {}
WriterClass.__index = WriterClass

function Writer()
	return setmetatable({
		parts = {},
		size = 0,
	}, WriterClass)
end

local function Append(w, bytes)
	w.parts[#w.parts + 1] = bytes
	w.size = w.size + #bytes
end

function WriterClass:Byte(n) Append(self, Byte(n)) end
function WriterClass:Int16(n) Append(self, Int16(n)) end
function WriterClass:Int32(n) Append(self, Int32(n)) end
function WriterClass:Float32(x) Append(self, Float32(x)) end
function WriterClass:Varint(n) Append(self, Varint(n)) end
function WriterClass:String(s) Append(self, String(s)) end
function WriterClass:Bytes() return concat(self.parts) end
function WriterClass:Size() return self.size end
