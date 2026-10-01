-- King of the Hill (docs/pass4-koth-cp.md §9.2), from a running round: the
-- point is locked and unlocks on its timer; both team clocks exist under
-- their map names; BLU bots on the hill capture it and run BLU's clock
-- while RED's stays paused; BLU's clock set to a few seconds runs out and
-- BLU wins.
local Tests = WETSAND_TESTS
local S = WETSAND.STATE
local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE
local CLOCK_NAMES = {
	[RED] = "zz_red_koth_timer",
	[BLUE] = "zz_blue_koth_timer",
}
local BOT_COUNT = 3
local UNLOCK_TIMEOUT = 60
local CAPTURE_TIMEOUT = 40
local CLOCK_SAMPLE = 2 -- seconds between two readings of a running clock
local CLOCK_TOLERANCE = 0.5
local SHORT_CLOCK = 5 -- seconds left on BLU's clock for the win
local WIN_TIMEOUT = 20

return function(t)
	local capture, rounds = t:Feature("capture"), t:Feature("rounds")
	if not (capture and rounds and t:Loaded("koth")) then return t:Skip("koth, capture or rounds not loaded") end
	t:Check("the round is running", WETSAND.State() == S.RND_RUNNING, Tests.StateName(WETSAND.State()))

	local points = capture:Points()
	t:Check("one point", #points == 1, #points .. " points")
	local point = points[1]
	if not point then return end
	local area = Tests.PointArea(capture, point)
	t:Info("point", Tests.PointName(capture, point))
	local unlockAt = capture:Set():UnlockAt(point)
	t:Info("unlocks_in_seconds", unlockAt and math.Round(unlockAt - CurTime(), 1) or "no unlock time")
	t:Check("the point starts locked", capture:Set():Locked(point), tostring(capture:Set():Locked(point)))

	local clocks = {}
	for team, name in pairs(CLOCK_NAMES) do
		clocks[team] = ents.FindByName(name)[1]
		t:Check(name .. " exists", IsValid(clocks[team]), tostring(clocks[team]))
		t:Check(name .. " is the team clock", rounds:TeamClock(team) == clocks[team], tostring(rounds:TeamClock(team)))
	end
	if not (IsValid(clocks[RED]) and IsValid(clocks[BLUE])) then return end

	local unlocked, waited = t:WaitFor(UNLOCK_TIMEOUT, function() return not capture:Set():Locked(point) end)
	t:Check("the point unlocks", unlocked ~= nil, string.format("after %.1f s more", waited))

	local bots = {}
	for _, ply in ipairs(player.GetBots()) do
		if ply:Team() == BLUE and #bots < BOT_COUNT then bots[#bots + 1] = ply end
	end
	t:Station(bots, function() return Tests.AreaSpots(area, #bots) end)
	local captured, took = t:WaitFor(CAPTURE_TIMEOUT, function() return capture:Owner(point) == BLUE end)
	t:Check(#bots .. " BLU bots on the hill capture it", captured ~= nil,
		string.format("owner %d after %.1f s", capture:Owner(point), took))

	local blueTimer, redTimer = rounds:TimerOf(clocks[BLUE]), rounds:TimerOf(clocks[RED])
	local blueBefore, redBefore = blueTimer:TimeRemaining(CurTime()), redTimer:TimeRemaining(CurTime())
	t:Wait(CLOCK_SAMPLE)
	local blueAfter, redAfter = blueTimer:TimeRemaining(CurTime()), redTimer:TimeRemaining(CurTime())
	t:Check("owning the point runs BLU's clock", not blueTimer:Paused() and blueBefore - blueAfter > CLOCK_SAMPLE - CLOCK_TOLERANCE,
		string.format("%.1f -> %.1f s, paused %s", blueBefore, blueAfter, tostring(blueTimer:Paused())))
	t:Check("RED's clock stays paused", redTimer:Paused() and math.abs(redBefore - redAfter) < CLOCK_TOLERANCE,
		string.format("%.1f -> %.1f s, paused %s", redBefore, redAfter, tostring(redTimer:Paused())))

	clocks[BLUE]:Fire("SetTime", tostring(SHORT_CLOCK))
	local won, wonAfter = t:WaitFor(WIN_TIMEOUT, function() return WETSAND.State() == S.TEAM_WIN end)
	t:Check("BLU's clock at 0 ends the round", won ~= nil,
		string.format("%s after %.1f s", Tests.StateName(WETSAND.State()), wonAfter))
	t:Check("BLU wins", Tests.Winner() == BLUE, "winner " .. Tests.Winner())
	t:Unstation()
end
