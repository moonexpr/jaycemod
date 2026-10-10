-- The cart HUD's model: the order the carts are drawn in, the wire format
-- of the lists the payload controller networks per cart (ws_cart_<i>_
-- cps, owners and hills, as strings), and the status line the payload view
-- draws above each cart's bar. Both ends use it, so they agree.
local ipairs, math, string, table, tonumber = ipairs, math, string, table, tonumber
local Payload = require("foundation.payload")
module(...)

POSITION_FORMAT = "%.4f" -- a checkpoint's fraction of the track
OWNER_FORMAT = "%d" -- a checkpoint owner's team
BLOCKED = "BLOCKED"

local LIST_SEPARATOR = ","
local HILL_SEPARATOR = ";"
local HILL_FORMAT = "%.4f:%.4f:%d"
local HILL_PATTERN = "([^:]+):([^:]+):(%d)"
local DOWNHILL, UPHILL = 1, 0
local STATUS_SEPARATOR = "  "
local ARROW_FORWARD, ARROW_BACK = ">", "<"

-- carts = { { team, index }... } (index: the watcher's entity index). A new
-- list: higher team numbers first, so BLU's cart (3) above RED's (2), then
-- by index, so the order holds from one publish to the next.
function Order(carts)
	local list = {}
	for i, cart in ipairs(carts) do list[i] = cart end
	table.sort(list, function(a, b)
		if a.team ~= b.team then return a.team > b.team end
		return a.index < b.index
	end)
	return list
end

function EncodeNumbers(list, format)
	local parts = {}
	for i, v in ipairs(list) do parts[i] = string.format(format, v) end
	return table.concat(parts, LIST_SEPARATOR)
end

function DecodeNumbers(text)
	local list = {}
	for part in string.gmatch(text, "[^" .. LIST_SEPARATOR .. "]+") do list[#list + 1] = tonumber(part) end
	return list
end

-- hills = { { from, to, down }... }, fractions of the track (Payload.HillSegments).
function EncodeHills(hills)
	local parts = {}
	for i, h in ipairs(hills) do
		parts[i] = string.format(HILL_FORMAT, h.from, h.to, h.down and DOWNHILL or UPHILL)
	end
	return table.concat(parts, HILL_SEPARATOR)
end

function DecodeHills(text)
	local hills = {}
	for part in string.gmatch(text, "[^" .. HILL_SEPARATOR .. "]+") do
		local from, to, down = string.match(part, HILL_PATTERN)
		if from then
			hills[#hills + 1] = {
				from = tonumber(from),
				to = tonumber(to),
				down = tonumber(down) == DOWNHILL,
			}
		end
	end
	return hills
end

-- The line above a cart's bar: the speed arrows (the watcher's speed level),
-- the pushers, and the rollback countdown; or BLOCKED while the enemy stands
-- on the cart. cart = { speed, cappers, recedeAt, canRecede }.
function Status(cart, now)
	if cart.cappers == Payload.CAPPERS_BLOCKED then return BLOCKED end
	local parts = {}
	if cart.speed > 0 then parts[#parts + 1] = string.rep(ARROW_FORWARD, cart.speed) end
	if cart.speed < 0 then parts[#parts + 1] = ARROW_BACK end
	if cart.cappers > 0 then parts[#parts + 1] = "x" .. cart.cappers end
	if cart.recedeAt > 0 and cart.canRecede then
		parts[#parts + 1] = "Rolls back in " .. math.max(0, math.ceil(cart.recedeAt - now))
	end
	return table.concat(parts, STATUS_SEPARATOR)
end
