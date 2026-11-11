-- nextsoldier.squad.interactions: the director's clearance (director) and the chain of command
-- (command).
local T = dofile ("tests/harness.lua")
local Director = nextsoldier.squad.interactions.director
local Command = nextsoldier.squad.interactions.command
local Radio = nextsoldier.squad.comms.radio
local GroupIdentity = nextsoldier.behavior.group_identity
local R = dofile ("tests/fake_room.lua")

local function Squad ()
	local order, leader = GroupIdentity.Muster ({ x = 0, y = 0, z = 0 }), { name = "leader" }
	order:Lead (leader)
	return order, leader
end

T.test ("asked once, the director answers the leader over the radio, its answer kept", function ()
	local order, leader = Squad ()
	local asked = {}
	Director.Set (order, { Request = function (_, o, request) asked [#asked + 1] = { order = o, request = request } end })
	T.eq (Director.Request (order, { kind = "VACATE" }), true, "asked")
	T.eq (Director.Request (order, { kind = "VACATE" }), false, "the once")
	T.eq (Director.Requested (order), true, "asked")
	T.eq (asked [1].order == order and asked [1].request.kind == "VACATE", true, "of the order, to vacate")
	T.eq (Director.Directive (order), nil, "no answer yet: the leader waits")
	local said = Director.Answer (order, "DEFEND", { plan = "AMBUSH" })
	T.eq (said.from == Radio.DIRECTOR and said.to == leader, true, "from the director to the leader")
	T.eq (said.text, Radio.CALLS.DEFEND, "its words")
	T.eq (Director.Directive (order).kind == "DEFEND" and Director.Directive (order).plan == "AMBUSH", true, "kept, with its plan")
	Director.Forget (order)
	T.eq (Director.Directive (order), nil, "forgotten")
	T.eq (Director.Request (order, { kind = "VACATE" }), true, "asked again")
end)

T.test ("a director must answer requests, and only with an answer it has", function ()
	local order = Squad ()
	T.eq (pcall (Director.Set, order, {}), false, "no Request, refused")
	T.eq (pcall (Director.Answer, order, "NO_SUCH"), false, "an unknown answer, refused")
end)

T.test ("with no director, the leader's own word stands: cleared at once", function ()
	local order = Squad ()
	Director.Request (order, { kind = "VACATE" })
	T.eq (Director.Directive (order).kind, "VACATE", "cleared")
end)

T.test ("its leader killed with the mission under way, the squad abandons it, away from where it fell", function ()
	local order = GroupIdentity.Assault (R.Room ({ 1, 0, 0, 0 }))
	local leader, member = { name = "leader" }, { name = "member" }
	order:Lead (leader)
	Command.Casualty (order, leader, { x = -300, y = 0, z = 0 })
	order:Casualty (leader)
	local call = Command.Abandon (order, member)
	T.eq (order.leader, member, "the lead taken")
	T.eq (call and call.call, "FALL_BACK", "the fall back called")
	T.eq (order.mode, GroupIdentity.MODE.PANIC, "evacuating")
	T.eq (order.from.x, -300, "away from where its leader fell")
	T.eq (Command.Abandon (order, member), nil, "the once")
end)

T.test ("its leader killed once the room is clear, or a member killed, the squad stays", function ()
	local order = GroupIdentity.Assault (R.Room ({ 1, 0, 0, 0 }))
	local leader, member = { name = "leader" }, { name = "member" }
	order:Lead (leader)
	Command.Casualty (order, member, { x = 0, y = 0, z = 0 })
	T.eq (Command.Abandon (order, leader), nil, "a member lost: no abandoning")
	order:Signal ()
	order:CallClear ()
	Command.Casualty (order, leader, { x = 0, y = 0, z = 0 })
	order:Casualty (leader)
	T.eq (Command.Abandon (order, member), nil, "the room clear: done, not abandoned")
	T.eq (order.routed, nil, "no fall back")
end)

T.finish ()
