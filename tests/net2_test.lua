-- net2: messages between the realms over GMod's net library, held on a fake
-- world of one server realm and client realms joined by a fake transport.
local T = dofile ("tests/harness.lua")

dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/net2.lua")
local Net2 = package.loaded.net2

-- Engine values, as the host recognises them.
local EntityMeta, VectorMeta, AngleMeta = {}, {}, {}
local NULL = setmetatable ({}, EntityMeta)
local function Ent (index, teamNumber)
	return setmetatable ({ index = index, team = teamNumber }, EntityMeta)
end
local function Vec (x, y, z) return setmetatable ({ x = x, y = y, z = z }, VectorMeta) end
local function Ang (p, y, r) return setmetatable ({ p = p, y = y, r = r }, AngleMeta) end

-- A toy compressor (runs of a byte), so compression is seen to shrink.
local function Compress (s)
	local out, i = {}, 1
	while i <= #s do
		local c, n = s:sub (i, i), 1
		while n < 255 and s:sub (i + n, i + n) == c do n = n + 1 end
		out [#out + 1] = string.char (n) .. c
		i = i + n
	end
	return table.concat (out)
end
local function Decompress (s, max)
	local out, size = {}, 0
	for i = 1, #s - 1, 2 do
		local n = s:byte (i)
		size = size + n
		if size > max then return nil end
		out [#out + 1] = s:sub (i + 1, i + 1):rep (n)
	end
	return table.concat (out)
end

-- A world: w.server, w.clients[ply], w:Join(index, team), w:Step(n).
local function World (options)
	options = options or {}
	local w =
	{
		now = 0,
		wire = {}, -- messages in flight, in order: { from, to, data, unreliable }
		players = {},
		clients = {},
		entities = {},
		kicked = {},
		reports = {},
		sent = { count = 0, bytes = 0 },
		predicting = nil
	}

	local function Common (server)
		return
		{
			server = server,
			Now = function () return w.now end,
			IsEntity = function (v) return getmetatable (v) == EntityMeta end,
			EntityIndex = function (v) return v.index end,
			Entity = function (index) return w.entities [index] or NULL end,
			NULL = NULL,
			IsVector = function (v) return getmetatable (v) == VectorMeta end,
			Vector = Vec,
			VectorParts = function (v) return v.x, v.y, v.z end,
			IsAngle = function (v) return getmetatable (v) == AngleMeta end,
			Angle = Ang,
			AngleParts = function (v) return v.p, v.y, v.r end,
			Compress = options.compress and Compress or nil,
			Decompress = options.compress and Decompress or nil,
			Report = function (text) w.reports [#w.reports + 1] = text end
		}
	end

	local serverHost = Common (true)
	serverHost.Send = function (data, recipients, unreliable)
		for _, ply in ipairs (recipients) do
			w.wire [#w.wire + 1] = { to = ply, data = data, unreliable = unreliable }
			w.sent.count = w.sent.count + 1
			w.sent.bytes = w.sent.bytes + #data
		end
	end
	serverHost.Players = function () return w.players end
	serverHost.Team = function (ply) return ply.team end
	serverHost.PVS = function (pos)
		local seen = {}
		for _, ply in ipairs (w.players) do
			if ply.pos and math.abs (ply.pos.x - pos.x) < 1000 then seen [#seen + 1] = ply end
		end
		return seen
	end
	serverHost.PredictionPlayer = function () return w.predicting end
	if options.budget then serverHost.Budget = function () return options.budget end end
	serverHost.Kick = function (ply, reason) w.kicked [#w.kicked + 1] = { ply = ply, reason = reason } end
	w.server = Net2.New (serverHost)

	function w:Join (index, teamNumber, version)
		local ply = Ent (index, teamNumber)
		self.entities [index] = ply
		self.players [#self.players + 1] = ply
		local host = Common (false)
		host.Send = function (data, _, unreliable)
			w.wire [#w.wire + 1] = { from = ply, data = data, unreliable = unreliable }
			w.sent.count = w.sent.count + 1
			w.sent.bytes = w.sent.bytes + #data
		end
		local client = Net2.New (host)
		if version then client:SetVersion (version) end
		self.clients [ply] = client
		return ply, client
	end

	function w:Leave (ply)
		for i, p in ipairs (self.players) do
			if p == ply then table.remove (self.players, i) end
		end
		self.clients [ply] = nil
		self.server:Disconnected (ply)
	end

	-- Delivers what is in flight, in order.
	function w:Pump ()
		local wire = self.wire
		self.wire = {}
		for _, m in ipairs (wire) do
			if m.from then
				self.server:Incoming (m.data, m.from)
			elseif self.clients [m.to] then
				self.clients [m.to]:Incoming (m.data)
			end
		end
	end

	-- n ticks of every realm, each followed by delivery.
	function w:Step (n)
		for _ = 1, n or 1 do
			self.now = self.now + 0.015
			self.server:Tick ()
			for _, ply in ipairs (self.players) do
				if self.clients [ply] then self.clients [ply]:Tick () end
			end
			self:Pump ()
		end
	end

	-- A client joined and ready.
	function w:Ready (index, teamNumber)
		local ply, client = self:Join (index, teamNumber)
		client:Start ()
		self:Step (3)
		return ply, client
	end

	return w
end

-- What a realm hears of an event: a list of { fields, ply }.
local function Hear (realm, name)
	local heard = {}
	realm:Receive (name, function (fields, ply) heard [#heard + 1] = { fields = fields, ply = ply } end)
	return heard
end

local function Raises (fn, kind)
	local ok, err = pcall (fn)
	T.eq (ok,                                         false, "raises " .. kind)
	T.eq (tostring (err):find (kind, 1, true) ~= nil, true,  "the error names " .. kind .. ": " .. tostring (err))
end

-- Codec

T.test ("every kind of value arrives as it was fired", function ()
	local w = World ()
	local ply, client = w:Ready (1, 2)
	local heard = Hear (client, "values")
	local nan = 0 / 0
	w.server:Send ("values",
		{
			no = false,
			yes = true,
			zero = 0,
			negative = -1,
			big = 2 ^ 31,
			huge = -(2 ^ 52),
			fraction = 0.1,
			tiny = 5e-324,
			far = -1e300,
			inf = 1 / 0,
			ninf = -1 / 0,
			nan = nan,
			empty = "",
			nul = "a\0b",
			long = ("x"):rep (1000),
			who = ply,
			gone = NULL,
			pos = Vec (1.5, -16384.25, 1e6),
			ang = Ang (-90, 179.5, 0.25),
			fine = Vec (16777215, 0.1, -0.75),
			list = { 1, "two", { three = 3 } },
			records = { { a = 1, b = 2 }, { a = 3, b = 4 } },
			nothing = {}
		}
	)
	w:Step ()
	T.eq (#heard, 1, "heard once")
	local f = heard [1].fields
	T.eq (f.no,                 false,               "false")
	T.eq (f.yes,                true,                "true")
	T.eq (f.zero,               0,                   "zero")
	T.eq (f.negative,           -1,                  "negative")
	T.eq (f.big,                2 ^ 31,              "past 32 bits")
	T.eq (f.huge,               -(2 ^ 52),           "to 52 bits")
	T.eq (f.fraction,           0.1,                 "a fraction, exact")
	T.eq (f.tiny,               5e-324,              "a subnormal")
	T.eq (f.far,                -1e300,              "far out")
	T.eq (f.inf,                1 / 0,               "infinity")
	T.eq (f.ninf,               -1 / 0,              "minus infinity")
	T.eq (f.nan ~= f.nan,       true,                "not a number")
	T.eq (f.empty,              "",                  "an empty string")
	T.eq (f.nul,                "a\0b",              "a string holding NUL, whole")
	T.eq (f.long,               ("x"):rep (1000),    "a long string")
	T.eq (f.who,                ply,                 "an entity")
	T.eq (f.gone,               NULL,                "a NULL entity")
	T.eq (getmetatable (f.pos), VectorMeta,          "a vector")
	T.eq (f.pos.x,              1.5,                 "x")
	T.eq (f.pos.y,              -16384.25,           "y, past WriteVector's range")
	T.eq (f.pos.z,              1e6,                 "z")
	T.eq (f.fine.x,             16777215,            "a float's whole mantissa")
	T.eq (f.fine.y,             0.10000000149011612, "a double rounded to the nearest float, as Source holds it")
	T.eq (getmetatable (f.ang), AngleMeta,           "an angle")
	T.eq (f.ang.p,              -90,                 "pitch")
	T.eq (f.ang.y,              179.5,               "yaw")
	T.eq (f.ang.r,              0.25,                "roll")
	T.eq (f.list [1],           1,                   "a list's number")
	T.eq (f.list [2],           "two",               "a list's string")
	T.eq (f.list [3].three,     3,                   "a record in a list")
	T.eq (f.records [2].b,      4,                   "a list of records")
	T.eq (next (f.nothing),     nil,                 "an empty table")
end)

T.test ("a value the wire cannot carry is refused at Fire, before any listener runs", function ()
	local w = World ()
	local ran = 0
	w.server:Receive ("bad", function () ran = ran + 1 end)
	Raises (function () w.server:Send ("bad", { f = print }) end, "bad_fields")
	local cycle = {}
	cycle.self = cycle
	Raises (function () w.server:Send ("bad", { c = cycle }) end,                "bad_fields")
	Raises (function () w.server:Send ("bad", { m = { 1, x = 2 } }) end,         "bad_fields")
	Raises (function () w.server:Send ("bad", { s = { [1] = 1, [3] = 3 } }) end, "bad_fields")
	Raises (function () w.server:Send ("bad", { k = { [{}] = 1 } }) end,         "bad_fields")
	Raises (function () w.server:Send ("bad", "fields") end,                     "bad_fields")
	T.eq (ran, 0, "no listener ran, though no client is there")
end)

T.test ("names are strings, and net2_ is the library's own", function ()
	local w = World ()
	Raises (function () w.server:Send (7, {}) end,                   "bad_name")
	Raises (function () w.server:Send ("", {}) end,                  "bad_name")
	Raises (function () w.server:Send ("net2_hello", {}) end,        "bad_name")
	Raises (function () w.server:Send ("x", {}, { colour = 1 }) end, "bad_options")
end)

-- Receivers

T.test ("a name has one receiver, and one that raises is reported", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local got
	client:Receive ("e", function () got = "first" end)
	client:Receive ("e", function () error ("boom") end)
	w.server:Send ("e", {})
	w:Step ()
	T.eq (got,        nil, "the first was replaced")
	T.eq (#w.reports, 1,   "the raise reported")
	client:Receive ("e", nil)
	w.server:Send ("e", {})
	w:Step ()
	T.eq (#w.reports, 1, "none: nothing runs")
end)

T.test ("a name is made up where it is used: nothing registers it", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local name = "made/up at run time #" .. 12345
	T.eq (w.server:Send (name, { n = 1 }), true, "sent, though no receiver is there yet")
	w:Step ()
	local heard = Hear (client, name)
	w.server:Send (name, { n = 2 })
	w:Step ()
	T.eq (heard [1].fields.n, 2, "heard once a receiver is there")
end)

T.test ("Send says whether it went anywhere, and why not", function ()
	local w = World ()
	local sent, why = w.server:Send ("e", {})
	T.eq (sent, false,    "nobody is there")
	T.eq (why,  "nobody", "why")
	local _, early = w:Join (9, 2)
	sent, why = early:Send ("e", {})
	T.eq (why, "not_ready", "a client before its hello is answered")
end)

-- Batching and the shape cache

T.test ("a tick's events go out together, in the order fired", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = {}
	client:Receive ("a", function (f) heard [#heard + 1] = "a" .. f.n end)
	client:Receive ("b", function (f) heard [#heard + 1] = "b" .. f.n end)
	local before = w.sent.count
	w.server:Send ("a", { n = 1 })
	w.server:Send ("b", { n = 2 })
	w.server:Send ("a", { n = 3 })
	T.eq (#heard, 0, "the other realm hears nothing before the tick")
	w:Step ()
	T.eq (w.sent.count - before,     1,          "one message")
	T.eq (table.concat (heard, ","), "a1,b2,a3", "in order")
end)

T.test ("a record's keys go over once a connection, then by number", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = Hear (client, "spot")
	local fields = { alpha_long_key = 1, beta_long_key = 2, gamma_long_key = 3 }
	local before = w.sent.bytes
	w.server:Send ("spot", fields)
	w:Step ()
	local first = w.sent.bytes - before
	before = w.sent.bytes
	w.server:Send ("spot", fields)
	w:Step ()
	local second = w.sent.bytes - before
	T.eq (second < first - 30,             true, "the second is smaller: " .. first .. " then " .. second)
	T.eq (second <= 16,                    true, "it names nothing again: " .. second .. " bytes")
	T.eq (heard [2].fields.gamma_long_key, 3,    "and still decodes")
end)

-- The ready gate and the handshake

T.test ("a client is sent nothing until it is ready, and both realms are told when it is", function ()
	local w = World ()
	local readyOnServer, readyOnClient = {}, 0
	w.server:OnReady ("t", function (ply) readyOnServer [#readyOnServer + 1] = ply end)
	local ply, client = w:Join (1, 2)
	local heard = Hear (client, "e")
	client:OnReady ("t", function () readyOnClient = readyOnClient + 1 end)
	w.server:Send ("e", { n = 1 })
	w:Step ()
	T.eq (#heard, 0, "not ready: not sent")
	client:Start ()
	w:Step (3)
	T.eq (readyOnServer [1], ply, "the server told, with the player")
	T.eq (readyOnClient,     1,   "the client told")
	w.server:Send ("e", { n = 2 })
	w:Step ()
	T.eq (#heard,             1, "now it hears")
	T.eq (heard [1].fields.n, 2, "what was sent after")
	local late, lateClient = {}, 0
	w.server:OnReady ("late", function (p) late [#late + 1] = p end)
	client:OnReady ("late", function () lateClient = lateClient + 1 end)
	T.eq (late [1],   ply, "OnReady runs at once for a client already ready")
	T.eq (lateClient, 1,   "and on a client already ready")
end)

T.test ("a client on another version is kicked, told to update", function ()
	local w = World ()
	w.server:SetVersion (2)
	local ply, client = w:Join (1, 2, 1)
	client:Start ()
	w:Step (3)
	T.eq (#w.kicked,                                            1,    "kicked")
	T.eq (w.kicked [1].ply,                                     ply,  "that client")
	T.eq (w.kicked [1].reason:find ("version", 1, true) ~= nil, true, "the reason says why")
end)

T.test ("a client that starts again (a Lua refresh) still decodes what follows", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = Hear (client, "e")
	w.server:Send ("e", { key = 1 })
	w:Step ()
	client:Start ()
	w:Step (3)
	w.server:Send ("e", { key = 2 })
	w:Step ()
	T.eq (#heard,               2, "both heard")
	T.eq (heard [2].fields.key, 2, "the record after the restart")
end)

-- Recipients

T.test ("to picks who hears: a team, a player, a list, the players who can see a point", function ()
	local w = World ()
	local a, ca = w:Ready (1, 2)
	local b, cb = w:Ready (2, 3)
	a.pos, b.pos = Vec (0, 0, 0), Vec (5000, 0, 0)
	local ha, hb = Hear (ca, "e"), Hear (cb, "e")
	w.server:Send ("e", { n = 1 }, { to = 3 })
	w.server:Send ("e", { n = 2 }, { to = a })
	w.server:Send ("e", { n = 3 }, { to = { a, b } })
	w.server:Send ("e", { n = 4 }, { to = Vec (10, 0, 0) })
	w:Step ()
	T.eq (#ha,             3, "a heard three")
	T.eq (ha [1].fields.n, 2, "the one to it")
	T.eq (ha [3].fields.n, 4, "the one where it can see")
	T.eq (#hb,             2, "b heard two")
	T.eq (hb [1].fields.n, 1, "its team's")
end)

-- Clients to the server

T.test ("what the server does not accept is not sent", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = Hear (w.server, "menu")
	local before = w.sent.count
	local sent, why = client:Send ("menu", { choice = 1 })
	w:Step ()
	T.eq (sent,         false,          "not sent")
	T.eq (why,          "not_accepted", "why")
	T.eq (#heard,       0,              "the server did not hear")
	T.eq (w.sent.count, before,         "nothing on the wire")
end)

T.test ("an accepted event reaches the server's listeners with its sender, within its rate", function ()
	local w = World ()
	w.server:Accept ("menu", { count = 2, seconds = 10 })
	local ply, client = w:Ready (1, 2)
	local heard = Hear (w.server, "menu")
	local refused = Hear (client, "net2_refused")
	for n = 1, 4 do client:Send ("menu", { choice = n }) end
	w:Step (2)
	T.eq (#heard,                  2,      "two within the rate")
	T.eq (heard [1].ply,           ply,    "with its sender")
	T.eq (heard [2].fields.choice, 2,      "in order")
	T.eq (#refused,                1,      "the client told once")
	T.eq (refused [1].fields.name, "menu", "which event")
	w.now = w.now + 10
	client:Send ("menu", { choice = 5 })
	w:Step ()
	T.eq (#heard, 3, "the rate refills")
end)

T.test ("an Accept after clients are ready reaches them", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = Hear (w.server, "late")
	w.server:Accept ("late", { count = 5, seconds = 1 })
	w:Step ()
	client:Send ("late", {})
	w:Step ()
	T.eq (#heard, 1, "heard")
end)

T.test ("a client may only send the library's own events and what is accepted", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = Hear (w.server, "net2_ready")
	-- a client sending the server's own event, as the library sends its own
	client:Internal ("net2_ready", {})
	w:Step ()
	T.eq (#heard, 0, "the server's own event is not taken from a client")
end)

T.test ("bytes a client forges are dropped and reported, and the server goes on", function ()
	local w = World ()
	w.server:Accept ("menu", { count = 100, seconds = 1 })
	local ply, client = w:Ready (1, 2)
	local heard = Hear (w.server, "menu")
	-- a frame defining the name "menu" (under an id the client has not used),
	-- then lists nested 200 deep
	local nested = string.char (9, 1):rep (200)
	local deep = string.char (1, 0, 1, 100, 4) .. "menu" .. string.char (0, 1, 100, 0) .. nested .. string.char (0)
	for _, data in ipairs (
		{
			"",
			string.char (99),
			string.char (1, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255),
			string.char (1, 0, 0, 0, 1, 77, 0, 2, 0),
			deep,
			string.char (3, 1, 0, 200) .. ("x"):rep (10),
			string.char (2) .. ("\255x"):rep (10000)
		}
	) do
		local ok, err = pcall (w.server.Incoming, w.server, data, ply)
		T.eq (ok, true, "no error escapes: " .. tostring (err))
	end
	T.eq (#w.reports > 0, true, "reported")
	client:Send ("menu", { choice = 1 })
	w:Step ()
	T.eq (#heard, 1, "a good frame after is taken")
end)

local function Varint (n)
	local out = {}
	while n >= 128 do
		out [#out + 1] = string.char (n % 128 + 128)
		n = math.floor (n / 128)
	end
	out [#out + 1] = string.char (n)
	return table.concat (out)
end

-- A frame from a client defining names, the last "menu", and one "menu"
-- event of fields { s = text } under a shape it defines.
local function MenuFrame (names, text)
	local parts = { string.char (0), Varint (names) }
	for i = 1, names - 2 do parts [#parts + 1] = Varint (1000 + i) .. Varint (1) .. "a" end
	parts [#parts + 1] = Varint (900) .. Varint (1) .. "s"
	parts [#parts + 1] = Varint (901) .. Varint (4) .. "menu"
	parts [#parts + 1] = Varint (1) .. Varint (900) .. Varint (1) .. Varint (900) -- shape 900: { s }
	parts [#parts + 1] = Varint (1) .. Varint (901) .. Varint (0) .. string.char (10) .. Varint (900)
	parts [#parts + 1] = string.char (4) .. Varint (#text) .. text
	return table.concat (parts)
end

T.test ("a client may define only so many names", function ()
	local w = World ()
	w.server:Accept ("menu", { count = 100, seconds = 1 })
	local ply = w:Ready (1, 2)
	local heard = Hear (w.server, "menu")
	w.server:Incoming (string.char (1) .. MenuFrame (10, "fine"), ply)
	T.eq (#heard, 1, "a frame within the limit is taken")
	w.server:Incoming (string.char (1) .. MenuFrame (Net2.CLIENT_STRINGS + 10, "many"), ply)
	T.eq (#heard, 1, "one past it is dropped")
end)

T.test ("a client's compressed frame may not unpack past its limit", function ()
	local w = World ({ compress = true })
	w.server:Accept ("menu", { count = 100, seconds = 1 })
	local ply = w:Ready (1, 2)
	local heard = Hear (w.server, "menu")
	w.server:Incoming (string.char (2) .. Compress (MenuFrame (2, ("b"):rep (1000))), ply)
	T.eq (#heard, 1, "a small one is taken")
	w.server:Incoming (string.char (2) .. Compress (MenuFrame (2, ("b"):rep (Net2.CLIENT_TRANSFER_BYTES + 1))), ply)
	T.eq (#heard, 1, "a bomb is dropped")
end)

T.test ("a client may have only so many payloads arriving in parts at once", function ()
	local w = World ()
	local ply = w:Ready (1, 2)
	local function Part (id)
		return string.char (3) .. Varint (id) .. Varint (0) .. Varint (2) .. "part"
	end
	for id = 1, Net2.TRANSFERS do w.server:Incoming (Part (id), ply) end
	T.eq (#w.reports, 0, "within the limit")
	w.server:Incoming (Part (Net2.TRANSFERS + 1), ply)
	T.eq (#w.reports, 1, "one more is dropped and reported")
end)

-- Unreliable

T.test ("an unreliable event older than one already heard is dropped", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = Hear (client, "snap")
	w.server:Send ("snap", { n = 1 }, { unreliable = true })
	w.server:Tick ()
	local first = w.wire
	w.wire = {}
	w.server:Send ("snap", { n = 2 }, { unreliable = true })
	w.server:Tick ()
	local second = w.wire
	w.wire = {}
	T.eq (first [1].unreliable, true, "sent unreliably")
	for _, m in ipairs (second) do client:Incoming (m.data) end
	for _, m in ipairs (first) do client:Incoming (m.data) end
	T.eq (#heard,             1, "the late, older one dropped")
	T.eq (heard [1].fields.n, 2, "the newest kept")
end)

T.test ("an unreliable event too big for a datagram is refused at Fire", function ()
	local w = World ()
	Raises (function ()
		w.server:Send ("snap", { s = ("x"):rep (Net2.UNRELIABLE_BYTES) }, { unreliable = true })
	end, "too_large")
end)

-- Large payloads

T.test ("an event past one message's size arrives whole, over several ticks", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local heard = Hear (client, "big")
	local parts = {}
	for i = 1, 30000 do parts [i] = i end
	w.server:Send ("big", { parts = parts, text = ("y"):rep (150000) })
	local before = w.sent.count
	w:Step ()
	T.eq (#heard, 0, "not yet whole after one tick")
	w:Step (20)
	T.eq (#heard,                         1,      "whole")
	T.eq (heard [1].fields.parts [30000], 30000,  "its last part")
	T.eq (#heard [1].fields.text,         150000, "its text")
	T.eq (w.sent.count - before > 3,      true,   "over several messages")
end)

T.test ("a small message sent after a large one arrives before it", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local order = {}
	client:Receive ("big",   function () order [#order + 1] = "big" end)
	client:Receive ("small", function (f) order [#order + 1] = "small" .. f.n end)
	w.server:Send ("big",   { text = ("y"):rep (300000), shape = { only_here = 1 } })
	w.server:Send ("small", { n = 1 })
	w:Step ()
	w.server:Send ("small", { n = 2, shape = { only_here = 2 } })
	w:Step (30)
	T.eq (table.concat (order, ","), "small1,small2,big", "the small ones passed it")
end)

T.test ("a peer is sent what its budget allows a tick", function ()
	local w = World ({ budget = 1000 })
	local _, client = w:Ready (1, 2)
	local heard = Hear (client, "e")
	-- four frames' worth, queued in one tick
	for n = 1, 10 do w.server:Send ("e", { n = n, pad = ("p"):rep (20000) }) end
	w:Step ()
	T.eq (#heard, 2, "one message in the first tick, whatever the budget")
	w:Step ()
	T.eq (#heard, 4, "one more the next")
	w:Step (5)
	T.eq (#heard,              10, "the rest over the next ticks")
	T.eq (heard [10].fields.n, 10, "in order")
end)

T.test ("a large frame is compressed when that makes it smaller", function ()
	local plain, packed = World (), World ({ compress = true })
	for _, w in ipairs ({ plain, packed }) do
		local _, client = w:Ready (1, 2)
		w.heard = Hear (client, "big")
		w.before = w.sent.bytes
		w.server:Send ("big", { text = ("z"):rep (20000) })
		w:Step (5)
	end
	T.eq (packed.heard [1].fields.text, ("z"):rep (20000), "arrives whole")
	T.eq (packed.sent.bytes - packed.before < (plain.sent.bytes - plain.before) / 10, true, "far smaller")
end)

T.test ("a client's event past its limit is refused at Fire when it would be sent", function ()
	local w = World ()
	w.server:Accept ("up", { count = 1, seconds = 1 })
	local _, client = w:Ready (1, 2)
	client:Send ("local_only", { s = ("x"):rep (Net2.CLIENT_TRANSFER_BYTES + 1) })
	Raises (function () client:Send ("up", { s = ("x"):rep (Net2.CLIENT_TRANSFER_BYTES + 1) }) end, "too_large")
end)

-- Calls

T.test ("a call gets the server's answer: a value, a refusal, or failed", function ()
	local w = World ()
	w.server:Serve ("buy", function (fields, ply)
		if fields.item == "hat" then return { cost = 10, who = ply } end
		if fields.item == "boom" then error ("our bug") end
		return nil, "unknown_item"
	end, { count = 10, seconds = 1 })
	local ply, client = w:Ready (1, 2)
	local answers = {}
	for _, item in ipairs ({ "hat", "shoe", "boom" }) do
		client:Call ("buy", { item = item }, function (ok, value) answers [item] = { ok, value } end)
	end
	w:Step (3)
	T.eq (answers.hat [1],      true,           "a value")
	T.eq (answers.hat [2].cost, 10,             "the value")
	T.eq (answers.hat [2].who,  ply,            "the handler had the caller")
	T.eq (answers.shoe [1],     false,          "a refusal")
	T.eq (answers.shoe [2],     "unknown_item", "the server's reason")
	T.eq (answers.boom [1],     false,          "a raise")
	T.eq (answers.boom [2],     "failed",       "is failed, and reported")
	T.eq (#w.reports,           1,              "reported on the server")
end)

T.test ("a call to what the server does not serve, or before ready, fails at once", function ()
	local w = World ()
	local _, early = w:Join (9, 2)
	local got
	early:Call ("buy", {}, function (ok, why) got = { ok, why } end)
	T.eq (got [2], "not_ready", "before ready")
	local _, client = w:Ready (1, 2)
	client:Call ("nothing", {}, function (ok, why) got = { ok, why } end)
	T.eq (got [1], false,          "failed")
	T.eq (got [2], "not_accepted", "not served")
end)

T.test ("a call waits in a coroutine its owner resumes, and times out", function ()
	local w = World ()
	w.server:Serve ("slow", function (fields)
		while w.now < fields.till do coroutine.yield () end
		return "done"
	end, { count = 10, seconds = 1 })
	local _, client = w:Ready (1, 2)
	local results = {}
	local function Run (till)
		return coroutine.create (function ()
			local ok, value = client:Call ("slow", { till = till })
			results [#results + 1] = { ok, value }
		end)
	end
	local soon, never = Run (w.now + 0.1), Run (w.now + 1000)
	for _ = 1, 20 do
		coroutine.resume (soon)
		coroutine.resume (never)
		w:Step ()
	end
	T.eq (#results,        1,      "the quick one answered")
	T.eq (results [1] [2], "done", "the server's handler waited across ticks")
	w.now = w.now + Net2.CALL_SECONDS
	w:Step ()
	coroutine.resume (never)
	T.eq (results [2] [1], false,     "the slow one failed")
	T.eq (results [2] [2], "timeout", "timed out")
	Raises (function () client:Call ("slow", {}) end, "bad_call")
end)

-- Replicated tables

T.test ("a table the server writes reaches each client, key by key", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local scores = w.server:Table ("scores")
	local seen = {}
	client:OnChange ("scores", "t", function (key, value, old) seen [#seen + 1] = { key, value, old } end)
	scores.red = 1
	scores.blue = 0
	w:Step ()
	local view = client:Table ("scores")
	T.eq (view.red,  1, "red")
	T.eq (view.blue, 0, "blue")
	T.eq (#seen,     2, "told of each")
	scores.red = 2
	scores.blue = nil
	w:Step ()
	T.eq (view.red,         2,   "changed")
	T.eq (view.blue,        nil, "removed")
	T.eq (seen [#seen] [3], 0,   "with its old value")
	local before = w.sent.count
	scores.red = 2
	w:Step ()
	T.eq (w.sent.count, before, "an unchanged value sends nothing")
	local count = 0
	for _ in view () do count = count + 1 end
	T.eq (count, 1, "walked by calling it")
	Raises (function () view.red = 5 end, "read_only")
end)

T.test ("an event's listeners read the tables as the tick left them", function ()
	local w = World ()
	local _, client = w:Ready (1, 2)
	local score = w.server:Table ("score")
	local read
	client:Receive ("scored", function () read = client:Table ("score").red end)
	w.server:Send ("scored", {})
	score.red = 5
	w:Step ()
	T.eq (read, 5, "the value set in the same tick")
end)

T.test ("a client that joins later gets the whole table", function ()
	local w = World ()
	local slots = w.server:Table ("slots")
	slots [1] = { name = "a" }
	slots [2] = { name = "b" }
	w:Step ()
	local _, client = w:Ready (1, 2)
	T.eq (client:Table ("slots") [2].name, "b", "the snapshot")
end)

T.test ("the server's own OnChange hears its writes", function ()
	local w = World ()
	local seen
	w.server:OnChange ("t", "x", function (key, value) seen = { key, value } end)
	w.server:Table ("t").k = "v"
	T.eq (seen [1], "k", "the key")
	T.eq (seen [2], "v", "the value")
	Raises (function () w.server:Table ("t").f = print end, "bad_fields")
end)

-- Prediction

T.test ("a predicted event is not sent back to the player who predicted it", function ()
	local w = World ()
	local a, ca = w:Ready (1, 2)
	local _, cb = w:Ready (2, 2)
	local ha, hb = Hear (ca, "shot"), Hear (cb, "shot")
	w.predicting = a
	w.server:Send ("shot", {}, { predicted = true })
	w.predicting = nil
	w:Step ()
	T.eq (#ha, 0, "not to the shooter")
	T.eq (#hb, 1, "to the others")
end)

T.test ("a client sends nothing from predicted code: the server runs its own", function ()
	local w = World ()
	w.server:Accept ("shot", { count = 10, seconds = 1 })
	local _, client = w:Ready (1, 2)
	local server = Hear (w.server, "shot")
	local sent, why = client:Send ("shot", {}, { predicted = true })
	w:Step ()
	T.eq (sent,    false,       "not sent")
	T.eq (why,     "predicted", "why")
	T.eq (#server, 0,           "nothing reached the server")
end)

-- Connections

T.test ("a player who leaves is forgotten", function ()
	local w = World ()
	local a = w:Ready (1, 2)
	w:Leave (a)
	w.server:Send ("e", {})
	local before = w.sent.count
	w:Step ()
	T.eq (w.sent.count, before, "nothing sent")
end)

T.test ("Stats counts what each event cost", function ()
	local w = World ()
	w:Ready (1, 2)
	w:Ready (2, 2)
	w.server:Send ("e", { n = 1 })
	w.server:Send ("e", { n = 2 })
	w:Step ()
	local s = w.server:Stats ().e
	T.eq (s.sends,     2,    "sent twice")
	T.eq (s.sent,      4,    "to two clients each")
	T.eq (s.bytes > 0, true, "bytes counted")
end)

T.finish ()
