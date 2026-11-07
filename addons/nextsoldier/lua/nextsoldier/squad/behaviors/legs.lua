-- What the squad's own leggings' actions share (nextsoldier.squad.behaviors' ambush and occupy): a
-- call over the radio said aloud, orders heard as the base's actions hear them, and where on a
-- room's floor members are placed.
--
-- Speak(me, order, to, call, ...) -> the radio's entry, said aloud (me:NSLegsSay(text, entry)).
-- OnOrders(self, me) -> a result: a new order (or none) changes the action back to ease, where the
-- base's leggings take it up; the first to see its leader lost takes the lead; the leader calls the
-- fall back on a danger near or heavy casualties. Evacuating(self) -> a change to evacuating once
-- the squad falls back, else nil.
-- Floor(room, spacing, admit) -> the room's floor in a lattice spacing / 2 apart, ROOM_INSET clear
-- of its walls; Nearest(slots, from, count, spacing) -> count of slots spacing apart, nearest from
-- first; Assign(point, slots, members) -> member index -> slot, the furthest from point choosing
-- first; Hidden(watched, p, door) -> whether one walking up to door sees neither p nor the ground
-- STACK_COVER round it.
local GroupIdentity = nextsoldier.behavior.group_identity
local GIB = nextsoldier.behavior.gib_behaviors
local Radio = nextsoldier.squad.comms.radio
local Geometry = math.geometry
local Select = list.select
local ipairs, cos, sin, pi, remove = ipairs, math.cos, math.sin, math.pi, table.remove
module("nextsoldier.squad.behaviors.legs")

function Speak(me, order, to, call, ...)
	local entry = Radio.Say(order, me, to, call, ...)
	me:NSLegsSay(entry.text, entry)
	return entry
end

function OnOrders(self, me)
	me:NSLegsSense()
	local order = me:NSLegsOrder()
	if order ~= self.order then
		return self:ChangeTo(GIB.LegsAtEase:New(), order and ("Told to " .. order.kind) or "Dissolved")
	end
	if order.leader == nil then order:Lead(me) end
	if order.leader ~= me then return self:Continue() end
	local danger = not order.routed and me:NSLegsDanger(order.point)
	if (danger and order:Endanger(danger)) or order:Rout() then Speak(me, order, Radio.SQUAD, "FALL_BACK") end
	return self:Continue()
end

function Evacuating(self)
	if self.order.mode ~= GroupIdentity.MODE.PANIC then return nil end
	return self:ChangeTo(GIB.LegsEvacuate:New({ order = self.order }), "Fall back")
end

function Floor(room, spacing, admit)
	local slots, step, inset = {}, spacing / 2, GroupIdentity.ROOM_INSET
	for x = room.lo.x + inset, room.hi.x - inset + 0.001, step do
		for y = room.lo.y + inset, room.hi.y - inset + 0.001, step do
			local slot = admit({ x = x, y = y, z = room.center.z })
			if slot then slots[#slots + 1] = slot end
		end
	end
	return slots
end

function Nearest(slots, from, count, spacing)
	local order = Select.Order(slots, function(a, b) return Geometry.Distance2D(a, from) < Geometry.Distance2D(b, from) end)
	local chosen = {}
	for _, i in ipairs(order) do
		if #chosen == count then break end
		local slot, clear = slots[i], true
		for _, other in ipairs(chosen) do
			if Geometry.Distance2D(slot, other) < spacing then clear = false break end
		end
		if clear then chosen[#chosen + 1] = slot end
	end
	return chosen
end

function Assign(point, slots, members)
	local places, open = {}, {}
	for i = 1, #slots do open[i] = slots[i] end
	local turn = Select.Order(members, function(a, b) return Geometry.Distance2D(a, point) > Geometry.Distance2D(b, point) end)
	for _, member in ipairs(turn) do
		local slot, _, at = Select.Lowest(open, function(s) return Geometry.Distance2D(members[member], s) end)
		if not slot then break end
		places[member] = slot
		remove(open, at)
	end
	return places
end

local AROUND = {}
for i = 0, 7 do
	AROUND[i + 1] = { cos(i * pi / 4) * GroupIdentity.STACK_COVER, sin(i * pi / 4) * GroupIdentity.STACK_COVER }
end

function Hidden(watched, p, door)
	if watched(p, door) then return false end
	for _, d in ipairs(AROUND) do
		if watched({ x = p.x + d[1], y = p.y + d[2], z = p.z }, door) then return false end
	end
	return true
end
