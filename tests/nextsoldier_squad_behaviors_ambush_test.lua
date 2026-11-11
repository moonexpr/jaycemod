-- nextsoldier.squad.behaviors.ambush: a squad lying in wait inside a room, beside the entrance the
-- enemy comes in by, out of its approach's sight, until its leader springs it.
local T = dofile ("tests/harness.lua")
local Ambush = nextsoldier.squad.behaviors.ambush
local Orders = nextsoldier.squad.orders
local Radio = nextsoldier.squad.comms.radio
local GIB = nextsoldier.behavior.gib_behaviors
local R = dofile ("tests/fake_room.lua")
local F = dofile ("tests/fake_legs.lua")

local function Lying (enemyFlows, count)
	local order = Ambush.Ambush (R.Room ({ 0, 0, 0, 0 }, enemyFlows))
	local at = R.East (count or 6)
	return order, order:Places (at, R.SPACING, R.AdmitAt (R.CENTER), R.AdmitAt), at
end

T.test ("an ambush lies in wait inside, beside the entrance the enemy comes in by, hidden from its approach", function ()
	local order, places = Lying ({ 3, 0, 0, 1 })
	T.eq (order.kind, "Ambush", "an ambush")
	T.eq (order.entrance, R.DOORS [1], "at the entrance the most of the enemy comes in by")
	for i = 1, 6 do
		local place = places [i]
		T.eq (place ~= nil, true, "placed: " .. i)
		T.eq (R.Inside (place), true, "inside: " .. i)
		T.eq (R.Watched (place, R.DOORS [1]), false, "out of the approach's sight: " .. i)
		T.eq (R.Distance2D (place, R.DOORS [1]) <= Ambush.AMBUSH_REACH, true, "beside the entrance: " .. i)
		for j = i + 1, 6 do T.eq (R.Distance2D (place, places [j]) >= R.SPACING, true, "apart: " .. i .. "," .. j) end
	end
end)

T.test ("an ambush is refused a room it cannot hide in, or one the enemy is not known to come into", function ()
	local room = R.Room ({ 0, 0, 0, 0 }, { 0, 0, 0, 0 })
	room.watched = nil
	local ok, err = pcall (Ambush.Ambush, room)
	T.eq (not ok and tostring (err):find ("watched", 1, true) ~= nil, true, "refused, unable to hide")
	room.watched = R.Watched
	ok, err = pcall (Ambush.Ambush, room)
	T.eq (not ok and tostring (err):find ("enemy", 1, true) ~= nil, true, "refused, the enemy's way in unknown")
end)

T.test ("a mission awaiting its springing, once, then fought out where it lies", function ()
	local order = Lying ({ 3, 0, 0, 0 })
	T.eq (Orders.Awaiting (order), true, "lying in wait")
	T.eq (order:Spring (), true, "sprung")
	T.eq (order:Spring (), false, "the once")
	T.eq (Orders.Awaiting (order), false, "activated")
	T.eq (Orders.Underway (order), true, "fought out where it lies")
end)

-- Three lying in wait, each on its leggings, led by the first.
local function Squad ()
	local order, places, at = Lying ({ 2, 0, 0, 0 }, 3)
	local squad = {}
	for i = 1, 3 do
		local me, _, orders = F.OnOrder (order, places [i])
		me.at = at [i]
		squad [i] = { me = me, orders = orders }
	end
	order:Lead (squad [1].me)
	return order, squad
end

T.test ("told an ambush, a member runs to its place and lies in wait there, crouched", function ()
	local order, squad = Squad ()
	local me, ambush = squad [2].me, squad [2].orders
	T.eq (ambush.name, "LegsAmbush", "the ambush")
	ambush:Update (me)
	T.eq (me.spot, me.place, "to its place")
	T.eq (me.gait, GIB.GAIT.RUN, "running")
	me.at = me.place
	ambush:Update (me)
	T.eq (me.gait, GIB.GAIT.REST, "lying in wait")
	T.eq (order:Sprung (), false, "not sprung")
end)

T.test ("an enemy seen by the entrance, its leader springs the ambush over the radio", function ()
	local order, squad = Squad ()
	local member, leader = squad [2], squad [1]
	member.me.enemyAt = { x = 0, y = 0, z = 0 }
	member.orders:Update (member.me)
	leader.orders:Update (leader.me)
	T.eq (order:Sprung (), false, "an enemy far off is let come on")
	member.me.enemyAt = { x = -400 - Ambush.SPRING_RANGE + 10, y = 0, z = 0 }
	member.orders:Update (member.me)
	T.eq (order:Sprung (), false, "the leader springs it, not the member")
	leader.orders:Update (leader.me)
	T.eq (order:Sprung (), true, "sprung")
	T.eq (F.Calls (leader.me, "NOW") [1].to, Radio.SQUAD, "Now!, to the squad")
end)

T.test ("a member hurt lying in wait, its leader springs the ambush", function ()
	local order, squad = Squad ()
	squad [3].me.hurt = true
	squad [3].orders:Update (squad [3].me)
	squad [1].orders:Update (squad [1].me)
	T.eq (order:Sprung (), true, "sprung")
end)

T.test ("falling back, it evacuates", function ()
	local order, squad = Squad ()
	order:Endanger ({ x = -500, y = 0, z = 0 })
	local result = squad [2].orders:Update (squad [2].me)
	T.eq (result.action.name, "LegsEvacuate", "evacuating")
end)

T.test ("the tuning of an ambush is defined", function ()
	T.defined (Ambush.AMBUSH_REACH, "AMBUSH_REACH")
	T.defined (Ambush.SPRING_RANGE, "SPRING_RANGE")
end)

T.finish ()
