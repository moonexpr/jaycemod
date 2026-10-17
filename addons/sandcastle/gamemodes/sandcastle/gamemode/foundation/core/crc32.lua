-- CRC32 (IEEE 802.3, as zlib and GMod's util.CRC compute it): Of(s) is the
-- checksum of string s, a whole number below 2^32.
local bit, byte = bit, string.byte
module(...)

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

function Of(s)
	local crc = bit.bnot(0)
	for i = 1, #s do
		crc = bit.bxor(bit.rshift(crc, 8), CRC_TABLE[bit.band(bit.bxor(crc, byte(s, i)), 0xFF)])
	end
	return bit.bnot(crc) % 2 ^ 32
end
