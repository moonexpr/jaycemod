-- Money (foundation.economy): an account for every player as they join and
-- every NPC as it joins a team (WS.SetTeamMember), each opened at
-- $2,000 and closed when its entity goes. Balances reach clients as the NW2
-- int ws_money (the scoreboard's Money column). Everything else earns
-- and spends through WS.EarnMoney and WS.SpendMoney, which raise
-- Economy.InsufficientFunds rather than overdraw.
local Economy = WS.require("foundation.economy")

local bank = Economy.New()

local function Sync(ent)
	ent:SetNW2Int("ws_money", bank:Balance(ent))
end

function WS.OpenAccount(ent)
	bank:Open(ent)
	Sync(ent)
end

function WS.Money(ent)
	return bank:Balance(ent)
end

function WS.CanAfford(ent, amount)
	return bank:CanAfford(ent, amount)
end

-- WSMoneyEarned(ent, amount) tells whoever counts earnings (the round's
-- cash limit, foundation.rounds.limits).
function WS.EarnMoney(ent, amount)
	bank:Earn(ent, amount)
	Sync(ent)
	hook.Run("WSMoneyEarned", ent, amount)
end

function WS.SpendMoney(ent, amount)
	bank:Spend(ent, amount)
	Sync(ent)
end

hook.Add("PlayerInitialSpawn", "ws_economy", WS.OpenAccount)
hook.Add("EntityRemoved", "ws_economy", function(ent) bank:Close(ent) end)

-- A reload of this file starts a new bank: the players already here get accounts.
for _, ply in player.Iterator() do WS.OpenAccount(ply) end
