-- The dev workbench's reading of a condition a player is given or loses by hand
-- (sandcastle_dev_condition), which PLAYER:AddCondition and RemoveCondition take.
local T = dofile("tests/harness.lua")
local Condition = T.require("sandcastle_dev_condition")

local COND = { BURNING = 22, URINE = 24, STUNNED = 15 }

T.test("a condition is one of the game's, by its number", function()
	T.eq(Condition.Parse(COND, 24), 24, "a number it has")
	T.eq(Condition.Parse(COND, 23), nil, "one it has not")
end)

T.test("a condition is also one of the game's by name, in any case", function()
	T.eq(Condition.Parse(COND, "URINE"), 24, "its name")
	T.eq(Condition.Parse(COND, "burning"), 22, "in lower case")
	T.eq(Condition.Parse(COND, "TF_COND_STUNNED"), 15, "as TF2 names it")
	T.eq(Condition.Parse(COND, "nonsense"), nil, "no such name")
end)

T.finish()
