-- ws_proxy: an unseen box an admin right-clicks for an entity with no
-- body of its own to click (a cart's watcher, from the cart or one of its
-- checkpoints). Only GMod's right-click trace finds it (properties'
-- GetHovered falls back to MASK_ALL); bullets, players and NPCs pass
-- through. Its target names what the right-click entries act on.
local T = dofile("tests/harness.lua")

local MASK_ALL, MASK_SHOT, MASK_PLAYERSOLID = 0xFFFFFFFF, 0x4600400B, 0x0201400B

local function Load()
	local ENT = {}
	local env = setmetatable({
		ENT = ENT,
		AddCSLuaFile = function() end,
		MASK_ALL = MASK_ALL,
		util = {
			IntersectRayWithOBB = function(start, delta) return { x = start.x + delta.x / 2 }, { z = 1 }, 0.5 end,
		},
		SERVER = true,
		CLIENT = false,
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/entities/entities/ws_proxy.lua")), env)()
	local proxy = setmetatable({
		GetPos = function() return {} end,
		GetAngles = function() return {} end,
		GetMins = function() return {} end,
		GetMaxs = function() return {} end,
	}, { __index = ENT })
	return ENT, proxy
end

T.test("only a MASK_ALL trace, the right-click's, hits it", function()
	local _, proxy = Load()
	local start, delta = { x = 0 }, { x = 100 }
	local hit = proxy:TestCollision(start, delta, false, nil, MASK_ALL)
	T.eq(hit ~= nil, true, "the right-click")
	T.eq(hit.HitPos.x, 50)
	T.eq(hit.Fraction, 0.5)
	T.eq(proxy:TestCollision(start, delta, false, nil, MASK_SHOT), nil, "bullets pass")
	T.eq(proxy:TestCollision(start, delta, true, nil, MASK_PLAYERSOLID), nil, "players pass")
end)

T.test("it is no spawnable thing and takes no tools", function()
	local ENT = Load()
	T.eq(ENT.Spawnable, false)
	T.eq(ENT.PhysgunDisabled, true)
	T.eq(next(ENT.m_tblToolsAllowed), nil, "no tool works on it")
end)

-- The cart's right-click entries (ws/sh_editors_cart.lua) show on a
-- proxy for a cart's watcher.
local function LoadCart()
	local added = {}
	local env = setmetatable({
		WS = { EditorAction = function(name, def) added[name] = def end },
		IsValid = function(v) return v ~= nil end,
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/gamemode/ws/sh_editors_cart.lua")), env)()
	return added
end

-- A proxy's kind and target as a client sees them: the kind, and no
-- target (a train watcher is never sent to clients).
local function Ent(class, kind, parent, children, proxy)
	return {
		GetClass = function() return class end,
		GetKind = function() return kind end,
		GetTarget = function() return nil end,
		GetParent = function() return parent end,
		GetChildren = function() return children or {} end,
		GetNW2Entity = function(_, name) return name == "ws_proxy" and proxy or nil end,
	}
end

T.test("the cart's entries show on a cart's proxy, by its kind, and nowhere else", function()
	local added = LoadCart()
	for _, name in ipairs({ "ws_retract_cart", "ws_advance_cart" }) do
		local match = added[name].match
		T.eq(match(Ent("ws_proxy", "cart")), true, name)
		T.eq(match(Ent("ws_proxy", "point")), false, name .. ": a point's proxy")
		T.eq(match(Ent("func_tracktrain")), false, name .. ": not a proxy")
	end
end)

-- GMod's right-click takes the first solid thing it hits, and on a cart
-- that is the cart's own prop, so the cart's entries show on whatever rides
-- the train that carries the cart's proxy.
T.test("the cart's entries also show on the train and the props riding it", function()
	local added = LoadCart()
	local proxy = Ent("ws_proxy", "cart")
	local train = Ent("func_tracktrain", nil, nil, { proxy })
	local prop = Ent("prop_physics", nil, train)
	local match = added.ws_advance_cart.match
	T.eq(match(train), true, "the train")
	T.eq(match(prop), true, "a prop riding it")
	T.eq(match(Ent("prop_physics", nil, Ent("func_tracktrain"))), false, "a train with no cart proxy")
end)

-- A payload cart's body is a prop the map ties to its train with a
-- constraint (pl_swiftwater's sspl_constraint), not parented to it: the
-- payload feature has it name the cart's proxy.
T.test("the cart's entries show on the body tied to the train, which names the cart's proxy", function()
	local added = LoadCart()
	local proxy = Ent("ws_proxy", "cart")
	local match = added.ws_retract_cart.match
	T.eq(match(Ent("prop_physics", nil, nil, nil, proxy)), true, "the cart's body")
	T.eq(match(Ent("prop_physics")), false, "another prop")
end)

T.finish()
