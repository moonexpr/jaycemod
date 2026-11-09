-- Choices made with a random number the caller draws and passes in, so a
-- choice is repeatable in a test.
-- This is the Lua twin, which clients run; a server with native/foundation
-- has the native one in its place, which keeps this contract.
local ipairs = ipairs
module(...)

-- An item of the list picked with odds by weight: r in [0, 1).
function PickWeighted(items, Weight, r)
	local total = 0
	for _, item in ipairs(items) do total = total + Weight(item) end
	if total <= 0 then return items[1] end
	local target = r * total
	for _, item in ipairs(items) do
		target = target - Weight(item)
		if target < 0 then return item end
	end
	return items[#items]
end
