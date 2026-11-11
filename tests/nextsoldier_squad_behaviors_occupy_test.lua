-- nextsoldier.squad.behaviors.occupy: a squad holding a room, guards patrolling round it and their
-- leader checking in on them; a guard missing, the squad stacks up and waits for its director's
-- clearance before it leaves the room.
local T = dofile ("tests/harness.lua")
local Occupy = nextsoldier.squad.behaviors.occupy
local Orders = nextsoldier.squad.orders
local Radio = nextsoldier.squad.comms.radio
local Director = nextsoldier.squad.interactions.director
local Action = nextsoldier.behavior.action
local GIB = nextsoldier.behavior.gib_behaviors
local R = dofile ("tests/fake_room.lua")
local F = dofile ("tests/fake_legs.lua")

local function Holding (count)
	local order = Occupy.Occupy (R.Room ())
	return order, order:Places (R.East (count), R.SPACING, R.AdmitAt (R.CENTER), R.AdmitAt)
end

T.test ("an occupation patrols round its room outside, a guard for each span of the loop, half the squad at most", function ()
	local order, places = Holding (6)
	T.eq (#order.loop >= 4, true, "a loop round the room")
	for i, stop in ipairs (order.loop) do T.eq (R.Inside (stop.point), false, "outside the room: " .. i) end
	local guards, holders = {}, {}
	for i, place in ipairs (places) do
		if order:PatrolOf (place) then guards [#guards + 1] = i else holders [#holders + 1] = i end
	end
	T.eq (#guards >= 1 and #guards <= 3, true, "a share of the squad on patrol")
	T.eq (order:PatrolOf (places [1]), nil, "its leader, the first, holds inside")
	for _, i in ipairs (holders) do T.eq (R.Inside (places [i]), true, "the rest hold inside: " .. i) end
	local starts = {}
	for _, i in ipairs (guards) do starts [#starts + 1] = order:PatrolOf (places [i]) end
	table.sort (starts)
	for k = 2, #starts do T.eq (starts [k] > starts [k - 1], true, "each guard from its own stop of the loop") end
end)

T.test ("a lone soldier occupying patrols nothing", function ()
	local order, places = Holding (1)
	T.eq (order:PatrolOf (places [1]), nil, "it holds inside")
end)

T.test ("a guard missing, the alarm: stacks inside by the exit nearest where it was last heard from, hidden", function ()
	local order = Holding (6)
	T.eq (Orders.Awaiting (order), false, "occupying, no mission awaits")
	local last = { x = 0, y = -600, z = 0 }
	T.eq (order:Alarm (last, R.SPACING, R.AdmitAt (R.CENTER)), true, "raised")
	T.eq (order:Alarm (last, R.SPACING, R.AdmitAt (R.CENTER)), false, "the once")
	T.eq (Orders.Awaiting (order), true, "the squad awaits its leader's word")
	T.eq (order.alarm.exit, R.DOORS [3], "by the south door, nearest it")
	local taken = {}
	for i = 1, 5 do
		local spot = order:StackAt ({})
		T.eq (spot ~= nil and R.Inside (spot), true, "a spot inside: " .. i)
		T.eq (R.Watched (spot, R.DOORS [3]), false, "out of sight from outside: " .. i)
		for _, other in ipairs (taken) do T.eq (R.Distance2D (spot, other) >= R.SPACING, true, "apart: " .. i) end
		taken [#taken + 1] = spot
	end
	order:Signal ()
	T.eq (Orders.Awaiting (order), false, "on the leader's word, it moves")
end)

-- Four occupying, each on its leggings, led by the first.
local function Squad ()
	local order, places = Holding (4)
	local squad = {}
	for i = 1, 4 do
		local me, action, orders = F.OnOrder (order, places [i])
		me.name, me.admit = "red " .. i, R.AdmitAt (R.CENTER)
		squad [i] = { me = me, action = action, orders = orders }
	end
	order:Lead (squad [1].me)
	return order, squad
end

local function GuardOf (order, squad)
	for _, member in ipairs (squad) do
		if order:PatrolOf (member.me.place) then return member end
	end
end

T.test ("occupying, the leader holds inside and a guard patrols", function ()
	local order, squad = Squad ()
	T.eq (squad [1].orders.name, "LegsOccupy", "the occupation")
	T.eq (squad [1].action.name, "LegsHold", "its leader holds")
	T.eq (GuardOf (order, squad).action.name, "LegsGuard", "a guard patrols")
end)

T.test ("a guard walks the loop one way round, stopping a while at each corner", function ()
	local order, squad = Squad ()
	local guard = GuardOf (order, squad)
	local me = guard.me
	local index, now, stops = order:PatrolOf (me.place), 0, 0
	for _ = 1, #order.loop do
		local stop = order.loop [index]
		me.at, me.now = stop.point, now
		guard.action:Update (me)
		if stop.stop then
			stops = stops + 1
			T.eq (me.spot, stop.point, "it stands at a corner a while")
			now = now + Occupy.PATROL_STOP
			me.now = now
			guard.action:Update (me)
		end
		index = index % #order.loop + 1
		T.eq (me.spot, order.loop [index].point, "then on to the next stop, one way round")
	end
	T.eq (stops, 4, "a stop at each corner")
end)

T.test ("the leader asks its guards for a status report a while apart, and each answers it", function ()
	local order, squad = Squad ()
	local leader, guard = squad [1], GuardOf (order, squad)
	guard.action:Update (guard.me)
	leader.me.now = 1
	leader.orders:Update (leader.me)
	T.eq (#leader.me.said, 0, "not asked at once")
	leader.me.now = Occupy.CHECK_INTERVAL
	leader.orders:Update (leader.me)
	T.eq (leader.me.calls [1].call == "STATUS" and leader.me.calls [1].to == guard.me, true, "the guard asked, over the radio")
	guard.action:Update (guard.me)
	T.eq (guard.me.calls [1].call == "ALL_CLEAR" and guard.me.calls [1].to == leader.me, true, "it answers its leader")
	leader.me.now = Occupy.CHECK_INTERVAL + Occupy.CHECK_TIMEOUT + 1
	leader.orders:Update (leader.me)
	T.eq (order.alarm, nil, "answered, no alarm")
end)

-- The squad with a guard gone missing south of the room: its leader has raised the alarm, and every
-- member but the guard stands stacked.
local function StackedUp (director)
	local order, squad = Squad ()
	if director then Director.Set (order, director) end
	local leader, guard = squad [1], GuardOf (order, squad)
	guard.me.at = { x = 0, y = -560, z = 0 }
	guard.action:Update (guard.me)
	order:Ask (guard.me, 0)
	leader.me.now = Occupy.CHECK_TIMEOUT + 1
	leader.orders:Update (leader.me)
	local stacking = {}
	for _, member in ipairs (squad) do
		if member ~= guard then
			member.action = Occupy.LegsStackUp:New ({ order = order })
			member.action:Update (member.me)
			member.me.at = order:StackAt (member.me)
			member.action:Update (member.me)
			stacking [#stacking + 1] = member
		end
	end
	order.size = #stacking
	return order, squad, leader, guard, stacking
end

T.test ("a guard silent past the timeout is missing: the leader tells the director and the squad stacks up", function ()
	local order, _, leader, guard = StackedUp ()
	local lost, stack = F.Calls (leader.me, "LOST") [1], F.Calls (leader.me, "STACK_UP") [1]
	T.eq (lost and lost.to, Radio.DIRECTOR, "the director told")
	T.eq (lost and lost.text, "Lost contact with " .. guard.me.name .. ".", "of whom")
	T.eq (stack and stack.to, Radio.SQUAD, "the squad told to stack up")
	T.eq (order.alarm.exit.y, -400, "by the south door, where it was last heard from")
	T.eq (order.alarm.at.y, -560, "where it was last heard from")
end)

T.test ("stacked up, the leader asks its director for clearance, and waits for it", function ()
	local asked = {}
	local order, _, leader, _, stacking = StackedUp ({ Request = function (_, _, request) asked [#asked + 1] = request end })
	leader.orders:Update (leader.me)
	T.eq (#asked == 1 and asked [1].kind == "VACATE", true, "the director asked to vacate")
	T.eq (F.Calls (leader.me, "REQUEST_VACATE") [1].to, Radio.DIRECTOR, "over the radio")
	T.eq (order:Signalled (), false, "no word to move before it answers")
	leader.orders:Update (leader.me)
	T.eq (#asked, 1, "asked the once")
	Director.Answer (order, "VACATE")
	leader.orders:Update (leader.me)
	T.eq (order:Signalled (), true, "cleared, the word to move")
	T.eq (#F.Calls (leader.me, "MOVE_IN"), 1, "Move in!")
	stacking [2].action:Update (stacking [2].me)
	T.eq (stacking [2].me.spot, order.alarm.at, "to where the guard was last heard from")
	T.eq (stacking [2].me.gait, GIB.GAIT.RUN, "at a run")
end)

T.test ("the leader's request goes out over the radio before the director's answer comes back", function ()
	local order, _, leader = StackedUp ({ Request = function (_, o) Director.Answer (o, "VACATE") end })
	leader.orders:Update (leader.me)
	local calls, request, answer = Radio.Calls (order)
	for i, entry in ipairs (calls) do
		if entry.call == "REQUEST_VACATE" then request = i end
		if entry.call == "VACATE" then answer = i end
	end
	T.eq (request ~= nil and answer ~= nil and request < answer, true, "asked, then answered")
end)

T.test ("told to stand by, the squad stands down and the leader appoints a holder to the missing guard's round", function ()
	local order, _, leader, _, stacking = StackedUp ({ Request = function (_, o) Director.Answer (o, "STANDBY") end })
	leader.orders:Update (leader.me)
	T.eq (order.alarm, nil, "the alarm let go")
	T.eq (Orders.Awaiting (order), false, "no mission awaits")
	local appointed = F.Calls (leader.me, "TAKE_PATROL") [1]
	T.eq (appointed ~= nil and appointed.to ~= leader.me, true, "a holder appointed over the radio, not the leader")
	local stop = order:AppointedTo (appointed.to)
	T.eq (stop ~= nil, true, "to the missing guard's round")
	for _, member in ipairs (stacking) do
		local result = member.action:Update (member.me)
		T.eq (result.type, Action.CHANGE_TO, "back from the stack")
		if member.me == appointed.to then
			T.eq (result.action.name, "LegsGuard", "the appointed to patrol")
			result.action:Update (member.me)
			T.eq (member.me.spot, order.loop [stop].point, "from the missing guard's stop")
		else
			T.eq (result.action.name, "LegsHold", "the rest back to holding")
		end
	end
end)

T.test ("told to stand by before any has stacked, the leader still appoints a holder", function ()
	local order, squad = Squad ()
	Director.Set (order, { Request = function (_, o) Director.Answer (o, "STANDBY") end })
	local leader, guard = squad [1], GuardOf (order, squad)
	for _, member in ipairs (squad) do member.action:Update (member.me) end
	guard.me.at = { x = 0, y = -560, z = 0 }
	guard.action:Update (guard.me)
	order:Ask (guard.me, 0)
	leader.me.now = Occupy.CHECK_TIMEOUT + 1
	leader.orders:Update (leader.me)
	leader.orders:Update (leader.me)
	local appointed = F.Calls (leader.me, "TAKE_PATROL") [1]
	T.eq (appointed ~= nil and appointed.to ~= leader.me and appointed.to ~= guard.me, true, "a holder appointed")
end)

T.test ("told to defend or attack, the leader acknowledges and waits stacked for its new order", function ()
	local order, _, leader = StackedUp ({ Request = function (_, o) Director.Answer (o, "DEFEND", { plan = "AMBUSH" }) end })
	leader.orders:Update (leader.me)
	leader.orders:Update (leader.me)
	T.eq (#F.Calls (leader.me, "COPY"), 1, "acknowledged, the once")
	T.eq (F.Calls (leader.me, "COPY") [1].to, Radio.DIRECTOR, "to the director")
	T.eq (order:Signalled (), false, "not vacating")
	T.eq (order.alarm ~= nil, true, "still stacked")
end)

T.test ("contact while stacked up engages the squad where it stands", function ()
	local order, _, _, _, stacking = StackedUp ({ Request = function () end })
	stacking [2].me.contact = true
	stacking [2].action:Update (stacking [2].me)
	T.eq (Orders.Awaiting (order), false, "fighting")
	T.eq (order:Signalled (), false, "not vacating")
end)

T.test ("guards silent together are all missing, and the leader's request counts each lost", function ()
	local asked = {}
	local order, squad = Squad ()
	Director.Set (order, { Request = function (_, _, request) asked [#asked + 1] = request end })
	local leader, guards = squad [1], {}
	for _, member in ipairs (squad) do
		if member ~= leader then
			member.action = Occupy.LegsGuard:New ({ order = order, stop = #guards + 1 })
			member.action:Update (member.me)
			order:Ask (member.me, 0)
			guards [#guards + 1] = member
		end
	end
	order:Answered (guards [1].me, guards [1].me:NSLegsAt ())
	leader.me.now = Occupy.CHECK_TIMEOUT + 1
	leader.orders:Update (leader.me)
	T.eq (#F.Calls (leader.me, "LOST"), #guards - 1, "the director told of each")
	leader.orders:Update (leader.me)
	T.eq (asked [1] and asked [1].missing, #guards - 1, "each counted in the request")
end)

T.test ("the tuning of an occupation is defined", function ()
	for _, name in ipairs ({ "PATROL_OUT", "GUARD_SPAN", "PATROL_STOP", "CHECK_INTERVAL", "CHECK_TIMEOUT" }) do
		T.defined (Occupy [name], name)
	end
end)

T.finish ()
