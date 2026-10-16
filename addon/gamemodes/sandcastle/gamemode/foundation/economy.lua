-- Money: every player and every NPC that fights for a team holds an
-- account, opened at STARTING_MONEY. Earning adds to it; spending refuses
-- (INSUFFICIENT_FUNDS) rather than overdraw it. Accounts are kept by whatever
-- key the controller gives (ws/sv_economy.lua keys them by entity) and
-- last until closed, so a respawn or a team change keeps a player's money.
-- A ledger is plain data with no metatable, so a rerun of this module
-- changes the behaviour of the live ledger too.
local error, floor, format, reverse, tostring, type =
	error, math.floor, string.format, string.reverse, tostring, type
local gsub = string.gsub
local Refusal = require("foundation.refusal")
module(...)

STARTING_MONEY = 2000

-- The refusal Spend raises: the caller asked for more than the account holds.
INSUFFICIENT_FUNDS = "insufficient funds"
-- The refusals Transfer adds: giving to yourself, or giving nothing.
SELF_TRANSFER = "self transfer"
NO_AMOUNT = "no amount"

-- The refusals that are the player's mistake.
PLAYER = {
	[INSUFFICIENT_FUNDS] = true,
	[SELF_TRANSFER] = true,
	[NO_AMOUNT] = true,
}

function New()
	return { balances = {} }
end

local function Amount(amount)
	if type(amount) ~= "number" or amount < 0 or amount ~= floor(amount) then
		error("not a whole, non-negative amount: " .. tostring(amount), 3)
	end
	return amount
end

local function Held(ledger, key)
	local held = ledger.balances[key]
	if held == nil then error("no account for " .. tostring(key), 3) end
	return held
end

-- Opens an account at STARTING_MONEY; an open one keeps its money.
function Open(ledger, key)
	if ledger.balances[key] == nil then ledger.balances[key] = STARTING_MONEY end
end

function Close(ledger, key)
	ledger.balances[key] = nil
end

function Has(ledger, key)
	return ledger.balances[key] ~= nil
end

function Balance(ledger, key)
	return Held(ledger, key)
end

function CanAfford(ledger, key, amount)
	return Held(ledger, key) >= Amount(amount)
end

function Earn(ledger, key, amount)
	ledger.balances[key] = Held(ledger, key) + Amount(amount)
end

function Spend(ledger, key, amount)
	local held, wanted = Held(ledger, key), Amount(amount)
	if wanted > held then Refusal.Raise(INSUFFICIENT_FUNDS, format("%d wanted, %d held", wanted, held)) end
	ledger.balances[key] = held - wanted
end

-- Moves amount from one account to another, all of it or none: a player
-- giving money to a teammate.
function Transfer(ledger, from, to, amount)
	if from == to then Refusal.Raise(SELF_TRANSFER, "you cannot give money to yourself") end
	if Amount(amount) == 0 then Refusal.Raise(NO_AMOUNT, "give at least $1") end
	Held(ledger, to)
	Spend(ledger, from, amount)
	Earn(ledger, to, amount)
end

-- $1,234,567
function Format(amount)
	local grouped = reverse((gsub(reverse(tostring(amount)), "(%d%d%d)", "%1,")))
	return "$" .. gsub(grouped, "^,", "")
end
