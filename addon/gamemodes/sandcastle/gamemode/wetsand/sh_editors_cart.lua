-- A payload cart's right-click entries, for admins: back to its last
-- checkpoint, or on to its next. They show on a proxy (wetsand_proxy) for
-- the cart's watcher, which the payload feature puts on the cart and on
-- each of its checkpoints, and on the cart's own train and props.
local function ProxyWatcher(proxy)
	if proxy:GetClass() ~= "wetsand_proxy" then return nil end
	local target = proxy:GetTarget()
	if IsValid(target) and target:GetClass() == "team_train_watcher" then return target end
end

-- The watcher of a proxy; else of the proxy ent names (the cart's body, a
-- prop the map ties to the train); else of the cart proxy riding the train
-- ent is or rides. GMod's right-click stops at the first solid thing, the
-- cart itself, before it would reach the cart's proxy.
local function Watcher(ent)
	local watcher = ProxyWatcher(ent)
	if watcher then return watcher end
	local named = ent:GetNW2Entity("wetsand_proxy")
	if IsValid(named) then return ProxyWatcher(named) end
	local root = ent
	while IsValid(root:GetParent()) do root = root:GetParent() end
	for _, child in ipairs(root:GetChildren()) do
		watcher = ProxyWatcher(child)
		if watcher then return watcher end
	end
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
