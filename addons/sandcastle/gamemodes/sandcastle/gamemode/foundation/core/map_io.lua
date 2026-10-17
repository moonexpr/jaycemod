-- A map's entity I/O, as Source's entity list and output system: lookups by
-- targetname and classname, the output connections recorded from map
-- keyvalues, firing them, and observers of the outputs fired and the inputs
-- the engine accepts.
--
-- Lookups read name and class maps built from one scan of the world. They
-- stay until Recache; an entity Tracked as it is created joins them at the
-- next lookup (its keyvalues, its name among them, arrive after creation),
-- a Forgotten one leaves, and a renamed one is Reindexed. Names and classes
-- match without case, and a trailing * matches a prefix (CGlobalEntityList's
-- NamesMatch). An entity no longer valid is never returned.
--
-- The world port:
--   world:Entities() -> every entity, in the engine's order
--   world:NameOf(ent), world:ClassOf(ent) -> its targetname, its classname
--   world:IsValid(ent) -> whether it still exists
--   world:FirstPlayer() -> a player or nil (the !player target)
--   world:Fire(target, input, param, delay, activator, caller)
--
-- Observers subscribe to OUTPUT or INPUT by name and are called in the order
-- they subscribed: an output observer as fn(caller, name, activator), an
-- input observer as fn(entity, input, param, activator, caller). They hold
-- whatever state the inputs drive (a path_track's disabled flag).
local error, ipairs, pairs, setmetatable, tonumber = error, ipairs, pairs, setmetatable, tonumber
local find, lower, sub = string.find, string.lower, string.sub
local remove, sort = table.remove, table.sort
module(...)

OUTPUT, INPUT = "output", "input"

-- An output connection's times when it may fire without end (Hammer's -1).
TIMES_UNLIMITED = -1

-- Hammer separates a connection's fields with ESC in newer maps, commas in
-- older ones.
local ESC = "\27"
local COMMA = ","
local OUTPUT_PREFIX = "on"
local WILDCARD = "*"

local SPECIAL_TARGETS = {
	["!self"] = function(caller) return caller end,
	["!caller"] = function(caller) return caller end,
	["!activator"] = function(_, activator) return activator end,
	["!player"] = function(_, _, world) return world:FirstPlayer() end,
}

local function Split(text, sep)
	local fields, start = {}, 1
	while true do
		local at = find(text, sep, start, true)
		if not at then
			fields[#fields + 1] = sub(text, start)
			return fields
		end
		fields[#fields + 1] = sub(text, start, at - 1)
		start = at + #sep
	end
end

-- An output connection as Hammer writes it: target,input,param,delay,times.
function ParseOutput(name, value)
	local f = Split(value, find(value, ESC, 1, true) and ESC or COMMA)
	return {
		name = name,
		target = f[1] or "",
		input = f[2] or "",
		param = f[3] or "",
		delay = tonumber(f[4]) or 0,
		times = tonumber(f[5]) or TIMES_UNLIMITED,
		fired = 0,
	}
end

local KINDS = {
	[OUTPUT] = true,
	[INPUT] = true,
}

local MapIO = {}
MapIO.__index = MapIO

function New(world)
	return setmetatable({
		world = world,
		names = nil, -- lower name -> entities, nil until the first lookup
		classes = nil, -- lower class -> entities
		indexed = setmetatable({}, { __mode = "k" }), -- entity -> { name, class, order } it is filed under
		filed = 0, -- entities filed since the last scan, for their order
		pending = {},
		keyvalues = setmetatable({}, { __mode = "k" }),
		observers = {
			[OUTPUT] = {},
			[INPUT] = {},
		},
		nextObserver = 1,
	}, MapIO)
end

local function File(map, key, ent)
	local list = map[key]
	if list then
		list[#list + 1] = ent
	else
		map[key] = { ent }
	end
end

local function Unfile(map, key, ent)
	local list = map[key]
	if not list then return end
	for i, other in ipairs(list) do
		if other == ent then
			remove(list, i)
			break
		end
	end
	if #list == 0 then map[key] = nil end
end

function MapIO:_Index(ent)
	local world = self.world
	if not world:IsValid(ent) or self.indexed[ent] then return end
	local name, class = lower(world:NameOf(ent) or ""), lower(world:ClassOf(ent))
	if name ~= "" then File(self.names, name, ent) end
	File(self.classes, class, ent)
	self.filed = self.filed + 1
	self.indexed[ent] = {
		name = name,
		class = class,
		order = self.filed,
	}
end

-- Rebuild the maps from a fresh scan of the world.
function MapIO:Recache()
	self.names, self.classes = {}, {}
	self.indexed = setmetatable({}, { __mode = "k" })
	self.filed = 0
	self.pending = {}
	for _, ent in ipairs(self.world:Entities()) do self:_Index(ent) end
end

function MapIO:_Ready()
	if self.names == nil then
		self:Recache()
		return
	end
	local pending = self.pending
	if #pending == 0 then return end
	self.pending = {}
	for _, ent in ipairs(pending) do self:_Index(ent) end
end

-- A new entity, indexed at the next lookup.
function MapIO:Track(ent)
	self.pending[#self.pending + 1] = ent
end

-- A removed entity leaves the maps.
function MapIO:Forget(ent)
	self:_Ready()
	local filed = self.indexed[ent]
	if not filed then return end
	if filed.name ~= "" then Unfile(self.names, filed.name, ent) end
	Unfile(self.classes, filed.class, ent)
	self.indexed[ent] = nil
end

-- An entity whose name changed is filed again under its new one.
function MapIO:Reindex(ent)
	self:Forget(ent)
	self:Track(ent)
end

function MapIO:_Find(map, key)
	key = lower(key)
	local found = {}
	if key == "" then return found end
	local world = self.world
	if sub(key, -1) == WILDCARD then
		local prefix = sub(key, 1, -2)
		for _, ent in ipairs(self:_Prefixed(map, prefix)) do
			if world:IsValid(ent) then found[#found + 1] = ent end
		end
		return found
	end
	for _, ent in ipairs(map[key] or found) do
		if world:IsValid(ent) then found[#found + 1] = ent end
	end
	return found
end

-- Every entity filed under a key starting with prefix, in the order filed
-- (the engine's order, for those found in one scan).
function MapIO:_Prefixed(map, prefix)
	local list = {}
	for key, entities in pairs(map) do
		if sub(key, 1, #prefix) == prefix then
			for _, ent in ipairs(entities) do list[#list + 1] = ent end
		end
	end
	local indexed = self.indexed
	sort(list, function(a, b) return indexed[a].order < indexed[b].order end)
	return list
end

function MapIO:FindByName(name)
	self:_Ready()
	return self:_Find(self.names, name)
end

function MapIO:FindByClass(class)
	self:_Ready()
	return self:_Find(self.classes, class)
end

function MapIO:FirstByName(name)
	return self:FindByName(name)[1]
end

-- A keyvalue the map sets: an output's connection, kept in map order since
-- an output may repeat, or a value under its lower-cased key.
function MapIO:RecordKeyValue(ent, key, value)
	local kv = self.keyvalues[ent]
	if not kv then
		kv = { outputs = {} }
		self.keyvalues[ent] = kv
	end
	local lowered = lower(key)
	if sub(lowered, 1, #OUTPUT_PREFIX) == OUTPUT_PREFIX then
		kv.outputs[#kv.outputs + 1] = ParseOutput(key, value)
	else
		kv[lowered] = value
	end
end

function MapIO:KeyValues(ent)
	return self.keyvalues[ent] or { outputs = {} }
end

function MapIO:_Targets(o, caller, activator)
	local special = SPECIAL_TARGETS[lower(o.target)]
	if special then return { special(caller, activator, self.world) } end
	return self:FindByName(o.target)
end

-- Fire the named output of an entity whose outputs were recorded, then
-- tell the output's observers.
function MapIO:FireOutput(caller, name, activator)
	local world = self.world
	for _, o in ipairs(self:KeyValues(caller).outputs) do
		if o.name == name and (o.times == TIMES_UNLIMITED or o.fired < o.times) then
			o.fired = o.fired + 1
			for _, target in ipairs(self:_Targets(o, caller, activator)) do
				if world:IsValid(target) then world:Fire(target, o.input, o.param, o.delay, activator, caller) end
			end
		end
	end
	local observers = self.observers[OUTPUT][lower(name)]
	if observers then
		for _, observer in ipairs(observers) do observer.fn(caller, name, activator) end
	end
end

-- An input the engine is delivering: its observers hear it.
function MapIO:AcceptInput(ent, input, param, activator, caller)
	local observers = self.observers[INPUT][lower(input)]
	if not observers then return end
	for _, observer in ipairs(observers) do observer.fn(ent, input, param, activator, caller) end
end

-- Subscribe fn to an OUTPUT or INPUT name; returns the id to Unobserve.
function MapIO:Observe(kind, name, fn)
	if not KINDS[kind] then error("map_io: no observer kind " .. kind, 2) end
	local id = self.nextObserver
	self.nextObserver = id + 1
	local key = lower(name)
	local byName = self.observers[kind]
	byName[key] = byName[key] or {}
	byName[key][#byName[key] + 1] = {
		id = id,
		fn = fn,
	}
	return id
end

function MapIO:Unobserve(id)
	for _, byName in pairs(self.observers) do
		for key, list in pairs(byName) do
			for i, observer in ipairs(list) do
				if observer.id == id then
					remove(list, i)
					if #list == 0 then byName[key] = nil end
					return
				end
			end
		end
	end
end
