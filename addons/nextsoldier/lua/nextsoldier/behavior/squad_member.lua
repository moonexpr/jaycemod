-- A squad member's main stack: what it fights, apart from its leggings (TacticalLeggings,
-- group_identity and gib_behaviors), which put its feet where its squad's order says. On a
-- mission its leader has yet to activate (an assault before its signal, an ambush before it is
-- sprung), it listens: it holds its fire and its instinctive reactions, so none gives the squad
-- away. Activated, abandoned (its leader lost), or with no mission, it fights as any soldier does.
--   SquadMember          its root: listening or fighting, as its order says
--   SquadMemberListen    ShouldAttack NO, until the order no longer awaits its leader
--   SquadMemberCombat    ShouldAttack YES, until a new mission awaits its leader
-- Its order is me:NSLegsOrder() (nil for none).
local Action = nextsoldier.behavior.action
module("nextsoldier.behavior.squad_member")

SquadMember = Action.Extend("SquadMember")
SquadMemberListen = Action.Extend("SquadMemberListen")
SquadMemberCombat = Action.Extend("SquadMemberCombat")

local function Listening(me)
	local order = me:NSLegsOrder()
	return order ~= nil and order:Awaiting()
end

function SquadMember:InitialContainedAction(me)
	if Listening(me) then return SquadMemberListen:New() end
	return SquadMemberCombat:New()
end

function SquadMember:Update() return self:Continue() end

function SquadMemberListen:Update(me)
	if Listening(me) then return self:Continue() end
	return self:ChangeTo(SquadMemberCombat:New(), "Activated")
end

function SquadMemberListen:ShouldAttack() return Action.ANSWER_NO end

function SquadMemberCombat:Update(me)
	if not Listening(me) then return self:Continue() end
	return self:ChangeTo(SquadMemberListen:New(), "On a mission")
end

function SquadMemberCombat:ShouldAttack() return Action.ANSWER_YES end
