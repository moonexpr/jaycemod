-- A payload cart's own right-click entries, for admins: back to its last
-- checkpoint, or on to its next. A cart is the train, or a prop riding it,
-- that the payload feature marks with its watcher (wetsand_cart_watcher).
local function Watcher(ent)
	local watcher = ent:GetNW2Entity("wetsand_cart_watcher")
	if IsValid(watcher) then return watcher end
end

local function IsCart(ent) return Watcher(ent) ~= nil end

WETSAND.EditorAction("wetsand_retract_cart", {
	match = IsCart, title = "Payload", label = "Retract Cart to Previous Checkpoint", icon = "icon16/arrow_left.png", order = 2100,
	run = function(e, ent) return e:RetractCart(Watcher(ent)) end,
	done = "the cart is back at its checkpoint (a point just taken is given back, with five more minutes)",
})

WETSAND.EditorAction("wetsand_advance_cart", {
	match = IsCart, title = "Payload", label = "Advance Cart to Next Checkpoint", icon = "icon16/arrow_right.png", order = 2101,
	run = function(e, ent) return e:AdvanceCart(Watcher(ent)) end,
	done = "the cart is on its way to the next checkpoint",
})
