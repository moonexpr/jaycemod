-- foundation.math.matrix: dense matrices as rows of numbers.
local T = dofile("tests/harness.lua")
local Matrix = T.require("foundation.math.matrix")

local function Rows(m)
	local out = {}
	for i = 1, m:Rows() do
		local row = {}
		for j = 1, m:Cols() do row[j] = string.format("%g", m:Get(i, j)) end
		out[i] = table.concat(row, " ")
	end
	return table.concat(out, " | ")
end

T.test("a matrix from rows, its shape and elements", function()
	local m = Matrix.New({ { 1, 2, 3 }, { 4, 5, 6 } })
	T.eq(m:Rows(), 2, "rows")
	T.eq(m:Cols(), 3, "cols")
	T.eq(m:Get(2, 3), 6, "an element")
	T.eq(Rows(m:Transpose()), "1 4 | 2 5 | 3 6", "transposed")
end)

T.test("rows of different lengths are refused", function()
	T.eq(pcall(Matrix.New, { { 1, 2 }, { 3 } }), false, "ragged")
	T.eq(pcall(Matrix.New, {}), false, "empty")
end)

T.test("products, and a shape mismatch refused", function()
	local a = Matrix.New({ { 1, 2 }, { 3, 4 } })
	local b = Matrix.New({ { 5, 6 }, { 7, 8 } })
	T.eq(Rows(a:Multiply(b)), "19 22 | 43 50", "a b")
	T.eq(Rows(Matrix.Identity(2):Multiply(a)), Rows(a), "identity")
	T.eq(pcall(a.Multiply, a, Matrix.New({ { 1, 2, 3 } })), false, "2x2 by 1x3")
end)

T.test("the determinant", function()
	T.eq(Matrix.New({ { 1, 2 }, { 3, 4 } }):Determinant(), -2, "2x2")
	T.near(Matrix.New({ { 2, 0, 1 }, { 1, 3, 2 }, { 1, 1, 2 } }):Determinant(), 6, 1e-12, "3x3")
	T.eq(Matrix.New({ { 1, 2 }, { 2, 4 } }):Determinant(), 0, "singular")
	T.eq(Matrix.New({ { 0, 1 }, { 1, 0 } }):Determinant(), -1, "needs a row swap")
end)

T.test("the inverse, and none for a singular matrix", function()
	local a = Matrix.New({ { 4, 7 }, { 2, 6 } })
	local product = a:Multiply(a:Inverse())
	T.near(product:Get(1, 1), 1, 1e-12, "1,1")
	T.near(product:Get(1, 2), 0, 1e-12, "1,2")
	T.near(product:Get(2, 1), 0, 1e-12, "2,1")
	T.near(product:Get(2, 2), 1, 1e-12, "2,2")
	T.eq(Matrix.New({ { 1, 2 }, { 2, 4 } }):Inverse(), nil, "singular")
end)

T.test("solving a linear system", function()
	-- 2x + y = 5, x - y = 1 -> x = 2, y = 1
	local x = Matrix.New({ { 2, 1 }, { 1, -1 } }):Solve({ 5, 1 })
	T.near(x[1], 2, 1e-12, "x")
	T.near(x[2], 1, 1e-12, "y")
end)

T.finish()
