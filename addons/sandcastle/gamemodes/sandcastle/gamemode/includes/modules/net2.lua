-- net2: GMod's net library taken further (docs/net2.md): messages between
-- the server and its clients as values, not as writes and reads in step.
--
--   net2.Send(name, payload[, options])  the payload, a table, to the other
--                                        realm's receiver of that name; true,
--                                        or false and why it went nowhere
--   net2.Receive(name, fn)               fn(payload[, ply]); one a name
--   net2.Accept(name, rate)              server: clients may send this, at
--                                        rate { count, seconds } each
--   net2.Serve(name, fn, rate)           server: fn(payload, ply) answers a
--                                        client's Call (a value, or nil and a
--                                        refusal); it may yield, resumed a tick
--   net2.Call(name, payload[, callback[, timeout]])   client: the server's
--                                        answer, ok and value (or the reason),
--                                        to the callback, or returned in a
--                                        coroutine its owner resumes
--   net2.Table(name)                     a table the server writes and every
--                                        ready client reads, sent key by key;
--                                        `for key, value in t() do` walks it
--   net2.OnChange(name, id, fn)          fn(key, value, old) as a table changes
--   net2.OnReady(id, fn)                 fn([ply]) as a connection becomes
--                                        ready, and at once for one that is
--   net2.SetVersion(n), net2.Stats()
--   net2.SetDebug(options)               for testing: trace, delay and loss
--                                        (the net2_debug_* convars)
--
-- A name is any string, made up where it is used: nothing registers it
-- (no util.AddNetworkString, no precache at load), on either realm, at any
-- time. It goes over once a connection, then as a number.
--
-- options: to (server: nil for every ready client, a team number, a player,
-- a list of players, or a Vector for the players whose PVS holds it),
-- unreliable (a snapshot small enough for a datagram; an older one arriving
-- after a newer is dropped), predicted (sent from predicted code: a client
-- sends nothing; the server sends to all but the player predicting it).
--
-- Values: nil, booleans, numbers (whole ones to 2^52 as integers, others as
-- doubles, exact), strings (any bytes), entities, vectors and angles (as
-- three floats, exact), and tables of them: a list, or a record with string
-- keys, nested without cycles. A record's keys go over once a connection,
-- then by number. Anything else is our bug, raised at Send. A tick's
-- messages go out together at its end, in order, within the peer's budget
-- (from its rate setting); a payload past one net message is sent in parts
-- over the next ticks, and smaller messages sent after it pass it.
--
-- A client is ready once its hello is answered: until then it is sent
-- nothing, and a client on another version (SetVersion) is kicked. What a
-- client sends is held to what the server accepts and at what rate; a
-- message that does not decode within the limits is dropped and reported.
-- Names beginning net2_ are the library's own: a client may Receive
-- net2_refused (why the server dropped one of its messages).
--
-- Events (local dispatch, listeners in order) are game_events', built on
-- this. net2.New(host) makes a realm over a host port (the GMod host below,
-- or a test's): the library itself reads no GMod global.
local SERVER, CLIENT = SERVER, CLIENT
local coroutine, debug, error, ipairs, next, pairs, pcall, rawget, setmetatable, tostring, type, unpack, xpcall =
	coroutine, debug, error, ipairs, next, pairs, pcall, rawget, setmetatable, tostring, type, unpack, xpcall
local byte, char, format, sub = string.byte, string.char, string.format, string.sub
local concat, sort = table.concat, table.sort
local ceil, floor, frexp, huge, ldexp, min = math.ceil, math.floor, math.frexp, math.huge, math.ldexp, math.min
module("net2", package.seeall)

WIRE_VERSION = 1 -- the wire's own; SetVersion is the game's
NET_MESSAGE = "N2/message"
MESSAGE_BYTES = 60000 -- one net message's payload (GMod's limit is 65533)
UNRELIABLE_BYTES = 1000 -- one unreliable frame; under Source's datagram, unmeasured
TRANSFER_BYTES = 16 * 1024 * 1024 -- a frame from the server, whole
CLIENT_TRANSFER_BYTES = 256 * 1024 -- a frame from a client, whole
PEER_BYTES_PER_TICK = 32 * 1024 -- sent to one peer a tick, but always one message, where the host gives no budget
RATE_FRACTION = 0.3 -- of a client's rate setting that is ours to fill
RATE_MIN, RATE_MAX = 10000, 60000 -- bytes a second, whatever its setting
TRANSFERS = 4 -- payloads arriving in parts from one peer at once
COMPRESS_OVER = 4096 -- frames longer are compressed when that makes them smaller
CALL_SECONDS = 10 -- a call unanswered by then fails, timed out
REPORT_SECONDS = 10 -- one report of a kind a peer, at most, in this time
DEPTH = 32 -- tables nested in an event
CLIENT_DEPTH = 16 -- ... from a client
CLIENT_STRINGS = 4096 -- names and keys a client may define
CLIENT_SHAPES = 1024 -- record shapes a client may define
CLIENT_KEY_BYTES = 256 -- one name or key from a client
SHAPE_KEYS = 256 -- keys of one record
HELLO_RATE = {
	count = 3,
	seconds = 10,
}
RESERVED = "net2_"
KICK_MESSAGE = "This server runs net2 wire %d, version %d; your game has wire %s, version %s. Reconnect to update."

local STATS_LINE = "%-40s sends %6d  sent %6d  bytes %9d  received %6d  refused %4d"
local MILLISECONDS = 1000
local CALLER = 3 -- an error's level from a realm's public method: the code calling net2
local INT_LIMIT = 2 ^ 52
local CLIENT_SLACK = 16 * 1024 -- what a frame adds to a client's event
local CHUNK_BYTES = MESSAGE_BYTES - 32

-- A message's first byte.
local FRAME, COMPRESSED, CHUNK = 1, 2, 3
-- A frame's flags.
local RESET = 1 -- the receiver forgets the names and shapes it holds from this sender first
-- A value's tag.
local T_FALSE, T_TRUE, T_INT, T_DOUBLE, T_STRING = 0, 1, 2, 3, 4
local T_ENTITY, T_NULL, T_VECTOR, T_ANGLE, T_LIST, T_RECORD = 5, 6, 7, 8, 9, 10

local OPTION = {
	to = true,
	unreliable = true,
	predicted = true,
}
local DEBUG_OPTION = {
	trace = true,
	delay = true,
	loss = true,
	random = true,
}
local NO_OPTIONS = {}
local NOBODY = {}

-- Our bugs at a call: a named error, raised at the caller's line by Raise.
local function fault(kind, message)
	error({ net2 = kind, message = message }, 0)
end

local function raise(err, level)
	if type(err) == "table" and err.net2 then
		error("net2: " .. err.net2 .. ": " .. err.message, level + 1)
	end
	error(err, 0)
end

-- A message we will not take: dropped, and reported.
local function malformed(what)
	error({ malformed = what }, 0)
end

local function checkName(name)
	if type(name) ~= "string" or name == "" then
		fault("bad_name", "an event's name is a string, not " .. tostring(name))
	end
	if sub(name, 1, #RESERVED) == RESERVED then
		fault("bad_name", name .. ": names beginning " .. RESERVED .. " are the library's")
	end
end

-- Writing

local function writeVarint(buf, n)
	while n >= 128 do
		buf[#buf + 1] = char(n % 128 + 128)
		n = floor(n / 128)
	end
	buf[#buf + 1] = char(n)
end

local function writeString(buf, s)
	writeVarint(buf, #s)
	buf[#buf + 1] = s
end

-- IEEE 754 single precision, little-endian, rounded to nearest.
local function writeF32(buf, x)
	local sign = 0
	if x < 0 or (x == 0 and 1 / x < 0) then
		sign = 1
		x = -x
	end
	local expo, mant
	if x ~= x then
		expo, mant = 255, 2 ^ 22
	elseif x == huge then
		expo, mant = 255, 0
	elseif x == 0 then
		expo, mant = 0, 0
	else
		local m, e = frexp(x)
		expo = e + 126
		if expo >= 1 then
			mant = floor((m * 2 - 1) * 2 ^ 23 + 0.5)
			if mant >= 2 ^ 23 then mant, expo = 0, expo + 1 end
			if expo >= 255 then expo, mant = 255, 0 end
		else
			mant = floor(ldexp(x, 149) + 0.5)
			if mant >= 2 ^ 23 then mant, expo = 0, 1 else expo = 0 end
		end
	end
	local low, mid = mant % 256, floor(mant / 256) % 256
	local high = floor(mant / 65536) + (expo % 2) * 128
	buf[#buf + 1] = char(low, mid, high, sign * 128 + floor(expo / 2))
end

-- IEEE 754 double precision, little-endian: exact.
local function writeF64(buf, x)
	local sign = 0
	if x < 0 or (x == 0 and 1 / x < 0) then
		sign = 1
		x = -x
	end
	local expo, mant
	if x ~= x then
		expo, mant = 2047, 2 ^ 51
	elseif x == huge then
		expo, mant = 2047, 0
	elseif x == 0 then
		expo, mant = 0, 0
	else
		local m, e = frexp(x)
		expo = e + 1022
		if expo >= 1 then
			mant = (m * 2 - 1) * 2 ^ 52
		else
			expo, mant = 0, ldexp(x, 1074)
		end
	end
	local bytes = {}
	for i = 1, 6 do
		bytes[i] = mant % 256
		mant = floor(mant / 256)
	end
	bytes[7] = mant + (expo % 16) * 16
	bytes[8] = sign * 128 + floor(expo / 16)
	buf[#buf + 1] = char(unpack(bytes))
end

-- Reading, bounded: a short or overlong message is Malformed, never an error of ours.

local function newReader(s, at)
	return { s = s, pos = at, size = #s }
end

local function remaining(r)
	return r.size - r.pos + 1
end

local function readByte(r)
	local p = r.pos
	if p > r.size then malformed("it ends early") end
	r.pos = p + 1

	return byte(r.s, p)
end

local function readVarint(r)
	local n, scale = 0, 1
	for _ = 1, 8 do
		local b = readByte(r)
		if b < 128 then return n + b * scale end
		n = n + (b - 128) * scale
		scale = scale * 128
	end
	malformed("a number past 56 bits")
end

local function readBytes(r, n)
	if n > remaining(r) then malformed("it ends early") end
	local s = sub(r.s, r.pos, r.pos + n - 1)
	r.pos = r.pos + n

	return s
end

local function readF32(r)
	local b1, b2, b3, b4 = byte(readBytes(r, 4), 1, 4)
	local sign = b4 >= 128 and -1 or 1
	local expo = (b4 % 128) * 2 + floor(b3 / 128)
	local mant = (b3 % 128) * 65536 + b2 * 256 + b1
	if expo == 0 then return sign * ldexp(mant, -149) end
	if expo == 255 then
		if mant == 0 then return sign * huge end
		return 0 / 0
	end

	return sign * ldexp(mant + 2 ^ 23, expo - 150)
end

local function readF64(r)
	local b1, b2, b3, b4, b5, b6, b7, b8 = byte(readBytes(r, 8), 1, 8)
	local sign = b8 >= 128 and -1 or 1
	local expo = (b8 % 128) * 16 + floor(b7 / 16)
	local mant = (b7 % 16) * 2 ^ 48 + b6 * 2 ^ 40 + b5 * 2 ^ 32 + b4 * 2 ^ 24 + b3 * 2 ^ 16 + b2 * 2 ^ 8 + b1
	if expo == 0 then return sign * ldexp(mant, -1074) end
	if expo == 2047 then
		if mant == 0 then return sign * huge end
		return 0 / 0
	end

	return sign * ldexp(mant + 2 ^ 52, expo - 1075)
end

-- Small structures

local function newQueue()
	return { first = 1, last = 0 }
end

local function enqueue(q, item)
	q.last = q.last + 1
	q[q.last] = item
end

local function dequeue(q)
	local i = q.first
	if i > q.last then return nil end
	local item = q[i]
	q[i] = nil
	q.first = i + 1

	return item
end

-- What a peer is known to hold of our names (strings) and shapes.
local function newKnown()
	return { strings = {}, shapes = {} }
end

-- What we hold of a peer's names and shapes, by its ids.
local function newDecoder()
	return { strings = {}, shapes = {}, nStrings = 0, nShapes = 0, lastSeq = {} }
end

-- The other end of a connection: a client, on the server (ply), or the
-- server, on a client (no ply).
local function newPeer(ply)
	return {
		ply = ply,
		ready = false,
		known = newKnown(),
		resetNext = true,
		pending = {}, -- reliable events, framed at the tick
		unreliable = {},
		queue = newQueue(), -- messages to send, in order
		slow = newQueue(), -- the parts of payloads past one message, which the queue passes
		decoder = newDecoder(),
		incoming = {}, -- payloads arriving in parts, by the sender's id
		transfers = 0,
		buckets = {},
		toldAt = {},
		reportedAt = nil,
	}
end

-- Listeners by name, each an ordered list of ids; replaced as a whole when
-- it changes, so a dispatch walks the list it started with.
local function addListener(map, name, id, fn)
	local entry = map[name]
	if not entry then
		entry = { order = {}, fns = {} }
		map[name] = entry
	end
	if entry.fns[id] == nil then
		local order = {}
		for i, other in ipairs(entry.order) do order[i] = other end
		order[#order + 1] = id
		entry.order = order
	end
	entry.fns[id] = fn
end

local function removeListener(map, name, id)
	local entry = map[name]
	if not entry or entry.fns[id] == nil then return end
	entry.fns[id] = nil
	local order = {}
	for _, other in ipairs(entry.order) do
		if other ~= id then order[#order + 1] = other end
	end
	entry.order = order
end

local function checkListener(name, id, fn)
	if type(name) ~= "string" or name == "" then
		fault("bad_listener", "a name is a string, not " .. tostring(name))
	end
	if id == nil then fault("bad_listener", name .. ": a listener needs an id") end
	if type(fn) ~= "function" then
		fault("bad_listener", name .. ": a listener is a function, not " .. type(fn))
	end
end

local function checkRate(name, rate)
	local shaped = type(rate) == "table" and type(rate.count) == "number" and type(rate.seconds) == "number"
	if not shaped or rate.count < 1 or rate.seconds <= 0 then
		fault("bad_options", name .. ": a rate is { count, seconds }")
	end

	return {
		count = rate.count,
		seconds = rate.seconds,
	}
end

-- The realm

local Realm = {}
Realm.__index = Realm

function New(host)
	local self = setmetatable({
		host = host,
		server = host.server and true or false,
		version = 0,
		receivers = {},
		held = {},
		readyFns = {},
		watchers = {},
		tables = {},
		stats = {},
		seq = {},
		dict = { ids = {}, strings = {}, shapeIds = {}, shapes = {}, nextString = 1, nextShape = 1 },
	}, Realm)
	if self.server then
		self.peers = {}
		self.accepted = {}
		self.serves = {}
		self.jobs = {}
	else
		self.peer = newPeer(nil)
		self.ready = false
		self.accepted = {}
		self.calls = {}
		self.nextCall = 0
	end

	return self
end

function Realm:Report(text)
	self.host.Report(text)
end

function Realm:Count(name)
	local stat = self.stats[name]
	if not stat then
		stat = { sends = 0, sent = 0, bytes = 0, received = 0, refused = 0 }
		self.stats[name] = stat
	end

	return stat
end

function Realm:Stats()
	return self.stats
end

function Realm:SetVersion(version)
	if type(version) ~= "number" or version ~= floor(version) then
		raise({ net2 = "bad_options", message = "a version is a whole number" }, CALLER)
	end
	self.version = version
end

-- Names and shapes, by our ids

function Realm:StringId(s)
	local dict = self.dict
	local id = dict.ids[s]
	if not id then
		id = dict.nextString
		dict.nextString = id + 1
		dict.ids[s] = id
		dict.strings[id] = s
	end

	return id
end

-- keys: sorted
function Realm:ShapeId(keys)
	local parts = {}
	for i, key in ipairs(keys) do parts[i] = #key .. ":" .. key end
	local signature = concat(parts)
	local dict = self.dict
	local id = dict.shapeIds[signature]
	if not id then
		id = dict.nextShape
		dict.nextShape = id + 1
		dict.shapeIds[signature] = id
		local keyIds = {}
		for i, key in ipairs(keys) do keyIds[i] = self:StringId(key) end
		dict.shapes[id] = keyIds
	end

	return id
end

-- Encoding

local function pathOf(stack, depth)
	local parts = { "fields" }
	for i = 1, depth do
		local key = stack[i]
		parts[#parts + 1] = type(key) == "number" and "[" .. key .. "]" or "." .. tostring(key)
	end

	return concat(parts)
end

local encode

local function encodeTable(self, buf, t, shapes, depth, stack, visiting)
	if depth >= DEPTH then
		fault("bad_fields", pathOf(stack, depth) .. " nests past " .. DEPTH .. " tables")
	end
	if visiting[t] then fault("bad_fields", pathOf(stack, depth) .. " is a cycle") end
	visiting[t] = true
	local count, keys = 0, nil
	for key in pairs(t) do
		local kind = type(key)
		if kind == "string" then
			keys = keys or {}
			keys[#keys + 1] = key
		elseif kind == "number" and key >= 1 and key == floor(key) then
			count = count + 1
		else
			fault("bad_fields", pathOf(stack, depth) .. " has a key the wire cannot carry: " .. tostring(key))
		end
	end
	if keys and count > 0 then fault("bad_fields", pathOf(stack, depth) .. " mixes a list and a record") end
	if keys then
		sort(keys)
		local id = self:ShapeId(keys)
		shapes[id] = true
		buf[#buf + 1] = char(T_RECORD)
		writeVarint(buf, id)
		for _, key in ipairs(keys) do
			stack[depth + 1] = key
			encode(self, buf, t[key], shapes, depth + 1, stack, visiting)
		end
	else
		for i = 1, count do
			if t[i] == nil then fault("bad_fields", pathOf(stack, depth) .. " is a list with holes") end
		end
		buf[#buf + 1] = char(T_LIST)
		writeVarint(buf, count)
		for i = 1, count do
			stack[depth + 1] = i
			encode(self, buf, t[i], shapes, depth + 1, stack, visiting)
		end
	end
	visiting[t] = nil
end

function encode(self, buf, v, shapes, depth, stack, visiting)
	local kind = type(v)
	if kind == "boolean" then
		buf[#buf + 1] = char(v and T_TRUE or T_FALSE)
	elseif kind == "number" then
		if v == floor(v) and v >= -INT_LIMIT and v <= INT_LIMIT then
			buf[#buf + 1] = char(T_INT)
			writeVarint(buf, v >= 0 and v * 2 or -v * 2 - 1)
		else
			buf[#buf + 1] = char(T_DOUBLE)
			writeF64(buf, v)
		end
	elseif kind == "string" then
		buf[#buf + 1] = char(T_STRING)
		writeString(buf, v)
	elseif kind == "table" or kind == "userdata" then
		local host = self.host
		if host.IsEntity(v) then
			local index = host.EntityIndex(v)
			if index == nil then
				buf[#buf + 1] = char(T_NULL)
			else
				buf[#buf + 1] = char(T_ENTITY)
				writeVarint(buf, index)
			end
		elseif host.IsVector(v) then
			local x, y, z = host.VectorParts(v)
			buf[#buf + 1] = char(T_VECTOR)
			writeF32(buf, x)
			writeF32(buf, y)
			writeF32(buf, z)
		elseif host.IsAngle(v) then
			local p, y, r = host.AngleParts(v)
			buf[#buf + 1] = char(T_ANGLE)
			writeF32(buf, p)
			writeF32(buf, y)
			writeF32(buf, r)
		elseif kind == "table" then
			encodeTable(self, buf, v, shapes, depth, stack, visiting)
		else
			fault("bad_fields", pathOf(stack, depth) .. " is userdata the wire cannot carry")
		end
	else
		fault("bad_fields", pathOf(stack, depth) .. " is a " .. kind)
	end
end

-- An event as it goes on the wire: its name's id, its sequence (unreliable
-- events count up a name, reliable ones are 0), and its fields, encoded once
-- for every recipient.
function Realm:EncodeEvent(name, fields, unreliable)
	if type(fields) ~= "table" then
		fault("bad_fields", name .. ": fields are a table, not a " .. type(fields))
	end
	local buf, shapes = {}, {}
	encodeTable(self, buf, fields, shapes, 0, {}, {})
	local payload = concat(buf)
	local seq = 0
	if unreliable then
		seq = (self.seq[name] or 0) + 1
		self.seq[name] = seq
	end

	return {
		name = name,
		nameId = self:StringId(name),
		seq = seq,
		payload = payload,
		shapes = shapes,
		size = #payload,
	}
end

-- A frame: its flags, the names and shapes its events use that the peer is
-- not known to hold (marking them known), then the events.
function Realm:Frame(events, known, flags)
	local dict = self.dict
	local strings, shapes = {}, {}
	local function needString(id)
		if known.strings[id] then return end
		known.strings[id] = true
		strings[#strings + 1] = id
	end
	for _, ev in ipairs(events) do
		needString(ev.nameId)
		for id in pairs(ev.shapes) do
			if not known.shapes[id] then
				known.shapes[id] = true
				shapes[#shapes + 1] = id
				for _, keyId in ipairs(dict.shapes[id]) do needString(keyId) end
			end
		end
	end
	sort(strings)
	sort(shapes)
	local buf = { char(flags) }
	writeVarint(buf, #strings)
	for _, id in ipairs(strings) do
		writeVarint(buf, id)
		writeString(buf, dict.strings[id])
	end
	writeVarint(buf, #shapes)
	for _, id in ipairs(shapes) do
		local keys = dict.shapes[id]
		writeVarint(buf, id)
		writeVarint(buf, #keys)
		for _, keyId in ipairs(keys) do writeVarint(buf, keyId) end
	end
	writeVarint(buf, #events)
	for _, ev in ipairs(events) do
		writeVarint(buf, ev.nameId)
		writeVarint(buf, ev.seq)
		buf[#buf + 1] = ev.payload
	end

	return concat(buf)
end

-- A frame as a message: compressed when that makes it smaller.
function Realm:Wrap(content)
	local compress = self.host.Compress
	if compress and #content > COMPRESS_OVER then
		local packed = compress(content)
		if packed and #packed < #content then return char(COMPRESSED) .. packed end
	end

	return char(FRAME) .. content
end

-- A message onto a peer's queue, in parts if it is past one net message.
function Realm:Queue(peer, queue, body)
	if #body <= MESSAGE_BYTES then
		enqueue(queue, body)

		return
	end
	peer.transfers = peer.transfers + 1
	local count = ceil(#body / CHUNK_BYTES)
	for i = 0, count - 1 do
		local head = { char(CHUNK) }
		writeVarint(head, peer.transfers)
		writeVarint(head, i)
		writeVarint(head, count)
		head[#head + 1] = sub(body, i * CHUNK_BYTES + 1, (i + 1) * CHUNK_BYTES)
		enqueue(queue, concat(head))
	end
end

function Realm:Deliver(peer, data, unreliable)
	if self.server then
		self.host.Send(data, { peer.ply }, unreliable)
	else
		self.host.Send(data, nil, unreliable)
	end
end

-- A message to the wire, through the debug layer: lost, held, or sent.
function Realm:Transmit(peer, data, unreliable)
	local debugging = self.debugging
	if not debugging then return self:Deliver(peer, data, unreliable) end
	if unreliable and debugging.loss and debugging.random() < debugging.loss then return end
	if not debugging.delay then return self:Deliver(peer, data, unreliable) end

	local held = self.held
	held[#held + 1] = { at = self.host.Now() + debugging.delay, peer = peer, data = data, unreliable = unreliable }
end

-- What the debug layer held and is now due, in the order sent.
function Realm:Release(now)
	local held = self.held
	local due = 0
	while held[due + 1] and held[due + 1].at <= now do due = due + 1 end
	if due == 0 then return end

	local rest = {}
	for i = due + 1, #held do rest[#rest + 1] = held[i] end
	self.held = rest
	for i = 1, due do
		local message = held[i]
		local gone = self.server and self.peers[message.peer.ply] ~= message.peer
		if not gone then self:Deliver(message.peer, message.data, message.unreliable) end
	end
end

-- For testing, on this realm: trace(way, name, bytes, ply) sees each
-- message sent ("out") and taken ("in"); delay holds everything sent that
-- many seconds; loss is the share of unreliable messages dropped (random:
-- the draw, 0..1). nil turns it all off.
function Realm:SetDebug(options)
	if options == nil then
		self.debugging = nil

		return
	end

	local shaped = type(options) == "table"
	for key in pairs(shaped and options or {}) do
		shaped = shaped and DEBUG_OPTION[key] == true
	end
	if not shaped then
		raise({ net2 = "bad_options", message = "SetDebug takes trace, delay, loss and random" }, CALLER)
	end

	self.debugging = {
		trace = options.trace,
		delay = options.delay,
		loss = options.loss,
		random = options.random or math.random,
	}
end

function Realm:Trace(way, name, bytes, ply)
	local debugging = self.debugging
	if debugging and debugging.trace then debugging.trace(way, name, bytes, ply) end
end

-- What one peer may be sent a tick.
function Realm:Budget(peer)
	local budget = self.host.Budget

	return budget and budget(peer.ply) or PEER_BYTES_PER_TICK
end

-- A peer's events this tick: the unreliable ones now, each frame defining
-- all it uses; the reliable ones framed onto its queue; then its queue sent,
-- up to its budget, and with what is left the parts of its large payloads.
function Realm:Flush(peer)
	local list = peer.unreliable
	if #list > 0 then
		peer.unreliable = {}
		local batch, size = {}, 0
		for _, ev in ipairs(list) do
			if size > 0 and size + ev.unreliableSize > UNRELIABLE_BYTES then
				self:Transmit(peer, self:Wrap(self:Frame(batch, newKnown(), 0)), true)
				batch, size = {}, 0
			end
			batch[#batch + 1] = ev
			size = size + ev.unreliableSize
		end
		self:Transmit(peer, self:Wrap(self:Frame(batch, newKnown(), 0)), true)
	end
	list = peer.pending
	if #list > 0 then
		peer.pending = {}
		local batch, size = {}, 0
		local function seal()
			if size > MESSAGE_BYTES then
				-- one event past a message: a frame defining all it uses, so
				-- that frames sent after it may arrive before it
				local body = self:Wrap(self:Frame(batch, newKnown(), 0))
				self:Queue(peer, #body > MESSAGE_BYTES and peer.slow or peer.queue, body)
			else
				local flags = 0
				if peer.resetNext then
					flags = RESET
					peer.resetNext = false
				end
				self:Queue(peer, peer.queue, self:Wrap(self:Frame(batch, peer.known, flags)))
			end
			batch, size = {}, 0
		end
		for _, ev in ipairs(list) do
			if size > 0 and size + ev.size > MESSAGE_BYTES then seal() end
			batch[#batch + 1] = ev
			size = size + ev.size
		end
		seal()
	end
	local budget, spent = self:Budget(peer), 0
	for _, queue in ipairs({ peer.queue, peer.slow }) do
		while queue.first <= queue.last do
			local data = queue[queue.first]
			if spent > 0 and spent + #data > budget then return end
			dequeue(queue)
			self:Transmit(peer, data, false)
			spent = spent + #data
		end
	end
end

-- Who hears an event the server fires: ready peers.
function Realm:Recipients(to, predicted)
	local host, peers, list, seen = self.host, self.peers, {}, {}
	local exclude = predicted and host.PredictionPlayer() or nil
	local function add(ply)
		local peer = peers[ply]
		if peer and peer.ready and ply ~= exclude and not seen[peer] then
			seen[peer] = true
			list[#list + 1] = peer
		end
	end
	if to == nil then
		for ply in pairs(peers) do add(ply) end
	elseif type(to) == "number" then
		for ply in pairs(peers) do
			if host.Team(ply) == to then add(ply) end
		end
	elseif host.IsEntity(to) then
		add(to)
	elseif host.IsVector(to) then
		for _, ply in ipairs(host.PVS(to)) do add(ply) end
	elseif type(to) == "table" then
		for _, ply in ipairs(to) do add(ply) end
	else
		fault("bad_options", "to is a team, a player, a list of players or a Vector, not a " .. type(to))
	end

	return list
end

-- Firing

function Realm:Dispatch(name, payload, ply)
	local fn = self.receivers[name]
	if not fn then return end
	local ok, err = xpcall(fn, debug.traceback, payload, ply)
	if not ok then self:Report(format("receiver of %s: %s", name, tostring(err))) end
end

-- What Send checks and encodes before anything happens: the event, the
-- peers it goes to, and why when that is nobody.
function Realm:Prepare(name, fields, options)
	checkName(name)
	if options == nil then
		options = NO_OPTIONS
	elseif type(options) ~= "table" then
		fault("bad_options", name .. ": options are a table")
	else
		for key in pairs(options) do
			if not OPTION[key] then fault("bad_options", name .. ": there is no option " .. tostring(key)) end
		end
	end
	local predicted, unreliable = options.predicted, options.unreliable
	if not self.server then
		if options.to ~= nil then
			fault("bad_options", name .. ": a client's events go to the server, so take no to")
		end
	end
	local ev = self:EncodeEvent(name, fields, unreliable)
	if unreliable then
		ev.unreliableSize = #self:Frame({ ev }, newKnown(), 0) + 1
		if ev.unreliableSize > UNRELIABLE_BYTES then
			local message = "%s: %d bytes, past an unreliable frame's %d"
			fault("too_large", format(message, name, ev.unreliableSize, UNRELIABLE_BYTES))
		end
	end
	if self.server then
		if ev.size > TRANSFER_BYTES then
			fault("too_large", format("%s: %d bytes, past %d", name, ev.size, TRANSFER_BYTES))
		end

		return ev, self:Recipients(options.to, predicted), "nobody"
	end
	if predicted then return ev, NOBODY, "predicted" end
	if not self.ready then return ev, NOBODY, "not_ready" end
	if not self.accepted[name] then return ev, NOBODY, "not_accepted" end
	if ev.size > CLIENT_TRANSFER_BYTES - CLIENT_SLACK then
		local limit = CLIENT_TRANSFER_BYTES - CLIENT_SLACK
		fault("too_large", format("%s: %d bytes, past a client's %d", name, ev.size, limit))
	end

	return ev, { self.peer }
end

-- first: ahead of what the tick has fired so far.
function Realm:Route(ev, peers, unreliable, first)
	if #peers == 0 then return end
	local stat = self:Count(ev.name)
	stat.sent = stat.sent + #peers
	stat.bytes = stat.bytes + ev.size * #peers
	for _, peer in ipairs(peers) do
		self:Trace("out", ev.name, ev.size, peer.ply)
		local list = unreliable and peer.unreliable or peer.pending
		if first then
			table.insert(list, 1, ev)
		else
			list[#list + 1] = ev
		end
	end
end

function Realm:Send(name, payload, options)
	local ok, ev, peers, why = pcall(self.Prepare, self, name, payload, options)
	if not ok then raise(ev, CALLER) end
	self:Count(name).sends = self:Count(name).sends + 1
	if #peers == 0 then return false, why end
	self:Route(ev, peers, options and options.unreliable)

	return true
end

-- The library's own events: to peers (the server's; nil for every ready
-- one), or to the server (a client's), whether or not it is ready; first,
-- ahead of the tick's events.
function Realm:Internal(name, fields, peers, first)
	local ev = self:EncodeEvent(name, fields, false)
	if not self.server then
		peers = { self.peer }
	elseif peers == nil then
		peers = self:Recipients(nil)
	end
	self:Route(ev, peers, false, first)
end

-- fn: nil for no receiver.
function Realm:Receive(name, fn)
	if type(name) ~= "string" or name == "" or (fn ~= nil and type(fn) ~= "function") then
		raise({ net2 = "bad_listener", message = "Receive takes a name and a function" }, CALLER)
	end
	self.receivers[name] = fn
end

function Realm:RunReady(ply)
	local entry = self.readyFns.ready
	if not entry then return end
	for _, id in ipairs(entry.order) do
		local fn = entry.fns[id]
		if fn then
			local ok, err = xpcall(fn, debug.traceback, ply)
			if not ok then self:Report(format("OnReady %s: %s", tostring(id), tostring(err))) end
		end
	end
end

function Realm:OnReady(id, fn)
	local ok, err = pcall(checkListener, "ready", id, fn)
	if not ok then raise(err, CALLER) end
	addListener(self.readyFns, "ready", id, fn)
	if not self.server then
		if self.ready then fn() end

		return
	end
	for ply, peer in pairs(self.peers) do
		if peer.ready then fn(ply) end
	end
end

-- Receiving

local SERVER_INTERNAL, CLIENT_INTERNAL = {}, {}

-- A message off the wire.
function Realm:Incoming(data, ply)
	local peer = self.peer
	if self.server then
		peer = self.peers[ply]
		if not peer then
			peer = newPeer(ply)
			self.peers[ply] = peer
		end
	end
	local ok, events = pcall(self.Unpack, self, peer, data)
	if not ok then
		if type(events) == "table" and events.malformed then
			local now = self.host.Now()
			if not peer.reportedAt or now - peer.reportedAt >= REPORT_SECONDS then
				peer.reportedAt = now
				local from = ply and tostring(ply) or "the server"
				self:Report(format("dropped a message from %s: %s", from, events.malformed))
			end

			return
		end
		error(events, 0)
	end
	if not events then return end
	local lastSeq = peer.decoder.lastSeq
	for _, ev in ipairs(events) do
		local last = lastSeq[ev.name]
		if ev.seq == 0 or not last or ev.seq > last then
			if ev.seq > 0 then lastSeq[ev.name] = ev.seq end
			self:Trace("in", ev.name, ev.size, peer.ply)
			self:Arrive(peer, ev.name, ev.fields)
		end
	end
end

function Realm:Unpack(peer, data)
	local content = self:Unwrap(peer, data, false)
	if content == nil then return nil end
	return self:Decode(peer, content)
end

-- A message's frame, or nil while a frame's parts are still arriving.
function Realm:Unwrap(peer, data, whole)
	local limit = self.server and CLIENT_TRANSFER_BYTES or TRANSFER_BYTES
	local kind = byte(data, 1)
	if kind == FRAME then return sub(data, 2) end
	if kind == COMPRESSED then
		local decompress = self.host.Decompress
		if not decompress then malformed("it is compressed, and this realm cannot decompress") end
		local content = decompress(sub(data, 2), limit)
		if not content then malformed("it does not decompress within " .. limit .. " bytes") end

		return content
	end
	if kind ~= CHUNK or whole then malformed("it is no kind of message: " .. tostring(kind)) end
	local r = newReader(data, 2)
	local id, index, count = readVarint(r), readVarint(r), readVarint(r)
	if count < 2 or index >= count or count > ceil(limit / CHUNK_BYTES) + 1 then
		malformed("a part out of bounds")
	end
	local incoming = peer.incoming
	local transfer = incoming[id]
	if index == 0 then
		incoming[id] = nil
		local open = 0
		for _ in pairs(incoming) do open = open + 1 end
		if open >= TRANSFERS then malformed("more than " .. TRANSFERS .. " payloads in parts at once") end
		transfer = { count = count, parts = {}, bytes = 0 }
		incoming[id] = transfer
	elseif not transfer or transfer.count ~= count or #transfer.parts ~= index then
		incoming[id] = nil
		malformed("a part out of order")
	end
	local part = sub(data, r.pos)
	transfer.bytes = transfer.bytes + #part
	if transfer.bytes > limit then
		incoming[id] = nil
		malformed("parts past " .. limit .. " bytes")
	end
	transfer.parts[index + 1] = part
	if index + 1 < count then return nil end
	incoming[id] = nil

	return self:Unwrap(peer, concat(transfer.parts), true)
end

local function sameKeys(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end

	return true
end

-- A value; a table also answers true.
function Realm:Read(r, shapeOf, limit, depth)
	local tag = readByte(r)
	if tag == T_FALSE then return false end
	if tag == T_TRUE then return true end
	if tag == T_INT then
		local z = readVarint(r)
		if z % 2 == 0 then return z / 2 end
		return -(z + 1) / 2
	end
	if tag == T_DOUBLE then return readF64(r) end
	if tag == T_STRING then return readBytes(r, readVarint(r)) end
	local host = self.host
	if tag == T_ENTITY then return host.Entity(readVarint(r)) end
	if tag == T_NULL then return host.NULL end
	if tag == T_VECTOR or tag == T_ANGLE then
		local a = readF32(r)
		local b = readF32(r)
		local c = readF32(r)
		if tag == T_VECTOR then return host.Vector(a, b, c) end
		return host.Angle(a, b, c)
	end
	if tag == T_LIST or tag == T_RECORD then
		if depth >= limit then malformed("tables nested past " .. limit) end
		local t = {}
		if tag == T_LIST then
			local count = readVarint(r)
			if count > remaining(r) then malformed("a list longer than the message") end
			for i = 1, count do t[i] = self:Read(r, shapeOf, limit, depth + 1) end
		else
			local keys = shapeOf(readVarint(r)) or malformed("a record of a shape not defined")
			for _, key in ipairs(keys) do t[key] = self:Read(r, shapeOf, limit, depth + 1) end
		end

		return t, true
	end
	malformed("an unknown tag " .. tostring(tag))
end

-- A frame's events. What it defines is taken only once the whole frame reads.
function Realm:Decode(peer, content)
	local fromClient = self.server
	local r = newReader(content, 1)
	local flags = readByte(r)
	local decoder = peer.decoder
	local strings, shapes, nStrings, nShapes = decoder.strings, decoder.shapes, decoder.nStrings, decoder.nShapes
	local reset = flags % 2 == RESET
	if reset then strings, shapes, nStrings, nShapes = {}, {}, 0, 0 end
	local newStrings, newShapes = {}, {}
	local function nameOf(id)
		return newStrings[id] or strings[id]
	end
	local function shapeOf(id)
		return newShapes[id] or shapes[id]
	end

	local n = readVarint(r)
	if n > remaining(r) then malformed("more names than bytes") end
	for _ = 1, n do
		local id, length = readVarint(r), readVarint(r)
		if fromClient and length > CLIENT_KEY_BYTES then
			malformed("a name past " .. CLIENT_KEY_BYTES .. " bytes")
		end
		local s = readBytes(r, length)
		local had = nameOf(id)
		if had == nil then
			nStrings = nStrings + 1
			newStrings[id] = s
		elseif had ~= s then
			malformed("a name redefined")
		end
	end
	if fromClient and nStrings > CLIENT_STRINGS then malformed("past " .. CLIENT_STRINGS .. " names") end

	n = readVarint(r)
	if n > remaining(r) then malformed("more shapes than bytes") end
	for _ = 1, n do
		local id, count = readVarint(r), readVarint(r)
		if count > SHAPE_KEYS or count > remaining(r) then malformed("a shape of too many keys") end
		local keys = {}
		for i = 1, count do keys[i] = nameOf(readVarint(r)) or malformed("a key not defined") end
		local had = shapeOf(id)
		if had == nil then
			nShapes = nShapes + 1
			newShapes[id] = keys
		elseif not sameKeys(had, keys) then
			malformed("a shape redefined")
		end
	end
	if fromClient and nShapes > CLIENT_SHAPES then malformed("past " .. CLIENT_SHAPES .. " shapes") end

	local limit = fromClient and CLIENT_DEPTH or DEPTH
	n = readVarint(r)
	if n > remaining(r) then malformed("more events than bytes") end
	local events = {}
	for i = 1, n do
		local from = r.pos
		local name = nameOf(readVarint(r)) or malformed("an event of a name not defined")
		local seq = readVarint(r)
		local fields, isTable = self:Read(r, shapeOf, limit, 0)
		if not isTable then malformed(name .. ": fields not a table") end
		events[i] = { name = name, seq = seq, fields = fields, size = r.pos - from }
	end
	if remaining(r) ~= 0 then malformed("bytes after the last event") end

	if reset then
		decoder.strings, decoder.shapes, decoder.lastSeq = strings, shapes, {}
	end
	for id, s in pairs(newStrings) do decoder.strings[id] = s end
	for id, keys in pairs(newShapes) do decoder.shapes[id] = keys end
	decoder.nStrings, decoder.nShapes = nStrings, nShapes

	return events
end

function Realm:Arrive(peer, name, fields)
	local internal = (self.server and SERVER_INTERNAL or CLIENT_INTERNAL)[name]
	if internal then return internal(self, peer, fields) end
	if self.server then
		if not peer.ready then return end
		if sub(name, 1, #RESERVED) == RESERVED then return self:Refuse(peer, name, "reserved") end
		local rate = self.accepted[name]
		if not rate then return self:Refuse(peer, name, "not_accepted") end
		if not self:Take(peer, name, rate) then return self:Refuse(peer, name, "rate_limited") end
	end
	self:Count(name).received = self:Count(name).received + 1
	self:Dispatch(name, fields, peer.ply)
end

-- The server

-- A token bucket a peer and name, full to start.
function Realm:Take(peer, name, rate)
	local now = self.host.Now()
	local bucket = peer.buckets[name]
	if not bucket then
		bucket = { tokens = rate.count, at = now }
		peer.buckets[name] = bucket
	end
	bucket.tokens = min(rate.count, bucket.tokens + (now - bucket.at) * rate.count / rate.seconds)
	bucket.at = now
	if bucket.tokens < 1 then return false end
	bucket.tokens = bucket.tokens - 1

	return true
end

-- A client's event dropped: it is told once a name in REPORT_SECONDS.
function Realm:Refuse(peer, name, reason)
	self:Count(name).refused = self:Count(name).refused + 1
	local now = self.host.Now()
	local told = peer.toldAt[name]
	if told and now - told < REPORT_SECONDS then return end
	peer.toldAt[name] = now
	self:Internal("net2_refused", { name = name, reason = reason }, { peer })
end

function Realm:AcceptedNames()
	local names = {}
	for name in pairs(self.accepted) do names[#names + 1] = name end
	sort(names)

	return names
end

function Realm:Accept(name, rate)
	local ok, err = pcall(function()
		if not self.server then fault("not_server", "only the server accepts") end
		checkName(name)
		self.accepted[name] = checkRate(name, rate)
	end)
	if not ok then raise(err, CALLER) end
	local peers = self:Recipients(nil)
	if #peers > 0 then self:Internal("net2_accept", { names = { name } }, peers) end
end

function Realm:Serve(name, fn, rate)
	if type(fn) ~= "function" then
		raise({ net2 = "bad_call", message = tostring(name) .. ": a handler is a function" }, CALLER)
	end
	self:Accept(name, rate)
	self.serves[name] = fn
end

function Realm:Reply(peer, id, ok, value)
	local sent = pcall(self.Internal, self, "net2_reply", { id = id, ok = ok, value = value }, { peer })
	if not sent then
		self:Report(format("an answer to call %s cannot go on the wire", tostring(id)))
		self:Internal("net2_reply", { id = id, ok = false, value = "failed" }, { peer })
	end
end

function Realm:Resume(job, ...)
	local ok, value, refusal = coroutine.resume(job.co, ...)
	if not ok then
		self:Report(format("serving %s: %s", job.name, debug.traceback(job.co, tostring(value))))

		return self:Reply(job.peer, job.id, false, "failed")
	end
	if coroutine.status(job.co) ~= "dead" then
		self.jobs[#self.jobs + 1] = job

		return
	end
	if value == nil then
		return self:Reply(job.peer, job.id, false, refusal ~= nil and tostring(refusal) or "refused")
	end
	self:Reply(job.peer, job.id, true, value)
end

function Realm:RunJobs(now)
	local jobs = self.jobs
	if #jobs == 0 then return end
	self.jobs = {}
	for _, job in ipairs(jobs) do
		if self.peers[job.peer.ply] == job.peer then
			if now >= job.deadline then
				self:Reply(job.peer, job.id, false, "timeout")
			else
				self:Resume(job)
			end
		end
	end
end

SERVER_INTERNAL.net2_hello = function(self, peer, fields)
	if not self:Take(peer, "net2_hello", HELLO_RATE) then return end
	if fields.wire ~= WIRE_VERSION or fields.version ~= self.version then
		peer.ready = false
		local theirWire, theirVersion = tostring(fields.wire), tostring(fields.version)
		self.host.Kick(peer.ply, format(KICK_MESSAGE, WIRE_VERSION, self.version, theirWire, theirVersion))

		return
	end
	-- the client forgot what it held of ours: start it over
	peer.ready = true
	peer.known = newKnown()
	peer.resetNext = true
	peer.queue = newQueue()
	peer.slow = newQueue()
	peer.pending = {}
	self:Internal("net2_welcome", { accepted = self:AcceptedNames() }, { peer })
	for name, tbl in pairs(self.tables) do self:Snapshot(peer, name, tbl) end
	self:RunReady(peer.ply)
end

SERVER_INTERNAL.net2_call = function(self, peer, fields)
	if not peer.ready then return end
	local id, name, args = fields.id, fields.name, fields.fields
	if type(id) ~= "number" or type(name) ~= "string" or type(args) ~= "table" then
		return self:Refuse(peer, "net2_call", "malformed")
	end
	local serve = self.serves[name]
	if not serve then return self:Reply(peer, id, false, "not_accepted") end
	if not self:Take(peer, name, self.accepted[name]) then
		return self:Reply(peer, id, false, "rate_limited")
	end
	self:Count(name).received = self:Count(name).received + 1
	self:Resume({
		co = coroutine.create(serve),
		peer = peer,
		id = id,
		name = name,
		deadline = self.host.Now() + CALL_SECONDS,
	}, args, peer.ply)
end

-- Any other net2_ event from a client is the server's own: refused.
setmetatable(SERVER_INTERNAL, {
	__index = function(_, name)
		if sub(name, 1, #RESERVED) == RESERVED then
			return function(self, peer)
				if peer.ready then self:Refuse(peer, name, "reserved") end
			end
		end
	end,
})

function Realm:Disconnected(ply)
	self.peers[ply] = nil
end

-- A client

function Realm:Start()
	local peer = self.peer
	peer.known = newKnown()
	peer.resetNext = true
	peer.queue = newQueue()
	peer.slow = newQueue()
	peer.pending = {}
	peer.unreliable = {}
	peer.decoder = newDecoder()
	peer.incoming = {}
	self.ready = false
	self.accepted = {}
	self:Internal("net2_hello", { wire = WIRE_VERSION, version = self.version })
end

local function settle(self, call, ok, value)
	call.done, call.ok, call.value = true, ok, value
	if call.callback then
		local fine, err = xpcall(call.callback, debug.traceback, ok, value)
		if not fine then self:Report("a call's callback: " .. tostring(err)) end
	end
end

function Realm:Call(name, fields, callback, timeout)
	local ok, err = pcall(function()
		if self.server then fault("bad_call", "the server serves; clients call") end
		checkName(name)
		if type(fields) ~= "table" then fault("bad_fields", name .. ": fields are a table") end
		if callback ~= nil and type(callback) ~= "function" then
			fault("bad_call", name .. ": a callback is a function")
		end
		if callback == nil and not coroutine.running() then
			fault("bad_call", name .. ": outside a coroutine, a call takes a callback")
		end
	end)
	if not ok then raise(err, CALLER) end
	local call = { callback = callback }
	if not self.ready then
		settle(self, call, false, "not_ready")
	elseif not self.accepted[name] then
		settle(self, call, false, "not_accepted")
	else
		local id = self.nextCall + 1
		local sent, why = pcall(self.Internal, self, "net2_call", { id = id, name = name, fields = fields })
		if not sent then raise(why, CALLER) end
		self.nextCall = id
		call.deadline = self.host.Now() + (timeout or CALL_SECONDS)
		self.calls[id] = call
	end
	if callback then return end
	while not call.done do coroutine.yield() end

	return call.ok, call.value
end

function Realm:ExpireCalls(now)
	for id, call in pairs(self.calls) do
		if now >= call.deadline then
			self.calls[id] = nil
			settle(self, call, false, "timeout")
		end
	end
end

CLIENT_INTERNAL.net2_welcome = function(self, _, fields)
	self.accepted = {}
	for _, name in ipairs(fields.accepted or {}) do self.accepted[name] = true end
	self.ready = true
	self:RunReady(nil)
end

CLIENT_INTERNAL.net2_accept = function(self, _, fields)
	for _, name in ipairs(fields.names or {}) do self.accepted[name] = true end
end

CLIENT_INTERNAL.net2_reply = function(self, _, fields)
	local call = self.calls[fields.id]
	if not call then return end
	self.calls[fields.id] = nil
	settle(self, call, fields.ok == true, fields.value)
end

CLIENT_INTERNAL.net2_refused = function(self, _, fields)
	self:Report(format("the server dropped %s: %s", tostring(fields.name), tostring(fields.reason)))
	self:Dispatch("net2_refused", fields)
end

CLIENT_INTERNAL.net2_table = function(self, _, fields)
	if type(fields.name) ~= "string" then return end
	self:Table(fields.name)
	local name, data = fields.name, self.tables[fields.name].data
	local keys, values = fields.keys or {}, fields.values or {}
	if fields.full then
		local present = {}
		for _, key in ipairs(keys) do present[key] = true end
		for key, old in pairs(data) do
			if not present[key] then
				data[key] = nil
				self:Watch(name, key, nil, old)
			end
		end
	end
	for i, key in ipairs(keys) do
		local old = data[key]
		data[key] = values[i]
		self:Watch(name, key, values[i], old)
	end
	for _, key in ipairs(fields.removed or {}) do
		local old = data[key]
		data[key] = nil
		if old ~= nil then self:Watch(name, key, nil, old) end
	end
end

-- Replicated tables

function Realm:Watch(name, key, value, old)
	local entry = self.watchers[name]
	if not entry then return end
	for _, id in ipairs(entry.order) do
		local fn = entry.fns[id]
		if fn then
			local ok, err = xpcall(fn, debug.traceback, key, value, old)
			if not ok then self:Report(format("OnChange %s of %s: %s", tostring(id), name, tostring(err))) end
		end
	end
end

function Realm:OnChange(name, id, fn)
	local ok, err = pcall(checkListener, name, id, fn)
	if not ok then raise(err, CALLER) end
	addListener(self.watchers, name, id, fn)
end

local function countKeys(data)
	local n = 0
	for _ in pairs(data) do n = n + 1 end

	return n
end

function Realm:Set(tbl, key, value)
	if not self.server then
		raise({ net2 = "read_only", message = "table " .. tbl.name .. " is the server's to write" }, 3)
	end
	local kind = type(key)
	if kind ~= "string" and not (kind == "number" and key == floor(key)) then
		raise({ net2 = "bad_fields", message = "table " .. tbl.name .. ": a key is a string or a whole number" }, 3)
	end
	local old = tbl.data[key]
	if value == old and type(value) ~= "table" then return end
	if value ~= nil then
		local ok, err = pcall(encode, self, {}, value, {}, 0, { key }, {})
		if not ok then raise(err, 3) end
	end
	tbl.data[key] = value
	tbl.dirty[key] = true
	self:Watch(tbl.name, key, value, old)
end

function Realm:Table(name)
	if type(name) ~= "string" or name == "" then
		raise({ net2 = "bad_name", message = "a table's name is a string" }, CALLER)
	end
	local tbl = self.tables[name]
	if tbl then return tbl.proxy end
	tbl = { name = name, data = {}, dirty = {} }
	tbl.proxy = setmetatable({}, {
		__index = tbl.data,
		__newindex = function(_, key, value) self:Set(tbl, key, value) end,
		__call = function() return next, tbl.data, nil end,
		__len = function() return countKeys(tbl.data) end,
		__tostring = function() return "net2 table " .. name end,
	})
	self.tables[name] = tbl

	return tbl.proxy
end

-- A table, whole, to a peer just ready.
function Realm:Snapshot(peer, name, tbl)
	local keys, values = {}, {}
	for key, value in pairs(tbl.data) do
		keys[#keys + 1] = key
		values[#values + 1] = value
	end
	self:Internal("net2_table", { name = name, full = true, keys = keys, values = values }, { peer })
end

-- The tick's changes, key by key, to every ready peer, ahead of the tick's
-- events: a listener reads the tables as they are now.
function Realm:FlushTables()
	for name, tbl in pairs(self.tables) do
		if next(tbl.dirty) ~= nil then
			local keys, values, removed = {}, {}, {}
			for key in pairs(tbl.dirty) do
				local value = tbl.data[key]
				if value == nil then
					removed[#removed + 1] = key
				else
					keys[#keys + 1] = key
					values[#values + 1] = value
				end
			end
			tbl.dirty = {}
			local peers = self:Recipients(nil)
			if #peers > 0 then
				local delta = { name = name, keys = keys, values = values, removed = removed }
				self:Internal("net2_table", delta, peers, true)
			end
		end
	end
end

-- The tick: what changed and what was fired goes out.
function Realm:Tick()
	local now = self.host.Now()
	self:Release(now)
	if self.server then
		self:FlushTables()
		self:RunJobs(now)
		for _, peer in pairs(self.peers) do self:Flush(peer) end
	else
		self:ExpireCalls(now)
		self:Flush(self.peer)
	end
end

-- GMod

local function gmodHost()
	local host = {
		server = SERVER,
		Now = SysTime,
		IsEntity = IsEntity,
		EntityIndex = function(v)
			if IsValid(v) then return v:EntIndex() end
			if v == game.GetWorld() then return 0 end
			return nil
		end,
		Entity = Entity,
		NULL = NULL,
		IsVector = isvector,
		Vector = Vector,
		VectorParts = function(v) return v.x, v.y, v.z end,
		IsAngle = isangle,
		Angle = Angle,
		AngleParts = function(a) return a.p, a.y, a.r end,
		Compress = util.Compress,
		Decompress = util.Decompress,
		Report = function(text) ErrorNoHalt("net2: " .. text .. "\n") end,
		Send = function(data, recipients, unreliable)
			net.Start(NET_MESSAGE, unreliable)
			net.WriteUInt(#data, 16)
			net.WriteData(data, #data)
			if SERVER then
				net.Send(recipients)
			else
				net.SendToServer()
			end
		end,
	}
	if SERVER then
		host.Team = function(ply) return ply:Team() end
		host.PVS = function(pos)
			local filter = RecipientFilter()
			filter:AddPVS(pos)

			return filter:GetPlayers()
		end
		host.PredictionPlayer = function()
			local ply = GetPredictionPlayer()
			if IsValid(ply) then return ply end
			return nil
		end
		host.Kick = function(ply, reason) ply:Kick(reason) end
		-- a share of the rate the client asked for, a tick
		host.Budget = function(ply)
			local rate = ply:GetInfoNum("rate", 0) * RATE_FRACTION
			if rate < RATE_MIN then rate = RATE_MIN elseif rate > RATE_MAX then rate = RATE_MAX end

			return rate * engine.TickInterval()
		end
	else
		host.FirstTimePredicted = IsFirstTimePredicted
	end

	return host
end

-- Each realm's, kept across a Lua refresh with what it holds.
local function install()
	local host = gmodHost()
	local current = rawget(_M, "realm")
	if current then
		setmetatable(current, Realm)
		current.host = host
	else
		current = New(host)
	end
	realm = current
	if SERVER then util.AddNetworkString(NET_MESSAGE) end
	net.Receive(NET_MESSAGE, function(bits, ply)
		local size = net.ReadUInt(16)
		if size * 8 + 16 > bits then return end
		realm:Incoming(size > 0 and net.ReadData(size) or "", ply)
	end)
	hook.Add("Tick", "sandcastle/net2/flush", function() realm:Tick() end)
	if SERVER then
		hook.Add("PlayerDisconnected", "sandcastle/net2/forget-peer", function(ply) realm:Disconnected(ply) end)
	else
		local function start() realm:Start() end
		if IsValid(LocalPlayer()) then
			timer.Simple(0, start)
		else
			hook.Add("InitPostEntity", "sandcastle/net2/hello", start)
		end
	end
	concommand.Add("net2_print", function()
		local names = {}
		for name in pairs(realm.stats) do names[#names + 1] = name end
		sort(names, function(a, b) return realm.stats[a].bytes > realm.stats[b].bytes end)
		for _, name in ipairs(names) do
			local s = realm.stats[name]
			MsgN(format(STATS_LINE, name, s.sends, s.sent, s.bytes, s.received, s.refused))
		end
	end, nil, "net2: what each name cost this realm")

	-- The debug layer, this realm's: set on the server's console for what it
	-- sends, on a client's for what that client sends.
	local traceHelp = "net2: print each message this realm sends and takes"
	local delayHelp = "net2: hold what this realm sends this many milliseconds"
	local lossHelp = "net2: the share (0 to 1) of unreliable messages dropped"
	local trace = CreateConVar("net2_debug_trace", "0", FCVAR_NONE, traceHelp)
	local delay = CreateConVar("net2_debug_delay", "0", FCVAR_NONE, delayHelp)
	local loss = CreateConVar("net2_debug_loss", "0", FCVAR_NONE, lossHelp)
	local function applyDebug()
		local seconds, share = delay:GetFloat() / MILLISECONDS, loss:GetFloat()
		if not trace:GetBool() and seconds <= 0 and share <= 0 then return realm:SetDebug(nil) end

		realm:SetDebug({
			trace = trace:GetBool() and function(way, name, bytes, ply)
				MsgN(format("net2 %-3s %-40s %6d bytes  %s", way, name, bytes, ply and tostring(ply) or ""))
			end or nil,
			delay = seconds > 0 and seconds or nil,
			loss = share > 0 and share or nil,
		})
	end
	for _, name in ipairs({ "net2_debug_trace", "net2_debug_delay", "net2_debug_loss" }) do
		cvars.AddChangeCallback(name, applyDebug, "sandcastle/net2/debug")
	end
	applyDebug()
end

-- The module's functions, on this realm's net2 (none under plain LuaJIT).
local function pass(...)
	return ...
end

local METHODS = {
	"Send",
	"Receive",
	"Accept",
	"Serve",
	"Call",
	"Table",
	"OnChange",
	"OnReady",
	"Stats",
	"SetVersion",
	"SetDebug",
}

for _, method in ipairs(METHODS) do
	_M[method] = function(...)
		local current = realm
		if not current then error("net2: not installed in this realm", 2) end

		return pass(current[method](current, ...))
	end
end

if SERVER or CLIENT then install() end
