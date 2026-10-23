-- The payload mode (features.payload.round, CTFGameRules's
-- TF_GAMETYPE_ESCORT) and payload played through the models: a single cart
-- pushed along its checkpoints, a payload race, the recede countdown,
-- overtime held by a pushed cart, and the cart HUD's wire format
-- (features.payload.hud). Also the seams of the payload feature.
local T = dofile("tests/harness.lua")
local Rounds = gameplay.rounds
local ControlPoints = T.require("features.rounds.control_points")
local PayloadMode = T.require("features.payload.round")
local Payload = T.require("features.payload.model")
local Race = T.require("features.payload.race")
local Hud = T.require("features.payload.hud")
local Timer = T.require("games.gameplay.rounds.timer")
local Teams = gameplay.teams

local NOBODY, RED, BLU = Teams.UNASSIGNED, Teams.RED, Teams.BLUE
local MODE = PayloadMode.Mode
local FULL_ROUND, MINI_ROUND = true, false
local RACE, NO_RACE = true, false

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

-- The watcher's convars and keyvalues, at TF2's defaults.
local RECEDE_TIME = 30 -- tf_escort_recede_time
local RECEDE_TIME_OVERTIME = 5 -- tf_escort_recede_time_overtime
local MAP_RECEDE_TIME = 0 -- train_recede_time unset: the convar decides
local LEVELS = { 30, 60, 90 } -- hud_min_speed_level_1..3

-- The mode ---------------------------------------------------------------------

T.test("the payload mode's members", function()
	T.eq(MODE.NAME, "payload", "name")
	T.eq(MODE.HUD, Rounds.HUD_PAYLOAD, "the cart HUD")
	T.eq(MODE.CREATES_TIME_LIMIT_TIMER, true, "a time limit timer")
	T.eq(MODE.ANNOUNCES_TIME_ADDED, true, "time added is announced")
	T.eq(#MODE:CapSounds(BLU, {
		wouldWinGame = false,
		scorePerRound = true,
	}), 0, "no special cap sounds")
	T.eq(MODE:MayWinByPoints(BLU, { timerMayExpire = false }), true, "points win at once")
end)

T.test("payload outranks control points, and koth outranks payload", function()
	T.eq(MODE.PRIORITY > ControlPoints.Mode.PRIORITY, true, "over control points")
	local round = Rounds.New(SETTINGS)
	T.eq(round:SetMode(ControlPoints.Mode), true, "the master's control points")
	T.eq(round:SetMode(MODE), true, "a train watcher's payload")
	T.eq(round:SetMode(ControlPoints.Mode), false, "control points never replace payload")
	T.eq(round:Mode(), MODE, "payload")
end)

T.test("a race's round win plays each side its stage outcome, as Race.OutcomeLines", function()
	for _, fullRound in ipairs({ FULL_ROUND, MINI_ROUND }) do
		local lines = MODE:RoundWinLines(RED, fullRound, RACE)
		local expected = Race.OutcomeLines(RED, fullRound)
		T.eq(lines[RED], expected[RED], "the winner's line")
		T.eq(lines[BLU], expected[BLU], "the loser's line")
	end
	T.eq(next(MODE:RoundWinLines(RED, FULL_ROUND, NO_RACE)), nil, "no lines without a race")
	T.eq(next(MODE:RoundWinLines(NOBODY, FULL_ROUND, RACE)), nil, "no lines for a stalemate")
end)

-- A single cart ------------------------------------------------------------------

-- A straight path of nodes every 500 units, the checkpoints at 1000 and 2000
-- (the goal).
local DISTANCE_AT = { 0, 500, 1000, 1500, 2000 }
local TOTAL = 2000

local function Links()
	return {
		{
			distance = 1000,
			alerted = false,
			index = 3,
		},
		{
			distance = 2000,
			alerted = false,
			index = 5,
		},
	}
end

T.test("a single cart: pushed faster by more pushers, it warns once per checkpoint and alarms at the goal", function()
	local cart = {
		numCappers = 1,
		hill = Payload.HILL_NONE,
		currentSpeed = 0,
		receding = false,
	}
	local speed = Payload.TrainSpeed(cart)
	T.eq(speed, 0.55, "one pusher")
	cart.numCappers = 3
	T.eq(Payload.TrainSpeed(cart), 1.0, "three pushers, full speed")
	T.eq(Payload.SpeedLevel(95, 95, LEVELS), 3, "three arrows at full speed")

	local links = Links()
	T.eq(#Payload.AlertsDue(links, 100, true), 0, "far from the first checkpoint")
	local due = Payload.AlertsDue(links, 1000 - Payload.ALERT_DISTANCE + 1, true)
	T.eq(#due, 1, "within the alert distance")
	T.eq(due[1], 1, "the first checkpoint's warning")
	T.eq(#Payload.AlertsDue(links, 900, true), 0, "only once")

	-- between nodes 4 and 5, 100 units past node 4, heading for the goal
	local target = Payload.TargetIndex(4, speed, #DISTANCE_AT)
	T.eq(target, 5, "heads for the goal node")
	local toGoal = Payload.DistanceToGoal(TOTAL, DISTANCE_AT, target, 400)
	T.eq(toGoal, 400, "400 left")
	T.near(Payload.Progress(TOTAL, toGoal), 0.8, 1e-9, "four fifths along")

	local alarm = Payload.NewAlarm()
	local HAS_LINKS, RUNNING, NOW = true, true, 10
	T.eq(#Payload.AlarmStep(alarm, 1000, RUNNING, true, HAS_LINKS, NOW), 0, "no alarm far from the goal")
	local actions = Payload.AlarmStep(alarm, Payload.ALARM_DISTANCE - 1, RUNNING, true, HAS_LINKS, NOW)
	T.eq(actions[1], "start", "the alarm loops near the goal")
end)

-- Recede ---------------------------------------------------------------------------

T.test("recede: left alone the cart waits tf_escort_recede_time, then rolls back until pushed again", function()
	local delay = Payload.RecedeDelay(false, MAP_RECEDE_TIME, RECEDE_TIME, RECEDE_TIME_OVERTIME)
	T.eq(delay, RECEDE_TIME, "the convar's 30 s")
	T.eq(Payload.RecedeDelay(false, 12, RECEDE_TIME, RECEDE_TIME_OVERTIME), 12, "the map's train_recede_time")
	T.eq(Payload.TimerMayExpire({
		disabled = false,
		waitingToRecede = true,
		capBlocked = false,
		areaCapturing = false,
	}), false, "a cart waiting to recede holds the clock")

	local cart = {
		numCappers = 0,
		hill = Payload.HILL_NONE,
		currentSpeed = 0,
		receding = false,
	}
	local speed, receding = Payload.TrainSpeed(cart, true)
	T.eq(speed < 0, true, "the countdown's end rolls it back")
	T.eq(receding, true, "receding")
	T.eq(Payload.SpeedLevel(-1, speed, LEVELS), Payload.SPEED_LEVEL_BACKWARDS, "the backwards arrow")
	cart.currentSpeed, cart.receding = speed, receding
	T.eq(Payload.TrainSpeed(cart), speed, "it keeps rolling back")
	cart.numCappers = 1
	speed, receding = Payload.TrainSpeed(cart)
	T.eq(speed, 0.55, "a pusher stops the recede")
	T.eq(receding, false, "no longer receding")
end)

-- Overtime while pushing ---------------------------------------------------------------

local function Q(mayExpire, overtime)
	return {
		mayExpire = mayExpire,
		roundWon = false,
		overtime = overtime,
		nagEnabled = false,
		random = function() return 0 end,
	}
end

local function Kinds(events)
	local list = {}
	for i, e in ipairs(events) do
		list[i] = e.kind == "output" and e.name or e.kind .. " " .. tostring(e.value)
	end
	return table.concat(list, ", ")
end

T.test("overtime while pushing: the clock holds at zero until the cart stands, then shortens its recede", function()
	local LENGTH = 0.5
	local timer = Timer.New({
		length = LENGTH,
		maxLength = 0,
		setupLength = 0,
		startPaused = false,
		showInHud = true,
		autoCountdown = true,
		resetTime = false,
		startDisabled = false,
		now = 0,
	})
	timer:RoundSpawn(0)
	local round = Rounds.New(SETTINGS)
	round:SetMode(MODE)
	local watcher = {
		disabled = false,
		waitingToRecede = false,
		capBlocked = false,
		areaCapturing = true,
	}
	local function MayExpire(now)
		return round:TimerMayExpire(now, {
			capturing = false,
			other = not Payload.TimerMayExpire(watcher),
		})
	end

	T.eq(Kinds(timer:Think(LENGTH, Q(MayExpire(LENGTH), false))), "overtime true", "pushed at zero: overtime")
	T.eq(timer:TimeRemaining(2), 0, "held")

	-- the pushers step off: the countdown starts with the overtime length
	watcher.areaCapturing = false
	watcher.waitingToRecede = true
	local now = 2
	local delay = Payload.RecedeDelay(true, MAP_RECEDE_TIME, RECEDE_TIME, RECEDE_TIME_OVERTIME)
	T.eq(delay, RECEDE_TIME_OVERTIME, "tf_escort_recede_time_overtime")
	T.eq(Kinds(timer:Think(now, Q(MayExpire(now), true))), "", "still held while it waits to recede")

	-- a countdown started before overtime is cut to the overtime length
	local longAt = 40
	T.eq(Payload.OvertimeRecedeAt(longAt, now, RECEDE_TIME_OVERTIME), now + RECEDE_TIME_OVERTIME, "shortened")
	T.eq(Payload.OvertimeRecedeAt(now + 1, now, RECEDE_TIME_OVERTIME), now + 1, "never lengthened")

	-- the countdown ends in overtime: the cart does not recede, the hold ends
	watcher.waitingToRecede = false
	now = now + delay + 1
	T.eq(Kinds(timer:Think(now, Q(MayExpire(now), true))), "OnFinished", "the round ends")
end)

T.test("a blocked cart holds the clock, and a disabled watcher never does", function()
	T.eq(Payload.TimerMayExpire({
		disabled = false,
		waitingToRecede = false,
		capBlocked = true,
		areaCapturing = false,
	}), false, "blocked")
	T.eq(Payload.TimerMayExpire({
		disabled = true,
		waitingToRecede = true,
		capBlocked = true,
		areaCapturing = true,
	}), true, "disabled")
	T.eq(Payload.TimerMayExpire({
		disabled = false,
		waitingToRecede = false,
		capBlocked = false,
		areaCapturing = false,
	}), true, "a cart standing idle")
end)

-- A race -------------------------------------------------------------------------------

T.test("a race: BLU's cart is drawn first, the leader is the cart farther along, the win plays the outcome", function()
	local carts = Hud.Order({
		{
			team = RED,
			index = 40,
		},
		{
			team = BLU,
			index = 70,
		},
		{
			team = BLU,
			index = 12,
		},
	})
	T.eq(carts[1].team, BLU, "BLU first")
	T.eq(carts[1].index, 12, "then by entity index")
	T.eq(carts[2].index, 70, "BLU's second")
	T.eq(carts[3].team, RED, "RED last")
	T.eq(Race.Leader({
		[RED] = 1200,
		[BLU] = 800,
	}), RED, "RED ahead")
	T.eq(Race.Leader({
		[RED] = 800,
		[BLU] = 800,
	}), NOBODY, "level")
	local round = Rounds.New(SETTINGS)
	round:SetMode(MODE)
	T.eq(round:Mode():RoundWinLines(BLU, MINI_ROUND, RACE)[BLU], Race.OutcomeLines(BLU, MINI_ROUND)[BLU], "the stage outcome")
end)

-- The cart HUD ---------------------------------------------------------------------------

T.test("the cart HUD's checkpoints, owners and hills survive the wire", function()
	local cps = { 0.25, 0.5, 1 }
	local owners = { BLU, RED, RED }
	local hills = {
		{
			from = 0.1,
			to = 0.2,
			down = false,
		},
		{
			from = 0.6,
			to = 0.75,
			down = true,
		},
	}
	local decodedCps = Hud.DecodeNumbers(Hud.EncodeNumbers(cps, Hud.POSITION_FORMAT))
	T.eq(#decodedCps, #cps, "every checkpoint")
	for i, v in ipairs(cps) do T.near(decodedCps[i], v, 1e-4, "checkpoint " .. i) end
	local decodedOwners = Hud.DecodeNumbers(Hud.EncodeNumbers(owners, Hud.OWNER_FORMAT))
	for i, v in ipairs(owners) do T.eq(decodedOwners[i], v, "owner " .. i) end
	local decodedHills = Hud.DecodeHills(Hud.EncodeHills(hills))
	T.eq(#decodedHills, #hills, "every hill")
	for i, h in ipairs(hills) do
		T.near(decodedHills[i].from, h.from, 1e-4, "hill from")
		T.near(decodedHills[i].to, h.to, 1e-4, "hill to")
		T.eq(decodedHills[i].down, h.down, "hill direction")
	end
	T.eq(#Hud.DecodeNumbers(""), 0, "no checkpoints")
	T.eq(#Hud.DecodeHills(""), 0, "no hills")
end)

local function Cart(over)
	local cart = {
		speed = 0,
		cappers = 0,
		recedeAt = 0,
		canRecede = true,
	}
	for k, v in pairs(over) do cart[k] = v end
	return cart
end

-- What TF2's escort HUD (CTFHudEscort) shows on the cart's icon.
T.test("the cart's indicator: blocked, rolling back, its pushers, or the rollback countdown", function()
	local NOW = 100
	T.eq(Hud.Indicator(Cart({ cappers = Payload.CAPPERS_BLOCKED }), NOW).blocked, true, "blocked")
	local pushed = Hud.Indicator(Cart({ speed = 2, cappers = 2 }), NOW)
	T.eq(pushed.cappers, 2, "two pushers")
	T.eq(pushed.recede, nil, "no countdown while pushed")
	T.eq(Hud.Indicator(Cart({ speed = Payload.SPEED_LEVEL_BACKWARDS }), NOW).backwards, true, "rolling back")
	T.eq(Hud.Indicator(Cart({ recedeAt = NOW + 11.5 }), NOW).recede, 12, "the countdown, rounded up")
	T.eq(Hud.Indicator(Cart({ recedeAt = NOW - 1 }), NOW).recede, 0, "never negative")
	T.eq(Hud.Indicator(Cart({ recedeAt = NOW + 5, canRecede = false }), NOW).recede, nil, "a cart that cannot recede shows none")
	local idle = Hud.Indicator(Cart({}), NOW)
	T.eq(idle.blocked or idle.backwards or idle.cappers or idle.recede, nil, "an idle cart shows nothing")
end)

T.test("the admin's cart speed scale is clamped to the editor's range", function()
	T.eq(Payload.SpeedScale(2), 2, "in range")
	T.eq(Payload.SpeedScale(100), Payload.CART_SPEED_MAX, "clamped high")
	T.eq(Payload.SpeedScale(0), Payload.CART_SPEED_MIN, "clamped low")
	T.eq(Payload.CART_SPEED_DEFAULT, 1, "the map's own speed")
end)

-- Seams --------------------------------------------------------------------------------

local ENTITIES = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

local function Exists(path)
	local f = io.open(path, "rb")
	if f then f:close() end
	return f ~= nil
end

T.test("the legacy payload files are gone", function()
	for _, name in ipairs({ "sv_payload", "cl_payload", "cl_hud" }) do
		T.eq(Exists(T.ROOT .. "ws/" .. name .. ".lua"), false, name)
	end
end)

T.test("the payload controller defines every method other code calls", function()
	local text = T.RealmSource("payload", "sv")
	for _, name in ipairs({ "CartSpeedScale", "SetCartSpeedScale", "HasMultipleTrains", "BindWatcher", "BindEscort" }) do
		T.eq(text:find("function Controller:" .. name .. "(", 1, true) ~= nil, true, name)
	end
end)

T.test("the payload bindings reach the controller, not the old globals", function()
	local watcher = Read(ENTITIES .. "team_train_watcher.lua")
	for _, old in ipairs({ "WS.Payload", "WS.CartSpeedScale", "WS.HoldTimersForWatchers" }) do
		T.eq(watcher:find(old, 1, true), nil, old)
	end
	T.eq(watcher:find(":BindWatcher(self)", 1, true) ~= nil, true, "the watcher binds")
	T.eq(Read(ENTITIES .. "tf_logic_multiple_escort.lua"):find(":BindEscort(self)", 1, true) ~= nil, true, "the escort binds")
end)

T.test("the payload view reads only networked state", function()
	T.eq(T.RealmSource("payload", "cl"):find("ents.Find", 1, true), nil, "no ents.Find")
end)

T.finish()
