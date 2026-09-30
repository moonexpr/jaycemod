-- The seam between the rounds and capture systems, driven end to end as the
-- two controllers drive them: a two-stage attack/defend map (cp_dustbowl's
-- shape) through the Round, the Master and the PointSet, with the master as
-- the Round's objective port.
local T = dofile("tests/harness.lua")
local Rounds = T.require("foundation.rounds")
local ControlPoints = T.require("foundation.rounds.control_points")
local Capture = T.require("foundation.capture")
local Master = T.require("foundation.capture.master")
local State = T.require("foundation.rounds.state")
local Teams = T.require("foundation.teams")

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local W = Rounds.WINREASON
local NO_FLAGS = 0
local T0 = 100
local BONUS = 15

local function first() return 1 end

local function Point(id, index)
	return {
		id = id,
		index = index,
		defaultOwner = RED,
		startLocked = false,
		group = 0,
		warnOnCap = Capture.CP_WARN.NORMAL,
		warnSound = Capture.WARN_SOUND_DEFAULT,
		printName = "",
		spawnflags = NO_FLAGS,
		previous = {},
		sounds = {},
		capSounds = {},
	}
end

local function Stage(name, priority, id)
	return {
		name = name,
		priority = priority,
		restrict = RED,
		printName = "",
		points = { id },
	}
end

-- The capture controller's objective port over the master.
local function Port(master, set)
	local port = {}
	function port:PlayingMiniRounds() return master:PlayingMiniRounds() end
	function port:NumPlayable() return master:NumPlayable(set) end
	function port:PlayAllRounds() return master:PlayAllRounds() end
	function port:RoundsRemaining(team) return master:RoundsRemaining(team, set) end
	function port:ScorePerRound() return not master:ScorePerCapture() end
	return port
end

local function Map()
	local set = Capture.New({
		caplinear = true,
		points = {
			Point("cap_1", 1),
			Point("cap_2", 2),
		},
	})
	local master = Master.New({
		restrict = RED,
		switchTeams = true,
		scoreStyle = Master.SCORE_PER_ROUND,
		playAllRounds = true,
		partialCapRate = 0,
		capLayout = "",
		disabled = false,
		rounds = {
			Stage("round_1", 100, "cap_1"),
			Stage("round_2", 50, "cap_2"),
		},
	})
	local round = Rounds.New({
		respawnWaveTime = 10,
		bonusRoundTime = BONUS,
		enableRoundWaitTime = 1,
		stalemateEnable = false,
		stalemateTimelimit = 240,
		winlimit = 0,
		maxrounds = 0,
		timelimit = 0,
		matchEndAtTimelimit = false,
		chattime = 10,
		mapResetTime = 0,
	})
	round:SetMode(ControlPoints.Mode)
	return {
		set = set,
		master = master,
		round = round,
		port = Port(master, set),
		kinds = {},
		ended = {},
	}
end

local function World(map)
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
		stalemateTimerLeft = nil,
		timerMayExpire = true,
		mapHasActiveTimer = true,
		objective = map.port,
	}
end

-- The effects the capture controller listens to, carried out as its round
-- listeners do; every kind is recorded.
local function Carry(map, effects)
	for _, e in ipairs(effects) do
		map.kinds[#map.kinds + 1] = e.kind
		if e.kind == "round_activate" then
			local name, firstAfterRestart = map.master:RoundActivate(map.set, map.round:History(), first)
			if name then
				map.round:AddPlayedRound(name)
				if firstAfterRestart then map.round:SetFirstRoundPlayed(name) end
			end
		elseif e.kind == "previous_round_end" then
			map.ended[#map.ended + 1] = map.master:EndRound()
		elseif e.kind == "publish_win" then
			map.remaining = e.winner ~= NOBODY and map.port:RoundsRemaining(e.winner) or 0
			map.fullRound = e.fullRound
		elseif e.kind == "score" then
			map.scored = e.team
		end
	end
end

local function Think(map, now)
	map.kinds = {}
	Carry(map, map.round:Think(now, World(map)))
end

-- A capture completing, then the master's win check (EndCapture's order).
local function Cap(map, id, team, now)
	map.kinds = {}
	map.set:SetOwner(id, team, Capture.CAUSE_CAPTURE, map.round:PointsMayBeCaptured())
	local winner = map.master:Winner(map.set)
	if not winner or not map.round:MayWinByPoints(winner, { timerMayExpire = true }) then return end
	local forceMapReset, switchTeams = map.master:WinArgs(map.set)
	Carry(map, map.round:SetWinningTeam(now, winner, W.ALL_POINTS_CAPTURED, forceMapReset, switchTeams, false, map.port))
end

local function Has(kinds, kind)
	for _, k in ipairs(kinds) do
		if k == kind then return true end
	end
	return false
end

T.test("a two-stage A/D map: stage 1 won without a reset, stage 2 wins the round, scores and switches", function()
	local map = Map()
	Think(map, T0)
	T.eq(map.master:Current(), "round_1", "the higher priority stage first")
	T.eq(map.round:History().first, "round_1", "remembered as the first")
	Think(map, T0 + Rounds.PREROUND_SECONDS)
	T.eq(map.round:State(), State.RND_RUNNING, "running")

	local now = T0 + 30
	Cap(map, "cap_1", BLUE, now)
	T.eq(map.round:State(), State.TEAM_WIN, "BLU seizes the area")
	T.eq(map.fullRound, false, "a mini-round")
	T.eq(map.remaining, 1, "one more area to win")
	T.eq(map.scored, nil, "no score for a mini-round")

	Think(map, now + BONUS)
	T.eq(map.ended[1], "round_1", "stage 1's OnEnd")
	T.eq(map.master:Current(), "round_2", "stage 2 chosen")
	T.eq(Has(map.kinds, "cleanup"), false, "no map reset")
	T.eq(Has(map.kinds, "new_round_outputs"), false, "no OnMultiNewRound")

	Think(map, now + BONUS + Rounds.PREROUND_SECONDS)
	now = now + 100
	Cap(map, "cap_2", BLUE, now)
	T.eq(map.fullRound, true, "the last stage wins the round")
	T.eq(map.scored, BLUE, "BLU scores")

	Think(map, now + BONUS)
	T.eq(Has(map.kinds, "cleanup"), true, "the map resets")
	T.eq(Has(map.kinds, "switch_teams"), true, "the teams switch")
	T.eq(Has(map.kinds, "new_round_outputs"), true, "logic_auto's OnMultiNewRound")
end)

T.test("in Sandbox mode nothing is captured and nothing is won", function()
	local map = Map()
	Think(map, T0)
	Think(map, T0 + Rounds.PREROUND_SECONDS)
	map.round:Halt(T0 + 10)
	Cap(map, "cap_1", BLUE, T0 + 11)
	T.eq(map.set:Owner("cap_1"), RED, "the capture is refused")
	T.eq(map.round:State(), State.BETWEEN_RNDS, "between rounds")
	T.eq(#map.kinds, 0, "no win")
end)

T.finish()
