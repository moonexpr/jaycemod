-- Choices made with a random number the caller draws and passes in, so a
-- choice is repeatable in a test.
-- Core-rule exception: stays Lua. PickWeighted calls the caller's weight
-- back for each item (49 ns for ten), which a native twin would cross back
-- into Lua for.
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
