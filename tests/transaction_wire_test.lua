-- A transaction across the wire, headless: the client's ledger opens it, the
-- request carries its id through the event registry, the server runs the
-- handler as a task and replies, and the reply settles the client's
-- transaction. The pieces ws/sh_events.lua's Transact and Serve join.
local T = dofile("tests/harness.lua")
local Events = T.require("games.system.events")
local Scheduler = T.require("foundation.list.schedule")
local Transaction = T.require("foundation.transaction")

local RATE = {
	count = 10,
	seconds = 1,
}
local SOLD_OUT = "sold out"
local PLAYER = { [SOLD_OUT] = true }

-- A wire that hands each written value to the reader in order.
local function Wire()
	local queue, head = {}, 1
	local wire = {}
	for _, kind in ipairs({ "UInt", "Int", "String", "Bool", "Float" }) do
		wire["Write" .. kind] = function(value) queue[#queue + 1] = value end
		wire["Read" .. kind] = function()
			local value = queue[head]
			head = head + 1
			return value
		end
	end
	return wire
end

local function Define(registry)
	registry:Define("game_buy", { item = Events.String() }, {
		clientSendable = true,
		rate = RATE,
		transaction = true,
	})
	registry:Define("system_transaction_settled", {
		[Events.TRANSACTION_FIELD] = Events.UInt(Transaction.ID_BITS),
		state = Events.String(),
		kind = Events.Optional(Events.String()),
		detail = Events.Optional(Events.String()),
	})
end

-- A client and a server joined by wires; handler(work, fields) serves "game_buy".
local function Pair(handler)
	local clock = { Now = function() return 0 end }
	local pair = {
		client = Events.NewRegistry({}),
		server = Events.NewRegistry({}),
		ledger = Transaction.Ledger(),
		scheduler = Scheduler.New(clock),
	}
	Define(pair.client)
	Define(pair.server)
	function pair:Transact(fields)
		local id, tx = self.ledger:Open(0, 10)
		fields[Events.TRANSACTION_FIELD] = id
		local up = Wire()
		self.client:Write(self.client:BuildRequest("game_buy", fields), up)
		local request = self.server:ReadRequest("ply", up, 0)
		local served = Transaction.Spawn(self.scheduler, handler, request.fields)
		served:OnSettle(function(settled)
			local reply = Transaction.Reply(settled, PLAYER)
			reply[Events.TRANSACTION_FIELD] = request.fields[Events.TRANSACTION_FIELD]
			local down = Wire()
			self.server:Write(self.server:Build("system_transaction_settled", reply), down)
			local fields = self.client:Read(down).fields
			self.ledger:Settle(fields[Events.TRANSACTION_FIELD], fields)
		end)
		return tx
	end
	return pair
end

T.test("a served request commits on the client once the server's task runs", function()
	local pair = Pair(function(work, fields) return fields.item end)
	local tx = pair:Transact({ item = "hat" })
	T.eq(tx:State(), Transaction.PENDING, "asynchronous: the server has not run it")
	pair.scheduler:Run(1)
	T.eq(tx:State(), Transaction.COMMITTED, "committed")
	T.eq(pair.ledger:Count(), 0, "closed")
end)

T.test("a player's refusal reaches the client with its kind and detail, the server's steps undone", function()
	local refunded = false
	local pair = Pair(function(work)
		work:Undo(function() refunded = true end)
		Transaction.Refuse(SOLD_OUT, "None left.")
	end)
	local tx = pair:Transact({ item = "hat" })
	pair.scheduler:Run(1)
	T.eq(tx:State(), Transaction.DECLINED, "declined")
	T.eq(Transaction.Message(tx:Refusal()), "sold out: None left.", "the refusal")
	T.eq(refunded, true, "undone on the server")
end)

T.test("our bug, and a refusal not the player's, reach the client only as failed", function()
	local pair = Pair(function() error("secret") end)
	local tx = pair:Transact({ item = "hat" })
	pair.scheduler:Run(1)
	T.eq(tx:State(), Transaction.FAILED, "failed")
	pair = Pair(function() Transaction.Refuse("bad catalog", "internal") end)
	tx = pair:Transact({ item = "hat" })
	pair.scheduler:Run(1)
	T.eq(tx:State(), Transaction.FAILED, "a catalog refusal is our bug")
end)

T.test("transactions in flight settle by their own ids", function()
	local pair = Pair(function(work, fields)
		if fields.item == "bad" then Transaction.Refuse(SOLD_OUT, "no") end
	end)
	local good, bad = pair:Transact({ item = "good" }), pair:Transact({ item = "bad" })
	pair.scheduler:Run(1)
	T.eq(good:State(), Transaction.COMMITTED, "the first")
	T.eq(bad:State(), Transaction.DECLINED, "the second")
end)

T.finish()
