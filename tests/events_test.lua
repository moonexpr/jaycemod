local T = dofile("tests/harness.lua")
local Events = T.require("foundation.events")

-- A fake net buffer with GMod's net.* write and read functions, called with
-- a dot as the adapter calls net's. Writes queue up; reads take them in
-- order and error when the kind differs, as a mismatched decoder would.
local function FakeBuffer()
	local buffer = {
		writes = {},
		next = 1,
	}
	local function Writer(kind)
		return function(value, bits)
			buffer.writes[#buffer.writes + 1] = {
				kind = kind,
				value = value,
				bits = bits,
			}
		end
	end
	local function Reader(kind)
		return function(bits)
			local w = buffer.writes[buffer.next]
			if w == nil then error("read past the end: " .. kind, 2) end
			if w.kind ~= kind or w.bits ~= bits then
				error(string.format("read %s(%s), wrote %s(%s)", kind, tostring(bits), w.kind, tostring(w.bits)), 2)
			end
			buffer.next = buffer.next + 1
			return w.value
		end
	end
	for _, kind in ipairs({ "UInt", "Int", "Float", "String", "Bool", "Entity", "Vector", "Angle" }) do
		buffer["Write" .. kind] = Writer(kind)
		buffer["Read" .. kind] = Reader(kind)
	end
	return buffer
end

-- The host's values for the engine types.
local FakeEntity = { __name = "entity" }
local FakeVector = { __name = "vector" }
local FakeAngle = { __name = "angle" }
local function Entity(index) return setmetatable({ index = index }, FakeEntity) end
local function Vec(x, y, z) return setmetatable({ x, y, z }, FakeVector) end
local function Ang(p, y, r) return setmetatable({ p, y, r }, FakeAngle) end

local CHECKS = {
	entity = function(v) return getmetatable(v) == FakeEntity end,
	vector = function(v) return getmetatable(v) == FakeVector end,
	angle = function(v) return getmetatable(v) == FakeAngle end,
}

local function Registry()
	return Events.NewRegistry(CHECKS)
end

local function ErrorOf(fn)
	local ok, err = pcall(fn)
	T.eq(ok, false, "call errors")
	return err
end

local function Has(text, fragment, what)
	if not tostring(text):find(fragment, 1, true) then
		error(string.format("%s: %q not in %q", what or "text", fragment, tostring(text)), 2)
	end
end

-- The capture as TF2's modevents.res declares it, and a request.
local function DefineCapture(registry)
	registry:Define("teamplay_point_captured", {
		cp = Events.UInt(8),
		cpname = Events.String(),
		team = Events.Team(),
		cappers = Events.Default(Events.String(), ""),
	})
end

local RATE = {
	count = 2,
	seconds = 1,
}

local function DefineJoin(registry)
	registry:Define("join_team", { team = Events.Team() }, {
		clientSendable = true,
		rate = RATE,
	})
end

-- Stable ids -------------------------------------------------------------------

T.test("CRC32 is the standard one (zlib's, GMod's util.CRC)", function()
	T.eq(Events.Crc32("The quick brown fox jumps over the lazy dog"), 0x414FA339, "check value")
	T.eq(Events.Crc32(""), 0, "empty")
end)

T.test("an event's id is its name's CRC32 cut to ID_BITS, the same in any registry and order", function()
	local a, b = Registry(), Registry()
	DefineCapture(a)
	DefineJoin(a)
	DefineJoin(b)
	DefineCapture(b)
	local id = Events.Crc32("teamplay_point_captured") % 2 ^ Events.ID_BITS
	T.eq(a:IdOf("teamplay_point_captured"), id, "derived from the name")
	T.eq(b:IdOf("teamplay_point_captured"), id, "not from the order")
end)

T.test("two names whose ids collide error loudly at declaration, naming both", function()
	local registry = Registry()
	-- CRC32s 0x8fd66e24 and 0xe0d66e24 share their low 24 bits.
	registry:Define("event_188781", {})
	local err = ErrorOf(function() registry:Define("event_326020", {}) end)
	T.eq(err.kind, Events.ID_COLLISION, "kind")
	Has(err, "event_188781", "names the first")
	Has(err, "event_326020", "names the second")
end)

T.test("defining a name again replaces its schema (a Lua refresh reruns the file)", function()
	local registry = Registry()
	registry:Define("x", { a = Events.Bool() })
	registry:Define("x", { b = Events.Bool() })
	local buffer = FakeBuffer()
	registry:Write(registry:Build("x", { b = true }), buffer)
	T.eq(registry:Read(buffer).fields.b, true, "the new field")
end)

-- The wire ----------------------------------------------------------------------

T.test("a fired event crosses the wire as its id, then its fields in name order", function()
	local registry = Registry()
	DefineCapture(registry)
	local buffer = FakeBuffer()
	registry:Write(registry:Build("teamplay_point_captured", {
		team = 2,
		cpname = "the Hatch",
		cp = 1,
		cappers = "ab",
	}), buffer)
	local w = buffer.writes
	T.eq(#w, 5, "id and four fields")
	T.eq(w[1].kind, "UInt", "id kind")
	T.eq(w[1].bits, Events.ID_BITS, "id width")
	T.eq(w[1].value, registry:IdOf("teamplay_point_captured"), "id")
	T.eq(w[2].value, "ab", "cappers")
	T.eq(w[3].value, 1, "cp")
	T.eq(w[3].bits, 8, "cp width")
	T.eq(w[4].value, "the Hatch", "cpname")
	T.eq(w[5].value, 2, "team")
	T.eq(w[5].bits, Events.TEAM_BITS, "team width")
	local event = registry:Read(buffer)
	T.eq(event.name, "teamplay_point_captured", "name")
	T.eq(event.fields.cp, 1, "cp back")
	T.eq(event.fields.cpname, "the Hatch", "cpname back")
	T.eq(event.fields.team, 2, "team back")
end)

T.test("every field type round-trips", function()
	local registry = Registry()
	local body = Entity(7)
	registry:Define("everything", {
		s = Events.String(),
		b = Events.Bool(),
		u = Events.UInt(3),
		i = Events.Int(8),
		f = Events.Float(),
		e = Events.Entity(),
		v = Events.Vector(),
		a = Events.Angle(),
		t = Events.Team(),
	})
	local sent = {
		s = "hi",
		b = false,
		u = 7,
		i = -128,
		f = 0.25,
		e = body,
		v = Vec(1, 2, 3),
		a = Ang(4, 5, 6),
		t = 5,
	}
	local buffer = FakeBuffer()
	registry:Write(registry:Build("everything", sent), buffer)
	local got = registry:Read(buffer).fields
	for name, value in pairs(sent) do T.eq(got[name], value, name) end
end)

T.test("lists and lists of records round-trip, with a count of the declared width", function()
	local registry = Registry()
	registry:Define("npc_ragdoll_create", {
		groups = Events.List(Events.UInt(8), 8),
		pose = Events.Optional(Events.List(Events.Record({
			pos = Events.Vector(),
			vel = Events.Optional(Events.Vector()),
		}), 8)),
	})
	local buffer = FakeBuffer()
	registry:Write(registry:Build("npc_ragdoll_create", {
		groups = { 3, 0, 1 },
		pose = {
			{ pos = Vec(1, 1, 1) },
			{
				pos = Vec(2, 2, 2),
				vel = Vec(0, 0, 9),
			},
		},
	}), buffer)
	T.eq(buffer.writes[2].bits, 8, "group count width")
	local got = registry:Read(buffer).fields
	T.eq(table.concat(got.groups, ","), "3,0,1", "groups")
	T.eq(#got.pose, 2, "pose count")
	T.eq(got.pose[1].vel, nil, "absent optional stays absent")
	T.eq(got.pose[2].vel[3], 9, "present optional")
end)

T.test("an optional field left out arrives as nil; given, it arrives", function()
	local registry = Registry()
	registry:Define("path", { total = Events.Optional(Events.Float()) })
	local buffer = FakeBuffer()
	registry:Write(registry:Build("path", {}), buffer)
	registry:Write(registry:Build("path", { total = 4.5 }), buffer)
	T.eq(registry:Read(buffer).fields.total, nil, "absent")
	T.eq(registry:Read(buffer).fields.total, 4.5, "present")
end)

T.test("a defaulted field left out gets its default, for local listeners and the receiver", function()
	local registry = Registry()
	DefineCapture(registry)
	local event = registry:Build("teamplay_point_captured", {
		cp = 0,
		cpname = "",
		team = 3,
	})
	T.eq(event.fields.cappers, "", "filled in")
	local buffer = FakeBuffer()
	registry:Write(event, buffer)
	T.eq(registry:Read(buffer).fields.cappers, "", "sent")
end)

T.test("Build copies the fields: changing the caller's table later changes nothing", function()
	local registry = Registry()
	registry:Define("x", { list = Events.List(Events.UInt(4), 4) })
	local mine = { list = { 1 } }
	local event = registry:Build("x", mine)
	mine.list[1] = 2
	T.eq(event.fields.list[1], 1, "copied")
end)

T.test("the unreliable option is the definition's", function()
	local registry = Registry()
	registry:Define("snapshot", {}, { unreliable = true })
	DefineCapture(registry)
	T.eq(registry:Build("snapshot", {}).definition.unreliable, true, "unreliable")
	T.eq(registry:Build("teamplay_point_captured", {
		cp = 0,
		cpname = "",
		team = 0,
	}).definition.unreliable, false, "reliable by default")
end)

-- Refusals: our own mistakes -------------------------------------------------------

T.test("building an unknown event is a named error", function()
	local err = ErrorOf(function() Registry():Build("nope", {}) end)
	T.eq(err.kind, Events.UNKNOWN_EVENT, "kind")
	Has(err, "nope", "names it")
end)

T.test("a wrong field type, a missing field and an undeclared field are named errors naming the field", function()
	local registry = Registry()
	DefineCapture(registry)
	local wrong = ErrorOf(function()
		registry:Build("teamplay_point_captured", {
			cp = "1",
			cpname = "",
			team = 2,
		})
	end)
	T.eq(wrong.kind, Events.BAD_FIELDS, "wrong type")
	Has(wrong, "cp", "names it")
	local missing = ErrorOf(function() registry:Build("teamplay_point_captured", { cp = 1, team = 2 }) end)
	T.eq(missing.kind, Events.BAD_FIELDS, "missing")
	Has(missing, "cpname", "names it")
	local extra = ErrorOf(function()
		registry:Build("teamplay_point_captured", {
			cp = 1,
			cpname = "",
			team = 2,
			color = 1,
		})
	end)
	T.eq(extra.kind, Events.BAD_FIELDS, "undeclared")
	Has(extra, "color", "names it")
end)

T.test("integers must fit their width and be whole", function()
	local registry = Registry()
	registry:Define("n", {
		u = Events.Default(Events.UInt(3), 0),
		i = Events.Default(Events.Int(4), 0),
	})
	local function Kind(fields) return ErrorOf(function() registry:Build("n", fields) end).kind end
	T.eq(Kind({ u = 8 }), Events.BAD_FIELDS, "uint too big")
	T.eq(Kind({ u = -1 }), Events.BAD_FIELDS, "uint negative")
	T.eq(Kind({ u = 1.5 }), Events.BAD_FIELDS, "uint fraction")
	T.eq(Kind({ i = 8 }), Events.BAD_FIELDS, "int too big")
	T.eq(Kind({ i = -9 }), Events.BAD_FIELDS, "int too small")
	T.eq(registry:Build("n", { i = -8 }).fields.i, -8, "int smallest")
end)

T.test("engine types are checked with the host's tests; a list too long for its count is refused", function()
	local registry = Registry()
	registry:Define("e", {
		body = Events.Default(Events.Entity(), Entity(0)),
		at = Events.Default(Events.Vector(), Vec(0, 0, 0)),
		list = Events.Default(Events.List(Events.Bool(), 2), {}),
	})
	T.eq(ErrorOf(function() registry:Build("e", { body = Vec(1, 1, 1) }) end).kind, Events.BAD_FIELDS, "vector as entity")
	T.eq(ErrorOf(function() registry:Build("e", { at = Ang(1, 1, 1) }) end).kind, Events.BAD_FIELDS, "angle as vector")
	local long = ErrorOf(function() registry:Build("e", { list = { true, true, true, true } }) end)
	T.eq(long.kind, Events.BAD_FIELDS, "4 in a 2-bit count")
	Has(long, "list", "names it")
	T.eq(ErrorOf(function() registry:Build("e", { list = { true, 1 } }) end).kind, Events.BAD_FIELDS, "element type")
end)

T.test("a bad schema is refused at declaration", function()
	local registry = Registry()
	local function Kind(fn) return ErrorOf(fn).kind end
	T.eq(Kind(function() Events.UInt(0) end), Events.BAD_SCHEMA, "no bits")
	T.eq(Kind(function() Events.UInt(33) end), Events.BAD_SCHEMA, "too many bits")
	T.eq(Kind(function() Events.Int(1) end), Events.BAD_SCHEMA, "a sign bit and nothing")
	T.eq(Kind(function() Events.List(Events.Bool(), 0) end), Events.BAD_SCHEMA, "no count bits")
	T.eq(Kind(function() Events.Default(Events.UInt(2), 9) end), Events.BAD_SCHEMA, "a default that does not fit")
	T.eq(Kind(function() registry:Define("x", { a = "string" }) end), Events.BAD_SCHEMA, "not a field type")
	T.eq(Kind(function() registry:Define("x", {}, { clientSendable = true }) end), Events.BAD_SCHEMA, "sendable without a rate")
	T.eq(Kind(function() registry:Define("x", {}, { sendable = true }) end), Events.BAD_SCHEMA, "an unknown option")
end)

T.test("reading an id no definition has is a named error", function()
	local sender, receiver = Registry(), Registry()
	DefineCapture(sender)
	local buffer = FakeBuffer()
	sender:Write(sender:Build("teamplay_point_captured", {
		cp = 0,
		cpname = "",
		team = 0,
	}), buffer)
	T.eq(ErrorOf(function() receiver:Read(buffer) end).kind, Events.UNKNOWN_EVENT, "unknown id")
end)

-- Listeners --------------------------------------------------------------------------

T.test("listeners run in the order added with the fields and what the adapter adds", function()
	local registry = Registry()
	DefineJoin(registry)
	local heard = {}
	registry:Listen("join_team", "first", function(fields, ply) heard[#heard + 1] = "first " .. fields.team .. " " .. ply end)
	registry:Listen("join_team", "second", function(fields) heard[#heard + 1] = "second" end)
	registry:Dispatch(registry:Build("join_team", { team = 2 }), "ply")
	T.eq(table.concat(heard, ","), "first 2 ply,second", "heard")
end)

T.test("listening again under an id replaces that listener in its place; Ignore removes it", function()
	local registry = Registry()
	DefineJoin(registry)
	local heard = {}
	registry:Listen("join_team", "a", function() heard[#heard + 1] = "a1" end)
	registry:Listen("join_team", "b", function() heard[#heard + 1] = "b" end)
	registry:Listen("join_team", "a", function() heard[#heard + 1] = "a2" end)
	registry:Dispatch(registry:Build("join_team", { team = 2 }))
	T.eq(table.concat(heard, ","), "a2,b", "replaced in place")
	registry:Ignore("join_team", "a")
	heard = {}
	registry:Dispatch(registry:Build("join_team", { team = 2 }))
	T.eq(table.concat(heard, ","), "b", "ignored")
end)

T.test("listening to an event nobody defined is a named error", function()
	T.eq(ErrorOf(function() Registry():Listen("nope", "id", print) end).kind, Events.UNKNOWN_EVENT, "kind")
end)

-- Requests: client to server ----------------------------------------------------------

T.test("a client may build only a client-sendable event", function()
	local registry = Registry()
	DefineCapture(registry)
	DefineJoin(registry)
	T.eq(registry:BuildRequest("join_team", { team = 3 }).fields.team, 3, "sendable")
	local err = ErrorOf(function()
		registry:BuildRequest("teamplay_point_captured", {
			cp = 0,
			cpname = "",
			team = 0,
		})
	end)
	T.eq(err.kind, Events.NOT_CLIENT_SENDABLE, "server-only")
end)

-- A client's request as the server's registry receives it.
local function Send(client, name, fields)
	local buffer = FakeBuffer()
	client:Write(client:BuildRequest(name, fields), buffer)
	return buffer
end

T.test("the server admits a client-sendable request and decodes it", function()
	local server, client = Registry(), Registry()
	DefineJoin(server)
	DefineJoin(client)
	local request = server:ReadRequest("ply", Send(client, "join_team", { team = 3 }), 0)
	T.eq(request.name, "join_team", "name")
	T.eq(request.fields.team, 3, "fields")
end)

T.test("the server refuses, without erroring, an unknown id or a server-only event from a client", function()
	local server = Registry()
	DefineCapture(server)
	-- A forged client that believes the capture is sendable.
	local forged = Registry()
	forged:Define("teamplay_point_captured", { cp = Events.UInt(8) }, {
		clientSendable = true,
		rate = RATE,
	})
	forged:Define("made_up", {}, {
		clientSendable = true,
		rate = RATE,
	})
	local request, refusal = server:ReadRequest("ply", Send(forged, "teamplay_point_captured", { cp = 1 }), 0)
	T.eq(request, nil, "no request")
	T.eq(refusal.kind, Events.NOT_CLIENT_SENDABLE, "server-only")
	request, refusal = server:ReadRequest("ply", Send(forged, "made_up", {}), 0)
	T.eq(request, nil, "no request")
	T.eq(refusal.kind, Events.UNKNOWN_EVENT, "unknown")
end)

T.test("each player's requests are rate limited per event; the allowance refills with time", function()
	local server, client = Registry(), Registry()
	DefineJoin(server)
	DefineJoin(client)
	local function Admitted(ply, now)
		local request, refusal = server:ReadRequest(ply, Send(client, "join_team", { team = 2 }), now)
		if request then return "yes" end
		return refusal.kind
	end
	T.eq(Admitted("a", 0), "yes", "first")
	T.eq(Admitted("a", 0.1), "yes", "second: RATE.count")
	T.eq(Admitted("a", 0.2), Events.RATE_LIMITED, "third within the second")
	T.eq(Admitted("b", 0.2), "yes", "another player has their own allowance")
	T.eq(Admitted("a", 0.8), "yes", "half a second refills one")
	T.eq(Admitted("a", 0.8), Events.RATE_LIMITED, "and only one")
	T.eq(Admitted("a", 100), "yes", "a long wait")
	T.eq(Admitted("a", 100), "yes", "refills to the count")
	T.eq(Admitted("a", 100), Events.RATE_LIMITED, "and no more")
end)

-- Every event the addon defines -----------------------------------------------------------

-- Lazy loading means no single map defines every event, so the collision
-- check at declaration cannot see them all: check every name in the source.
-- Definitions name their event with a literal: Define("name", ...).
T.test("no two event names defined anywhere in the addon share an id", function()
	local names, byId = {}, {}
	local files = io.popen("find addons/sandcastle -name '*.lua'")
	for path in files:lines() do
		local f = assert(io.open(path, "r"))
		local text = f:read("*a")
		f:close()
		for name in text:gmatch("Define%(%s*\"([%w_]+)\"") do names[name] = path end
	end
	files:close()
	local count = 0
	for name in pairs(names) do
		local id = Events.Crc32(name) % 2 ^ Events.ID_BITS
		if byId[id] then error(string.format("%s and %s share id %d", byId[id], name, id)) end
		byId[id] = name
		count = count + 1
	end
	T.eq(count > 0, true, "found the definitions")
end)

-- A name fired, listened to or requested with a literal is defined
-- somewhere (the registry would refuse it at run time, on some map).
T.test("every event named in a Fire, Listen or Request is defined in the addon", function()
	local defined, used = {}, {}
	local files = io.popen("find addons/sandcastle -name '*.lua'")
	for path in files:lines() do
		local f = assert(io.open(path, "r"))
		local text = f:read("*a")
		f:close()
		for name in text:gmatch("Define%(%s*\"([%w_]+)\"") do defined[name] = true end
		for _, call in ipairs({ "Fire", "Listen", "Request" }) do
			for name in text:gmatch("Events%." .. call .. "%(%s*\"([%w_]+)\"") do used[name] = path end
			for name in text:gmatch("%f[%w]E%." .. call .. "%(%s*\"([%w_]+)\"") do used[name] = path end
		end
	end
	files:close()
	local count = 0
	for name, path in pairs(used) do
		T.eq(defined[name], true, name .. " (" .. path .. ")")
		count = count + 1
	end
	T.eq(count > 0, true, "found the uses")
end)

-- The library's two net messages are the only ones, for good: a feature
-- defines events instead of registering its own.
T.test("only the event adapter registers, starts or receives net messages", function()
	local ADAPTER = "addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_events.lua"
	local registered = 0
	local files = io.popen("find addons/sandcastle -name '*.lua'")
	for path in files:lines() do
		local f = assert(io.open(path, "r"))
		local text = f:read("*a")
		f:close()
		for _ in text:gmatch("util%.AddNetworkString%(") do
			T.eq(path, ADAPTER, "registers a net message")
			registered = registered + 1
		end
		if text:find("net%.Start%(") or text:find("net%.Receive%(") then T.eq(path, ADAPTER, "uses net directly") end
	end
	files:close()
	T.eq(registered, 2, "the adapter's two: fire and request")
end)

T.finish()
