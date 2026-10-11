-- Money (foundation.economy): an account for every player as they join and
-- every NPC as it joins a team (WS.SetTeamMember), each opened at
-- $2,000 and closed when its entity goes. Balances reach clients as the NW2
-- int ws_money (the scoreboard's Money column). Everything else earns
-- and spends through WS.EarnMoney and WS.SpendMoney, which raise a
-- refusal (Economy.INSUFFICIENT_FUNDS, foundation.refusal) rather than overdraw.
local Economy = WS.require("foundation.economy")

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
-- cash limit, foundation.rounds.limits).
function WS.EarnMoney(ent, amount)
	Economy.Earn(ledger, ent, amount)
	Sync(ent)
	hook.Run("WSMoneyEarned", ent, amount)
end

function WS.SpendMoney(ent, amount)
	Economy.Spend(ledger, ent, amount)
	Sync(ent)
end

hook.Add("PlayerInitialSpawn", "ws_economy", WS.OpenAccount)
hook.Add("EntityRemoved", "ws_economy", function(ent) Economy.Close(ledger, ent) end)

-- A reload of this file starts a new ledger: the players already here get accounts.
for _, ply in player.Iterator() do WS.OpenAccount(ply) end
