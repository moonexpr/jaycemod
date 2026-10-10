-- The cart HUD's model: the order the carts are drawn in, the wire format
-- of the lists the payload controller networks per cart (ws_cart_<i>_
-- cps, owners and hills, as strings), and what the payload view shows on
-- each cart's icon. Both ends use it, so they agree.
local ipairs, math, string, table, tonumber = ipairs, math, string, table, tonumber
local Payload = require("foundation.payload")
module(...)

POSITION_FORMAT = "%.4f" -- a checkpoint's fraction of the track
OWNER_FORMAT = "%d" -- a checkpoint owner's team

local LIST_SEPARATOR = ","
local HILL_SEPARATOR = ";"
local HILL_FORMAT = "%.4f:%.4f:%d"
local HILL_PATTERN = "([^:]+):([^:]+):(%d)"
local DOWNHILL, UPHILL = 1, 0

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

-- What TF2's escort HUD (CTFHudEscort) shows on the cart's icon: blocked
-- while the enemy stands on it, rolling back (the watcher's speed level
-- below 0), its pushers (the capture icon and their count), or, idle, the
-- seconds until it rolls back. cart = { speed, cappers, recedeAt,
-- canRecede }. Returns { blocked, backwards, cappers, recede }, each nil
-- when not shown.
function Indicator(cart, now)
	if cart.cappers == Payload.CAPPERS_BLOCKED then return { blocked = true } end
	if cart.speed < 0 then return { backwards = true } end
	if cart.cappers > 0 then return { cappers = cart.cappers } end
	if cart.recedeAt > 0 and cart.canRecede then return { recede = math.max(0, math.ceil(cart.recedeAt - now)) } end
	return {}
end
