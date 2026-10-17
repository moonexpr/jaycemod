-- Little-endian binary, as Source's files store it: integers low byte first
-- and IEEE 754 single-precision floats.
--   Byte(n), Int16(n), Int32(n), Float32(x) -> the bytes, a string;
--     an integer is written modulo its width, so signed and unsigned alike
--   Reader(data) -> r: r:Byte(), r:Int16(), r:UInt16(), r:Int32(),
--     r:Float32() read the next value; r:Consumed() is how many bytes it has read
local byte, char, floor, frexp, huge, ldexp, setmetatable = string.byte, string.char, math.floor, math.frexp, math.huge, math.ldexp, setmetatable
module(...)

local TWO_16, TWO_31, TWO_32 = 65536, 2147483648, 4294967296
local TWO_15 = 32768
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
