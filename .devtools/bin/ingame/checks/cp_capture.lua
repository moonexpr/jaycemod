-- Control points (docs/pass4-koth-cp.md §9.1, docs/aiwar-koth-cp.md §6):
-- after setup, BLU bots stand on the first point BLU may capture until it
-- is BLU's, then the next, until BLU wins the round. Before the first
-- capture some point BLU does not own must be closed to it by the capture
-- order; after each capture the order is recorded.
-- args: { team_size = n BLU bots on a point (default 3), timeout = seconds }
local Tests = WETSAND_TESTS
local S = WETSAND.STATE
local BLUE = WETSAND.TEAM_BLUE
local DEFAULT_TEAM_SIZE = 3
local SETUP_TIMEOUT = 100
local CAPTURE_TIMEOUT = 60
local DEFAULT_TIMEOUT = 300

local function NextPoint(capture)
	for _, point in ipairs(capture:Points()) do
		if capture:Owner(point) ~= BLUE and capture:IsInRound(point) and capture:TeamMayCapture(point, BLUE)
			and Tests.PointArea(capture, point) then
			return point
		end
	end
end

local function ClosedByOrder(capture)
	local closed = {}
	for _, point in ipairs(capture:Points()) do
		if capture:Owner(point) ~= BLUE and capture:IsInRound(point) and not capture:TeamMayCapture(point, BLUE) then
			closed[#closed + 1] = Tests.PointName(capture, point)
		end
	end
	return closed
end

return function(t)
	local capture, rounds = t:Feature("capture"), t:Feature("rounds")
	if not (capture and rounds) then return t:Skip("capture or rounds not loaded") end
	local deadline = CurTime() + (t.args.timeout or DEFAULT_TIMEOUT)

	local open, waited = t:WaitFor(SETUP_TIMEOUT, function()
		return WETSAND.State() == S.RND_RUNNING and rounds:PointsMayBeCaptured()
	end)
	t:Check("points may be captured (setup over)", open ~= nil,
		string.format("%s, setup %s, after %.1f s", Tests.StateName(WETSAND.State()), tostring(WETSAND.InSetup()), waited))
	if not open then return end
	t:Info("points_at_start", Tests.DescribePoints(capture, BLUE))
	local closed = ClosedByOrder(capture)
	t:Check("the capture order closes some point to BLU at the start", #closed > 0, table.concat(closed, ", "))

	local bots = {}
	for _, ply in ipairs(player.GetBots()) do
		if ply:Team() == BLUE and #bots < (t.args.team_size or DEFAULT_TEAM_SIZE) then bots[#bots + 1] = ply end
	end
	t:Check("BLU bots to capture with", #bots > 0, #bots .. " bots")

	local steps = {}
	while WETSAND.State() == S.RND_RUNNING and CurTime() < deadline do
		local point = NextPoint(capture)
		if not point then
			t:Check("a point BLU may capture while the round runs", false, table.concat(ClosedByOrder(capture), ", "))
			break
		end
		local area = Tests.PointArea(capture, point)
		t:Station(bots, function() return Tests.AreaSpots(area, #bots) end)
		local taken, took = t:WaitFor(CAPTURE_TIMEOUT, function()
			return capture:Owner(point) == BLUE or WETSAND.State() ~= S.RND_RUNNING
		end)
		t:Unstation()
		local name = Tests.PointName(capture, point)
		steps[#steps + 1] = {
			point = name,
			captured = capture:Owner(point) == BLUE,
			seconds = math.Round(took, 1),
			closed_after = ClosedByOrder(capture),
		}
		if not t:Check("BLU bots capture " .. name, capture:Owner(point) == BLUE,
			string.format("owner %d after %.1f s, %s", capture:Owner(point), took, Tests.StateName(WETSAND.State()))) then
			break
		end
		if not taken then break end
	end
	t:Info("captures", steps)
	t:Info("points_at_end", Tests.DescribePoints(capture, BLUE))
	t:Info("mini_round_stage", GetGlobal2Int("wetsand_mini_round_stage", 0))
	t:Check("BLU wins the round", WETSAND.State() == S.TEAM_WIN and Tests.Winner() == BLUE,
		Tests.StateName(WETSAND.State()) .. ", winner " .. Tests.Winner())
end
