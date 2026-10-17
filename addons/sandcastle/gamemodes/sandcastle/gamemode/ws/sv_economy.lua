-- Money (foundation.economy): an account for every player as they join and
-- every NPC as it joins a team (WS.SetTeamMember), each opened at
-- $2,000 and closed when its entity goes. Balances reach clients as the NW2
-- int ws_money (the scoreboard's Money column). Everything else earns
-- and spends through WS.EarnMoney and WS.SpendMoney, which raise a
-- refusal (Economy.INSUFFICIENT_FUNDS, foundation.refusal) rather than overdraw.
local Economy = WS.require("foundation.economy")
local Refusal = WS.require("foundation.refusal")

local ledger = Economy.New()

local function Sync(ent)
	ent:SetNW2Int("ws_money", Economy.Balance(ledger, ent))
end

function WS.OpenAccount(ent)
	Economy.Open(ledger, ent)
	Sync(ent)
end

function WS.Money(ent)
	return Economy.Balance(ledger, ent)
end

function WS.CanAfford(ent, amount)
	return Economy.CanAfford(ledger, ent, amount)
end

-- WSMoneyEarned(ent, amount) tells whoever counts earnings (the round's
-- cash limit, foundation.rounds.limits). With the economy off, money stops
-- counting: nothing is earned.
function WS.EarnMoney(ent, amount)
	if not WS.EconomyEnabled() then return end
	Economy.Earn(ledger, ent, amount)
	Sync(ent)
	hook.Run("WSMoneyEarned", ent, amount)
end

local function Open()
	if not WS.EconomyEnabled() then Refusal.Raise(Economy.ECONOMY_OFF, "Money is switched off on this server.") end
end

-- A purchase: on credit where it is allowed (WS.CreditFloor).
function WS.SpendMoney(ent, amount)
	Open()
	Economy.SpendWithCredit(ledger, ent, amount, WS.CreditFloor())
	Sync(ent)
end

-- A player giving money to another; it is not earned, so it never counts
-- toward a round's cash limit, and never on credit.
function WS.TransferMoney(from, to, amount)
	Open()
	Economy.Transfer(ledger, from, to, amount)
	Sync(from)
	Sync(to)
end

-- Money an admin grants; not earned either.
function WS.GrantMoney(ent, amount)
	Economy.Earn(ledger, ent, amount)
	Sync(ent)
end

hook.Add("PlayerInitialSpawn", "ws_economy", WS.OpenAccount)
hook.Add("EntityRemoved", "ws_economy", function(ent) Economy.Close(ledger, ent) end)

-- A reload of this file starts a new ledger: the players already here get accounts.
for _, ply in player.Iterator() do WS.OpenAccount(ply) end
