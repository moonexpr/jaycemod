-- The dev workbench's diff of two plain trees (captured states, scenarios):
--   Of(a, b[, tolerance[, ignore]]) -> { { path, a, b } }, sorted by path;
--     numbers within tolerance are equal; ignore lists paths left out, a *
--     segment matching any one key
--   Text(list) -> one "path: a -> b" line each
local abs = math.abs
local ipairs, pairs, tostring, type = ipairs, pairs, tostring, type
local concat, sort = table.concat, table.sort
module(...)

local WILDCARD = "*"

local function Segments(path)
	local list = {}
	for segment in path:gmatch("[^.]+") do list[#list + 1] = segment end
	return list
end

local function Ignored(ignore, keys)
	for _, segments in ipairs(ignore) do
		if #segments <= #keys then
			local match = true
			for i, segment in ipairs(segments) do
				if segment ~= WILDCARD and segment ~= tostring(keys[i]) then
					match = false
					break
				end
			end
			if match then return true end
		end
	end
	return false
end

local function Join(keys)
	local parts = {}
	for i, key in ipairs(keys) do parts[i] = tostring(key) end
	return concat(parts, ".")
end

local function Walk(a, b, keys, ctx)
	if Ignored(ctx.ignore, keys) then return end
	if type(a) == "table" and type(b) == "table" then
		local seen = {}
		for k in pairs(a) do seen[k] = true end
		for k in pairs(b) do seen[k] = true end
		for k in pairs(seen) do
			keys[#keys + 1] = k
			Walk(a[k], b[k], keys, ctx)
			keys[#keys] = nil
		end
		return
	end
	if type(a) == "number" and type(b) == "number" and abs(a - b) <= ctx.tolerance then return end
	if a ~= b then
		ctx.list[#ctx.list + 1] = {
			path = Join(keys),
			a = a,
			b = b,
		}
	end
end

function Of(a, b, tolerance, ignore)
	local parsed = {}
	for i, path in ipairs(ignore or {}) do parsed[i] = Segments(path) end
	local ctx = {
		tolerance = tolerance or 0,
		ignore = parsed,
		list = {},
	}
	Walk(a, b, {}, ctx)
	sort(ctx.list, function(x, y) return x.path < y.path end)
	return ctx.list
end

local function Show(value)
	if type(value) == "table" then return "{...}" end
	return tostring(value)
end

function Text(list)
	local lines = {}
	for i, d in ipairs(list) do lines[i] = d.path .. ": " .. Show(d.a) .. " -> " .. Show(d.b) end
	return concat(lines, "\n")
end
