-- A binary heap of values keyed by numbers: the lowest key comes out
-- first, and of equal keys the one pushed first, so a search ordered by it
-- breaks ties the way NavAreaBuildPath does without a count of its own.
-- This is the Lua twin; a server with native/foundation has it replaced in
-- place by the native heap, which keeps this contract.
--   Heap() (New()) -> a heap
--   heap:Push(key, value)   key a number, value anything but nil
--   heap:Pop() -> value, key of the first, taken out; nil when empty
--   heap:Peek() -> value, key of the first, left in; nil when empty
--   heap:Size() (__len), heap:Clear() (and the push order starts again)
-- Entries live in three arrays by heap position (key, push number,
-- value), so a push allocates no table.
local setmetatable = setmetatable
module(...)

local Heap = {}
Heap.__index = Heap

function New()
	return setmetatable({ n = 0, pushed = 0, keys = {}, seqs = {}, values = {} }, Heap)
end

setmetatable(_M, { __call = function() return New() end })

function Heap:Size()
	return self.n
end
Heap.__len = Heap.Size

function Heap:Clear()
	self.n, self.pushed, self.keys, self.seqs, self.values = 0, 0, {}, {}, {}
end

function Heap:Push(key, value)
	local keys, seqs, values = self.keys, self.seqs, self.values
	local seq = self.pushed + 1
	self.pushed = seq
	local i = self.n + 1
	self.n = i
	while i > 1 do
		local parent = (i - i % 2) / 2
		local pk = keys[parent]
		if pk < key or (pk == key and seqs[parent] < seq) then break end
		keys[i], seqs[i], values[i] = pk, seqs[parent], values[parent]
		i = parent
	end
	keys[i], seqs[i], values[i] = key, seq, value
end

function Heap:Peek()
	if self.n == 0 then return nil end
	return self.values[1], self.keys[1]
end

function Heap:Pop()
	local n = self.n
	if n == 0 then return nil end
	local keys, seqs, values = self.keys, self.seqs, self.values
	local topValue, topKey = values[1], keys[1]
	local key, seq, value = keys[n], seqs[n], values[n]
	keys[n], seqs[n], values[n] = nil, nil, nil
	n = n - 1
	self.n = n
	if n > 0 then
		local i = 1
		while true do
			local child = i * 2
			if child > n then break end
			local ck, cs = keys[child], seqs[child]
			if child < n then
				local rk, rs = keys[child + 1], seqs[child + 1]
				if rk < ck or (rk == ck and rs < cs) then
					child, ck, cs = child + 1, rk, rs
				end
			end
			if key < ck or (key == ck and seq < cs) then break end
			keys[i], seqs[i], values[i] = ck, cs, values[child]
			i = child
		end
		keys[i], seqs[i], values[i] = key, seq, value
	end
	return topValue, topKey
end
