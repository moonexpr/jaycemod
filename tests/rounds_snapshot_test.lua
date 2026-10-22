-- The Round's Snapshot and Restore: a round taken at one time and put back
-- into a fresh round at another plays on exactly as the original does.
local T = dofile("tests/harness.lua")
local FakeObjective = dofile("tests/fake_objective.lua")
local Rounds = T.require("games.gameplay.rounds")
local CPMode = T.require("foundation.rounds.control_points").Mode
local State = T.require("games.gameplay.rounds.state")
local Teams = T.require("games.gameplay.teams")

local RED, BLUE = Teams.RED, Teams.BLUE
local W = Rounds.WINREASON
local T0 = 100
local LATER = 5000 -- the restored round's clock, far from the original's

local function Settings()
	return {
		respawnWaveTime = 10,
		bonusRoundTime = 15,
		enableRoundWaitTime = 1,
		stalemateEnable = false,
		stalemateTimelimit = 240,
		winlimit = 0,
		maxrounds = 0,
		timelimit = 30,
		matchEndAtTimelimit = true,
		chattime = 10,
		mapResetTime = 0,
	}
end

local function World()
	return {
		havePlayers = true,
		teams = {
			[RED] = {
				players = 1,
				alive = 1,
			},
			[BLUE] = {
				players = 1,
				alive = 1,
			},
		},
		scores = {
			[RED] = 0,
			[BLUE] = 0,
		},
		timerMayExpire = true,
		mapHasActiveTimer = true,
		objective = FakeObjective.Objective(),
	}
end

local function Kinds(effects)
	local list = {}
	for i, e in ipairs(effects) do list[i] = e.kind .. (e.to and (" " .. e.to) or "") .. (e.name and (" " .. e.name) or "") end
	return table.concat(list, ", ")
end

local function Fresh()
	local round = Rounds.New(Settings())
	round:SetMode(CPMode)
	return round
end

-- The original thinks at T0 + t, the copy at LATER + t: every think's
-- effects must match.
local function SamePlay(original, copy, from, steps, what)
	for i = 1, steps do
		local t = from + i
		T.eq(Kinds(copy:Think(LATER + t, World())), Kinds(original:Think(T0 + t, World())), what .. " at +" .. t)
		T.eq(copy:State(), original:State(), what .. " state at +" .. t)
	end
end

local function Copy(original, at)
	local copy = Fresh()
	copy:Restore(original:Snapshot(T0 + at), LATER + at)
	return copy
end

T.test("a round taken in its pre-round reaches RND_RUNNING when the original does", function()
	local original = Fresh()
	original:Think(T0, World())
	T.eq(original:State(), State.PREROUND, "pre-round")
	local copy = Copy(original, 0)
	T.eq(copy:State(), State.PREROUND, "restored pre-round")
	SamePlay(original, copy, 0, Rounds.PREROUND_SECONDS + 2, "pre-round")
	T.eq(copy:State(), State.RND_RUNNING, "running")
end)

T.test("a round taken running wins, celebrates and restarts as the original does", function()
	local original = Fresh()
	original:Think(T0, World())
	original:Think(T0 + 1 + Rounds.PREROUND_SECONDS, World())
	local at = 2 + Rounds.PREROUND_SECONDS
	local copy = Copy(original, at)
	T.eq(Kinds(copy:SetWinningTeam(LATER + at, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())),
		Kinds(original:SetWinningTeam(T0 + at, RED, W.ALL_POINTS_CAPTURED, true, false, false, FakeObjective.Objective())), "the win")
	T.eq(copy:Winner(), RED, "red won")
	SamePlay(original, copy, at, Settings().bonusRoundTime + 3, "after the win")
end)

T.test("the map's time left is kept as time left", function()
	local original = Fresh()
	original:Think(T0, World())
	local copy = Copy(original, 7)
	T.near(copy:TimeLeft(LATER + 7), original:TimeLeft(T0 + 7), 1e-9, "time left")
end)

T.test("respawn waves due are kept as time to go", function()
	local original = Fresh()
	original:Think(T0, World())
	original:Think(T0 + 1 + Rounds.PREROUND_SECONDS, World())
	local at = 2 + Rounds.PREROUND_SECONDS
	original:SetTeamWaveTime(RED, 20)
	local copy = Copy(original, at)
	for i = 1, 25 do
		T.eq(copy:WaveDue(RED, LATER + at + i, 1), original:WaveDue(RED, T0 + at + i, 1), "wave due at +" .. i)
	end
end)

T.test("a snapshot is plain data", function()
	local original = Fresh()
	original:Think(T0, World())
	local function Plain(value, path)
		local kind = type(value)
		T.eq(kind == "table" or kind == "string" or kind == "number" or kind == "boolean", true, path .. " is " .. kind)
		if kind == "table" then
			T.eq(getmetatable(value), nil, path .. " has no metatable")
			for k, v in pairs(value) do Plain(v, path .. "." .. tostring(k)) end
		end
	end
	Plain(original:Snapshot(T0), "round")
end)

T.test("a snapshot of another mode is refused, naming both", function()
	local original = Fresh()
	local snap = original:Snapshot(T0)
	local other = Rounds.New(Settings())
	local ok, err = pcall(other.Restore, other, snap, LATER)
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("control_points", 1, true) ~= nil and tostring(err):find("none", 1, true) ~= nil, true, "names both modes: " .. tostring(err))
end)

-- The round timer's (games.gameplay.rounds.timer) Snapshot and Restore.
local Timer = T.require("games.gameplay.rounds.timer")

local function NewTimer(now, setupLength)
	return Timer.New({
		length = 120,
		maxLength = 0,
		setupLength = setupLength,
		startPaused = false,
		showInHud = true,
		autoCountdown = true,
		resetTime = false,
		startDisabled = false,
		now = now,
	})
end

local function TimerQuery()
	return {
		mayExpire = true,
		roundWon = false,
		overtime = false,
		nagEnabled = false,
		random = function() return 0 end,
	}
end

local function TimerEvents(events)
	local list = {}
	for i, e in ipairs(events) do list[i] = e.kind .. (e.name and (" " .. e.name) or "") end
	return table.concat(list, ", ")
end

T.test("a timer taken in setup counts down, ends setup and finishes as the original does", function()
	local original = NewTimer(T0, 30)
	original:RoundSpawn(T0)
	original:Think(T0 + 1, TimerQuery())
	local copy = NewTimer(LATER, 0)
	copy:Restore(original:Snapshot(T0 + 5), LATER + 5)
	T.eq(copy:InSetup(), true, "in setup")
	T.near(copy:TimeRemaining(LATER + 5), original:TimeRemaining(T0 + 5), 1e-9, "time left")
	for t = 6, 30 + 120 + 2 do
		T.eq(TimerEvents(copy:Think(LATER + t, TimerQuery())), TimerEvents(original:Think(T0 + t, TimerQuery())), "events at +" .. t)
	end
	T.eq(copy:InSetup(), false, "setup over")
end)

T.test("a paused timer stays paused with its time left", function()
	local original = NewTimer(T0, 0)
	original:RoundSpawn(T0)
	original:Pause(T0 + 10)
	local copy = NewTimer(LATER, 0)
	copy:Restore(original:Snapshot(T0 + 50), LATER + 999)
	T.eq(copy:Paused(), true, "paused")
	T.near(copy:TimeRemaining(LATER + 999), original:TimeRemaining(T0 + 50), 1e-9, "time left")
end)

T.finish()
