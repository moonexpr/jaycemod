local T = dofile("tests/harness.lua")
local Path = nextsoldier.path
local Ground = T.require("games.nextsoldier.path.ground")
local Scatter = T.require("games.nextsoldier.path.scatter")

local LIMITS = {
	runSpeed = 300,
	stepHeight = 18,
	jumpHeight = 18,
	deathDropHeight = 200,
	maxYawRate = 200,
	acceleration = 500,
	deceleration = 500,
}

local BOT = {
	entIndex = 7,
	now = 12,
}

-- Whether a walker can make a move that changes its height by deltaZ: up
-- less than its jump, down no further than its death drop.
T.test("a walker climbs less than its jump and drops no further than its death drop", function()
	T.eq(Path.Walkable(0, LIMITS), true, "flat")
	T.eq(Path.Walkable(LIMITS.jumpHeight - 1, LIMITS), true, "just under the jump")
	T.eq(Path.Walkable(LIMITS.jumpHeight, LIMITS), false, "the jump itself")
	T.eq(Path.Walkable(-LIMITS.deathDropHeight, LIMITS), true, "the death drop itself")
	T.eq(Path.Walkable(-LIMITS.deathDropHeight - 1, LIMITS), false, "past the death drop")
end)

-- A step from one area to the next, 100 units apart on flat ground.
local function Step(overrides)
	local step = {
		hasFrom = true,
		traversable = true,
		ladderLength = nil,
		length = 0,
		centerDistance = 100,
		heightChange = 0,
		fromCostSoFar = 40,
		areaId = 3,
	}
	for k, v in pairs(overrides or {}) do step[k] = v end
	return step
end

local JUMPER = {
	stepHeight = 18,
	jumpHeight = 72,
	deathDropHeight = 200,
}

-- CZombiePathCost and CHeadlessHatmanPathCost share this body

T.test("the first area costs nothing", function()
	local first = Step({
		hasFrom = false,
		traversable = false,
	})
	T.eq(Ground.Cost(first, LIMITS, BOT), 0, "first area")
end)

T.test("an area the locomotor cannot cross is impassable", function()
	T.eq(Ground.Cost(Step({ traversable = false }), LIMITS, BOT), Path.IMPASSABLE, "not traversable")
end)

T.test("the distance is the ladder's length, else the given length, else the centre distance", function()
	local ladder = Step({
		ladderLength = 250,
		length = 80,
	})
	T.eq(Ground.Cost(ladder, LIMITS, BOT), 40 + 250, "ladder")
	T.eq(Ground.Cost(Step({ length = 80 }), LIMITS, BOT), 40 + 80, "length")
	T.eq(Ground.Cost(Step({ length = 0 }), LIMITS, BOT), 40 + 100, "centre distance")
end)

T.test("a climb of a step or more is a jump: impassable at the jump height, else penalised", function()
	T.eq(Ground.Cost(Step({ heightChange = 17.9 }), JUMPER, BOT), 40 + 100, "below a step")
	T.eq(Ground.Cost(Step({ heightChange = 18 }), JUMPER, BOT), 40 + 100 + Path.JUMP_PENALTY * 100, "a jump")
	T.eq(Ground.Cost(Step({ heightChange = 72 }), JUMPER, BOT), Path.IMPASSABLE, "too high")
	T.eq(Ground.Cost(Step({ heightChange = 18 }), LIMITS, BOT), Path.IMPASSABLE, "a bot whose jump is a step")
end)

T.test("a drop deeper than the death drop is impassable", function()
	T.eq(Ground.Cost(Step({ heightChange = -200 }), LIMITS, BOT), 40 + 100, "at the limit")
	T.eq(Ground.Cost(Step({ heightChange = -200.5 }), LIMITS, BOT), Path.IMPASSABLE, "below it")
end)

-- CZombiePathCost's preference term

local function Preference(entIndex, areaId, now)
	return 1 + 50 * (1 + math.cos(entIndex * areaId * (math.floor(now / 10) + 1)))
end

T.test("scatter weighs the distance by a per-bot, per-area, per-ten-seconds preference", function()
	local p = Preference(7, 3, 12)
	T.near(Scatter.Cost(Step(), LIMITS, BOT), 40 + 100 * p, 1e-6, "flat")
	T.near(Scatter.Cost(Step({ heightChange = 10 }), LIMITS, BOT), 40 + 100 * p, 1e-6, "under a step")
	T.near(Scatter.Cost(Step({ heightChange = 18 }), JUMPER, BOT), 40 + 6 * 100 * p, 1e-6, "the jump penalty is weighed too")
	T.eq(Scatter.Cost(Step({ traversable = false }), LIMITS, BOT), Path.IMPASSABLE, "still impassable")
	T.eq(Scatter.Cost(Step({ hasFrom = false }), LIMITS, BOT), 0, "first area")
end)

-- NavAreaBuildPath's first call has no from-area, so the binding fills
-- nothing else in, not even the area id.
T.test("scatter costs the first area nothing without reading its id", function()
	local first = { hasFrom = false }
	T.eq(Scatter.Cost(first, LIMITS, BOT), 0, "first area, bare")
end)

T.test("scatter keeps a route for ten seconds and differs between bots", function()
	local at = function(entIndex, now)
		return Scatter.Cost(Step(), LIMITS, {
			entIndex = entIndex,
			now = now,
		})
	end
	T.eq(at(7, 10), at(7, 19.9), "same ten-second window")
	T.eq(at(7, 10) ~= at(7, 20), true, "next window")
	T.eq(at(7, 10) ~= at(8, 10), true, "another bot")
	T.near(at(7, 10), 40 + 100 * Preference(7, 3, 10), 1e-6, "value")
end)

T.finish()
