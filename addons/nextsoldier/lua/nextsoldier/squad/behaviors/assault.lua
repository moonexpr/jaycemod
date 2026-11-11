-- The base's assault (behavior.group_identity's Assault, gib_behaviors' LegsAssault) as a squad
-- mission: it awaits its leader's signal ("Move in!"), and is under way until the room is called
-- clear or the squad falls back. Its leggings are the base's own.
local Orders = nextsoldier.squad.orders
module ("nextsoldier.squad.behaviors.assault")

Orders.Register (
	{
		kind = "Assault",
		awaiting = function (order) return not order.routed and not order:Signalled () end,
		underway = function (order) return not order.routed and not order.cleared end
	}
)
