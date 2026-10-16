-- foundation.combat.fixed_spread: TF2's tf_use_fixed_weaponspreads, the
-- pellets of a multi-pellet shot in a fixed pattern (g_vecFixedWpnSpreadPellets)
-- instead of at random: the first and the tenth down the middle, the rest
-- in a cross and a square around it, scaled by half the weapon's spread.
local T = dofile("tests/harness.lua")
local FixedSpread = T.require("foundation.combat.fixed_spread")

T.test("the first pellet goes down the middle", function()
	local x, y = FixedSpread.Offset(1)
	T.eq(x, 0)
	T.eq(y, 0)
end)

T.test("pellets past the pattern wrap around to its start", function()
	local n = #FixedSpread.PATTERN
	for i = 1, n do
		local x1, y1 = FixedSpread.Offset(i)
		local x2, y2 = FixedSpread.Offset(i + n)
		T.eq(x1, x2, "pellet " .. i)
		T.eq(y1, y2, "pellet " .. i)
	end
end)

T.test("every offset stays within the scaled spread", function()
	T.defined(FixedSpread.SCALE, "FixedSpread.SCALE")
	for i = 1, #FixedSpread.PATTERN do
		local x, y = FixedSpread.Offset(i)
		T.eq(math.abs(x) <= FixedSpread.SCALE and math.abs(y) <= FixedSpread.SCALE, true, "pellet " .. i)
	end
end)

T.test("a shot's pellets are spread, not stacked", function()
	local seen = {}
	for i = 1, 7 do
		local x, y = FixedSpread.Offset(i)
		local key = x .. "," .. y
		T.eq(seen[key], nil, "pellet " .. i .. " has its own place")
		seen[key] = true
	end
end)

T.finish()
