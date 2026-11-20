-- nextsoldier.locomotion.pursuit's path budget: what the path searches of one tick may spend
-- together. A search starts while the tick has spent less than the budget, the first always;
-- a new tick starts it afresh; 0 is no limit.
local T = dofile ("tests/harness.lua")
local Pursuit = nextsoldier.locomotion.pursuit

T.test ("the default budget is 2 ms a tick", function ()
	T.eq (Pursuit.PATH_BUDGET,          0.002)
	T.eq (Pursuit.NewBudget ().seconds, 0.002)
end)

T.test ("a tick's first search starts whatever it costs; the next only while under the budget", function ()
	local budget = Pursuit.NewBudget (0.002)
	T.eq (budget:Allows (1), true, "the first")
	budget:Spend (1, 0.0015)
	T.eq (budget:Allows (1), true, "1.5 ms spent")
	budget:Spend (1, 0.001)
	T.eq (budget:Allows (1), false, "2.5 ms spent: the rest wait")
end)

T.test ("a new tick starts the budget afresh", function ()
	local budget = Pursuit.NewBudget (0.002)
	budget:Spend (1, 0.010)
	T.eq (budget:Allows (1), false)
	T.eq (budget:Allows (2), true)
	budget:Spend (3, 0.001)
	T.eq (budget.spent, 0.001, "spent in its own tick")
end)

T.test ("no budget is no limit", function ()
	local budget = Pursuit.NewBudget (0)
	budget:Spend (1, 1)
	T.eq (budget:Allows (1), true)
end)

T.finish ()
