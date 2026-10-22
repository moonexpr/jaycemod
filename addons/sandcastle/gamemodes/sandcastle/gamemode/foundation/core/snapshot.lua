-- A model's state as plain data, and back: what a save, a diff or a JSON
-- file can hold, taken from a live model and put back into one in place.
--
-- Spec(spec) parses a model's description once:
--   name      the root of every path an error names
--   skip      optional: fields neither taken nor touched (settings the
--             controller refreshes, a strategy chosen by the map)
--   times     optional: paths of absolute times ("dueAt", "waves.*" for
--             every value of waves), kept as seconds from the snapshot's now
--             and put back from the new now
--   machines  optional: fields holding a foundation.core.cfsm machine, kept
--             as its state and put back with Machine:Restore
-- Take(model, spec, now[, refs]) -> the snapshot: every other field of the
-- model, copied deep. Apply(model, snapshot, spec, now[, refs]) writes it
-- back, clearing the fields the snapshot lacks, so a model holds exactly
-- what was taken. Values and keys that are not plain data (a table with a
-- metatable, a function, userdata) go through refs:Encode(value, path) to
-- plain data and refs:Decode(data, path) back, nil when it no longer
-- resolves; without refs, or unresolved, they are refused with their path.
-- A weak table (a metatable of __mode alone) is data, its mode kept. Pairs
-- keyed by refs are sorted, so two snapshots of one state are equal. Apply
-- writes raw: a __newindex guard does not see the model's own fields.
-- Infinite numbers are kept as data a JSON encoder can write.
local error, getmetatable, ipairs, pairs, rawset, setmetatable, tostring, type = error, getmetatable, ipairs, pairs, rawset, setmetatable, tostring, type
local huge = math.huge
local sort = table.sort
module(...)

local REF, NUM, MAP, MODE = "$ref", "$num", "$map", "$mode"
local INFINITE, NEGATIVE_INFINITE = "inf", "-inf"
local WILDCARD = "*"

local function Refuse(path, why)
	error("snapshot: " .. path .. ": " .. why, 0)
end

local function Join(path, key)
	return path .. "." .. tostring(key)
end

local function Segments(path)
	local list = {}
	for segment in path:gmatch("[^.]+") do list[#list + 1] = segment end
	return list
end

local function Set(list, what, name)
	local set = {}
	for _, item in ipairs(list or {}) do
		if set[item] then Refuse(name, what .. " names " .. tostring(item) .. " twice") end
		set[item] = true
	end
	return set
end

function Spec(spec)
	if type(spec.name) ~= "string" or spec.name == "" then Refuse(tostring(spec.name), "a spec needs a name") end
	local parsed = {
		name = spec.name,
		skip = Set(spec.skip, "skip", spec.name),
		machines = Set(spec.machines, "machines", spec.name),
		times = {},
	}
	Set(spec.times, "times", spec.name)
	for i, path in ipairs(spec.times or {}) do parsed.times[i] = Segments(path) end
	return parsed
end

local function IsPlainKey(key)
	local kind = type(key)
	return kind == "string" or kind == "number" or kind == "boolean"
end

local Copy

local function Encode(value, path, refs)
	if not refs then Refuse(path, "holds " .. tostring(value) .. ", not plain data, and no refs were given") end
	return { [REF] = refs:Encode(value, path) }
end

-- Whether the key path from the model's root is one of the time paths.
local function IsTime(times, keys)
	for _, segments in ipairs(times) do
		if #segments == #keys then
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

-- Copies one level down: keys is the path so far, as the model's own keys.
local function Child(item, path, key, keys, ctx)
	keys[#keys + 1] = key
	local copy = Copy(item, Join(path, key), keys, ctx)
	keys[#keys] = nil
	return copy
end

-- A key of a $map pair as text to sort by: a ref by what refs encoded.
local function KeyText(data)
	if type(data) == "table" then return "r" .. tostring(data[REF]) end
	return type(data):sub(1, 1) .. tostring(data)
end

-- A weak table's metatable holds only its __mode: the table is still data.
local function WeakMode(value)
	local meta = getmetatable(value)
	if type(meta) ~= "table" or type(meta.__mode) ~= "string" then return nil end
	for key in pairs(meta) do
		if key ~= "__mode" then return nil end
	end
	return meta.__mode
end

local function CopyTable(value, path, keys, ctx)
	if ctx.open[value] then Refuse(path, "is a cycle") end
	ctx.open[value] = true
	local copy, plainKeys = {}, true
	for key in pairs(value) do
		if not IsPlainKey(key) then plainKeys = false end
		if type(key) == "string" and key:sub(1, 1) == "$" then Refuse(Join(path, key), "a key starting with $ is the snapshot's own") end
	end
	if plainKeys then
		for key, item in pairs(value) do copy[key] = Child(item, path, key, keys, ctx) end
	else
		local pairsList = {}
		for key, item in pairs(value) do
			local data = IsPlainKey(key) and key or Encode(key, Join(path, key), ctx.refs)
			pairsList[#pairsList + 1] = { data, Child(item, path, key, keys, ctx) }
		end
		-- pairs' order is the hash's: sorted by key, two snapshots of one state are equal
		sort(pairsList, function(a, b) return KeyText(a[1]) < KeyText(b[1]) end)
		copy = { [MAP] = pairsList }
	end
	copy[MODE] = WeakMode(value)
	ctx.open[value] = nil
	return copy
end

-- ctx = { refs, open (the tables being copied), times, delta (added to each time) }
function Copy(value, path, keys, ctx)
	local kind = type(value)
	if kind == "number" then
		if value == huge then return { [NUM] = INFINITE } end
		if value == -huge then return { [NUM] = NEGATIVE_INFINITE } end
		if IsTime(ctx.times, keys) then return value + ctx.delta end
		return value
	end
	if kind == "string" or kind == "boolean" or kind == "nil" then return value end
	if kind == "table" and (getmetatable(value) == nil or WeakMode(value)) then return CopyTable(value, path, keys, ctx) end
	return Encode(value, path, ctx.refs)
end

local Restore

local function Decode(data, path, refs)
	if not refs then Refuse(path, "holds a reference, and no refs were given") end
	local value = refs:Decode(data[REF], path)
	if value == nil then Refuse(path, "its reference no longer resolves") end
	return value
end

function Restore(data, path, refs)
	if type(data) ~= "table" then return data end
	if data[REF] ~= nil then return Decode(data, path, refs) end
	if data[NUM] == INFINITE then return huge end
	if data[NUM] == NEGATIVE_INFINITE then return -huge end
	local value = {}
	if data[MAP] ~= nil then
		for _, pair in ipairs(data[MAP]) do
			local key = type(pair[1]) == "table" and Decode(pair[1], path, refs) or pair[1]
			local keyPath = Join(path, key)
			value[key] = Restore(pair[2], keyPath, refs)
		end
	else
		for key, item in pairs(data) do
			if key ~= MODE then value[key] = Restore(item, Join(path, key), refs) end
		end
	end
	if data[MODE] ~= nil then setmetatable(value, { __mode = data[MODE] }) end
	return value
end

-- Calls shift(container, key) on every number a time path reaches.
local function EachTime(root, segments, shift)
	local function Walk(container, i)
		if type(container) ~= "table" then return end
		local segment = segments[i]
		local last = i == #segments
		local function Visit(key)
			if last then
				if type(container[key]) == "number" then shift(container, key) end
			else
				Walk(container[key], i + 1)
			end
		end
		if segment == WILDCARD then
			for key in pairs(container) do Visit(key) end
		else
			Visit(segment)
		end
	end
	Walk(root, 1)
end

local function Shift(snapshot, spec, delta)
	for _, segments in ipairs(spec.times) do
		EachTime(snapshot, segments, function(container, key)
			local value = container[key]
			if value ~= huge and value ~= -huge then container[key] = value + delta end
		end)
	end
end

function Take(model, spec, now, refs)
	local ctx = {
		refs = refs,
		open = {},
		times = spec.times,
		delta = -now,
	}
	local snapshot = {}
	for key, value in pairs(model) do
		if not spec.skip[key] then
			if spec.machines[key] then
				snapshot[key] = value:State()
			else
				snapshot[key] = Child(value, spec.name, key, {}, ctx)
			end
		end
	end
	return snapshot
end

function Apply(model, snapshot, spec, now, refs)
	local values = {}
	for key, data in pairs(snapshot) do
		if not spec.machines[key] then values[key] = Restore(data, Join(spec.name, key), refs) end
	end
	for key in pairs(spec.machines) do
		if snapshot[key] == nil then Refuse(Join(spec.name, key), "the snapshot has no state for this machine") end
	end
	Shift(values, spec, now)
	-- raw: the snapshot holds the model's own fields, which a guard against
	-- new keys (meta.class's Guard) must not refuse
	for key in pairs(model) do
		if not spec.skip[key] and not spec.machines[key] and snapshot[key] == nil then rawset(model, key, nil) end
	end
	for key, value in pairs(values) do rawset(model, key, value) end
	for key in pairs(spec.machines) do model[key]:Restore(snapshot[key]) end
end
