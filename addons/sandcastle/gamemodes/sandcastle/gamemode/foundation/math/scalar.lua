-- Arithmetic on single numbers.
--   Clamp(value, low, high) -> value held within [low, high]; a range whose
--   low is above its high is the caller's mistake
--   Saturate(value) -> value held within [0, 1]
--   Lerp(a, b, t) -> a + (b - a) * t, with t not held to [0, 1]
--   InverseLerp(a, b, value) -> how far value is from a to b, held to [0, 1];
--     a equal to b is the caller's mistake
--   Remap(value, a, b, c, d) -> value carried from the span a..b to the span
--     c..d, held to the span's ends (Source's RemapValClamped)
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local error, tostring = error, tostring
module(...)

function Clamp(value, low, high)
	if low > high then error("an empty range: " .. tostring(low) .. " above " .. tostring(high), 2) end
	if value < low then return low end
	if value > high then return high end
	return value
end

function Saturate(value)
	if value < 0 then return 0 end
	if value > 1 then return 1 end
	return value
end

function Lerp(a, b, t)
	return a + (b - a) * t
end

function InverseLerp(a, b, value)
	if a == b then error("a span with no length: " .. tostring(a) .. " to " .. tostring(b), 2) end
	return Saturate((value - a) / (b - a))
end

function Remap(value, a, b, c, d)
	if a == b then error("a span with no length: " .. tostring(a) .. " to " .. tostring(b), 2) end
	return Lerp(c, d, Saturate((value - a) / (b - a)))
end
