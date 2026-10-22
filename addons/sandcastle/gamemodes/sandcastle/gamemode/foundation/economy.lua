-- Money: every player and every NPC that fights for a team holds an
-- account, opened at STARTING_MONEY. Earning adds to it; spending refuses
-- (INSUFFICIENT_FUNDS) rather than overdraw it, unless spending on credit
-- (SpendWithCredit), which may go down to a floor below zero: Floor gives
-- the floor, unlimited credit with deficit spending switched on
-- (mp_economy_credit_enabled) or on a map played like Sandbox, none
-- otherwise. Accounts are kept by whatever key the controller gives
-- (ws/sv_economy.lua keys them by entity) and last until closed, so a
-- respawn or a team change keeps a player's money.
-- A ledger is plain data with no metatable, so a rerun of this module
-- changes the behaviour of the live ledger too.
local error, floor, format, reverse, tostring, type =
	error, math.floor, string.format, string.reverse, tostring, type
local gsub = string.gsub
local Transaction = require("foundation.transaction")
module(...)

STARTING_MONEY = 2000

-- The lowest balance a spend may leave: none below zero, or as low as the
-- NW2 int ws_money (signed 32-bit) carries, so a debt never wraps.
NO_CREDIT = 0
BALANCE_MIN = -2 ^ 31

-- The refusal Spend raises: the caller asked for more than the account holds.
INSUFFICIENT_FUNDS = "insufficient funds"
-- The refusals Transfer adds: giving to yourself, or giving nothing.
SELF_TRANSFER = "self transfer"
NO_AMOUNT = "no amount"
-- The economy is switched off (mp_economy_enabled 0): nothing is bought or given.
ECONOMY_OFF = "economy off"

-- The refusals that are the player's mistake.
PLAYER = {
	[INSUFFICIENT_FUNDS] = true,
	[SELF_TRANSFER] = true,
	[NO_AMOUNT] = true,
	[ECONOMY_OFF] = true,
}

-- How far below zero a purchase may take a balance.
function Floor(creditEnabled, sandbox)
	if creditEnabled or sandbox then return BALANCE_MIN end
	return NO_CREDIT
end

-- Whether a balance covers amount, going no lower than floor.
function Affords(balance, amount, floorAt)
	return balance - amount >= floorAt
end

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
	if wanted > held then Transaction.Refuse(INSUFFICIENT_FUNDS, format("%d wanted, %d held", wanted, held)) end
	ledger.balances[key] = held - wanted
end

-- Spends amount, leaving the balance no lower than floorAt (Floor's): a
-- purchase, which may go into debt where credit is allowed.
function SpendWithCredit(ledger, key, amount, floorAt)
	if type(floorAt) ~= "number" or floorAt > NO_CREDIT or floorAt ~= floor(floorAt) then
		error("not a whole floor at or below zero: " .. tostring(floorAt), 2)
	end
	local held, wanted = Held(ledger, key), Amount(amount)
	if not Affords(held, wanted, floorAt) then
		Transaction.Refuse(INSUFFICIENT_FUNDS, "You have only " .. Format(held) .. ".")
	end
	ledger.balances[key] = held - wanted
end

-- Moves amount from one account to another, all of it or none: a player
-- giving money to a teammate.
function Transfer(ledger, from, to, amount)
	if from == to then Transaction.Refuse(SELF_TRANSFER, "You cannot give money to yourself.") end
	if Amount(amount) == 0 then Transaction.Refuse(NO_AMOUNT, "Give at least $1.") end
	Held(ledger, to)
	local held = Held(ledger, from)
	if amount > held then Transaction.Refuse(INSUFFICIENT_FUNDS, "You have only " .. Format(held) .. ".") end
	Spend(ledger, from, amount)
	Earn(ledger, to, amount)
end

-- $1,234,567; a debt -$1,234.
function Format(amount)
	local sign = amount < 0 and "-" or ""
	local grouped = reverse((gsub(reverse(tostring(amount < 0 and -amount or amount)), "(%d%d%d)", "%1,")))
	return sign .. "$" .. gsub(grouped, "^,", "")
end
