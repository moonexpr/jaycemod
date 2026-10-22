-- foundation.core.math.scalar: arithmetic on single numbers.
local T = dofile("tests/harness.lua")
local Scalar = T.require("foundation.core.math.scalar")

T.test("Clamp holds a value within [low, high]", function()
	T.eq(Scalar.Clamp(5, 0, 10), 5, "inside: as it is")
	T.eq(Scalar.Clamp(-3, 0, 10), 0, "below: low")
	T.eq(Scalar.Clamp(12, 0, 10), 10, "above: high")
	T.eq(Scalar.Clamp(4, 4, 4), 4, "a single point")
end)

T.test("Clamp refuses a range whose low is above its high", function()
	T.eq(pcall(Scalar.Clamp, 1, 10, 0), false, "an empty range")
end)

T.finish()
