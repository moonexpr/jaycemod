-- The dev workbench's gamerules harness, as a model: what becomes of each
-- input a map sends the gamerules (forwarded to the real gamerules, dropped,
-- or queued until released), and a numbered trace of everything the
-- harness saw: inputs, the round's effects, outputs, notes.
--   New(capacity) -> a harness whose trace keeps the newest `capacity`
--   harness:SetMode(FORWARD | INTERCEPT | QUEUE), harness:Mode()
--   harness:SetRule(input, action | nil): one input's own action, any case
--   harness:Input(input, now) -> the action taken; input = { name, value, caller }
--   harness:TakeQueued() -> the queued inputs, oldest first, once
--   harness:Record(kind, fields, now), harness:Since(seq), harness:LastSeq(),
--   harness:Dropped() -> entries the trace no longer holds
local error, ipairs, pairs, setmetatable, tostring = error, ipairs, pairs, setmetatable, tostring
local concat, lower, sort = table.concat, string.lower, table.sort
module(...)

FORWARD, INTERCEPT, QUEUE = "forward", "intercept", "queue"
local ACTIONS = {
	[FORWARD] = true,
	[INTERCEPT] = true,
	[QUEUE] = true,
}

local INPUT = "input"

local function Check(action, what)
	if ACTIONS[action] then return action end
	local known = {}
	for name in pairs(ACTIONS) do known[#known + 1] = name end
	sort(known)
	error(what .. " " .. tostring(action) .. " is not one of " .. concat(known, ", "), 3)
end

local Harness = {}
Harness.__index = Harness

function New(capacity)
	return setmetatable({
		mode = FORWARD,
		rules = {},
		queued = {},
		capacity = capacity,
		entries = {},
		first = 1, -- the oldest entry's index in entries
		seq = 0,
		dropped = 0,
	}, Harness)
end

function Harness:Mode() return self.mode end

function Harness:SetMode(mode)
	self.mode = Check(mode, "mode")
end

function Harness:SetRule(input, action)
	if action ~= nil then Check(action, "rule action") end
	self.rules[lower(input)] = action
end

function Harness:Rules()
	local copy = {}
	for name, action in pairs(self.rules) do copy[name] = action end
	return copy
end

local OWN_KEYS = { "seq", "kind", "at" }

function Harness:Record(kind, fields, now)
	for _, key in ipairs(OWN_KEYS) do
		if fields[key] ~= nil then error("a trace entry's " .. key .. " is its own; name the field otherwise", 2) end
	end
	self.seq = self.seq + 1
	local entry = {
		seq = self.seq,
		kind = kind,
		at = now,
	}
	for k, v in pairs(fields) do entry[k] = v end
	self.entries[self.seq] = entry
	if self.seq - self.first + 1 > self.capacity then
		self.entries[self.first] = nil
		self.first = self.first + 1
		self.dropped = self.dropped + 1
	end
	return entry
end

function Harness:Input(input, now)
	local action = self.rules[lower(input.name)] or self.mode
	self:Record(INPUT, {
		name = input.name,
		value = input.value,
		caller = input.caller,
		action = action,
	}, now)
	if action == QUEUE then self.queued[#self.queued + 1] = input end
	return action
end

function Harness:TakeQueued()
	local queued = self.queued
	self.queued = {}
	return queued
end

function Harness:QueuedCount() return #self.queued end

function Harness:Since(seq)
	local list = {}
	for i = self.first, self.seq do
		if i > seq then list[#list + 1] = self.entries[i] end
	end
	return list
end

function Harness:LastSeq() return self.seq end
function Harness:Dropped() return self.dropped end

-- Every entry whose kind is one of kinds, for a filtered trace.
function Of(entries, kinds)
	local wanted = {}
	for _, kind in ipairs(kinds) do wanted[kind] = true end
	local list = {}
	for _, entry in ipairs(entries) do
		if wanted[entry.kind] then list[#list + 1] = entry end
	end
	return list
end
