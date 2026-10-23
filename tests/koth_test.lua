-- King of the Hill, driven as whole rounds: the Round, a Timer per team
-- clock, the PointSet, the Master and the koth mode together on a fake
-- clock, wired as the rounds, capture and koth controllers wire them
-- (koth_viaduct's shape: one neutral point, tf_logic_koth 180/30, a master
-- scoring per round).
local T = dofile("tests/harness.lua")
local Rounds = gameplay.rounds
local ControlPoints = T.require("features.rounds.control_points")
local Koth = T.require("features.koth.model")
local Timer = T.require("games.gameplay.rounds.timer")
local Capture = gameplay.capture
local Master = T.require("games.gameplay.capture.master")
local State = T.require("games.gameplay.rounds.state")
local Teams = gameplay.teams

local NOBODY, RED, BLUE = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local HILL = "hill"
local NO_FLAGS = 0
local T0 = 100
local RUNNING_AT = T0 + Rounds.PREROUND_SECONDS
local CLOCK = Koth.TIMER_LENGTH_DEFAULT
local UNLOCK = Koth.UNLOCK_POINT_DEFAULT

local function first() return 1 end

local SETTINGS = {
	respawnWaveTime = 10,
	bonusRoundTime = 15,
	enableRoundWaitTime = 1,
	stalemateEnable = false,
	stalemateTimelimit = 240,
	winlimit = 0,
	maxrounds = 0,
	timelimit = 0,
	matchEndAtTimelimit = false,
	chattime = 10,
	mapResetTime = 0,
}

-- koth_viaduct's point: neutral, unlocked in its keyvalues.
local function HillPoint()
	return {
		id = HILL,
		index = 0,
		defaultOwner = NOBODY,
		startLocked = false,
		group = 0,
		warnOnCap = Capture.CP_WARN.NORMAL,
		warnSound = Capture.WARN_SOUND_DEFAULT,
		printName = "",
		spawnflags = NO_FLAGS,
		previous = {},
		sounds = {},
		capSounds = {},
		icons = {},
	}
end

local function Port(master, set)
	local port = {}
	function port:PlayingMiniRounds() return master:PlayingMiniRounds() end
	function port:NumPlayable() return master:NumPlayable(set) end
	function port:PlayAllRounds() return master:PlayAllRounds() end
	function port:RoundsRemaining(team) return master:RoundsRemaining(team, set) end
	function port:ScorePerRound() return not master:ScorePerCapture() end
	return port
end

-- The map and its three controllers' wiring, in one table.
local Hill = {}
Hill.__index = Hill

local function NewHill(kv)
	local set = Capture.New({
		caplinear = true,
		points = { HillPoint() },
	})
	local master = Master.New({
		-- cpm_restrict_team_cap_win unset: either team may win
		restrict = NOBODY,
		switchTeams = false,
		scoreStyle = Master.SCORE_PER_ROUND,
		playAllRounds = false,
		partialCapRate = 0,
		capLayout = "",
		disabled = false,
		rounds = {},
	})
	local round = Rounds.New(SETTINGS)
	-- The master's map is a control points one; tf_logic_koth raises it.
	round:SetMode(ControlPoints.Mode)
	round:SetMode(Koth.Mode)
	return setmetatable({
		koth = Koth.New(kv or {}),
		set = set,
		master = master,
		round = round,
		port = Port(master, set),
		clocks = {},
		names = {},
		capturing = false,
		kinds = {},
		outputs = {},
		clockOutputs = {},
		unlocked = 0,
		clocksAtNewRound = nil,
	}, Hill)
end

function Hill:World()
	local life = {
		players = 1,
		alive = 1,
	}
	return {
		havePlayers = true,
		teams = {
			[RED] = life,
			[BLUE] = life,
		},
		scores = {
			[RED] = 0,
			[BLUE] = 0,
		},
		stalemateTimerLeft = nil,
		timerMayExpire = true,
		mapHasActiveTimer = false,
		objective = self.port,
	}
end

-- CKothLogic::InputRoundSpawn as the koth controller does it: each clock
-- is a team_round_timer the rounds controller creates (running, shown),
-- then paused.
function Hill:RoundSpawn(now)
	self.clocks, self.names = {}, {}
	for _, c in ipairs(self.koth:Clocks()) do
		local clock = Timer.New({
			length = Timer.LENGTH_DEFAULT,
			maxLength = 0,
			setupLength = 0,
			startPaused = true,
			showInHud = true,
			autoCountdown = true,
			resetTime = false,
			startDisabled = false,
			now = now,
		})
		clock:SetTimeRemaining(now, c.length)
		clock:Resume(now)
		clock:Pause(now)
		self.clocks[c.team] = clock
		self.names[#self.names + 1] = c.name
	end
end

-- The capture controller's RoundActivate, then CKothLogic::InputRoundActivate.
function Hill:RoundActivate(now)
	self.set:RoundActivate()
	local lock = self.koth:PointLock()
	for _, id in ipairs(self.set:Ids()) do
		self.set:SetLocked(id, lock.locked)
		if lock.unlockTime then self.set:SetUnlockTime(id, lock.unlockTime, now) end
	end
end

local EFFECTS = {
	round_spawn = function(self, e, now) self:RoundSpawn(now) end,
	round_activate = function(self, e, now) self:RoundActivate(now) end,
	new_round_outputs = function(self)
		self.clocksAtNewRound = {}
		for i, name in ipairs(self.names) do self.clocksAtNewRound[i] = name end
	end,
	output = function(self, e) self.outputs[#self.outputs + 1] = e.name end,
	overtime = function(self, e) self.round:SetOvertime(e.value) end,
}

function Hill:Apply(effects, now)
	for _, e in ipairs(effects) do
		self.kinds[#self.kinds + 1] = e.kind
		if EFFECTS[e.kind] then EFFECTS[e.kind](self, e, now) end
	end
end

function Hill:MayExpire(now)
	return self.round:TimerMayExpire(now, {
		capturing = self.capturing,
		other = false,
	})
end

-- The clocks' events, carried out as the rounds controller's TIMER_EVENTS.
function Hill:ClockEvents(team, events)
	for _, e in ipairs(events) do
		if e.kind == "overtime" then self.round:SetOvertime(e.value) end
		if e.kind == "output" then self.clockOutputs[#self.clockOutputs + 1] = team .. " " .. e.name end
	end
end

-- One think of everything: the round, the unlock, the clocks, then the
-- master's win check (CPMThink) with KOTH's gate.
function Hill:Think(now)
	self:Apply(self.round:Think(now, self:World()), now)
	for _, e in ipairs(self.set:Tick(now, self.round:State() == State.RND_RUNNING)) do
		if e.kind == "unlocked" then self.unlocked = self.unlocked + 1 end
	end
	if not self.round:Halted() then
		for _, team in ipairs({ BLUE, RED }) do
			local clock = self.clocks[team]
			if clock then
				self:ClockEvents(team, clock:Think(now, {
					mayExpire = self:MayExpire(now),
					roundWon = self.round:State() == State.TEAM_WIN,
					overtime = self.round:InOvertime(),
					nagEnabled = false,
					random = first,
				}))
			end
		end
	end
	if not (self.master:Active() and self.round:PointsMayBeCaptured()) then return end
	local winner = self.master:Winner(self.set)
	if not winner then return end
	local clock = self.clocks[winner]
	local mayWin = self.round:MayWinByPoints(winner, {
		clockRemaining = clock and clock:TimeRemaining(now) or nil,
		timerMayExpire = self:MayExpire(now),
	})
	if mayWin then
		self:Apply(self.round:SetWinningTeam(now, winner, Rounds.WINREASON.ALL_POINTS_CAPTURED, true, false, false, self.port), now)
	end
end

-- Thinks every tenth of a second up to `last`.
function Hill:RunUntil(from, last)
	local now = from
	while now <= last + 1e-9 do
		self:Think(now)
		now = now + 0.1
	end
end

-- A team completes the capture: the area's OnCapTeam sends the gamerules
-- Set<Team>KothClockActive, the point changes hands. Returns the cap sounds.
function Hill:Capture(team, now)
	local changed = self.set:SetOwner(HILL, team, Capture.CAUSE_CAPTURE, self.round:PointsMayBeCaptured())
	if #changed == 0 then return nil end
	local resume, pause = Koth.ClockActive(team)
	if self.clocks[pause] then self.clocks[pause]:Pause(now) end
	if self.clocks[resume] then self.clocks[resume]:Resume(now) end
	return self.round:Mode():CapSounds(team, {
		wouldWinGame = self.master:WouldNewOwnerWin(self.set, HILL, team),
		scorePerRound = self.port:ScorePerRound(),
	})
end

-- Sandbox mode: tf_gamerules' Halt, which pauses every timer.
function Hill:Halt(now)
	self:Apply(self.round:Halt(now), now)
	for _, clock in pairs(self.clocks) do clock:Pause(now) end
end

-- A hill whose round is running, the point still locked.
local function Running(kv)
	local h = NewHill(kv)
	h:Think(T0)
	h:Think(RUNNING_AT)
	T.eq(h.round:State(), State.RND_RUNNING, "running")
	return h
end

local function Has(list, value)
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

-- The logic model ---------------------------------------------------------------------

T.test("tf_logic_koth defaults to CKothLogic's 180 s clocks and 30 s unlock", function()
	local koth = Koth.New({})
	local clocks = koth:Clocks()
	T.eq(#clocks, 2, "two clocks")
	T.eq(clocks[1].team, BLUE, "BLU's clock first, as InputRoundSpawn makes it")
	T.eq(clocks[1].name, "zz_blue_koth_timer", "BLU's name")
	T.eq(clocks[1].length, 180, "BLU's length")
	T.eq(clocks[2].team, RED, "RED's clock second")
	T.eq(clocks[2].name, "zz_red_koth_timer", "RED's name")
	T.eq(clocks[2].length, 180, "RED's length")
	local lock = koth:PointLock()
	T.eq(lock.locked, true, "locked")
	T.eq(lock.unlockTime, 30, "unlocks after 30 s")
end)

T.test("the map's timer_length and unlock_point", function()
	local koth = Koth.New({
		timerLength = 240,
		unlockPoint = 35,
	})
	T.eq(koth:Clocks()[1].length, 240, "BLU's length")
	T.eq(koth:Clocks()[2].length, 240, "RED's length")
	T.eq(koth:PointLock().unlockTime, 35, "lakeside's unlock")
end)

T.test("unlock_point 0 leaves the point unlocked with no unlock time", function()
	local lock = Koth.New({ unlockPoint = 0 }):PointLock()
	T.eq(lock.locked, false, "unlocked")
	T.eq(lock.unlockTime, nil, "no unlock time")
end)

T.test("a negative unlock_point unlocks, as InputSetLocked's value > 0 test does", function()
	local lock = Koth.New({ unlockPoint = -5 }):PointLock()
	T.eq(lock.locked, false, "unlocked")
	T.eq(lock.unlockTime, nil, "no unlock time")
end)

T.test("a team's clock resumes and the enemy's pauses", function()
	local resume, pause = Koth.ClockActive(RED)
	T.eq(resume, RED, "RED's resumes")
	T.eq(pause, BLUE, "BLU's pauses")
	resume, pause = Koth.ClockActive(BLUE)
	T.eq(resume, BLUE, "BLU's resumes")
	T.eq(pause, RED, "RED's pauses")
end)

T.test("the clock inputs reach their team's clock as SetTime and AddTime", function()
	T.eq(Koth.CLOCK_INPUTS.setredtimer.team, RED, "SetRedTimer")
	T.eq(Koth.CLOCK_INPUTS.setredtimer.timerInput, Koth.TIMER_SET, "SetRedTimer sets")
	T.eq(Koth.CLOCK_INPUTS.setbluetimer.team, BLUE, "SetBlueTimer")
	T.eq(Koth.CLOCK_INPUTS.setbluetimer.timerInput, Koth.TIMER_SET, "SetBlueTimer sets")
	T.eq(Koth.CLOCK_INPUTS.addredtimer.team, RED, "AddRedTimer")
	T.eq(Koth.CLOCK_INPUTS.addredtimer.timerInput, Koth.TIMER_ADD, "AddRedTimer adds")
	T.eq(Koth.CLOCK_INPUTS.addbluetimer.team, BLUE, "AddBlueTimer")
	T.eq(Koth.CLOCK_INPUTS.addbluetimer.timerInput, Koth.TIMER_ADD, "AddBlueTimer adds")
	T.eq(Koth.TIMER_SET, "settime", "team_round_timer's SetTime")
	T.eq(Koth.TIMER_ADD, "addtime", "team_round_timer's AddTime")
end)

-- The mode ------------------------------------------------------------------------------

T.test("the koth mode extends control points and outranks it and payload", function()
	local mode = Koth.Mode
	T.eq(mode.NAME, "koth", "name")
	T.eq(mode.HUD, Rounds.HUD_KOTH, "the koth HUD")
	T.eq(mode.CREATES_TIME_LIMIT_TIMER, false, "no time limit timer (CreateTimeLimitTimer)")
	T.eq(mode.ANNOUNCES_TIME_ADDED, false, "AddTimerSeconds is silent in koth")
	local round = Rounds.New(SETTINGS)
	round:SetMode(ControlPoints.Mode)
	T.eq(round:SetMode(Koth.Mode), true, "koth over control points")
	local payload = ControlPoints.Mode:Extend("payload")
	payload.PRIORITY = 2
	T.eq(round:SetMode(payload), false, "payload does not replace koth")
	T.eq(round:SetMode(ControlPoints.Mode), false, "nor control points")
	T.eq(round:Mode(), Koth.Mode, "koth")
end)

T.test("an owner wins by points only at its clock's zero and when the timer may expire", function()
	local mode = Koth.Mode
	local function q(clock, mayExpire)
		return {
			clockRemaining = clock,
			timerMayExpire = mayExpire,
		}
	end
	T.eq(mode:MayWinByPoints(RED, q(nil, false)), true, "no clock: at once")
	T.eq(mode:MayWinByPoints(RED, q(12, true)), false, "time left")
	T.eq(mode:MayWinByPoints(RED, q(0, false)), false, "held at zero")
	T.eq(mode:MayWinByPoints(RED, q(0, true)), true, "zero and free")
end)

T.test("every cap plays Hud.PointCaptured then Success or Failure to each team, even a winning one", function()
	for _, wouldWin in ipairs({ false, true }) do
		for _, scorePerRound in ipairs({ true, false }) do
			local lines = Koth.Mode:CapSounds(BLUE, {
				wouldWinGame = wouldWin,
				scorePerRound = scorePerRound,
			})
			T.eq(#lines, 4, "four lines")
			T.eq(lines[1].team, RED, "RED first (FIRST_GAME_TEAM)")
			T.eq(lines[1].sound, "Hud.PointCaptured", "RED's chime")
			T.eq(lines[2].team, RED, "RED's line")
			T.eq(lines[2].sound, "Announcer.Failure", "RED lost it")
			T.eq(lines[3].team, BLUE, "BLU's chime")
			T.eq(lines[3].sound, "Hud.PointCaptured", "BLU's chime")
			T.eq(lines[4].team, BLUE, "BLU's line")
			T.eq(lines[4].sound, "Announcer.Success", "BLU took it")
		end
	end
end)

-- Whole rounds ---------------------------------------------------------------------------

T.test("the round spawns the clocks, named, paused at 180, before OnMultiNewRound fires", function()
	local h = NewHill()
	h:Think(T0)
	T.eq(h.names[1], "zz_blue_koth_timer", "BLU's clock by name")
	T.eq(h.names[2], "zz_red_koth_timer", "RED's clock by name")
	T.eq(h.clocksAtNewRound ~= nil, true, "OnMultiNewRound fired")
	T.eq(h.clocksAtNewRound[1], "zz_blue_koth_timer", "BLU's clock exists for the maps' AddOutput")
	T.eq(h.clocksAtNewRound[2], "zz_red_koth_timer", "RED's clock exists for the maps' AddOutput")
	for _, team in ipairs({ RED, BLUE }) do
		T.eq(h.clocks[team]:Paused(), true, "paused")
		T.eq(h.clocks[team]:ShowInHud(), true, "shown")
		T.eq(h.clocks[team]:InSetup(), false, "never setup, so no siren")
		T.eq(h.clocks[team]:TimeRemaining(T0 + 50), CLOCK, "holding 3:00")
	end
end)

T.test("the point is locked, and unlocks unlock_point seconds after RoundActivate, once running", function()
	local h = NewHill()
	h:Think(T0)
	T.eq(h.set:Locked(HILL), true, "locked at RoundActivate")
	T.eq(h.set:UnlockAt(HILL), T0 + UNLOCK, "the HUD's unlock time")
	T.eq(h.set:TeamMayCapture(HILL, RED, {
		playingMiniRounds = false,
		inRound = nil,
		base = Capture.NO_POINT,
	}), false, "nobody may cap a locked point")
	h:RunUntil(RUNNING_AT, T0 + UNLOCK - 0.1)
	T.eq(h.set:Locked(HILL), true, "still locked just before")
	T.eq(h.unlocked, 0, "no unlock yet")
	h:RunUntil(T0 + UNLOCK, T0 + UNLOCK + 0.3)
	T.eq(h.set:Locked(HILL), false, "unlocked")
	T.eq(h.unlocked, 1, "OnUnlocked once")
end)

T.test("the pre-round never unlocks the point, however short unlock_point is", function()
	local h = NewHill({ unlockPoint = 1 })
	h:RunUntil(T0, RUNNING_AT - 0.1)
	T.eq(h.round:State(), State.PREROUND, "pre-round")
	T.eq(h.set:Locked(HILL), true, "locked through the pre-round")
	h:RunUntil(RUNNING_AT, RUNNING_AT + 0.2)
	T.eq(h.set:Locked(HILL), false, "unlocked once running")
end)

T.test("unlock_point 0 leaves a neutral point open from the start", function()
	local h = NewHill({ unlockPoint = 0 })
	h:Think(T0)
	T.eq(h.set:Locked(HILL), false, "open")
	T.eq(h.set:UnlockAt(HILL), nil, "no countdown")
end)

T.test("the capper's clock runs while the other's pauses, and a recapture swaps them", function()
	local h = Running()
	h:RunUntil(RUNNING_AT, T0 + UNLOCK + 0.5)
	local capAt = T0 + 40
	local sounds = h:Capture(RED, capAt)
	T.eq(#sounds, 4, "the cap's four lines")
	T.eq(h.clocks[RED]:Paused(), false, "RED's clock runs")
	T.eq(h.clocks[BLUE]:Paused(), true, "BLU's clock waits")
	h:RunUntil(capAt, capAt + 60)
	T.near(h.clocks[RED]:TimeRemaining(capAt + 60), CLOCK - 60, 1e-6, "RED spent a minute")
	T.eq(h.clocks[BLUE]:TimeRemaining(capAt + 60), CLOCK, "BLU's untouched")
	T.eq(h.round:State(), State.RND_RUNNING, "no win with time left")
	h:Capture(BLUE, capAt + 60)
	T.eq(h.clocks[RED]:Paused(), true, "RED's clock waits")
	T.eq(h.clocks[BLUE]:Paused(), false, "BLU's clock runs")
	h:RunUntil(capAt + 60, capAt + 90)
	T.near(h.clocks[RED]:TimeRemaining(capAt + 90), CLOCK - 60, 1e-6, "RED's stays")
	T.near(h.clocks[BLUE]:TimeRemaining(capAt + 90), CLOCK - 30, 1e-6, "BLU's runs")
end)

T.test("the owner wins when its clock reaches zero and the timer may expire", function()
	local h = Running()
	local capAt = T0 + 40
	h:RunUntil(RUNNING_AT, capAt)
	h:Capture(RED, capAt)
	h:RunUntil(capAt, capAt + CLOCK - 0.2)
	T.eq(h.round:State(), State.RND_RUNNING, "not yet")
	h:RunUntil(capAt + CLOCK - 0.1, capAt + CLOCK + 0.2)
	T.eq(h.round:State(), State.TEAM_WIN, "won")
	T.eq(h.round:Winner(), RED, "by RED")
	T.eq(Has(h.outputs, "OnWonByTeam1"), true, "the proxy's OnWonByTeam1")
	T.eq(Has(h.clockOutputs, RED .. " OnFinished"), true, "RED's clock finished")
	T.eq(h.round:InOvertime(), false, "no overtime")
end)

T.test("overtime: the owner's clock holds at zero while the enemy caps, then wins 0.1 s after", function()
	local h = Running()
	local capAt = T0 + 40
	h:RunUntil(RUNNING_AT, capAt)
	h:Capture(RED, capAt)
	local zero = capAt + CLOCK
	h:RunUntil(capAt, zero - 1)
	h.capturing = true -- BLU steps on the point
	h:RunUntil(zero - 0.9, zero + 5)
	T.near(h.clocks[RED]:TimeRemaining(zero + 5), 0, 1e-6, "RED's clock at zero")
	T.eq(h.round:InOvertime(), true, "overtime")
	T.eq(h.round:State(), State.RND_RUNNING, "no win while BLU caps")
	T.eq(Has(h.clockOutputs, RED .. " OnFinished"), false, "the clock holds")
	h.capturing = false -- BLU is driven off
	h:Think(zero + 5.05)
	T.eq(h.round:State(), State.RND_RUNNING, "the 0.1 s buffer holds it")
	h:RunUntil(zero + 5.15, zero + 5.3)
	T.eq(h.round:State(), State.TEAM_WIN, "RED wins")
	T.eq(h.round:Winner(), RED, "RED")
end)

T.test("overtime lost: BLU completes the cap, BLU's clock runs and overtime ends", function()
	local h = Running()
	local capAt = T0 + 40
	h:RunUntil(RUNNING_AT, capAt)
	h:Capture(RED, capAt)
	local zero = capAt + CLOCK
	h.capturing = true
	h:RunUntil(capAt, zero + 3)
	T.eq(h.round:InOvertime(), true, "overtime")
	h.capturing = false
	h:Capture(BLUE, zero + 3)
	T.eq(h.clocks[RED]:Paused(), true, "RED's clock waits at zero")
	T.near(h.clocks[RED]:TimeRemaining(zero + 3), 0, 1e-6, "at zero")
	T.eq(h.clocks[BLUE]:Paused(), false, "BLU's runs")
	h:RunUntil(zero + 3.1, zero + 4)
	T.eq(h.round:InOvertime(), false, "BLU's think ends overtime")
	T.eq(h.round:State(), State.RND_RUNNING, "BLU has time left: nobody wins")
end)

T.test("SetRedTimer and AddBlueTimer reach their clocks, and the added time is silent", function()
	local h = Running()
	local now = RUNNING_AT + 1
	local set = Koth.CLOCK_INPUTS.setredtimer
	h.clocks[set.team]:SetTimeRemaining(now, 60)
	T.eq(h.clocks[RED]:TimeRemaining(now), 60, "RED's clock set")
	local add = Koth.CLOCK_INPUTS.addbluetimer
	local events, added = h.clocks[add.team]:AddSeconds(now, 30, NOBODY, {
		roundRunningOrWon = true,
		isHud = false,
		roundWon = false,
		inStalemate = false,
		announces = h.round:Mode().ANNOUNCES_TIME_ADDED,
	})
	T.eq(added, 30, "thirty seconds")
	T.eq(h.clocks[BLUE]:TimeRemaining(now), CLOCK + 30, "BLU's clock added to")
	for _, e in ipairs(events) do T.eq(e.kind ~= "time_added", true, "no time-added line") end
end)

T.test("Sandbox mode freezes the hill: no unlock, no capture, clocks still, no win", function()
	local h = Running()
	h:RunUntil(RUNNING_AT, RUNNING_AT + 2)
	local haltAt = RUNNING_AT + 2
	h:Halt(haltAt)
	T.eq(h.round:State(), State.BETWEEN_RNDS, "between rounds")
	h:RunUntil(haltAt, haltAt + 60)
	T.eq(h.set:Locked(HILL), true, "the unlock waits")
	T.eq(h.unlocked, 0, "never unlocked")
	T.eq(h:Capture(RED, haltAt + 60), nil, "points may not be captured")
	T.eq(h.set:Owner(HILL), NOBODY, "still neutral")
	T.eq(h.clocks[RED]:TimeRemaining(haltAt + 60), CLOCK, "RED's clock still")
	T.eq(h.clocks[BLUE]:TimeRemaining(haltAt + 60), CLOCK, "BLU's clock still")
	T.eq(h.round:State(), State.BETWEEN_RNDS, "no round starts or ends")
end)

T.test("Sandbox mode stops a running clock where it stands", function()
	local h = Running()
	local capAt = T0 + 40
	h:RunUntil(RUNNING_AT, capAt)
	h:Capture(RED, capAt)
	h:RunUntil(capAt, capAt + 10)
	h:Halt(capAt + 10)
	h:RunUntil(capAt + 10, capAt + CLOCK + 30)
	T.near(h.clocks[RED]:TimeRemaining(capAt + CLOCK + 30), CLOCK - 10, 1e-6, "RED's clock stopped")
	T.eq(h.round:State(), State.BETWEEN_RNDS, "no win")
	T.eq(h.round:InOvertime(), false, "no overtime")
end)

-- The cues a KOTH clock gives, as each client's CTeamRoundTimer::ClientThink
-- plays them.

T.test("every running KOTH clock speaks Mission ends in...; a paused one or Sandbox mode is silent", function()
	local function Speaks(paused, halted)
		return Timer.Speaks({
			paused = paused,
			autoCountdown = true,
			halted = halted,
			isHud = false,
			koth = true,
		})
	end
	T.eq(Speaks(false, false), true, "a running clock, not the HUD timer")
	T.eq(Speaks(true, false), false, "a paused clock")
	T.eq(Speaks(false, true), false, "Sandbox mode")
	local armed = Timer.ArmClientWarnings(CLOCK, false)
	armed[120] = false -- "2 minutes" was spoken at 121 s
	T.eq(Timer.NextClientWarning(armed, 61, false), 60, "at 61 s")
	T.eq(Timer.WarningSound(60, false), "Announcer.RoundEnds60seconds", "mission ends in 60")
	T.eq(Timer.StartsRound(false, false), false, "a clock with no setup never plays the siren")
end)

-- Seams, read as text ---------------------------------------------------------------------

local function Source(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("tf_logic_koth loads its feature on first use, never at file load, and holds no rule", function()
	local text = Source("addons/sandcastle/gamemodes/sandcastle/entities/entities/tf_logic_koth.lua")
	for line in text:gmatch("[^\n]+") do
		if not line:match("^%s") and not line:match("^%-%-") then
			T.eq(line:find("Feature") == nil and line:find("require") == nil, true, "top level: " .. line)
		end
	end
	T.eq(text:find("require(\"foundation", 1, true) == nil, true, "no foundation module")
	T.eq(text:find("if .*RED") == nil and text:find("if .*BLUE") == nil and text:find("if .*locked") == nil, true, "no rule")
end)

T.test("the koth controller has the methods the binding calls, and the view reads only networked state", function()
	local sv = T.RealmSource("koth", "sv")
	for _, name in ipairs({ "BindLogic", "UnbindLogic", "LogicInput" }) do
		T.eq(sv:find("function Controller:" .. name .. "(", 1, true) ~= nil, true, name)
	end
	T.eq(sv:find("CreateTimer(c.name", 1, true) ~= nil, true, "each clock made with its zz_ name")
	local cl = T.RealmSource("koth", "cl")
	T.eq(cl:find("ents.Find", 1, true) == nil, true, "no ents.Find in the view")
end)

T.finish()
