-- The chain of command in a squad: its leader killed while its mission is under way
-- (nextsoldier.squad.orders' Underway), the first member to hear of it abandons the mission, takes
-- the lead and calls the fall back, the squad evacuating away from where its leader fell.
--
-- Casualty(order, member, at): a member killed at at, told before the order's own Casualty (which
-- forgets its leader). Abandon(order, me) -> the radio's entry, the once a mission is abandoned
-- (me then leading); nil otherwise.
local Orders = nextsoldier.squad.orders
local Radio = nextsoldier.squad.comms.radio
module ("nextsoldier.squad.interactions.command")

function Casualty (order, member, at)
	if member == order.leader then order.leaderKilledAt = at end
end

function Abandon (order, me)
	local at = order.leaderKilledAt
	if not at or order.routed or not Orders.Underway (order) then return nil end
	if order.leader == nil then order:Lead (me) end
	if order.leader ~= me or not order:Endanger (at) then return nil end
	return Radio.Say (order, me, Radio.SQUAD, "FALL_BACK")
end
