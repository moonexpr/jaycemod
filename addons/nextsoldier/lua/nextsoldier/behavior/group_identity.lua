-- The tree a soldier runs beside its main one, as L4D2's survivors run their legs: who it
-- is with, and where that puts its feet. Its root is native (engine.GroupIdentityBehavior);
-- what it does under that grows here. With no group to be part of yet, it waits.
local Action = nextsoldier.behavior.action
module("nextsoldier.behavior.group_identity")

LegsWait = Action.Extend("LegsWait")

function LegsWait:Update() return self:Continue() end

function InitialAction(engine)
	return engine.GroupIdentityBehavior({ initial = LegsWait:New() })
end

-- Puts the tree on ent, telling its actions me. Whether it could: where the binary is not
-- bound, a soldier goes without.
function Give(ent, engine, me)
	if not (engine and engine.InsertGroup) then return false end
	engine.InsertGroup(ent, InitialAction(engine), me)
	return true
end
