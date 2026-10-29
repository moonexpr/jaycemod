-- games.gameplay.standing: which team stands nearer to completing its
-- objective, for a match closed before it is won (the gamerules' forced
-- closure): the match score first, then the round's objective; nil when it
-- is genuinely a tie (a deciding round decides it).
local T = dofile("tests/harness.lua")
local Standing = gameplay.standing
local Teams = gameplay.teams

local RED, BLUE = Teams.RED, Teams.BLUE
local EVEN = { [RED] = 0, [BLUE] = 0 }

T.test("the team ahead on the match score leads, whatever the round", function()
	T.eq(Standing.Leader({}, { [RED] = 2, [BLUE] = 1 }), RED, "red has won more rounds")
	T.eq(Standing.Leader({ carts = { [RED] = 0, [BLUE] = 0.9 } }, { [RED] = 0, [BLUE] = 1 }), BLUE, "blue ahead, its cart too")
end)

T.test("on an even score, the cart farther along its track leads", function()
	T.eq(Standing.Leader({ carts = { [RED] = 0.3, [BLUE] = 0.4 } }, EVEN), BLUE, "blue's is 40% along, red's 30%")
	T.eq(Standing.Leader({ carts = { [BLUE] = 0.1 } }, EVEN), BLUE, "only blue has a cart, and it has moved")
end)

T.test("on an even score, the team with more of the flags it needs leads", function()
	T.eq(Standing.Leader({ captures = { [RED] = 2, [BLUE] = 1 }, caplimit = 3 }, EVEN), RED, "two of three")
end)

T.test("on an even score, the team whose clock has less left leads", function()
	T.eq(Standing.Leader({ clocks = { [RED] = 40, [BLUE] = 90 } }, EVEN), RED, "red's clock nearer zero")
end)

T.test("on an even score, the team owning more of the round's points leads", function()
	local points = {
		{ owner = RED, inRound = true }, { owner = RED, inRound = true }, { owner = BLUE, inRound = true },
		{ owner = BLUE, inRound = false }, { owner = BLUE, inRound = true, hidden = true },
	}
	T.eq(Standing.Leader({ points = points }, EVEN), RED, "two of the round's three, the others not in play")
end)

T.test("a genuine tie has no leader", function()
	T.eq(Standing.Leader({}, EVEN), nil, "no objective, even score")
	T.eq(Standing.Leader({ points = { { owner = RED, inRound = true }, { owner = BLUE, inRound = true } } }, EVEN), nil, "a point each")
	T.eq(Standing.Leader({ clocks = { [RED] = 60, [BLUE] = 60 } }, EVEN), nil, "even clocks")
	T.eq(Standing.Leader({ carts = { [RED] = 0.5, [BLUE] = 0.5 } }, EVEN), nil, "carts level")
end)

T.finish()
