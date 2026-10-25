-- Polynomials as lists of coefficients from the constant up: { c0, c1, c2 }
-- is c0 + c1 x + c2 x^2.
--   Evaluate(c, x)   Horner's rule
--   Derivative(c)    the derivative's coefficients
--   Roots(c)         the real roots, ascending, each once, up to a cubic:
--                    the quadratic by the stable formula (no cancellation
--                    in the small root), the cubic by Cardano for one real
--                    root and by the trigonometric form for three
-- Core-rule exception: stays Lua. Evaluate costs 9.6 ns JIT-compiled, under
-- a call into native/foundation costs about 15 ns (20 on the dev server;
-- docs/native-foundation-plan.md); Roots (362 ns on the dev server) has no
-- hot caller in the game.
local abs, acos, cos, error, huge, max, pi, sort, sqrt = math.abs, math.acos, math.cos, error, math.huge, math.max, math.pi, table.sort, math.sqrt
local ipairs, tostring = ipairs, tostring
module(...)

-- Roots closer than this are one root; a discriminant within it is zero.
local EPSILON = 1e-12
local MAX_DEGREE = 3

function Evaluate(c, x)
	local sum = 0
	for i = #c, 1, -1 do sum = sum * x + c[i] end
	return sum
end

function Derivative(c)
	local d = {}
	for i = 2, #c do d[i - 1] = c[i] * (i - 1) end
	return d
end

local function Cbrt(x)
	if x < 0 then return -(-x) ^ (1 / 3) end
	return x ^ (1 / 3)
end

local function Quadratic(c0, c1, c2)
	local disc = c1 * c1 - 4 * c2 * c0
	if disc < 0 then return {} end
	if disc == 0 then return { -c1 / (2 * c2) } end
	local q = -0.5 * (c1 + (c1 < 0 and -1 or 1) * sqrt(disc))
	if q == 0 then return { 0 } end
	return { q / c2, c0 / q }
end

local function Cubic(c0, c1, c2, c3)
	local a, b, c = c2 / c3, c1 / c3, c0 / c3
	-- x = t - a/3 gives t^3 + p t + q = 0
	local p = b - a * a / 3
	local q = 2 * a * a * a / 27 - a * b / 3 + c
	local shift = a / 3
	local disc = (q / 2) ^ 2 + (p / 3) ^ 3
	local scale = max(1, abs(q) ^ 2, abs(p) ^ 3)
	if disc > EPSILON * scale then
		local root = sqrt(disc)
		return { Cbrt(-q / 2 + root) + Cbrt(-q / 2 - root) - shift }
	end
	if disc < -EPSILON * scale then
		local r = sqrt(-p / 3)
		local cosine = -q / (2 * r * r * r)
		if cosine > 1 then cosine = 1 elseif cosine < -1 then cosine = -1 end
		local phi = acos(cosine)
		local roots = {}
		for k = 0, 2 do roots[k + 1] = 2 * r * cos((phi + 2 * pi * k) / 3) - shift end
		return roots
	end
	if abs(p) <= EPSILON * scale then return { -shift } end
	return { 3 * q / p - shift, -3 * q / (2 * p) - shift }
end

function Roots(c)
	local degree = #c - 1
	while degree > 0 and c[degree + 1] == 0 do degree = degree - 1 end
	if degree > MAX_DEGREE then error("polynomial roots are solved up to cubics, not degree " .. tostring(degree), 2) end
	local roots
	if degree <= 0 then
		roots = {}
	elseif degree == 1 then
		roots = { -c[1] / c[2] }
	elseif degree == 2 then
		roots = Quadratic(c[1], c[2], c[3])
	else
		roots = Cubic(c[1], c[2], c[3], c[4])
	end
	sort(roots)
	local distinct, last = {}, -huge
	for _, root in ipairs(roots) do
		if root - last > EPSILON * max(1, abs(root)) then distinct[#distinct + 1] = root end
		last = root
	end
	return distinct
end
