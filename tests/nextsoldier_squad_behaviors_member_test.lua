-- nextsoldier.squad.behaviors.member: a squad member's main stack, apart from its leggings. The
-- engine runs it on a server (native/nextsoldier); here each action answers a fake soldier on an
-- order.
local T = dofile("tests/harness.lua")
local Action = nextsoldier.behavior.action
local Member = nextsoldier.squad.behaviors.member
local Command = nextsoldier.squad.interactions.command
local GroupIdentity = nextsoldier.behavior.group_identity
local R = dofile("tests/fake_room.lua")

local function Me(order)
	local me = { order = order, said = {} }
	function me:NSLegsOrder() return self.order end
	function me:NSLegsSay(line, call) self.said[#self.said + 1] = call or line end
	return me
end

local function Assault() return GroupIdentity.Assault(R.Room({ 1, 0, 0, 0 })) end

T.test("with no mission, a member fights as any soldier does", function()
	local me = Me(nil)
	local first = Member.SquadMember:New():InitialContainedAction(me)
	T.eq(first.name, "SquadMemberCombat", "fighting")
	T.eq(first:ShouldAttack(me), Action.ANSWER_YES, "it attacks")
	me.order = GroupIdentity.Muster({ x = 0, y = 0, z = 0 })
	T.eq(Member.SquadMember:New():InitialContainedAction(me).name, "SquadMemberCombat", "a muster is no mission")
end)

T.test("on a mission its leader has not activated, a member listens, holding its fire", function()
	local me = Me(Assault())
	local listen = Member.SquadMember:New():InitialContainedAction(me)
	T.eq(listen.name, "SquadMemberListen", "listening")
	T.eq(listen:ShouldAttack(me), Action.ANSWER_NO, "no attack, which would give the squad away")
	T.eq(listen:Update(me).type, Action.CONTINUE, "while the leader has not signalled")
end)

T.test("the leader's signal activates the assault: the member changes to combat", function()
	local me = Me(Assault())
	me.order:Signal()
	local result = Member.SquadMemberListen:New():Update(me)
	T.eq(result.type, Action.CHANGE_TO, "changed")
	T.eq(result.action.name, "SquadMemberCombat", "to combat")
end)

T.test("told a new mission while fighting, a member listens again", function()
	local me = Me(nil)
	local combat = Member.SquadMemberCombat:New()
	T.eq(combat:Update(me).type, Action.CONTINUE, "fighting on")
	me.order = Assault()
	local result = combat:Update(me)
	T.eq(result.type, Action.CHANGE_TO, "changed")
	T.eq(result.action.name, "SquadMemberListen", "to listening")
end)

T.test("its leader killed with the mission under way, the first to hear of it calls the fall back", function()
	local me, leader = Me(Assault()), { name = "leader" }
	me.order:Lead(leader)
	Command.Casualty(me.order, leader, { x = -300, y = 0, z = 0 })
	me.order:Casualty(leader)
	Member.SquadMember:New():Update(me)
	T.eq(me.said[1] and me.said[1].call, "FALL_BACK", "the fall back called")
	T.eq(me.order.leader, me, "the lead taken")
	local result = Member.SquadMemberListen:New():Update(me)
	T.eq(result.action.name, "SquadMemberCombat", "no longer listening: it fights its way out")
end)

T.finish()
