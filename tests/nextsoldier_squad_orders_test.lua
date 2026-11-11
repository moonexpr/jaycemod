-- nextsoldier.squad.orders: the seam where a kind of order the squad adds registers its leggings'
-- action, which the base's leggings look up for a kind they do not know, and any kind its
-- mission's rules.
local T = dofile ("tests/harness.lua")
local Orders = nextsoldier.squad.orders
local GroupIdentity = nextsoldier.behavior.group_identity
local GIB = nextsoldier.behavior.gib_behaviors
local Action = nextsoldier.behavior.action
local F = dofile ("tests/fake_legs.lua")

local LegsTest = Action.Extend ("LegsTest")
function LegsTest:Update () return self:Continue () end

T.test ("an order of a kind of the squad's is the base's own Order, with its own methods", function ()
	local class = Orders.Kind ()
	function class:Kind () return "mine" end
	local order = Orders.New (class, { kind = "Test", point = { x = 1, y = 2, z = 0 } })
	T.eq (order:Kind (), "mine", "its own")
	order:Lead ("leader")
	T.eq (order.leader, "leader", "the base's own")
	T.eq (order.mode, GroupIdentity.MODE.STATIONARY, "a muster's fields")
	T.eq (order.point.y, 2, "at its point")
end)

T.test ("the base's leggings run the action a kind registered", function ()
	Orders.Register ({ kind = "Test", action = LegsTest })
	local order = Orders.New (Orders.Kind (), { kind = "Test", point = { x = 0, y = 0, z = 0 } })
	local result = GIB.LegsAtEase:New ():Update (F.Member (order))
	T.eq (result.action.name, "LegsTest", "the registered action")
	T.eq (Orders.Action ("Test"), LegsTest, "looked up by kind")
	T.eq (pcall (Orders.Action, "Nothing"), false, "an unknown kind, refused")
end)

T.test ("a kind's mission rules: awaiting and under way, none for a kind without them", function ()
	Orders.Register ({ kind = "Test", awaiting = function (order) return order.waiting end,
		underway = function () return true end })
	local order = Orders.New (Orders.Kind (), { kind = "Test", point = { x = 0, y = 0, z = 0 }, waiting = true })
	T.eq (Orders.Awaiting (order), true, "awaiting")
	T.eq (Orders.Underway (order), true, "under way")
	T.eq (Orders.Awaiting (GroupIdentity.Muster ({ x = 0, y = 0, z = 0 })), false, "a muster, no mission")
	T.eq (Orders.Awaiting (nil), false, "no order, none")
end)

T.test ("the base's assault is a mission: awaiting its signal, under way until the room is clear", function ()
	local room = dofile ("tests/fake_room.lua").Room ({ 1, 0, 0, 0 })
	local order = GroupIdentity.Assault (room)
	T.eq (Orders.Awaiting (order), true, "before its signal")
	order:Signal ()
	T.eq (Orders.Awaiting (order), false, "signalled")
	T.eq (Orders.Underway (order), true, "under way")
	order:CallClear ()
	T.eq (Orders.Underway (order), false, "the room clear")
end)

T.finish ()
