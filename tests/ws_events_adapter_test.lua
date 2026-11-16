-- WS.Events on net2: sh_events.lua loaded for a server and for a client,
-- each over its own net2 realm, the two joined by a fake transport.
local T = dofile ("tests/harness.lua")

dofile ("addons/sandcastle/gamemodes/sandcastle/gamemode/includes/modules/net2.lua")
local Net2 = package.loaded.net2
local Transaction = transaction

local ADAPTER = "addons/sandcastle/gamemodes/wetsands/gamemode/sh_events.lua"
local RED, BLU = 2, 3
local SOLD_OUT = "sold out"

local PlayerMeta = {}
PlayerMeta.__index = PlayerMeta
function PlayerMeta:IsBot () return self.bot == true end
function PlayerMeta:Team () return self.team end

local VectorMeta = {}
local NULL = setmetatable ({}, PlayerMeta)

-- A server and one client's adapters. w.server and w.client are their
-- WS.Events; w:Step (n) runs n ticks of both realms and their Think hooks.
local function World ()
	local w = { now = 0, wire = {}, players = {}, entities = {}, thinks = {}, fired = {}, printed = {} }

	local function Host (server)
		return
		{
			server = server,
			Now = function () return w.now end,
			IsEntity = function (v) return getmetatable (v) == PlayerMeta end,
			EntityIndex = function (v) return v.index end,
			Entity = function (index) return w.entities [index] or NULL end,
			NULL = NULL,
			IsVector = function (v) return getmetatable (v) == VectorMeta end,
			Vector = function (x, y, z) return setmetatable ({ x = x, y = y, z = z }, VectorMeta) end,
			VectorParts = function (v) return v.x, v.y, v.z end,
			IsAngle = function () return false end,
			Report = function (text) w.printed [#w.printed + 1] = text end
		}
	end

	local serverHost = Host (true)
	serverHost.Send = function (data, recipients)
		for _, ply in ipairs (recipients) do w.wire [#w.wire + 1] = { to = ply, data = data } end
	end
	serverHost.Team = function (ply) return ply.team end
	serverHost.PVS = function () return w.players end
	serverHost.PredictionPlayer = function () return nil end
	serverHost.Kick = function () end
	w.serverRealm = Net2.New (serverHost)

	local function Player (index, teamNumber, bot)
		local ply = setmetatable ({ index = index, team = teamNumber, bot = bot }, PlayerMeta)
		w.entities [index] = ply
		w.players [#w.players + 1] = ply
		return ply
	end
	w.ply = Player (1, RED)
	w.bot = Player (2, BLU, true)

	local clientHost = Host (false)
	clientHost.Send = function (data) w.wire [#w.wire + 1] = { from = w.ply, data = data } end
	w.clientRealm = Net2.New (clientHost)

	-- What the adapter reads of GMod.
	SysTime = function () return w.now end
	CurTime = SysTime
	IsEntity = function (v) return getmetatable (v) == PlayerMeta end
	IsValid = function (v) return v ~= nil and v ~= NULL end
	isvector = function (v) return getmetatable (v) == VectorMeta end
	isangle = function () return false end
	isnumber = function (v) return type (v) == "number" end
	player = { GetAll = function () return w.players end }
	team =
	{
		GetPlayers = function (number)
			local list = {}
			for _, ply in ipairs (w.players) do
				if ply.team == number then list [#list + 1] = ply end
			end
			return list
		end
	}
	GetConVar = function () return { GetInt = function () return 0 end } end
	ErrorNoHalt = function (text) w.printed [#w.printed + 1] = text end
	hook =
	{
		Add = function (name, _, fn)
			if name == "Think" then w.thinks [#w.thinks + 1] = fn end
		end,
		Run = function (name, event, fields, count)
			if name == "WSGameEventFired" then w.fired [#w.fired + 1] = { name = event, count = count } end
		end
	}

	-- The adapter for one realm: net2's functions on that realm, as the
	-- module's are in the game.
	local function Load (realm, server)
		SERVER, CLIENT = server, not server
		net2 = {}
		for _, method in ipairs ({ "Send", "Receive", "Accept", "OnReady", "Registry" }) do
			net2 [method] = function (...) return realm [method] (realm, ...) end
		end
		WS = { Events = nil }
		dofile (ADAPTER)
		return WS.Events, WS
	end
	w.server, w.serverWS = Load (w.serverRealm, true)
	w.client, w.clientWS = Load (w.clientRealm, false)

	function w:Pump ()
		local wire = self.wire
		self.wire = {}
		for _, m in ipairs (wire) do
			if m.from then self.serverRealm:Incoming (m.data, m.from) else self.clientRealm:Incoming (m.data) end
		end
	end

	function w:Step (n)
		for _ = 1, n or 1 do
			self.now = self.now + 0.015
			for _, think in ipairs (self.thinks) do think () end
			self.serverRealm:Tick ()
			self.clientRealm:Tick ()
			self:Pump ()
		end
	end

	-- The same definition in both realms, as a shared file makes it.
	function w:Define (name, fields, options)
		for _, realm in ipairs ({ self.server, self.client }) do realm.Define (name, fields, options) end
	end

	-- The client joins and is ready.
	function w:Join ()
		self.clientRealm:Start ()
		self:Step (4)
	end

	return w
end

local function Hear (events, name)
	local heard = {}
	events.Listen (name, "test", function (fields, ply) heard [#heard + 1] = { fields = fields, ply = ply } end)
	return heard
end

local RATE =
{
	count = 2,
	seconds = 10
}

T.test ("the server's listeners hear an event at once, a ready client's with its defaults filled", function ()
	local w = World ()
	local E = w.server
	w:Define ("game_point", { cp = E.UInt (8), name = E.String (), icon = E.Default (E.String (), "none") })
	local onServer, onClient = Hear (w.server, "game_point"), Hear (w.client, "game_point")
	w:Join ()
	w.server.Fire ("game_point", { cp = 3, name = "the well" })
	T.eq (#onServer, 1, "the server at once")
	T.eq (#onClient, 0, "the client not before the tick")
	w:Step ()
	T.eq (#onClient,                1,            "the client after it")
	T.eq (onClient [1].fields.cp,   3,            "a number")
	T.eq (onClient [1].fields.name, "the well",   "a string")
	T.eq (onClient [1].fields.icon, "none",       "the default")
	T.eq (w.fired [#w.fired].name,  "game_point", "the debugger's hook told")
	T.eq (w.fired [#w.fired].count, 1,            "of one recipient: the bot is sent nothing")
end)

T.test ("an event's fields are held to its definition before anything hears it", function ()
	local w = World ()
	local E = w.server
	w:Define ("game_point", { cp = E.UInt (8) })
	local heard = Hear (w.server, "game_point")
	T.eq (pcall (w.server.Fire, "game_point", { cp = "three" }), false, "a wrong type raises")
	T.eq (pcall (w.server.Fire, "game_nothing", {}),             false, "an event not defined raises")
	T.eq (#heard,                                                0,     "nothing heard")
end)

T.test ("a client is ready once the server has answered it, and is sent nothing before", function ()
	local w = World ()
	local E = w.server
	w:Define ("game_point", { cp = E.UInt (8) })
	local onClient = Hear (w.client, "game_point")
	local ready = Hear (w.server, "system_client_ready")
	w.server.Fire ("game_point", { cp = 1 })
	w:Step ()
	T.eq (#onClient,                  0,     "not ready: not sent")
	T.eq (w.fired [#w.fired].count,   0,     "and not counted a recipient")
	T.eq (w.serverWS.IsReady (w.ply), false, "not ready on the server")
	T.eq (w.clientWS.LocalReady (),   false, "nor on the client")
	w:Join ()
	T.eq (#ready,                     1,     "the server heard system_client_ready")
	T.eq (ready [1].ply,              w.ply, "with the player")
	T.eq (w.serverWS.IsReady (w.ply), true,  "ready on the server")
	T.eq (w.clientWS.LocalReady (),   true,  "and on the client")
	w.server.Fire ("game_point", { cp = 2 })
	w:Step ()
	T.eq (onClient [1].fields.cp, 2, "sent from then on")
end)

T.test ("recipients pick who is sent it", function ()
	local w = World ()
	local E = w.server
	w:Define ("game_point", { cp = E.UInt (8) })
	local onClient = Hear (w.client, "game_point")
	w:Join ()
	w.server.Fire ("game_point", { cp = 1 }, BLU)
	w.server.Fire ("game_point", { cp = 2 }, RED)
	w.server.Fire ("game_point", { cp = 3 }, w.ply)
	w.server.Fire ("game_point", { cp = 4 }, { w.bot })
	w:Step ()
	T.eq (#onClient,              2, "its team's and its own")
	T.eq (onClient [1].fields.cp, 2, "its team's")
	T.eq (onClient [2].fields.cp, 3, "its own")
end)

T.test ("a client's request reaches the server's listeners with its sender, within its rate", function ()
	local w = World ()
	local E = w.server
	w:Define ("game_choice", { choice = E.UInt (4) }, { clientSendable = true, rate = RATE })
	local heard = Hear (w.server, "game_choice")
	local onClient = Hear (w.client, "game_choice")
	w:Join ()
	for n = 1, 4 do w.client.Request ("game_choice", { choice = n }) end
	w:Step (2)
	T.eq (#heard,                  2,     "two within the rate")
	T.eq (heard [1].ply,           w.ply, "with its sender")
	T.eq (heard [2].fields.choice, 2,     "in order")
	T.eq (#onClient,               0,     "a request runs no listener of the client's")
end)

T.test ("only a client-sendable event is taken from a client, and only one that fits its definition", function ()
	local w = World ()
	local E = w.server
	w:Define ("game_choice", { choice = E.UInt (4) }, { clientSendable = true, rate = { count = 50, seconds = 1 } })
	w:Define ("game_point", { cp = E.UInt (8) })
	local choices, points = Hear (w.server, "game_choice"), Hear (w.server, "game_point")
	w:Join ()
	T.eq (pcall (w.client.Request, "game_point", { cp = 1 }),        false, "a request of another raises on the client")
	T.eq (pcall (w.client.Request, "game_choice", { choice = "x" }), false, "as does one that does not fit")
	-- a client that skips the adapter's checks
	w.clientRealm:Send ("game_point",  { cp = 1 })
	w.clientRealm:Send ("game_choice", { choice = "x" })
	w.clientRealm:Send ("game_choice", { choice = 99 })
	w.clientRealm:Send ("game_choice", { choice = 1, extra = true })
	w.clientRealm:Send ("game_choice", {})
	w:Step (2)
	T.eq (#points,  0, "an event not client-sendable is not taken")
	T.eq (#choices, 0, "nor a request that does not fit")
	w.client.Request ("game_choice", { choice = 5 })
	w:Step (2)
	T.eq (choices [1].fields.choice, 5, "a good one after is")
end)

T.test ("a request made before the client is ready is sent once it is", function ()
	local w = World ()
	local E = w.server
	w:Define ("game_choice", { choice = E.UInt (4) }, { clientSendable = true, rate = RATE })
	local heard = Hear (w.server, "game_choice")
	w.client.Request ("game_choice", { choice = 7 })
	w:Step (2)
	T.eq (#heard, 0, "held")
	w:Join ()
	w:Step (2)
	T.eq (#heard,                  1, "sent")
	T.eq (heard [1].fields.choice, 7, "as asked")
end)

T.test ("a transaction's answer comes back to the client that asked", function ()
	local w = World ()
	local E = w.server
	local options = { clientSendable = true, rate = { count = 10, seconds = 1 }, transaction = true }
	w:Define ("game_buy", { item = E.String () }, options)
	w.server.Serve ("game_buy", "test", { [SOLD_OUT] = true }, function (_, fields)
		if fields.item ~= "hat" then Transaction.Refuse (SOLD_OUT, fields.item) end
	end)
	w:Join ()
	local bought = w.client.Transact ("game_buy", { item = "hat" })
	local refused = w.client.Transact ("game_buy", { item = "shoe" })
	w:Step (6)
	T.eq (bought:State (),                                                   Transaction.COMMITTED, "committed")
	T.eq (refused:State (),                                                  Transaction.DECLINED, "declined")
	T.eq (Transaction.IsRefusal (refused:Refusal (), { [SOLD_OUT] = true }), true, "with the server's refusal")
end)

-- A Define as a feature's shared file makes it, from where that file lives.
local function DefineIn (events, file, name, fields)
	local code = "local E, fields = ... E.Define (" .. string.format ("%q", name) .. ", fields)"
	local chunk = assert (load (code, "@" .. file))
	chunk (events, fields)
end

local CAPTURE = "addons/sandcastle/gamemodes/wetsands/gamemode/features/capture/sh.lua"

T.test ("each definition is registered with net2, a feature's in a registry of its own", function ()
	local w = World ()
	local E = w.server
	local mismatches = {}
	w.serverRealm:OnMismatch ("test", function (name, policy) mismatches [#mismatches + 1] = name .. ":" .. policy end)
	w:Define ("game_point", { cp = E.UInt (8) })
	DefineIn (w.server, CAPTURE, "game_captured", { team = E.Team () })
	DefineIn (w.client, CAPTURE, "game_captured", { team = E.Team () })
	T.eq (w.serverRealm.registryOf.game_point,    "wetsands",         "the core's in wetsands")
	T.eq (w.serverRealm.registryOf.game_captured, "wetsands/capture", "a feature's in its own")
	w:Join ()
	w:Step (2)
	T.eq (#mismatches, 0, "the same definitions match")
	-- the client's copy of the feature changed
	DefineIn (w.client, CAPTURE, "game_captured", { team = E.Team (), cp = E.UInt (8) })
	w:Step (3)
	T.eq (mismatches [1], "wetsands/capture:warn", "found, and warned of")
	T.eq (#mismatches,    1,                       "the core's registry still matches")
end)

T.finish ()
