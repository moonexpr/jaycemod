-- foundation.npc.path.tfbot: CTFBotPathCost (tf_bot.h) with
-- CTFBotLocomotion::IsAreaTraversable, the path cost of TF2's bots and
-- MvM's robots.
local T = dofile("tests/harness.lua")
local Path = T.require("foundation.npc.path")
local TFBot = T.require("foundation.npc.path.tfbot")
local Scatter = T.require("foundation.npc.path.scatter")
local Teams = T.require("foundation.teams")

local LIMITS = { stepHeight = 18, jumpHeight = 72, deathDropHeight = 1000 }

local function Bot(overrides)
	local bot = {
		entIndex = 7,
		now = 12,
		team = Teams.BLUE,
		route = TFBot.FASTEST_ROUTE,
		miniBoss = false,
		roundWon = false,
		winningTeam = Teams.UNASSIGNED,
	}
	for k, v in pairs(overrides or {}) do bot[k] = v end
	return bot
end

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
		spawnRoomTeam = Teams.UNASSIGNED,
	}
	for k, v in pairs(overrides or {}) do step[k] = v end
	return step
end

T.test("the first area costs nothing", function()
	T.eq(TFBot.Cost(Step({ hasFrom = false, traversable = false }), LIMITS, Bot()), 0, "first")
end)

T.test("a fastest route costs the distance on top of the cost so far", function()
	T.eq(TFBot.Cost(Step(), LIMITS, Bot()), 140, "centre distance")
	T.eq(TFBot.Cost(Step({ length = 80 }), LIMITS, Bot()), 120, "connection length")
	T.eq(TFBot.Cost(Step({ ladderLength = 60, length = 80 }), LIMITS, Bot()), 100, "ladder length")
end)

T.test("a blocked area is a dead end", function()
	T.eq(TFBot.Cost(Step({ traversable = false }), LIMITS, Bot()), Path.IMPASSABLE, "blocked")
end)

T.test("a climb over the step height costs double, and one of a full jump is a dead end", function()
	T.eq(TFBot.Cost(Step({ heightChange = 18 }), LIMITS, Bot()), 240, "jump")
	T.eq(TFBot.Cost(Step({ heightChange = 72 }), LIMITS, Bot()), Path.IMPASSABLE, "too high")
	T.eq(TFBot.Cost(Step({ heightChange = 17.9 }), LIMITS, Bot()), 140, "a step")
end)

T.test("a drop past the death drop height is a dead end", function()
	T.eq(TFBot.Cost(Step({ heightChange = -1000 }), LIMITS, Bot()), 140, "at the limit")
	T.eq(TFBot.Cost(Step({ heightChange = -1001 }), LIMITS, Bot()), Path.IMPASSABLE, "past it")
end)

T.test("the enemy's spawn room is a dead end until the round is won", function()
	local red = Step({ spawnRoomTeam = Teams.RED })
	T.eq(TFBot.Cost(red, LIMITS, Bot()), Path.IMPASSABLE, "BLU in RED's room")
	T.eq(TFBot.Cost(red, LIMITS, Bot({ team = Teams.RED })), 140, "RED in its own room")
	local blue = Step({ spawnRoomTeam = Teams.BLUE })
	T.eq(TFBot.Cost(blue, LIMITS, Bot({ team = Teams.RED })), Path.IMPASSABLE, "RED in BLU's room")
end)

T.test("after the round only the winners may enter the losers' spawn room", function()
	local red = Step({ spawnRoomTeam = Teams.RED })
	T.eq(TFBot.Cost(red, LIMITS, Bot({ roundWon = true, winningTeam = Teams.BLUE })), 140, "the winners")
	T.eq(TFBot.Cost(Step({ spawnRoomTeam = Teams.BLUE }), LIMITS,
		Bot({ team = Teams.RED, roundWon = true, winningTeam = Teams.BLUE })), Path.IMPASSABLE, "the losers")
end)

T.test("a default route weighs each area by the bot's own preference, as the skeletons do", function()
	local bot = Bot({ route = TFBot.DEFAULT_ROUTE })
	local preference = Scatter.Preference(bot.entIndex, 3, bot.now)
	T.near(TFBot.Cost(Step(), LIMITS, bot), 100 * preference + 40, 1e-9, "preferred")
end)

T.test("a giant (mini-boss) takes no preference on a default route", function()
	T.eq(TFBot.Cost(Step(), LIMITS, Bot({ route = TFBot.DEFAULT_ROUTE, miniBoss = true })), 140, "straight")
end)

T.test("a safest or retreat route costs as a fastest one here", function()
	T.eq(TFBot.Cost(Step(), LIMITS, Bot({ route = TFBot.SAFEST_ROUTE })), 140, "safest")
	T.eq(TFBot.Cost(Step(), LIMITS, Bot({ route = TFBot.RETREAT_ROUTE })), 140, "retreat")
end)

T.finish()
