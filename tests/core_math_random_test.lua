-- foundation.core.math.random: choices made with a random number passed in.
local T = dofile("tests/harness.lua")
local Random = T.require("foundation.core.math.random")

T.test("items are picked with odds by their weight", function()
	local items = { { id = 1, w = 1 }, { id = 2, w = 3 } }
	local function W(item) return item.w end
	T.eq(Random.PickWeighted(items, W, 0).id, 1, "the start of the range")
	T.eq(Random.PickWeighted(items, W, 0.2).id, 1, "within the first quarter")
	T.eq(Random.PickWeighted(items, W, 0.3).id, 2, "past it")
	T.eq(Random.PickWeighted(items, W, 0.999).id, 2, "the end")
end)

T.finish()
