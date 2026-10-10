-- Proxies (ws_proxy): the boxes an admin right-clicks for what has no
-- body of its own to click. WS.Proxy keeps one for each entity it
-- stands at, made when missing (a cleanup removed it); a payload
-- checkpoint is a control point too, and a cart's proxy (kind "cart")
-- takes the place of a point's ("point"), never the other way round.
local RANK = { point = 1, cart = 2 }
local proxies = setmetatable({}, { __mode = "k" }) -- entity it stands at -> its proxy

-- The proxy of kind for target at at's position, its box mins..maxs,
-- riding parent when given; and whether it was made just now.
function WS.Proxy(at, kind, target, mins, maxs, parent)
	local old = proxies[at]
	if IsValid(old) then
		if RANK[old:GetKind()] >= RANK[kind] then return old, false end
		old:Remove()
	end
	local proxy = ents.Create("ws_proxy")
	proxy:SetPos(at:GetPos())
	proxy:SetKind(kind)
	proxy:SetTarget(target)
	proxy:SetMins(mins)
	proxy:SetMaxs(maxs)
	proxy:Spawn()
	proxy:SetCollisionBounds(mins, maxs)
	if parent then proxy:SetParent(parent) end
	proxies[at] = proxy
	return proxy, true
end

-- GMod's right-click stops at the first solid thing, the base of a point or
-- a checkpoint, before it would reach the proxy above it: the props
-- standing on the spot (BODY_MINS..BODY_MAXS about center) name the proxy,
-- as ws_proxy, which the right-click entries follow.
local BODY_MINS, BODY_MAXS = Vector(-64, -64, -32), Vector(64, 64, 96)

function WS.ProxyBodies(proxy, center)
	for _, ent in ipairs(ents.FindInBox(center + BODY_MINS, center + BODY_MAXS)) do
		if ent:GetClass():sub(1, 5) == "prop_" then ent:SetNW2Entity("ws_proxy", proxy) end
	end
end
