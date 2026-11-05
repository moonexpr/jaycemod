-- npc_pathfollower's bench as the engine's own actions: a tool's follower between Idle and
-- Travel as its stool says, and a console's on its Errand. What they ask of the soldier:
-- NSMayAct(), NSWantedBehavior() -> "Idle" or "Travel", NSUpdateToolBehavior(),
-- NSUpdateErrand().
local Action = nextsoldier.behavior.action
module("nextsoldier.behavior.pathfollower")

Idle = Action.Extend("Idle")
Travel = Action.Extend("Travel")
Errand = Action.Extend("Errand")

local function Steered(me)
	if me:NSMayAct() then me:NSUpdateToolBehavior() end
end

function Idle:Update(me)
	if me:NSWantedBehavior() == "Travel" then return self:ChangeTo(Travel:New(), "Sent somewhere") end
	Steered(me)
	return self:Continue()
end

function Travel:Update(me)
	if me:NSWantedBehavior() == "Idle" then return self:ChangeTo(Idle:New(), "Told to stop") end
	Steered(me)
	return self:Continue()
end

function Errand:Update(me)
	if me:NSMayAct() then me:NSUpdateErrand() end
	return self:Continue()
end

-- The first of them: a tool's follower waits to be sent.
function InitialAction(toolManaged)
	if toolManaged then return Idle:New() end
	return Errand:New()
end
