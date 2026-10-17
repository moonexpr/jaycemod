-- A control point's right-click entries (ws/sh_editors_point.lua), for
-- admins: its owner, and whether it is locked. They show on a point's proxy
-- (ws_proxy, kind "point") and on the props of its base, which name it,
-- and act on the point through the capture feature.
local T = dofile("tests/harness.lua")

local RED, BLUE, NOBODY = 2, 3, 0

local function Load(capture)
	local added = {}
	local env = setmetatable({
		WS = {
			TEAM_RED = RED, TEAM_BLUE = BLUE, TEAM_UNASSIGNED = NOBODY,
			TeamName = { [RED] = "RED", [BLUE] = "BLU" },
			EditorAction = function(name, def) added[name] = def end,
			Feature = function(name) assert(name == "capture", name) return capture end,
		},
		IsValid = function(v) return v ~= nil end,
	}, { __index = _G })
	setfenv(assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_editors_point.lua")), env)()
	return added
end

local function Ent(class, kind, target, proxy)
	return {
		GetClass = function() return class end,
		GetKind = function() return kind end,
		GetTarget = function() return target end,
		GetNW2Entity = function(_, name) return name == "ws_proxy" and proxy or nil end,
	}
end

local function Capture()
	local c = { calls = {} }
	function c:ForceOwner(point, team) self.calls[#self.calls + 1] = { "owner", point, team } end
	function c:SetPointLocked(point, locked) self.calls[#self.calls + 1] = { "locked", point, locked } end
	function c:CapturePoint(point, team)
		self.calls[#self.calls + 1] = { "capture", point, team }
		return self.refuse == nil, self.refuse
	end
	return c
end

T.test("its entries show on a point's proxy and on the props of its base, nowhere else", function()
	local added = Load(Capture())
	local proxy = Ent("ws_proxy", "point")
	for _, name in ipairs({ "ws_point_owner", "ws_point_team", "ws_point_lock" }) do
		local match = added[name].match
		T.eq(match(proxy), true, name)
		T.eq(match(Ent("prop_dynamic", nil, nil, proxy)), true, name .. ": its base")
		T.eq(match(Ent("ws_proxy", "cart")), false, name .. ": a cart's proxy")
		T.eq(match(Ent("prop_dynamic")), false, name .. ": another prop")
	end
end)

T.test("Set Owner gives the point to RED, BLU or nobody", function()
	local added = Load(Capture())
	local values = {}
	for _, choice in ipairs(added.ws_point_owner.choices) do values[#values + 1] = choice.value end
	T.eq(table.concat(values, ","), RED .. "," .. BLUE .. "," .. NOBODY)
	local capture = Capture()
	added = Load(capture)
	local point = {}
	T.eq(added.ws_point_owner.run(nil, Ent("ws_proxy", "point", point), BLUE), true)
	T.eq(capture.calls[1][1], "owner")
	T.eq(capture.calls[1][2], point, "the proxy's point")
	T.eq(capture.calls[1][3], BLUE)
end)

T.test("Lock or Unlock, from the proxy or the base", function()
	local capture = Capture()
	local added = Load(capture)
	local point = {}
	local proxy = Ent("ws_proxy", "point", point)
	added.ws_point_lock.run(nil, proxy, 1)
	added.ws_point_lock.run(nil, Ent("prop_dynamic", nil, nil, proxy), 0)
	T.eq(capture.calls[1][3], true, "locked")
	T.eq(capture.calls[2][2], point, "through its base")
	T.eq(capture.calls[2][3], false, "unlocked")
end)

-- Set Team captures it for RED or BLU as a player's SetOwner input would:
-- the map's outputs fire (OnOwnerChangedTo..., OnCap...), its capture sound
-- plays and it scores; Set Owner forces it quietly.
T.test("Set Team captures it for RED or BLU, with its outputs, and says why not when it cannot", function()
	local capture = Capture()
	local added = Load(capture)
	local values = {}
	for _, choice in ipairs(added.ws_point_team.choices) do values[#values + 1] = choice.value end
	T.eq(table.concat(values, ","), RED .. "," .. BLUE)
	local point = {}
	T.eq(added.ws_point_team.run(nil, Ent("ws_proxy", "point", point), RED), true)
	T.eq(capture.calls[1][1], "capture")
	T.eq(capture.calls[1][2], point)
	T.eq(capture.calls[1][3], RED)
	capture.refuse = "points cannot be captured now"
	local ok, why = added.ws_point_team.run(nil, Ent("ws_proxy", "point", point), BLUE)
	T.eq(ok, false)
	T.eq(why, "points cannot be captured now")
end)

T.finish()
