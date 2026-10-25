-- foundation.wetsands.path's strategies as models: each strategy's
-- Model(limits, bot), priced by native/wetsands' walker, gives the very
-- double its Lua Cost gives, step for step, over steps chosen to sit on
-- every boundary the costs test (a rise of exactly a step, a jump, a drop;
-- each room; each attribute; penalised or not; a closed area).
local T = dofile("tests/harness.lua")
local Native = T.native("wetsands").wetsands.navsearch
local Path = wetsands.path
local Ground = T.require("foundation.wetsands.path.ground")
local Scatter = T.require("foundation.wetsands.path.scatter")
local TFBot = T.require("foundation.wetsands.path.tfbot")
local HL2 = T.require("foundation.wetsands.path.hl2")
local Lanes = nextsoldier.lanes

local STEPS = 4000

-- A fixed linear congruential sequence: the same steps every run.
local function Sequence(seed)
	local x = seed
	return function(n)
		x = (x * 1103515245 + 12345) % 2147483648
		return x % n
	end
end

local function Pick(next, list) return list[next(#list) + 1] end

local LIMITS = {
	HL2.LIMITS,
	HL2.SOLDIER_LIMITS,
	{ stepHeight = 18, jumpHeight = 66, deathDropHeight = 400 },
}

local function Rises(limits)
	return { 0, 5.25, limits.stepHeight - 0.5, limits.stepHeight, limits.stepHeight + 0.25,
		limits.jumpHeight - 0.5, limits.jumpHeight, -limits.deathDropHeight, -limits.deathDropHeight - 0.5, -37.75 }
end

local function Bot(next)
	return {
		entIndex = next(64) + 1,
		now = next(100000) / 7,
		team = Pick(next, { 2, 3, nil }),
		route = Pick(next, { TFBot.DEFAULT_ROUTE, TFBot.FASTEST_ROUTE, nil }),
		miniBoss = next(4) == 0,
		roundWon = next(3) == 0,
		winningTeam = Pick(next, { 2, 3, nil }),
		penalized = { [7] = true, [11] = true },
	}
end

local function Step(next, limits)
	local distance = Pick(next, { 0, 1, 37.5, 100, 251.125 }) + next(1000) / 8
	return {
		hasFrom = true,
		traversable = next(8) ~= 0,
		ladderLength = nil,
		length = distance,
		centerDistance = distance,
		heightChange = Pick(next, Rises(limits)),
		fromCostSoFar = next(100000) / 3,
		areaId = Pick(next, { 7, 11, 12, 1999, next(5000) + 1 }),
		spawnRoomTeam = Pick(next, { 0, 0, 2, 3 }),
		attributes = Pick(next, { 0, 1, 2, 3, 0x80 }),
	}
end

local function NativePrice(walker, step, bot)
	local penalized = bot.penalized[step.areaId] == true
	return walker:Price(step.traversable, step.spawnRoomTeam, step.attributes, step.centerDistance,
		step.heightChange, step.fromCostSoFar, step.areaId, penalized)
end

local STRATEGIES = {
	{ "ground", Ground },
	{ "scatter", Scatter },
	{ "tfbot", TFBot },
	{ "hl2", HL2 },
	{ "lanes", Lanes.Strategy },
}

for i, entry in ipairs(STRATEGIES) do
	local name, strategy = entry[1], entry[2]
	T.test(name .. "'s model prices every step to the double its Cost gives", function()
		local next = Sequence(i * 7919)
		local mismatches, impassable, first = 0, 0, nil
		for _ = 1, STEPS do
			local limits, bot = Pick(next, LIMITS), Bot(next)
			local step = Step(next, limits)
			local lua = strategy.Cost(step, limits, bot)
			local native = NativePrice(Native.Walker(strategy.Model(limits, bot)), step, bot)
			if lua == Path.IMPASSABLE then impassable = impassable + 1 end
			if lua ~= native then
				mismatches = mismatches + 1
				first = first or string.format("area %d rise %s: Lua %.17g, native %.17g", step.areaId, step.heightChange, lua, native)
			end
		end
		T.eq(first, nil, name .. ": first mismatch")
		T.eq(mismatches, 0, name .. ": mismatches")
		T.eq(impassable > 0 and impassable < STEPS, true, name .. ": the steps reach both answers")
	end)
end

T.test("a model without its jump rule, or without a limit, is refused", function()
	local ok, why = pcall(Native.Walker, { stepHeight = 18, jumpHeight = 56, deathDropHeight = 100 })
	T.eq(ok, false, "no jump rule")
	T.eq(why:find("jumpAdded", 1, true) ~= nil, true, "names the rule")
	ok, why = pcall(Native.Walker, { jumpHeight = 56, deathDropHeight = 100, jumpScaled = 2 })
	T.eq(ok, false, "no step height")
	T.eq(why:find("stepHeight", 1, true) ~= nil, true, "names the limit")
end)

T.finish()
