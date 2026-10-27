-- foundation.math.scalar: arithmetic on single numbers.
local T = dofile("tests/harness.lua")
local Scalar = math.scalar

T.test("Clamp holds a value within [low, high]", function()
	T.eq(Scalar.Clamp(5, 0, 10), 5, "inside: as it is")
	T.eq(Scalar.Clamp(-3, 0, 10), 0, "below: low")
	T.eq(Scalar.Clamp(12, 0, 10), 10, "above: high")
	T.eq(Scalar.Clamp(4, 4, 4), 4, "a single point")
end)

T.test("Clamp refuses a range whose low is above its high", function()
	T.eq(pcall(Scalar.Clamp, 1, 10, 0), false, "an empty range")
end)

T.test("Lerp walks from a to b and does not hold t within [0, 1]", function()
	T.eq(Scalar.Lerp(10, 20, 0), 10, "t of 0: a")
	T.eq(Scalar.Lerp(10, 20, 1), 20, "t of 1: b")
	T.eq(Scalar.Lerp(10, 20, 0.25), 12.5, "between")
	T.eq(Scalar.Lerp(20, 10, 0.25), 17.5, "downward")
	T.eq(Scalar.Lerp(10, 20, 2), 30, "past b")
	T.eq(Scalar.Lerp(10, 20, -1), 0, "before a")
end)

T.test("Saturate holds a value within [0, 1]", function()
	T.eq(Scalar.Saturate(0.4), 0.4, "inside")
	T.eq(Scalar.Saturate(-2), 0, "below")
	T.eq(Scalar.Saturate(7), 1, "above")
end)

T.test("InverseLerp is how far value is from a to b, held to [0, 1]", function()
	T.eq(Scalar.InverseLerp(10, 20, 15), 0.5, "halfway")
	T.eq(Scalar.InverseLerp(10, 20, 10), 0, "at a")
	T.eq(Scalar.InverseLerp(10, 20, 5), 0, "before a")
	T.eq(Scalar.InverseLerp(10, 20, 99), 1, "past b")
	T.eq(Scalar.InverseLerp(20, 10, 15), 0.5, "a span read downward")
	T.eq(Scalar.InverseLerp(20, 10, 25), 0, "downward, before a")
end)

T.test("InverseLerp refuses a span with no length", function()
	T.eq(pcall(Scalar.InverseLerp, 3, 3, 3), false, "a equal to b")
end)

T.test("Remap carries value from the span a..b to the span c..d, held to its ends", function()
	T.eq(Scalar.Remap(5, 0, 10, 100, 200), 150, "halfway")
	T.eq(Scalar.Remap(-5, 0, 10, 100, 200), 100, "before a: c")
	T.eq(Scalar.Remap(50, 0, 10, 100, 200), 200, "past b: d")
	T.eq(Scalar.Remap(2.5, 0, 10, 200, 100), 175, "a falling target span")
	T.eq(pcall(Scalar.Remap, 1, 4, 4, 0, 1), false, "an empty source span")
end)

T.finish()
