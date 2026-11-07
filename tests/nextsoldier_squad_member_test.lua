-- nextsoldier.behavior.squad_member: a squad member's main stack, apart from its leggings. The
-- engine runs it on a server (native/nextsoldier); here each action answers a fake soldier on an
-- order of group_identity's.
local T = dofile("tests/harness.lua")
local Action = nextsoldier.behavior.action
local SquadMember = nextsoldier.behavior.squad_member
local GroupIdentity = nextsoldier.behavior.group_identity

local function Me(order)
	local me = { order = order }
	function me:NSLegsOrder() return self.order end
	return me
end

-- An assault on a room with one door, as the legs' tests have it.
local function Assault()
	return GroupIdentity.Assault({ center = { x = 0, y = 0, z = 0 }, entry = { x = -400, y = 0, z = 0 },
		seen = function() return false end, score = function() return 0 end })
end

T.test("with no mission, a member fights as any soldier does", function()
	local me = Me(nil)
	local first = SquadMember.SquadMember:New():InitialContainedAction(me)
	T.eq(first.name, "SquadMemberCombat", "fighting")
	T.eq(first:ShouldAttack(me), Action.ANSWER_YES, "it attacks")
	me.order = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	T.eq(SquadMember.SquadMember:New():InitialContainedAction(me).name, "SquadMemberCombat", "a muster is no mission")
end)

T.test("on a mission its leader has not activated, a member listens, holding its fire", function()
	local me = Me(Assault())
	local listen = SquadMember.SquadMember:New():InitialContainedAction(me)
	T.eq(listen.name, "SquadMemberListen", "listening")
	T.eq(listen:ShouldAttack(me), Action.ANSWER_NO, "no attack, which would give the squad away")
	T.eq(listen:Update(me).type, Action.CONTINUE, "while the leader has not signalled")
end)

T.test("the leader's signal activates the assault: the member changes to combat", function()
	local me = Me(Assault())
	local listen = SquadMember.SquadMemberListen:New()
	me.order:Signal()
	local result = listen:Update(me)
	T.eq(result.type, Action.CHANGE_TO, "changed")
	T.eq(result.action.name, "SquadMemberCombat", "to combat")
end)

T.test("an abandoned mission is no longer listened for: the member fights its way out", function()
	local me = Me(Assault())
	me.order:Abandon()
	T.eq(SquadMember.SquadMemberListen:New():Update(me).action.name, "SquadMemberCombat", "fighting")
end)

T.test("told a new mission while fighting, a member listens again", function()
	local me = Me(nil)
	local combat = SquadMember.SquadMemberCombat:New()
	T.eq(combat:Update(me).type, Action.CONTINUE, "fighting on")
	me.order = Assault()
	local result = combat:Update(me)
	T.eq(result.type, Action.CHANGE_TO, "changed")
	T.eq(result.action.name, "SquadMemberListen", "to listening")
end)

T.finish()
