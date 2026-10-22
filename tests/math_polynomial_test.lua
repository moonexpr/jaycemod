-- foundation.math.polynomial: evaluation and real roots.
local T = dofile("tests/harness.lua")
local Polynomial = T.require("foundation.math.polynomial")

local EPS = 1e-9

local function Near(list, expected, what)
	T.eq(#list, #expected, what .. ": count")
	for i = 1, #expected do T.near(list[i], expected[i], 1e-7, what .. " " .. i) end
end

T.test("coefficients run from the constant up, and Horner evaluates them", function()
	-- 2 + 3x + x^2
	T.eq(Polynomial.Evaluate({ 2, 3, 1 }, 2), 12, "at 2")
	T.eq(Polynomial.Evaluate({ 7 }, 100), 7, "a constant")
end)

T.test("the derivative", function()
	local d = Polynomial.Derivative({ 2, 3, 1 })
	T.eq(table.concat(d, " "), "3 2", "3 + 2x")
	T.eq(#Polynomial.Derivative({ 5 }), 0, "of a constant: none")
end)

T.test("linear and quadratic roots, in order", function()
	Near(Polynomial.Roots({ -6, 2 }), { 3 }, "2x - 6")
	Near(Polynomial.Roots({ 6, -5, 1 }), { 2, 3 }, "(x-2)(x-3)")
	Near(Polynomial.Roots({ 4, -4, 1 }), { 2 }, "a double root, once")
	Near(Polynomial.Roots({ 1, 0, 1 }), {}, "x^2 + 1: none real")
end)

T.test("a quadratic's small root keeps its precision", function()
	-- roots 1e-8 and 1e8: the textbook formula loses the small one
	local roots = Polynomial.Roots({ 1, -(1e8 + 1e-8), 1 })
	T.near(roots[1] / 1e-8, 1, 1e-6, "the small root")
	T.near(roots[2] / 1e8, 1, 1e-12, "the large root")
end)

T.test("cubic roots: three real, one real, and repeated", function()
	Near(Polynomial.Roots({ -6, 11, -6, 1 }), { 1, 2, 3 }, "(x-1)(x-2)(x-3)")
	Near(Polynomial.Roots({ -1, 0, 0, 1 }), { 1 }, "x^3 - 1")
	Near(Polynomial.Roots({ -4, 8, -5, 1 }), { 1, 2 }, "(x-1)(x-2)^2")
	Near(Polynomial.Roots({ 0, 0, 0, 2 }), { 0 }, "2x^3")
end)

T.test("leading zero coefficients lower the degree", function()
	Near(Polynomial.Roots({ 6, -5, 1, 0 }), { 2, 3 }, "a quadratic written as a cubic")
	Near(Polynomial.Roots({ 5, 0 }), {}, "a nonzero constant has no roots")
end)

T.test("roots beyond a cubic are refused", function()
	T.eq(pcall(Polynomial.Roots, { 1, 0, 0, 0, 1 }), false, "quartic")
end)

T.finish()
