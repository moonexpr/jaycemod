-- Estimated memory held by named roots: a walk over each root's tables
-- (keys, values and metatables), strings and functions, every object
-- counted once and credited to the first root that reaches it. The sizes
-- are LuaJIT 2.1's objects on 64-bit (GC64, as GMod's x86-64 build runs),
-- so the figures say what a module costs and how roots compare, not what
-- collectgarbage("count") will read to the byte. A function counts as its
-- closure; its upvalues and environment are not followed.
--
-- Measure(roots) with roots a list of { name, value } -> { rows = list of
--   { name, bytes } in roots' order, total }
-- Format(report, rows) -> lines: the total, then the `rows` largest roots
--   (equal sizes by name)
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local format, getinfo, getmetatable, ipairs, next, sort, type = string.format, debug.getinfo, getmetatable, ipairs, next, table.sort, type
module(...)

TABLE = 64       -- GCtab
ARRAY_SLOT = 8   -- TValue
HASH_NODE = 24   -- Node: value, key, next
STRING = 24      -- GCstr header; its bytes and terminator follow
FUNCTION = 40    -- GCfuncL
UPVALUE = 8      -- an upvalue reference in the closure

local BYTES_PER_KB = 1024

local function HashNodes(count)
	if count == 0 then return 0 end
	local nodes = 1
	while nodes < count do nodes = nodes * 2 end
	return nodes
end

-- The bytes of value not yet counted, marking what it counts.
local function Walk(value, seen)
	local kind = type(value)
	if (kind ~= "table" and kind ~= "string" and kind ~= "function") or seen[value] then return 0 end
	seen[value] = true
	if kind == "string" then return STRING + #value + 1 end
	if kind == "function" then return FUNCTION + UPVALUE * getinfo(value, "u").nups end
	local length, entries = #value, 0
	local bytes = 0
	for k, v in next, value do
		entries = entries + 1
		bytes = bytes + Walk(k, seen) + Walk(v, seen)
	end
	bytes = bytes + TABLE + length * ARRAY_SLOT + HashNodes(entries - length) * HASH_NODE
	return bytes + Walk(getmetatable(value), seen)
end

function Measure(roots)
	local seen, rows, total = {}, {}, 0
	for i, root in ipairs(roots) do
		local bytes = Walk(root[2], seen)
		rows[i] = {
			name = root[1],
			bytes = bytes,
		}
		total = total + bytes
	end
	return {
		rows = rows,
		total = total,
	}
end

function Format(report, rows)
	local sorted = {}
	for i, row in ipairs(report.rows) do sorted[i] = row end
	sort(sorted, function(a, b)
		if a.bytes ~= b.bytes then return a.bytes > b.bytes end
		return a.name < b.name
	end)
	local lines = { format("memory: %.1f KB estimated over %d roots", report.total / BYTES_PER_KB, #report.rows) }
	for i = 1, rows < #sorted and rows or #sorted do
		lines[#lines + 1] = format("%10.1f KB  %s", sorted[i].bytes / BYTES_PER_KB, sorted[i].name)
	end
	return lines
end
