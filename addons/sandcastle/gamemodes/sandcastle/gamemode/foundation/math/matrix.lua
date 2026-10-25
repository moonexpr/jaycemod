-- Dense matrices of numbers, kept as rows. Each operation returns a new one.
--   New(rows) refuses an empty or ragged list of rows; Identity(n)
--   m:Rows(), m:Cols(), m:Get(i, j), m:Transpose(), m:Multiply(b)
--   m:Determinant(), m:Inverse() -> nil when singular,
--   m:Solve(b) -> x with m x = b (b and x lists), nil when singular;
--   elimination pivots on the largest entry of each column
-- Core-rule exception: stays Lua. A 32x32 inverse costs 1.4 ms on the dev
-- server, but nothing in the game calls it on a hot path; a native matrix
-- waits for a caller.
local abs, error, ipairs, setmetatable, tostring, type = math.abs, error, ipairs, setmetatable, tostring, type
module(...)

-- A pivot this small counts as zero: the matrix is singular.
local SINGULAR = 1e-12

local Matrix = {}
Matrix.__index = Matrix

local function Make(rows, cols, at)
	local data = {}
	for i = 1, rows do
		local row = {}
		for j = 1, cols do row[j] = at(i, j) end
		data[i] = row
	end
	return setmetatable({
		data = data,
		rows = rows,
		cols = cols,
	}, Matrix)
end

function New(rows)
	if type(rows) ~= "table" or #rows == 0 then error("a matrix needs at least one row", 2) end
	local cols = #rows[1]
	for i, row in ipairs(rows) do
		if #row ~= cols or cols == 0 then error("matrix row " .. i .. " has " .. #row .. " entries, not " .. cols, 2) end
	end
	return Make(#rows, cols, function(i, j) return rows[i][j] end)
end

function Identity(n)
	return Make(n, n, function(i, j) return i == j and 1 or 0 end)
end

function Matrix:Rows() return self.rows end
function Matrix:Cols() return self.cols end
function Matrix:Get(i, j) return self.data[i][j] end

function Matrix:Transpose()
	local data = self.data
	return Make(self.cols, self.rows, function(i, j) return data[j][i] end)
end

function Matrix:Multiply(b)
	if self.cols ~= b.rows then
		error("cannot multiply " .. self.rows .. "x" .. self.cols .. " by " .. b.rows .. "x" .. b.cols, 2)
	end
	local a, bd, n = self.data, b.data, self.cols
	return Make(self.rows, b.cols, function(i, j)
		local sum = 0
		for k = 1, n do sum = sum + a[i][k] * bd[k][j] end
		return sum
	end)
end

local function CopyRows(data)
	local copy = {}
	for i, row in ipairs(data) do
		local r = {}
		for j, v in ipairs(row) do r[j] = v end
		copy[i] = r
	end
	return copy
end

local function Square(m, what)
	if m.rows ~= m.cols then error(what .. " needs a square matrix, not " .. m.rows .. "x" .. m.cols, 3) end
end

-- Gauss-Jordan on rows of the square part [a | extra]: reduces a to the
-- identity, carrying the extra columns along. Returns the determinant (0
-- when singular, the rows then left part-reduced).
local function Eliminate(a, n)
	local det = 1
	for col = 1, n do
		local pivot = col
		for r = col + 1, n do
			if abs(a[r][col]) > abs(a[pivot][col]) then pivot = r end
		end
		if abs(a[pivot][col]) < SINGULAR then return 0 end
		if pivot ~= col then
			a[pivot], a[col] = a[col], a[pivot]
			det = -det
		end
		local lead = a[col][col]
		det = det * lead
		local row = a[col]
		for j = col, #row do row[j] = row[j] / lead end
		for r = 1, n do
			if r ~= col and a[r][col] ~= 0 then
				local factor, other = a[r][col], a[r]
				for j = col, #row do other[j] = other[j] - factor * row[j] end
			end
		end
	end
	return det
end

function Matrix:Determinant()
	Square(self, "a determinant")
	return Eliminate(CopyRows(self.data), self.rows)
end

function Matrix:Inverse()
	Square(self, "an inverse")
	local n = self.rows
	local a = CopyRows(self.data)
	for i = 1, n do
		for j = 1, n do a[i][n + j] = i == j and 1 or 0 end
	end
	if Eliminate(a, n) == 0 then return nil end
	return Make(n, n, function(i, j) return a[i][n + j] end)
end

function Matrix:Solve(b)
	Square(self, "solving")
	local n = self.rows
	if #b ~= n then error("solving needs " .. n .. " right-hand values, not " .. tostring(#b), 2) end
	local a = CopyRows(self.data)
	for i = 1, n do a[i][n + 1] = b[i] end
	if Eliminate(a, n) == 0 then return nil end
	local x = {}
	for i = 1, n do x[i] = a[i][n + 1] end
	return x
end
