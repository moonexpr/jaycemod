-- The game event library's realm adapter (docs/game-events.md): the
-- foundation.events registry carried on GMod's net library, as
-- WS.Events. Every message between server and clients is an event, on
-- one of this file's two net messages; nothing else registers one.
--
--   Define(name, fields, options)   both realms, where the feature loads
--   Listen(name, id, fn), Ignore(name, id)   both realms; fn(fields[, ply])
--   Fire(name, fields, recipients)  server: its listeners, then the clients
--   Request(name, fields)           client: a client-sendable event to the server
--   Transact(name, fields) -> tx    client: a transaction request (option
--                                   transaction); tx (foundation.core.transaction)
--                                   settles from the server's reply, or
--                                   declines as timed out
--   Serve(name, id, kinds, handler) server: handler(work, fields, ply) runs as
--                                   a transaction on WS.Transactions; its
--                                   outcome goes back to the sender. kinds
--                                   are the refusals that are the player's
--                                   mistake; a decline of any other kind is
--                                   our bug, logged and answered as failed
--
-- WS.Transactions is each realm's scheduler (foundation.core.scheduler) for
-- transactions and other work spread over ticks, run TRANSACTION_SECONDS a
-- tick. A transaction's reply, transaction_settled, belongs to this library,
-- not to the game's events: like the recovery events it changes with the
-- library (docs/game-events-v2.md).
--
-- and the field types (String, Bool, UInt(bits), Int(bits), Float, Entity,
-- Vector, Angle, Team, List(type, countBits), Record(fields), Optional(type),
-- Default(type, value)). Included by sh_core.lua, before anything that
-- defines an event.
local Events = WS.require("foundation.events")
local Scheduler = WS.require("foundation.core.scheduler")
local Transaction = WS.require("foundation.core.transaction")

local FIRE_NET = "ws_game_event_fire" -- server to clients
local REQUEST_NET = "ws_game_event_request" -- client to server

-- A client says it is ready once, and may repeat it after a Lua refresh.
local CLIENT_READY_RATE = {
	count = 2,
	seconds = 10,
}

-- Kept across a Lua refresh: features define their events once, as they load.
WS.EventRegistry = WS.EventRegistry or Events.NewRegistry({
	entity = IsEntity,
	vector = isvector,
	angle = isangle,
})
local registry = WS.EventRegistry

local API = {}
WS.Events = API

for _, name in ipairs({ "String", "Bool", "UInt", "Int", "Float", "Entity", "Vector", "Angle", "Team", "List", "Record", "Optional", "Default" }) do
	API[name] = Events[name]
end

-- The core raises named errors (tables); GMod reports a string best, at
-- the line that called the API.
local function Checked(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then error(tostring(result), 3) end
	return result
end

function API.Define(name, fields, options)
	Checked(registry.Define, registry, name, fields, options)
end

function API.Listen(name, id, fn)
	Checked(registry.Listen, registry, name, id, fn)
end

function API.Ignore(name, id)
	registry:Ignore(name, id)
end

-- Whether a player's client has loaded (its client_ready request): events
-- go only to ready clients, since net messages sent earlier are lost.
function WS.IsReady(ply)
	return ply.wsReady == true
end

local TRANSACTION_SECONDS = 0.001
local TRANSACTION_TIMEOUT = 10 -- seconds a client waits for a reply
local TRANSACTION_HOOK = "ws_transactions"

local Clock = {}
function Clock:Now() return SysTime() end

-- Kept across a Lua refresh: tasks in flight keep running.
WS.Transactions = WS.Transactions or Scheduler.New(Clock)
hook.Add("Think", TRANSACTION_HOOK, function() WS.Transactions:Run(TRANSACTION_SECONDS) end)

-- A transaction's outcome, to the client that asked: its state, and for a
-- decline the refusal's kind and detail (never our error's).
API.Define("transaction_settled", {
	[Events.TRANSACTION_FIELD] = Events.UInt(Transaction.ID_BITS),
	state = Events.String(),
	kind = Events.Optional(Events.String()),
	detail = Events.Optional(Events.String()),
})

-- Sent by a client as it finishes loading (InitPostEntity); a fresh join and
-- a returning player alike.
API.Define("client_ready", {}, {
	clientSendable = true,
	rate = CLIENT_READY_RATE,
})

if SERVER then
	util.AddNetworkString(FIRE_NET)
	util.AddNetworkString(REQUEST_NET)

	local DEVELOPER = GetConVar("developer")

	local function Listed(list)
		local players = {}
		for _, ply in ipairs(list) do
			if IsValid(ply) and not ply:IsBot() and WS.IsReady(ply) then players[#players + 1] = ply end
		end
		return players
	end

	-- recipients: nil for every player, a team number, a player, a list of
	-- players, or a Vector for the players whose PVS holds it.
	local function Recipients(recipients)
		if recipients == nil then return Listed(player.GetAll()) end
		if isnumber(recipients) then return Listed(team.GetPlayers(recipients)) end
		if isvector(recipients) then
			local filter = RecipientFilter()
			filter:AddPVS(recipients)
			return Listed(filter:GetPlayers())
		end
		if IsEntity(recipients) then return Listed({ recipients }) end
		return Listed(recipients)
	end

	-- The server's own listeners hear it first, then the ready clients among
	-- the recipients. WSGameEventFired tells the dev server's debugger
	-- (.devtools/bin/server_root/sandcastle_debug.lua), which keeps the newest.
	function API.Fire(name, fields, recipients)
		local event = Checked(registry.Build, registry, name, fields or {})
		registry:Dispatch(event)
		local players = Recipients(recipients)
		hook.Run("WSGameEventFired", name, event.fields, #players)
		if #players == 0 then return end
		net.Start(FIRE_NET, event.definition.unreliable)
		registry:Write(event, net)
		net.Send(players)
	end

	-- A request the model refuses is the client's mistake: dropped, and
	-- shown only with developer on.
	net.Receive(REQUEST_NET, function(_, ply)
		local event, refusal = registry:ReadRequest(ply, net, CurTime())
		if not event then
			if DEVELOPER:GetInt() > 0 then print(string.format("game event request from %s refused: %s", tostring(ply), tostring(refusal))) end
			return
		end
		registry:Dispatch(event, ply)
	end)

	API.Listen("client_ready", "ws_events", function(_, ply)
		ply.wsReady = true
	end)

	-- Our failures are logged here, once, with the request that met them.
	function API.Serve(name, id, kinds, handler)
		local definition = Checked(registry.Definition, registry, name)
		if not definition.transaction then error(name .. " is not a transaction (Define it with transaction = true)", 2) end
		API.Listen(name, id, function(fields, ply)
			local tx = Transaction.Spawn(WS.Transactions, handler, fields, ply)
			tx:OnSettle(function(settled)
				local reply = Transaction.Reply(settled, kinds)
				if settled:State() == Transaction.DECLINED and reply.state == Transaction.FAILED then
					ErrorNoHalt(string.format("transaction %s from %s refused with no player's refusal: %s\n", name, tostring(ply), Transaction.Message(settled:Refusal())))
				elseif settled:State() == Transaction.FAILED then
					ErrorNoHalt(string.format("transaction %s from %s failed: %s\n", name, tostring(ply), tostring(settled:Error())))
				end
				if not IsValid(ply) then return end
				reply[Events.TRANSACTION_FIELD] = fields[Events.TRANSACTION_FIELD]
				API.Fire("transaction_settled", reply, ply)
			end)
		end)
	end
else
	function API.Request(name, fields)
		local event = Checked(registry.BuildRequest, registry, name, fields or {})
		net.Start(REQUEST_NET, event.definition.unreliable)
		registry:Write(event, net)
		net.SendToServer()
	end

	-- Kept across a Lua refresh, so replies still find their transactions.
	WS.TransactionLedger = WS.TransactionLedger or Transaction.Ledger()
	local ledger = WS.TransactionLedger

	function API.Transact(name, fields)
		local id, tx = ledger:Open(SysTime(), TRANSACTION_TIMEOUT)
		local request = { [Events.TRANSACTION_FIELD] = id }
		for key, value in pairs(fields or {}) do request[key] = value end
		API.Request(name, request)
		return tx
	end

	API.Listen("transaction_settled", "ws_events", function(fields)
		ledger:Settle(fields[Events.TRANSACTION_FIELD], fields)
	end)

	hook.Add("Think", "ws_transaction_ledger", function()
		if ledger:Count() > 0 then ledger:Expire(SysTime()) end
	end)

	-- An event this client has no definition of means the realms disagree:
	-- the error names its id.
	net.Receive(FIRE_NET, function()
		registry:Dispatch(Checked(registry.Read, registry, net))
	end)

	-- Whether this client has loaded: net messages reach it from
	-- InitPostEntity on.
	function WS.LocalReady()
		return WS.localReady == true
	end

	hook.Add("InitPostEntity", "ws_events", function()
		WS.localReady = true
		API.Request("client_ready")
	end)
end
