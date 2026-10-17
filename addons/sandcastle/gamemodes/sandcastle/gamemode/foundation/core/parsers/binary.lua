-- Little-endian binary read back (foundation.core.encoding writes it):
-- Reader(data) -> r: r:Byte(), r:Int16(), r:UInt16(), r:Int32(), r:Float32()
-- read the next value; r:Consumed() is how many bytes it has read.
local byte, floor, huge, ldexp, setmetatable = string.byte, math.floor, math.huge, math.ldexp, setmetatable
module(...)

local TWO_15, TWO_16, TWO_31, TWO_32 = 32768, 65536, 2147483648, 4294967296
local MANTISSA_BITS_VALUE = 8388608 -- 2^23
local EXPONENT_MAX = 255

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
