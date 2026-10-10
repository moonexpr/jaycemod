-- Money: every player and every NPC that fights for a team holds an
-- account, opened at STARTING_MONEY. Earning adds to it; spending refuses
-- (InsufficientFunds) rather than overdraw it. Accounts are kept by whatever
-- key the controller gives (ws/sv_economy.lua keys them by entity) and
-- last until closed, so a respawn or a team change keeps a player's money.
local error, floor, format, reverse, setmetatable, tostring, type =
	error, math.floor, string.format, string.reverse, setmetatable, tostring, type
local gsub = string.gsub
module(...)

STARTING_MONEY = 2000

-- The refusal Spend raises: the caller asked for more than the account holds.
InsufficientFunds = {}
InsufficientFunds.__index = InsufficientFunds
InsufficientFunds.__tostring = function(e)
	return format("insufficient funds: %d wanted, %d held", e.wanted, e.held)
end

local Bank = {}
Bank.__index = Bank

function New()
	return setmetatable({ balances = {} }, Bank)
end

local function Amount(amount)
	if type(amount) ~= "number" or amount < 0 or amount ~= floor(amount) then
		error("not a whole, non-negative amount: " .. tostring(amount), 3)
	end
	return amount
end

local function Held(bank, key)
	local held = bank.balances[key]
	if held == nil then error("no account for " .. tostring(key), 3) end
	return held
end

-- Opens an account at STARTING_MONEY; an open one keeps its money.
function Bank:Open(key)
	if self.balances[key] == nil then self.balances[key] = STARTING_MONEY end
end

function Bank:Close(key)
	self.balances[key] = nil
end

function Bank:Has(key)
	return self.balances[key] ~= nil
end

function Bank:Balance(key)
	return Held(self, key)
end

function Bank:CanAfford(key, amount)
	return Held(self, key) >= Amount(amount)
end

function Bank:Earn(key, amount)
	self.balances[key] = Held(self, key) + Amount(amount)
end

function Bank:Spend(key, amount)
	local held, wanted = Held(self, key), Amount(amount)
	if wanted > held then
		error(setmetatable({
			wanted = wanted,
			held = held,
		}, InsufficientFunds), 2)
	end
	self.balances[key] = held - wanted
end

-- $1,234,567
function Format(amount)
	local grouped = reverse((gsub(reverse(tostring(amount)), "(%d%d%d)", "%1,")))
	return "$" .. gsub(grouped, "^,", "")
end
