-- Arithmetic on single numbers.
--   Clamp(value, low, high) -> value held within [low, high]; a range whose
--   low is above its high is the caller's mistake
-- Core-rule exception: stays Lua. Clamp costs 1.6 ns JIT-compiled; a call
-- into native/foundation costs about 15 ns (20 on the dev server;
-- docs/native-foundation-plan.md), so a native twin could only be slower.
local error, tostring = error, tostring
module(...)

function Clamp(value, low, high)
	if low > high then error("an empty range: " .. tostring(low) .. " above " .. tostring(high), 2) end
	if value < low then return low end
	if value > high then return high end
	return value
end
