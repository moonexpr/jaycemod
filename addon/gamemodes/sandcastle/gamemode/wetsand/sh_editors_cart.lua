-- A payload cart's right-click entries, for admins: back to its last
-- checkpoint, or on to its next. They show on a cart's proxy
-- (wetsand_proxy, kind "cart"), which the payload feature puts on the cart
-- and on each of its checkpoints, and on the cart's own train and props.
-- A cart's proxy, by its kind: its target, the watcher, is never sent to
-- clients, so a client knows the proxy by its kind alone, and the server
-- acts on its target.
local function IsCartProxy(ent)
	return IsValid(ent) and ent:GetClass() == "wetsand_proxy" and ent:GetKind() == "cart"
end

-- The cart's proxy ent is, or names (the cart's body, a prop the map ties
-- to the train), or rides with on the train: GMod's right-click stops at
-- the first solid thing, the cart itself, before it would reach the proxy.
local function CartProxy(ent)
	if IsCartProxy(ent) then return ent end
	local named = ent:GetNW2Entity("wetsand_proxy")
	if IsCartProxy(named) then return named end
	local root = ent
	while IsValid(root:GetParent()) do root = root:GetParent() end
	for _, child in ipairs(root:GetChildren()) do
		if IsCartProxy(child) then return child end
	end
end

local function IsCart(ent) return CartProxy(ent) ~= nil end
local function Watcher(ent) return CartProxy(ent):GetTarget() end

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
