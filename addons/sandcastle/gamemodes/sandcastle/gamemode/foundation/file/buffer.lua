-- Buffers: values as the bytes Source's files and GMod's wire carry them,
-- written and read back.
--
-- Writing. Each returns a string:
--   Byte(n), Int16(n), Int32(n): little-endian integers, written modulo their
--     width, so signed and unsigned alike
--   Float32(x): an IEEE 754 single, little-endian, rounded to nearest
--   Varint(n): a whole number n >= 0 as ULEB128, seven bits a byte, low
--     group first, the high bit set on every byte but the last
--   String(s): its length as a Varint, then its bytes
--   Utf8(code): a Unicode code point as UTF-8
--   Crc32(s): CRC32 (IEEE 802.3, as zlib and GMod's util.CRC compute it) of
--     string s, a whole number below 2^32
--   Writer() -> w: w:Byte, w:Int16, w:Int32, w:Float32, w:Varint, w:String
--     append in order; w:Bytes() is all of it, w:Size() its length
--
-- Reading. Reader(data) -> r: r:Byte(), r:Int16(), r:UInt16(), r:Int32(),
-- r:Float32(), r:Varint(), r:String() read the next value; r:Consumed() is
-- how many bytes it has read.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local bit, byte, char, floor, frexp, huge, ldexp = bit, string.byte, string.char, math.floor, math.frexp, math.huge, math.ldexp
local sub = string.sub
local concat, error, setmetatable, tostring, type = table.concat, error, setmetatable, tostring, type
module(...)

local TWO_15, TWO_16, TWO_31, TWO_32 = 32768, 65536, 2147483648, 4294967296
local MANTISSA_BITS_VALUE = 8388608 -- 2^23
local EXPONENT_BIAS, EXPONENT_MAX = 126, 255

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

-------------------------------------------------------------------------------
-- Reading

local ReaderClass = {}
ReaderClass.__index = ReaderClass

function Reader(data)
	return setmetatable({
		data = data,
		at = 1,
	}, ReaderClass)
end

function ReaderClass:Byte()
	local b = byte(self.data, self.at)
	self.at = self.at + 1
	return b
end

function ReaderClass:UInt16()
	local a, b = byte(self.data, self.at, self.at + 1)
	self.at = self.at + 2
	return a + b * 256
end

function ReaderClass:Int16()
	local n = self:UInt16()
	if n >= TWO_15 then n = n - TWO_16 end
	return n
end

function ReaderClass:Int32()
	local a, b, c, d = byte(self.data, self.at, self.at + 3)
	self.at = self.at + 4
	local n = a + b * 256 + c * 65536 + d * 16777216
	if n >= TWO_31 then n = n - TWO_32 end
	return n
end

function ReaderClass:Float32()
	local a, b, c, d = byte(self.data, self.at, self.at + 3)
	self.at = self.at + 4
	local sign = d >= 128 and -1 or 1
	local exponent = (d % 128) * 2 + floor(c / 128)
	local mantissa = (c % 128) * 65536 + b * 256 + a
	if exponent == 0 then
		if mantissa == 0 then return 0 end
		return sign * ldexp(mantissa, -149)
	end
	if exponent == EXPONENT_MAX then return sign * huge end
	return sign * ldexp(mantissa + MANTISSA_BITS_VALUE, exponent - 150)
end

function ReaderClass:Consumed()
	return self.at - 1
end

function ReaderClass:Varint()
	local n, scale = 0, 1
	repeat
		local b = self:Byte()
		n = n + (b % VARINT_GROUP) * scale
		scale = scale * VARINT_GROUP
	until b < VARINT_GROUP
	return n
end

function ReaderClass:String()
	local length = self:Varint()
	local s = sub(self.data, self.at, self.at + length - 1)
	self.at = self.at + length
	return s
end
