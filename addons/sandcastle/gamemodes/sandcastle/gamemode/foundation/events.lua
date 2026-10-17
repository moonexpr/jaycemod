-- Game events, after Source's IGameEventManager and TF2's
-- resource/modevents.res: the server fires facts ("the point was
-- captured", "the Horsemann rose") and each client decides what to show and
-- play. This is the pure core: the registry of definitions, their typed
-- fields, validation, the wire format, listeners, and the rules for
-- requests a client sends the server. The realm adapter
-- (ws/sh_events.lua) carries events on GMod's net library.
--
-- An event is declared as data: a name, its fields and their types, and
-- options. On the wire it is its id, the name's CRC32 cut to ID_BITS (the
-- same in every realm, whatever order lazy loading defines things in),
-- then its fields in name order. A buffer is anything with net.*'s
-- Write<Kind>(value[, bits]) and Read<Kind>([bits]) functions, called with a
-- dot, so the adapter passes net itself.
--
-- Mistakes in our own code (an unknown event, a wrong field, a bad schema)
-- raise a named error: a table with kind and message that prints as
-- "kind: message". A client's request the server will not take (unknown,
-- not client-sendable, over its rate) is refused instead: ReadRequest
-- returns nil and the refusal, since a client's mistake is not ours.
local Crc32 = require("foundation.core.crc32")
local Sets = require("foundation.core.structs.sets")
local error, format, getmetatable, ipairs, pairs, pcall, setmetatable, sort, tostring, type =
	error, string.format, getmetatable, ipairs, pairs, pcall, setmetatable, table.sort, tostring, type
local match = string.match
local floor, min = math.floor, math.min
module(...)

ID_BITS = 24
TEAM_BITS = 10 -- team numbers up to 1023 (GMod's own go to 1002)
MAX_BITS = 32

-- The named errors, and the refusals of a client's request.
UNKNOWN_EVENT = "unknown_event"
BAD_FIELDS = "bad_fields"
BAD_SCHEMA = "bad_schema"
ID_COLLISION = "id_collision"
NOT_CLIENT_SENDABLE = "not_client_sendable"
RATE_LIMITED = "rate_limited"

-- Field kinds.
STRING, BOOL, UINT, INT, FLOAT = "string", "bool", "uint", "int", "float"
ENTITY, VECTOR, ANGLE, LIST, RECORD = "entity", "vector", "angle", "list", "record"

-- The net functions that carry each scalar kind: Write<Kind> and Read<Kind>.
local NET_KIND = {
	[STRING] = "String",
	[BOOL] = "Bool",
	[UINT] = "UInt",
	[INT] = "Int",
	[FLOAT] = "Float",
	[ENTITY] = "Entity",
	[VECTOR] = "Vector",
	[ANGLE] = "Angle",
}

-- Kinds only the host can recognise (the registry's checks).
local ENGINE_KIND = {
	[ENTITY] = true,
	[VECTOR] = true,
	[ANGLE] = true,
}

local OPTIONS = Sets.Named("event option", {
	"clientSendable",
	"rate",
	"unreliable",
})

local ErrorMeta = {
	__tostring = function(e) return e.kind .. ": " .. e.message end,
}

local function Named(kind, message)
	return setmetatable({
		kind = kind,
		message = message,
	}, ErrorMeta)
end

local function Raise(kind, fmt, ...)
	error(Named(kind, format(fmt, ...)), 0)
end

local function IdOfName(name)
	return Crc32.Of(name) % 2 ^ ID_BITS
end

-------------------------------------------------------------------------------
-- Checking values against types. checks: the host's { entity, vector,
-- angle } tests, or nil at declaration, where engine values pass unchecked.

local TypeMeta = {}

local function IsType(t)
	return type(t) == "table" and getmetatable(t) == TypeMeta
end

local function IsWhole(v)
	return type(v) == "number" and v == floor(v)
end

local SCALAR_OK = {
	[STRING] = function(v) return type(v) == "string" end,
	[BOOL] = function(v) return type(v) == "boolean" end,
	[FLOAT] = function(v) return type(v) == "number" end,
	[UINT] = function(v, t) return IsWhole(v) and v >= 0 and v < 2 ^ t.bits end,
	[INT] = function(v, t) return IsWhole(v) and v >= -2 ^ (t.bits - 1) and v < 2 ^ (t.bits - 1) end,
}

local function Describe(t)
	if t.bits and t.kind ~= LIST then return format("%s(%d)", t.kind, t.bits) end
	return t.kind
end

local Check

-- A record's or an event's fields: each declared one checked (a default
-- filled in), nothing undeclared. Returns a new table.
local function CheckFields(fields, value, path, checks)
	if type(value) ~= "table" then Raise(BAD_FIELDS, "%s: expected a table of fields, got %s", path, type(value)) end
	local known = {}
	for _, field in ipairs(fields) do known[field.name] = true end
	for name in pairs(value) do
		if not known[name] then Raise(BAD_FIELDS, "%s: undeclared field %s", path, tostring(name)) end
	end
	local out = {}
	for _, field in ipairs(fields) do
		local t, v = field.type, value[field.name]
		local where = path .. "." .. field.name
		if v == nil and t.hasDefault then v = t.default end
		if v == nil then
			if not t.optional then Raise(BAD_FIELDS, "%s: missing (a %s)", where, Describe(t)) end
		else
			out[field.name] = Check(t, v, where, checks)
		end
	end
	return out
end

-- The value, copied where it is a table, or a BAD_FIELDS error naming path.
function Check(t, v, path, checks)
	local kind = t.kind
	if kind == LIST then
		if type(v) ~= "table" then Raise(BAD_FIELDS, "%s: expected a list, got %s", path, type(v)) end
		if #v >= 2 ^ t.bits then Raise(BAD_FIELDS, "%s: %d items, more than a %d-bit count holds", path, #v, t.bits) end
		local out = {}
		for i = 1, #v do out[i] = Check(t.of, v[i], path .. "[" .. i .. "]", checks) end
		return out
	elseif kind == RECORD then
		return CheckFields(t.fields, v, path, checks)
	elseif ENGINE_KIND[kind] then
		if checks and not checks[kind](v) then Raise(BAD_FIELDS, "%s: expected an %s, got %s", path, kind, tostring(v)) end
		return v
	end
	if not SCALAR_OK[kind](v, t) then Raise(BAD_FIELDS, "%s: expected a %s, got %s", path, Describe(t), tostring(v)) end
	return v
end

-------------------------------------------------------------------------------
-- Field types

local function NewType(t)
	return setmetatable(t, TypeMeta)
end

local function Copy(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return NewType(c)
end

local function CheckBits(bits, lowest, what)
	if not IsWhole(bits) or bits < lowest or bits > MAX_BITS then
		Raise(BAD_SCHEMA, "%s needs %d to %d bits, not %s", what, lowest, MAX_BITS, tostring(bits))
	end
end

local function CheckType(t, what)
	if not IsType(t) then Raise(BAD_SCHEMA, "%s is not a field type (Events.String() and the like)", what) end
end

-- Declared fields as a list sorted by name, the order on the wire.
local function Compile(fields, what)
	if type(fields) ~= "table" then Raise(BAD_SCHEMA, "%s: fields must be a table", what) end
	local list = {}
	for name, t in pairs(fields) do
		if type(name) ~= "string" then Raise(BAD_SCHEMA, "%s: a field name must be a string", what) end
		CheckType(t, what .. "." .. name)
		list[#list + 1] = {
			name = name,
			type = t,
		}
	end
	sort(list, function(a, b) return a.name < b.name end)
	return list
end

function String() return NewType({ kind = STRING }) end
function Bool() return NewType({ kind = BOOL }) end
function Float() return NewType({ kind = FLOAT }) end
function Entity() return NewType({ kind = ENTITY }) end
function Vector() return NewType({ kind = VECTOR }) end
function Angle() return NewType({ kind = ANGLE }) end

function UInt(bits)
	CheckBits(bits, 1, "a uint")
	return NewType({
		kind = UINT,
		bits = bits,
	})
end

-- One of the bits is the sign.
function Int(bits)
	CheckBits(bits, 2, "an int")
	return NewType({
		kind = INT,
		bits = bits,
	})
end

-- A team number (foundation.teams).
function Team()
	return UInt(TEAM_BITS)
end

-- A sequence of one type, its length sent in countBits.
function List(of, countBits)
	CheckType(of, "a list's items")
	CheckBits(countBits, 1, "a list's count")
	return NewType({
		kind = LIST,
		of = of,
		bits = countBits,
	})
end

-- Named fields, inside a list or another record.
function Record(fields)
	return NewType({
		kind = RECORD,
		fields = Compile(fields, "a record"),
	})
end

-- A field that may be left out and arrives as nil (a presence bit on the wire).
function Optional(t)
	CheckType(t, "an optional field")
	if t.hasDefault then Raise(BAD_SCHEMA, "a field is optional or has a default, not both") end
	local c = Copy(t)
	c.optional = true
	return c
end

-- A field that may be left out: the event carries value instead.
function Default(t, value)
	CheckType(t, "a defaulted field")
	if t.optional then Raise(BAD_SCHEMA, "a field is optional or has a default, not both") end
	local ok, err = pcall(Check, t, value, "default")
	if not ok then Raise(BAD_SCHEMA, "the default does not fit: %s", tostring(err)) end
	local c = Copy(t)
	c.hasDefault = true
	c.default = value
	return c
end

-------------------------------------------------------------------------------
-- Encoding against a buffer

local Write, Read

local function WriteFields(fields, values, buffer)
	for _, field in ipairs(fields) do Write(field.type, values[field.name], buffer) end
end

local function ReadFields(fields, buffer)
	local values = {}
	for _, field in ipairs(fields) do values[field.name] = Read(field.type, buffer) end
	return values
end

function Write(t, v, buffer)
	if t.optional then
		buffer.WriteBool(v ~= nil)
		if v == nil then return end
	end
	local kind = t.kind
	if kind == LIST then
		buffer.WriteUInt(#v, t.bits)
		for i = 1, #v do Write(t.of, v[i], buffer) end
	elseif kind == RECORD then
		WriteFields(t.fields, v, buffer)
	else
		buffer["Write" .. NET_KIND[kind]](v, t.bits)
	end
end

function Read(t, buffer)
	if t.optional and not buffer.ReadBool() then return nil end
	local kind = t.kind
	if kind == LIST then
		local list = {}
		for i = 1, buffer.ReadUInt(t.bits) do list[i] = Read(t.of, buffer) end
		return list
	elseif kind == RECORD then
		return ReadFields(t.fields, buffer)
	end
	return buffer["Read" .. NET_KIND[kind]](t.bits)
end

-------------------------------------------------------------------------------
-- The registry: one realm's definitions and listeners

local Registry = {}
Registry.__index = Registry

-- checks: the host's tests for its engine values, { entity = fn(v) -> bool,
-- vector = fn, angle = fn }.
function NewRegistry(checks)
	return setmetatable({
		checks = checks,
		byName = {},
		byId = {},
		listeners = {},
		allowances = setmetatable({}, { __mode = "k" }), -- sender -> name -> { tokens, at }
	}, Registry)
end

local function CheckRate(rate, name)
	if type(rate) ~= "table" or not IsWhole(rate.count) or rate.count < 1
		or type(rate.seconds) ~= "number" or rate.seconds <= 0 then
		Raise(BAD_SCHEMA, "%s: a client-sendable event needs rate = { count, seconds }", name)
	end
end

-- name: snake_case, as TF2's; fields: name -> field type; options:
-- clientSendable (a client may Request it; needs rate = { count, seconds },
-- the most each player may send in that many seconds), unreliable (sent
-- unreliably, for high-rate snapshots). Defining a name again replaces it.
function Registry:Define(name, fields, options)
	if type(name) ~= "string" or not match(name, "^[%w_]+$") then
		Raise(BAD_SCHEMA, "an event name is letters, digits and underscores, not %s", tostring(name))
	end
	options = options or {}
	for key in pairs(options) do
		if not OPTIONS:Has(key) then Raise(BAD_SCHEMA, "%s: unknown option %s", name, tostring(key)) end
	end
	if options.clientSendable then CheckRate(options.rate, name) end
	local id = IdOfName(name)
	local other = self.byId[id]
	if other and other.name ~= name then
		Raise(ID_COLLISION, "%s and %s share the id %d; rename one", other.name, name, id)
	end
	local definition = {
		name = name,
		id = id,
		fields = Compile(fields, name),
		clientSendable = options.clientSendable == true,
		rate = options.rate,
		unreliable = options.unreliable == true,
	}
	self.byName[name] = definition
	self.byId[id] = definition
end

function Registry:Definition(name)
	local definition = self.byName[name]
	if not definition then Raise(UNKNOWN_EVENT, "no event %s is defined", tostring(name)) end
	return definition
end

function Registry:IdOf(name)
	return self:Definition(name).id
end

local function NewEvent(definition, fields)
	return {
		definition = definition,
		name = definition.name,
		fields = fields,
	}
end

-- An event ready to dispatch and write: its fields checked, copied, and
-- the defaults filled in.
function Registry:Build(name, fields)
	local definition = self:Definition(name)
	return NewEvent(definition, CheckFields(definition.fields, fields, name, self.checks))
end

-- A client's request: as Build, for client-sendable events only.
function Registry:BuildRequest(name, fields)
	local definition = self:Definition(name)
	if not definition.clientSendable then Raise(NOT_CLIENT_SENDABLE, "%s is not client-sendable", name) end
	return self:Build(name, fields)
end

function Registry:Write(event, buffer)
	buffer.WriteUInt(event.definition.id, ID_BITS)
	WriteFields(event.definition.fields, event.fields, buffer)
end

-- The event a buffer holds. An id with no definition is a named error: the
-- sender and this realm disagree about what is defined.
function Registry:Read(buffer)
	local id = buffer.ReadUInt(ID_BITS)
	local definition = self.byId[id]
	if not definition then Raise(UNKNOWN_EVENT, "no event has the id %d", id) end
	return NewEvent(definition, ReadFields(definition.fields, buffer))
end

-- A token bucket per sender and event: rate.count at most, refilled at
-- rate.count per rate.seconds.
local function Admit(self, sender, definition, now)
	local bySender = self.allowances[sender]
	if not bySender then
		bySender = {}
		self.allowances[sender] = bySender
	end
	local rate = definition.rate
	local allowance = bySender[definition.name]
	if not allowance then
		allowance = {
			tokens = rate.count,
			at = now,
		}
		bySender[definition.name] = allowance
	end
	allowance.tokens = min(rate.count, allowance.tokens + (now - allowance.at) * rate.count / rate.seconds)
	allowance.at = now
	if allowance.tokens < 1 then return false end
	allowance.tokens = allowance.tokens - 1
	return true
end

-- A client's request as the server receives it: the event, or nil and the
-- refusal (UNKNOWN_EVENT, NOT_CLIENT_SENDABLE or RATE_LIMITED). sender is
-- any key for the player; now is the time in seconds. The fields are of
-- the declared types, but what they say is the client's word.
function Registry:ReadRequest(sender, buffer, now)
	local id = buffer.ReadUInt(ID_BITS)
	local definition = self.byId[id]
	if not definition then return nil, Named(UNKNOWN_EVENT, format("no event has the id %d", id)) end
	if not definition.clientSendable then
		return nil, Named(NOT_CLIENT_SENDABLE, format("%s is not client-sendable", definition.name))
	end
	if not Admit(self, sender, definition, now) then
		return nil, Named(RATE_LIMITED, format("%s: more than %d in %g s", definition.name, definition.rate.count, definition.rate.seconds))
	end
	return NewEvent(definition, ReadFields(definition.fields, buffer))
end

-- fn(fields, ...) runs on each dispatch of the event, in the order added;
-- listening again under the same id replaces that listener in its place.
function Registry:Listen(name, id, fn)
	self:Definition(name)
	local list = self.listeners[name]
	if not list then
		list = {}
		self.listeners[name] = list
	end
	for _, entry in ipairs(list) do
		if entry.id == id then
			entry.fn = fn
			return
		end
	end
	list[#list + 1] = {
		id = id,
		fn = fn,
	}
end

function Registry:Ignore(name, id)
	local list = self.listeners[name] or {}
	for i, entry in ipairs(list) do
		if entry.id == id then
			for j = i, #list do list[j] = list[j + 1] end
			return
		end
	end
end

-- Runs the event's listeners with its fields and the adapter's extra
-- arguments (the sending player, for a request). A listener added or
-- removed meanwhile counts from the next dispatch.
function Registry:Dispatch(event, ...)
	local snapshot = {}
	for i, entry in ipairs(self.listeners[event.name] or {}) do snapshot[i] = entry.fn end
	for _, fn in ipairs(snapshot) do fn(event.fields, ...) end
end
