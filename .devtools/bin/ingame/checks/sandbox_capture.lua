-- Sandbox mode (docs/pass4-koth-cp.md, foundation.rounds Round:Halt): the
-- rounds wait in BETWEEN_RNDS "whatever the map or players do". BLU bots on
-- a point make no capture progress; a capture completed by the point's
-- SetOwner input and the master's SetWinner leave the rounds in
-- BETWEEN_RNDS.
local Tests = WS_TESTS
local BLUE = WS.TEAM_BLUE
local BOT_COUNT = 2
local HOLD_SECONDS = 8
local SETTLE = 2

return function(t)
	local capture = t:Feature("capture")
	if not capture then return t:Skip("the capture feature is not loaded") end
	t:Check("in Sandbox mode before the check", WS.GameplayStopped(), Tests.StateName(WS.State()))

	local point
	for _, p in ipairs(capture:Points()) do
		if capture:Owner(p) ~= BLUE and Tests.PointArea(capture, p) then
			point = p
			break
		end
	end
	if not point then return t:Check("a point BLU does not own, with an area", false, "none") end
	local name, area = Tests.PointName(capture, point), Tests.PointArea(capture, point)
	t:Info("point", name)
	local ownerBefore = capture:Owner(point)

	local bots = t:Bots(BOT_COUNT)
	t:Check("bots joined BLU and are alive", t:Join(bots, BLUE), #bots .. " bots")
	t:Station(bots, function() return Tests.AreaSpots(area, #bots) end)
	t:Wait(HOLD_SECONDS)
	local inside = #WS.PlayersInside(area)
	t:Info("bots_inside_area", inside)
	t:Check("BLU bots stood in the point's area", inside == #bots, inside .. " of " .. #bots)
	t:Check("no capture in Sandbox mode: owner unchanged", capture:Owner(point) == ownerBefore,
		"owner " .. capture:Owner(point) .. ", was " .. ownerBefore)
	t:Check("no capture in progress", not capture:IsCapturing(point), tostring(capture:IsCapturing(point)))
	t:Check("still BETWEEN_RNDS with bots on the point", WS.State() == WS.STATE.BETWEEN_RNDS,
		Tests.StateName(WS.State()))
	t:Unstation()

	point:Fire("SetOwner", tostring(BLUE))
	t:Wait(SETTLE)
	t:Info("owner_after_set_owner", capture:Owner(point))
	t:Check("still BETWEEN_RNDS after the point's SetOwner " .. BLUE, WS.State() == WS.STATE.BETWEEN_RNDS,
		Tests.StateName(WS.State()) .. ", owner now " .. capture:Owner(point))

	for _, master in ipairs(ents.FindByClass("team_control_point_master")) do
		master:Fire("SetWinner", tostring(BLUE))
	end
	t:Wait(SETTLE)
	t:Check("still BETWEEN_RNDS after the master's SetWinner " .. BLUE, WS.State() == WS.STATE.BETWEEN_RNDS,
		Tests.StateName(WS.State()))
	t:Check("still in Sandbox mode", WS.GameplayStopped(), tostring(WS.GameplayStopped()))
end
