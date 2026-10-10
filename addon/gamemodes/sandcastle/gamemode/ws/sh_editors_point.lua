-- A control point's right-click entries, for admins: who owns it, quietly
-- (Set Owner: ForceOwner) or captured with the map's outputs (Set Team:
-- CapturePoint), and whether it is locked (SetPointLocked), through the
-- capture feature. They show on a point's proxy (ws_proxy, kind
-- "point", which the capture feature puts on every point that is not a
-- payload checkpoint) and on the props of its base, which name it: GMod's
-- right-click stops at the first solid thing, the base, before it would
-- reach the proxy. A point entity is never sent to clients, so a client
-- knows the proxy by its kind alone.
local RED, BLUE, NOBODY = WS.TEAM_RED, WS.TEAM_BLUE, WS.TEAM_UNASSIGNED

local function IsPointProxy(ent)
	return IsValid(ent) and ent:GetClass() == "ws_proxy" and ent:GetKind() == "point"
end

local function PointProxy(ent)
	if IsPointProxy(ent) then return ent end
	local named = ent:GetNW2Entity("ws_proxy")
	if IsPointProxy(named) then return named end
end

local function IsPoint(ent) return PointProxy(ent) ~= nil end
local function Point(ent) return PointProxy(ent):GetTarget() end

WS.EditorAction("ws_point_owner", {
	match = IsPoint, title = "Control Point", label = "Set Owner", icon = "icon16/flag_blue.png", order = 2100,
	choices = {
		{ label = WS.TeamName[RED], value = RED },
		{ label = WS.TeamName[BLUE], value = BLUE },
		{ label = "Neutral", value = NOBODY },
	},
	run = function(_, ent, team)
		WS.Feature("capture"):ForceOwner(Point(ent), team)
		return true
	end,
	done = "the point changed hands",
})

WS.EditorAction("ws_point_team", {
	match = IsPoint, title = "Control Point", label = "Set Team", icon = "icon16/flag_red.png", order = 2101,
	choices = {
		{ label = WS.TeamName[RED], value = RED },
		{ label = WS.TeamName[BLUE], value = BLUE },
	},
	run = function(_, ent, team) return WS.Feature("capture"):CapturePoint(Point(ent), team) end,
	done = "the point was captured, and the map told",
})

WS.EditorAction("ws_point_lock", {
	match = IsPoint, title = "Control Point", label = "Lock or Unlock", icon = "icon16/lock.png", order = 2102,
	choices = { { label = "Lock", value = 1 }, { label = "Unlock", value = 0 } },
	run = function(_, ent, value)
		WS.Feature("capture"):SetPointLocked(Point(ent), value == 1)
		return true
	end,
	done = "the point's lock changed",
})
