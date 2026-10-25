-- UTF-16LE text, as Valve's resource files store it, decoded to UTF-8:
-- Decode(raw) drops the byte-order mark, joins surrogate pairs, and ignores
-- a trailing odd byte.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local Buffer = file.buffer
local byte, char, concat = string.byte, string.char, table.concat
module(...)

local BOM = 0xFEFF
local HIGH_SURROGATE, LOW_SURROGATE, SURROGATE_END = 0xD800, 0xDC00, 0xE000

-- The file's text as UTF-8, its byte-order mark dropped.
function Decode(raw)
	local out, n = {}, 0
	local i = 1
	local length = #raw - 1
	while i <= length do
		local a, b = byte(raw, i, i + 1)
		local unit = a + b * 0x100
		i = i + 2
		if unit >= HIGH_SURROGATE and unit < LOW_SURROGATE and i <= length then
			local c, d = byte(raw, i, i + 1)
			local low = c + d * 0x100
			unit = 0x10000 + (unit - HIGH_SURROGATE) * 0x400 + (low - LOW_SURROGATE)
			i = i + 2
		end
		if unit ~= BOM then
			n = n + 1
			out[n] = unit < 0x80 and char(unit) or Buffer.Utf8(unit)
		end
	end
	return concat(out)
end
