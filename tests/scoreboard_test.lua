-- foundation.scoreboard: who goes in which team's column and in what order,
-- and the match's win conditions as TF2's scoreboard words them.
local T = dofile("tests/harness.lua")
local Board = T.require("foundation.scoreboard")
local Teams = T.require("games.gameplay.teams")
local Rounds = T.require("games.gameplay.rounds")
local RED, BLUE, SPECTATOR, UNASSIGNED = Teams.RED, Teams.BLUE, Teams.SPECTATOR, Teams.UNASSIGNED
local SANDBOX_UNASSIGNED = 1001 -- GMod's TEAM_UNASSIGNED, a Sandbox map's players

local function Row(name, team, kills, deaths, npc, assists)
	return {
		name = name,
		team = team,
		kills = kills or 0,
		deaths = deaths or 0,
		npc = npc or false,
		assists = assists or 0,
	}
end

local function Names(rows)
	local names = {}
	for i, row in ipairs(rows) do names[i] = row.name end
	return table.concat(names, ",")
end

-- CTFGameRules::CalcPlayerScore: two assists are worth a kill.
T.test("a column ranks by points, two assists worth a kill", function()
	local b = Board.Build({
		Row("Killer", RED, 2, 0),
		Row("Helper", RED, 1, 0, false, 4),
		Row("Half", RED, 2, 0, false, 1),
	})
	T.eq(Names(b.teams[RED]), "Helper,Half,Killer", "3 points, then 2 with an assist over 2 without")
end)

T.test("BLU's column is on the left and RED's on the right, as in TF2", function()
	T.eq(Board.COLUMN_TEAMS[1], BLUE)
	T.eq(Board.COLUMN_TEAMS[2], RED)
end)

T.test("players and NPCs sit in their team's column", function()
	local b = Board.Build({
		Row("Scout", RED),
		Row("Rebel", BLUE, 0, 0, true),
		Row("Combine", RED, 0, 0, true),
		Row("Heavy", BLUE),
	})
	T.eq(Names(b.teams[RED]), "Scout,Combine", "RED")
	T.eq(Names(b.teams[BLUE]), "Heavy,Rebel", "BLU")
end)

T.test("a column is ordered by kills, then fewest deaths, then players before NPCs, then name", function()
	local b = Board.Build({
		Row("b", RED, 1, 0),
		Row("a", RED, 1, 0),
		Row("bot", RED, 1, 0, true),
		Row("dies", RED, 1, 3),
		Row("top", RED, 5, 9),
	})
	T.eq(Names(b.teams[RED]), "top,a,b,bot,dies")
end)

T.test("an empty team still has a column", function()
	local b = Board.Build({ Row("Scout", RED) })
	T.eq(#b.teams[BLUE], 0)
end)

T.test("spectators are a line of names, not rows", function()
	local b = Board.Build({
		Row("zed", SPECTATOR),
		Row("amy", SPECTATOR),
	})
	T.eq(table.concat(b.spectators, ","), "amy,zed")
	T.eq(#b.unassigned, 0)
end)

T.test("players on no team are rows of their own, so a Sandbox map's players still show", function()
	local b = Board.Build({
		Row("new", UNASSIGNED),
		Row("builder", SANDBOX_UNASSIGNED, 2),
	})
	T.eq(Names(b.unassigned), "builder,new")
end)

T.test("TF2's time left: minutes and seconds, hours when there are any", function()
	T.eq(Board.Clock(0), "0:00")
	T.eq(Board.Clock(65), "1:05")
	T.eq(Board.Clock(3600 + 61), "1:01:01")
end)

local function Limits(over)
	local limits = {
		winlimit = 0,
		maxrounds = 0,
		timelimit = 0,
		roundsPlayed = 0,
		timeLeft = 0,
	}
	for k, v in pairs(over) do limits[k] = v end
	return limits
end

T.test("no limits: only that the map has no time limit", function()
	local lines = Board.WinConditions(Limits({}))
	T.eq(#lines, 1)
	T.eq(lines[1], "No time limit")
end)

T.test("a win limit says how many round wins take the match", function()
	local lines = Board.WinConditions(Limits({ winlimit = 3 }))
	T.eq(lines[1], "Win limit: 3 rounds")
	T.eq(Board.WinConditions(Limits({ winlimit = 1 }))[1], "Win limit: 1 round", "singular")
end)

T.test("a round limit counts the rounds played", function()
	local lines = Board.WinConditions(Limits({
		maxrounds = 5,
		roundsPlayed = 2,
	}))
	T.eq(lines[1], "Rounds played: 2 of 5")
end)

T.test("a time limit counts down, then the map changes at the round's end", function()
	T.eq(Board.WinConditions(Limits({
		timelimit = 30,
		timeLeft = 125,
	}))[1], "Time left on map: 2:05")
	T.eq(Board.WinConditions(Limits({ timelimit = 30 }))[1], "Map will change at end of round")
end)

T.test("every limit at once, in TF2's order", function()
	local lines = Board.WinConditions(Limits({
		winlimit = 2,
		maxrounds = 4,
		roundsPlayed = 1,
		timelimit = 20,
		timeLeft = 60,
	}))
	T.eq(table.concat(lines, "|"), "Win limit: 2 rounds|Rounds played: 1 of 4|Time left on map: 1:00")
end)

T.test("a round reports the limits the scoreboard shows", function()
	local round = Rounds.New({
		respawnWaveTime = 10,
		bonusRoundTime = 15,
		enableRoundWaitTime = 6,
		stalemateEnable = false,
		stalemateTimelimit = 240,
		winlimit = 3,
		maxrounds = 5,
		timelimit = 10,
		matchEndAtTimelimit = false,
		chattime = 10,
		scrambleAuto = false,
		scrambleWinDifference = 0,
		mapResetTime = 100,
	})
	local limits = round:Limits(160)
	T.eq(limits.winlimit, 3)
	T.eq(limits.maxrounds, 5)
	T.eq(limits.timelimit, 10)
	T.eq(limits.roundsPlayed, 0)
	T.eq(limits.timeLeft, 540, "ten minutes from 100, at 160")
end)

-- TF2 reads mp_winlimit, mp_maxrounds and mp_timelimit live: changing one
-- mid-match changes the match's end.
T.test("a round takes new limits mid-match, its clock still from the map's start", function()
	local round = Rounds.New({
		respawnWaveTime = 10,
		bonusRoundTime = 15,
		enableRoundWaitTime = 6,
		stalemateEnable = false,
		stalemateTimelimit = 240,
		winlimit = 0,
		maxrounds = 0,
		timelimit = 0,
		matchEndAtTimelimit = false,
		chattime = 10,
		scrambleAuto = false,
		scrambleWinDifference = 0,
		mapResetTime = 100,
	})
	round:SetLimits({
		winlimit = 2,
		maxrounds = 4,
		timelimit = 20,
	})
	local limits = round:Limits(160)
	T.eq(limits.winlimit, 2)
	T.eq(limits.maxrounds, 4)
	T.eq(limits.timelimit, 20)
	T.eq(limits.timeLeft, 1140, "twenty minutes from 100, at 160")
	T.eq(round:TimeLeft(160), 1140, "the round's own clock agrees")
end)

T.finish()
