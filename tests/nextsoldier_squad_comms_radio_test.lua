-- nextsoldier.squad.comms.radio: a squad's channel. Its leader speaks to its director, the squad
-- or one member; a member only to its leader; the director only to the leader.
local T = dofile ("tests/harness.lua")
local Radio = nextsoldier.squad.comms.radio
local GroupIdentity = nextsoldier.behavior.group_identity
local GIB = nextsoldier.behavior.gib_behaviors

local function Squad ()
	local order, leader = GroupIdentity.Muster ({ x = 0, y = 0, z = 0 }), { name = "leader" }
	order:Lead (leader)
	return order, leader, { name = "member" }, { name = "other" }
end

T.test ("the leader to anyone, a member only to its leader, the director only to the leader", function ()
	local order, leader, member, other = Squad ()
	local said = Radio.Say (order, leader, Radio.SQUAD, "MOVE_IN")
	T.eq (said.text, Radio.CALLS.MOVE_IN, "the call's words")
	T.eq (said.from == leader and said.to == Radio.SQUAD, true, "from and to")
	T.eq (Radio.Say (order, leader, Radio.DIRECTOR, "LOST", "red 3").text, "Lost contact with red 3.", "to the director, with whom")
	T.eq (Radio.Say (order, member, leader, "ALL_CLEAR").to, leader, "a member to its leader")
	T.eq (Radio.Say (order, Radio.DIRECTOR, leader, "STANDBY").to, leader, "the director to the leader")
	T.eq (pcall (Radio.Say, order, member, other, "ALL_CLEAR"), false, "a member to another, refused")
	T.eq (pcall (Radio.Say, order, member, Radio.DIRECTOR, "ALL_CLEAR"), false, "a member to the director, refused")
	T.eq (pcall (Radio.Say, order, Radio.DIRECTOR, member, "STATUS"), false, "the director to a member, refused")
	T.eq (pcall (Radio.Say, order, leader, member, "NO_SUCH_CALL"), false, "an unknown call, refused")
	T.eq (#Radio.Calls (order), 4, "each call kept on the channel")
end)

T.test ("a line the leggings call out aloud is the leader's call to the squad, kept on the channel", function ()
	local order, leader = Squad ()
	for _, line in ipairs ({ GIB.FALL_BACK_LINE, GIB.SIGNAL_LINE, GIB.CLEAR_LINE }) do
		local entry = Radio.Line (order, leader, line)
		T.eq (entry ~= nil and entry.to == Radio.SQUAD and entry.text == line, true, line)
	end
	T.eq (Radio.Line (order, leader, "Nonsense"), nil, "no call")
	T.eq (#Radio.Calls (order), 3, "kept")
end)

T.test ("each order's channel is its own", function ()
	local a, leader = Squad ()
	local b = Squad ()
	Radio.Say (a, leader, Radio.SQUAD, "MOVE_IN")
	T.eq (#Radio.Calls (b), 0, "another order hears none")
end)

T.finish ()
