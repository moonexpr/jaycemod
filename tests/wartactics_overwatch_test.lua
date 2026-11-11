-- wartactics.overwatch: what a squad's director answers its leader's request to vacate the place
-- it holds, from the squad's situation.
local T = dofile ("tests/harness.lua")
local Overwatch = wartactics.overwatch

local function Situation (fields)
	local situation = { size = 6, lost = 1, missing = 1, contact = false }
	for key, value in pairs (fields or {}) do situation [key] = value end
	return situation
end

T.test ("a guard lost and the squad strong enough to leave: clear to vacate", function ()
	T.eq (Overwatch.Decide (Situation ()).kind, "VACATE", "cleared")
end)

T.test ("an enemy met: hold the location, lying in wait for it", function ()
	local decision = Overwatch.Decide (Situation ({ contact = true }))
	T.eq (decision.kind, "DEFEND", "hold")
	T.eq (decision.plan, "AMBUSH", "in ambush")
end)

T.test ("too few left to leave the place: stand by", function ()
	local size = Overwatch.VACATE_FLOOR + 1
	T.eq (Overwatch.Decide (Situation ({ size = size, lost = 2 })).kind, "STANDBY", "stand by, a new patrol appointed")
end)

T.test ("guards lost again and again with somewhere to strike: assault it; with nowhere, lie in wait", function ()
	local target = { x = 1, y = 2, z = 0 }
	local decision = Overwatch.Decide (Situation ({ missing = Overwatch.ATTACK_AFTER, target = target }))
	T.eq (decision.kind, "ATTACK", "assault")
	T.eq (decision.target, target, "where the enemy comes from")
	decision = Overwatch.Decide (Situation ({ missing = Overwatch.ATTACK_AFTER }))
	T.eq (decision.kind == "DEFEND" and decision.plan == "AMBUSH", true, "no target: lie in wait")
end)

T.test ("the tuning is defined", function ()
	T.defined (Overwatch.VACATE_FLOOR, "VACATE_FLOOR")
	T.defined (Overwatch.ATTACK_AFTER, "ATTACK_AFTER")
end)

T.finish ()
