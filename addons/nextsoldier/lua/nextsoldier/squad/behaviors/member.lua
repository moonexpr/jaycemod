-- A squad member's main stack: what it fights, apart from its leggings (NextLegs,
-- behavior.group_identity and gib_behaviors), which put its feet where its squad's order says. On
-- a mission its leader has yet to activate (nextsoldier.squad.orders' Awaiting: an assault before
-- its signal, an ambush before it is sprung, an occupation stacked up before its word), it listens:
-- it holds its fire and its instinctive reactions, so none gives the squad away. Activated, or with
-- no mission, it fights as any soldier does. Its leader killed with the mission under way, the
-- first to hear of it abandons the mission and calls the fall back (squad.interactions.command).
--   SquadMember          its root: listening or fighting, as its order says
--   SquadMemberListen    ShouldAttack NO, until the order no longer awaits its leader
--   SquadMemberCombat    ShouldAttack YES, until a new mission awaits its leader
-- Its order is me:NSLegsOrder() (nil for none); it calls out by me:NSLegsSay(line, call).
local Action = nextsoldier.behavior.action
local Orders = nextsoldier.squad.orders
local Command = nextsoldier.squad.interactions.command
module ("nextsoldier.squad.behaviors.member")

SquadMember = Action.Extend ("SquadMember")
SquadMemberListen = Action.Extend ("SquadMemberListen")
SquadMemberCombat = Action.Extend ("SquadMemberCombat")

local function Listening (me) return Orders.Awaiting (me:NSLegsOrder ()) end

function SquadMember:InitialContainedAction (me)
	if Listening (me) then return SquadMemberListen:New () end
	return SquadMemberCombat:New ()
end

function SquadMember:Update (me)
	local order = me:NSLegsOrder ()
	local call = order and Command.Abandon (order, me)
	if call then me:NSLegsSay (call.text, call) end
	return self:Continue ()
end

function SquadMemberListen:Update (me)
	if Listening (me) then return self:Continue () end
	return self:ChangeTo (SquadMemberCombat:New (), "Activated")
end

function SquadMemberListen:ShouldAttack () return Action.ANSWER_NO end

function SquadMemberCombat:Update (me)
	if not Listening (me) then return self:Continue () end
	return self:ChangeTo (SquadMemberListen:New (), "On a mission")
end

function SquadMemberCombat:ShouldAttack () return Action.ANSWER_YES end
