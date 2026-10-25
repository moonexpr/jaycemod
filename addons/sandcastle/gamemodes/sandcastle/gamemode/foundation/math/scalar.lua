-- Arithmetic on single numbers.
--   Clamp(value, low, high) -> value held within [low, high]; a range whose
--   low is above its high is the caller's mistake
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
