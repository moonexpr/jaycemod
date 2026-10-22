-- foundation.player_analytics: players' joins, leaves and victories (an
-- enemy killed, a capture, a round won), read back as retention by day
-- cohort and the time to each player's first victory of each kind.
local T = dofile("tests/harness.lua")
local A = T.require("foundation.player_analytics")

local DAY, HOUR, MINUTE = 86400, 3600, 60
local D0 = 20000 * DAY -- a day's start, in Unix seconds
local ANN, BOB, CAT = "76561198000000001", "76561198000000002", "76561198000000003"

local function Raises(fn, pattern, what)
	local ok, err = pcall(fn)
	T.eq(ok, false, what .. " raises")
	T.eq(tostring(err):find(pattern, 1, true) ~= nil, true, what .. " says " .. pattern .. ": " .. tostring(err))
end

T.test("events go to lines and back", function()
	local events = {
		A.Join(ANN, D0),
		A.Victory(A.ROUND, { ANN, BOB }, D0 + 10),
		A.Leave(ANN, D0 + 20),
	}
	local back = {}
	for i, e in ipairs(events) do back[i] = A.Parse(A.Encode(e), i) end
	T.eq(back[1].kind, A.JOIN, "join")
	T.eq(back[1].id, ANN, "its player")
	T.eq(back[2].victory, A.ROUND, "the victory's kind")
	T.eq(table.concat(back[2].ids, ","), ANN .. "," .. BOB, "its players")
	T.eq(back[3].at, D0 + 20, "when")
end)

T.test("a line that is not an event is refused with its number", function()
	Raises(function() A.Parse("dance\t1\t2", 7) end, "line 7", "an unknown kind")
	Raises(function() A.Parse("join\tnotanid\t2", 8) end, "line 8", "a bad id")
	Raises(function() A.Parse("join\t" .. ANN .. "\tsoon", 9) end, "line 9", "a bad time")
end)

T.test("an id is a SteamID64, digits only", function()
	Raises(function() A.Join("STEAM_0:1:2", D0) end, "SteamID64", "a SteamID")
end)

T.test("play time sums the sessions; a rejoin within the gap is the same session", function()
	local players = A.Players({
		A.Join(ANN, D0),
		A.Leave(ANN, D0 + HOUR),
		A.Join(ANN, D0 + HOUR + 30), -- a map change
		A.Leave(ANN, D0 + 2 * HOUR),
		A.Join(ANN, D0 + 5 * HOUR),
		A.Leave(ANN, D0 + 6 * HOUR),
	}, D0 + DAY)
	local ann = players[ANN]
	T.eq(ann.sessions, 2, "two sessions")
	T.eq(ann.playSeconds, 3 * HOUR - 30, "play time without the gap")
	T.eq(ann.firstSeen, D0, "first seen")
end)

T.test("a session left open (a crash) is closed at the next join, or at now", function()
	local players = A.Players({
		A.Join(ANN, D0),
		A.Join(ANN, D0 + 2 * HOUR),
		A.Leave(ANN, D0 + 3 * HOUR),
		A.Join(BOB, D0),
	}, D0 + 10 * MINUTE)
	T.eq(players[ANN].sessions, 2, "the open one ended at the next join")
	T.eq(players[BOB].playSeconds, 10 * MINUTE, "still playing: up to now")
end)

T.test("a player's first victory of each kind, with the play time and sessions before it", function()
	local players = A.Players({
		A.Join(ANN, D0),
		A.Join(BOB, D0),
		A.Victory(A.KILL, { BOB }, D0 + 5 * MINUTE),
		A.Leave(ANN, D0 + HOUR),
		A.Join(ANN, D0 + DAY),
		A.Victory(A.CAPTURE, { ANN, BOB }, D0 + DAY + 10 * MINUTE),
		A.Victory(A.ROUND, { ANN }, D0 + DAY + 20 * MINUTE),
		A.Victory(A.ROUND, { ANN }, D0 + DAY + 40 * MINUTE),
	}, D0 + 2 * DAY)
	local ann = players[ANN]
	T.eq(ann.first[A.ROUND].playSeconds, HOUR + 20 * MINUTE, "play time to her first round win")
	T.eq(ann.first[A.ROUND].sessions, 2, "in her second session")
	T.eq(ann.first[A.ROUND].wallSeconds, DAY + 20 * MINUTE, "since first seen")
	T.eq(ann.first[A.KILL], nil, "no kill yet")
	T.eq(ann.first[A.ANY].playSeconds, HOUR + 10 * MINUTE, "her first victory of any kind: the capture")
	T.eq(ann.victories[A.ROUND], 2, "both round wins counted")
	T.eq(players[BOB].first[A.ANY].playSeconds, 5 * MINUTE, "bob's first: the kill")
	T.eq(players[BOB].first[A.CAPTURE].playSeconds, DAY + 10 * MINUTE, "bob never left")
end)

T.test("an unknown victory kind is refused", function()
	Raises(function() A.Victory("dance", { ANN }, D0) end, "kind", "dance")
end)

T.test("a victory for someone never seen joining is dropped, not counted", function()
	local players = A.Players({ A.Victory(A.ROUND, { CAT }, D0) }, D0)
	T.eq(players[CAT], nil, "no such player")
end)

T.test("retention: each day's new players, back the next day and within a week", function()
	local players = A.Players({
		A.Join(ANN, D0), A.Leave(ANN, D0 + HOUR),
		A.Join(BOB, D0 + 2 * HOUR), A.Leave(BOB, D0 + 3 * HOUR),
		A.Join(CAT, D0 + DAY), A.Leave(CAT, D0 + DAY + HOUR),
		A.Join(ANN, D0 + DAY + 2 * HOUR), A.Leave(ANN, D0 + DAY + 3 * HOUR),
		A.Join(BOB, D0 + 5 * DAY), A.Leave(BOB, D0 + 5 * DAY + HOUR),
	}, D0 + 9 * DAY)
	local cohorts = A.Retention(players, D0 + 9 * DAY)
	T.eq(#cohorts, 2, "two days with new players")
	local first = cohorts[1]
	T.eq(first.day, D0 / DAY, "the first day")
	T.eq(first.new, 2, "ann and bob")
	T.eq(first.day1, 1, "ann came back the next day")
	T.eq(first.day7, 2, "bob within the week")
	T.eq(cohorts[2].new, 1, "cat")
	T.eq(cohorts[2].day1, 0, "not back")
end)

T.test("a cohort too young to know is not yet counted", function()
	local players = A.Players({ A.Join(ANN, D0), A.Leave(ANN, D0 + HOUR) }, D0 + 3 * DAY)
	local cohort = A.Retention(players, D0 + 3 * DAY)[1]
	T.eq(cohort.day1, 0, "day 1 has passed")
	T.eq(cohort.day7, nil, "day 7 has not")
end)

T.test("first victory: how many have had one of each kind, and the median time it took", function()
	local players = A.Players({
		A.Join(ANN, D0), A.Victory(A.KILL, { ANN }, D0 + 10 * MINUTE),
		A.Join(BOB, D0), A.Victory(A.ROUND, { BOB }, D0 + 30 * MINUTE),
		A.Join(CAT, D0),
	}, D0 + HOUR)
	local fv = A.FirstVictory(players)
	T.eq(fv[A.ANY].won, 2, "two have had a victory")
	T.eq(fv[A.ANY].notYet, 1, "one has not")
	T.eq(fv[A.ANY].medianPlaySeconds, 20 * MINUTE, "the median of 10 and 30 minutes")
	T.eq(fv[A.ANY].medianSessions, 1, "in their first session")
	T.eq(fv[A.KILL].won, 1, "one kill")
	T.eq(fv[A.CAPTURE].won, 0, "no capture")
	T.eq(fv[A.CAPTURE].medianPlaySeconds, nil, "no median of nothing")
end)

T.finish()
