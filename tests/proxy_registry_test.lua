-- WS.Proxy (ws/sv_proxy.lua): one proxy (ws_proxy) per
-- entity it stands at, made when missing; a cart's (a payload checkpoint is
-- a control point too) takes the place of a point's, never the other way.
-- Run against fakes of ents.Create and IsValid.
local T = dofile("tests/harness.lua")

local function Load()
	local made = {}
	local env = setmetatable({
		WS = {},
		ents = {
			Create = function(class)
				local p = { class = class, removed = false }
				function p:SetPos(v) self.pos = v end
				function p:SetKind(k) self.kind = k end
				function p:GetKind() return self.kind end
				function p:SetTarget(t) self.target = t end
				function p:SetMins(v) self.mins = v end
				function p:SetMaxs(v) self.maxs = v end
				function p:Spawn() end
				function p:SetCollisionBounds() end
				function p:SetParent(e) self.parent = e end
				function p:Remove() self.removed = true end
				made[#made + 1] = p
				return p
			end,
		},
		IsValid = function(v) return v ~= nil and not v.removed end,
		Vector = function(x, y, z)
			return setmetatable({ x = x, y = y, z = z }, { __add = function(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end })
		end,
		setmetatable = setmetatable,
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/gamemode/ws/sv_proxy.lua")), env)()
	return env.WS, made, env
end

local function At(name) return { name = name, GetPos = function() return { x = 1 } end } end
local MINS, MAXS = { x = -1 }, { x = 1 }

T.test("a proxy is made once for what it stands at, with its kind, target and box", function()
	local W, made = Load()
	local point, watcher = At("cp"), At("watcher")
	local p = W.Proxy(point, "point", point, MINS, MAXS)
	T.eq(p.class, "ws_proxy")
	T.eq(p.kind, "point")
	T.eq(p.target, point)
	T.eq(p.mins, MINS)
	local again, made2 = W.Proxy(point, "point", point, MINS, MAXS)
	T.eq(again, p, "the same one again")
	T.eq(made2, false, "not made this time")
	T.eq(select(2, W.Proxy(At("other"), "point", point, MINS, MAXS)), true, "a new one is made")
	T.eq(#made, 2)
end)

T.test("it rides what it is given to ride", function()
	local W = Load()
	local train = At("train")
	T.eq(W.Proxy(train, "cart", At("watcher"), MINS, MAXS, train).parent, train)
end)

T.test("a cart's proxy takes a point's place at a checkpoint; a point's never takes a cart's", function()
	local W, made = Load()
	local point, watcher = At("cp"), At("watcher")
	local pointProxy = W.Proxy(point, "point", point, MINS, MAXS)
	local cartProxy = W.Proxy(point, "cart", watcher, MINS, MAXS)
	T.eq(pointProxy.removed, true, "the point's is gone")
	T.eq(cartProxy.kind, "cart")
	T.eq(W.Proxy(point, "point", point, MINS, MAXS), cartProxy, "the cart's stays")
	T.eq(#made, 2)
end)

T.test("one removed (a cleanup) is made again", function()
	local W, made = Load()
	local point = At("cp")
	W.Proxy(point, "point", point, MINS, MAXS):Remove()
	W.Proxy(point, "point", point, MINS, MAXS)
	T.eq(#made, 2)
end)

-- GMod's right-click stops at the first solid thing: a point's base, a
-- checkpoint's, before the proxy above it. The props standing on its spot
-- name the proxy.
T.test("the props standing on its spot name the proxy; other things do not", function()
	local W, _, env = Load()
	local function Prop(class)
		local e = { class = class, nw = {} }
		function e:GetClass() return self.class end
		function e:SetNW2Entity(k, v) self.nw[k] = v end
		return e
	end
	local base, wall, player = Prop("prop_dynamic"), Prop("prop_physics"), Prop("player")
	env.ents.FindInBox = function() return { base, wall, player } end
	local proxy = {}
	W.ProxyBodies(proxy, env.Vector(0, 0, 0))
	T.eq(base.nw.ws_proxy, proxy, "the base")
	T.eq(wall.nw.ws_proxy, proxy, "a prop on the spot")
	T.eq(player.nw.ws_proxy, nil, "not a player")
end)

T.finish()
