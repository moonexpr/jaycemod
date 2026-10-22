-- Arithmetic on single numbers.
--   Clamp(value, low, high) -> value held within [low, high]; a range whose
--   low is above its high is the caller's mistake
local error, tostring = error, tostring
module(...)

function Clamp(value, low, high)
	if low > high then error("an empty range: " .. tostring(low) .. " above " .. tostring(high), 2) end
	if value < low then return low end
	if value > high then return high end
	return value
end
