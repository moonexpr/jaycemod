-- The round timer model (foundation.rounds.timer), CTeamRoundTimer
-- (teamplay_round_timer.cpp): setup then normal time, its marks, overtime,
-- added time, mini-round carry-over, and the client's countdown and the HUD
-- timer choice.
local T = dofile("tests/harness.lua")
local Timer = T.require("foundation.rounds.timer")
local Teams = T.require("foundation.teams")

local NOBODY, RED = Teams.UNASSIGNED, Teams.RED

local function New(over)
	local kv = {
		length = 270,
		maxLength = 0,
		setupLength = 0,
		startPaused = false,
		showInHud = true,
		autoCountdown = true,
		resetTime = false,
		startDisabled = false,
		now = 0,
	}
	for k, v in pairs(over or {}) do kv[k] = v end
	return Timer.New(kv)
end

local DESCRIBE = {
	output = function(e) return e.name end,
	setup = function(e) return "setup " .. tostring(e.value) end,
	overtime = function(e) return "overtime " .. tostring(e.value) end,
	time_added = function(e) return "time_added " .. e.team .. " " .. e.seconds end,
}

local function Describe(events)
	local lines = {}
	for i, e in ipairs(events) do
		local describe = DESCRIBE[e.kind]
		lines[i] = describe and describe(e) or e.kind
	end
	return table.concat(lines, ", ")
end

local function Expect(events, expected, what)
	T.eq(Describe(events), table.concat(expected, ", "), what)
end

local function Q(over)
	local q = {
		mayExpire = true,
		roundWon = false,
		overtime = false,
		nagEnabled = false,
		random = function() return 0 end,
	}
	for k, v in pairs(over or {}) do q[k] = v end
	return q
end

local RUNNING = {
	roundRunningOrWon = true,
	isHud = true,
	roundWon = false,
	inStalemate = false,
	announces = true,
}

local function AddQ(over)
	local q = {}
	for k, v in pairs(RUNNING) do q[k] = v end
	for k, v in pairs(over or {}) do q[k] = v end
	return q
end

T.test("a new timer is paused, holding its setup time, and says so when it spawns", function()
	local timer = New({ setupLength = 60 })
	T.eq(timer:Paused(), true, "paused")
	T.eq(timer:InSetup(), true, "in setup")
	T.eq(timer:TimeRemaining(5), 60, "setup time")
	Expect(timer:SpawnEvents(), { "setup true", "OnSetupStart" }, "spawn")
	Expect(New():SpawnEvents(), { "setup false", "OnRoundStart" }, "no setup")
	local disabled = New({ startDisabled = true })
	T.eq(disabled:Disabled(), true, "disabled")
	T.eq(disabled:TimeRemaining(0), 270, "a disabled timer still takes its time")
end)

T.test("setup 60 then 270 of normal time: the marks, one per think, then the round", function()
	local timer = New({ setupLength = 60 })
	Expect(timer:RoundSpawn(0), { "setup true", "OnSetupStart", "length_changed" }, "round spawn")
	T.eq(timer:Paused(), false, "start_paused 0 resumes")
	local marks = {
		{ 1, "On1MinRemain" },
		{ 2, "" },
		{ 31, "On30SecRemain" },
		{ 51, "On10SecRemain" },
		{ 55, "On5SecRemain" },
		{ 56, "On4SecRemain" },
		{ 57, "On3SecRemain" },
		{ 58, "On2SecRemain" },
		{ 59, "On1SecRemain" },
	}
	for _, m in ipairs(marks) do
		Expect(timer:Think(m[1], Q()), m[2] == "" and {} or { m[2] }, "t=" .. m[1])
	end
	Expect(timer:Think(60, Q()), {
		"OnSetupFinished",
		"setup false",
		"OnRoundStart",
		"length_changed",
	}, "setup ends")
	T.eq(timer:InSetup(), false, "normal time")
	T.eq(timer:TimeRemaining(60), 270, "the round's time")
	Expect(timer:Think(61, Q()), {}, "no 5 min mark under 5 minutes")
	Expect(timer:Think(90, Q()), { "On4MinRemain" }, "4 minutes")
	Expect(timer:Think(91, Q()), {}, "once")
end)

T.test("setup's think ends overtime", function()
	local timer = New({ setupLength = 60 })
	timer:RoundSpawn(0)
	Expect(timer:Think(0.5, Q({ overtime = true })), { "overtime false", "On1MinRemain" }, "no overtime in setup")
end)

-- Half a second arms no mark, so only overtime and OnFinished can fire.
local SHORT = 0.5

T.test("at zero the clock holds while it may not expire: overtime, a nag at most once a second", function()
	local timer = New({ length = SHORT })
	timer:RoundSpawn(0)
	local heads = function() return 1 end
	local tails = function() return 0 end
	Expect(timer:Think(0.5, Q({ mayExpire = false })), { "overtime true" }, "overtime")
	Expect(timer:Think(1, Q({
		mayExpire = false,
		overtime = true,
		nagEnabled = true,
		random = heads,
	})), { "nag" }, "a nag")
	Expect(timer:Think(1.5, Q({
		mayExpire = false,
		overtime = true,
		nagEnabled = true,
		random = heads,
	})), {}, "not within the second")
	Expect(timer:Think(2.1, Q({
		mayExpire = false,
		overtime = true,
		nagEnabled = true,
		random = tails,
	})), {}, "the coin says no")
	Expect(timer:Think(3.2, Q({
		mayExpire = false,
		overtime = true,
	})), {}, "tf_overtime_nag 0")
	T.eq(timer:TimeRemaining(3.2), 0, "held at zero")
	Expect(timer:SetTimeRemaining(3.2, SHORT), { "length_changed" }, "time again")
	T.near(timer:TimeRemaining(3.3), 0.4, 1e-9, "the held clock never ran negative")
	Expect(timer:Think(3.3, Q({ overtime = true })), { "overtime false" }, "time left ends overtime")
	Expect(timer:Think(3.7, Q()), { "OnFinished" }, "finished")
	Expect(timer:Think(4, Q()), {}, "once")
end)

T.test("OnFinished fires once the clock may expire, and leaves overtime to the next round", function()
	local timer = New({ length = SHORT })
	timer:RoundSpawn(0)
	Expect(timer:Think(0.5, Q({ mayExpire = false })), { "overtime true" }, "overtime")
	Expect(timer:Think(1, Q({ overtime = true })), { "OnFinished" }, "finished")
	Expect(timer:Think(2, Q({ overtime = true })), {}, "no overtime change at zero (RoundTimerThink)")
end)

T.test("a clock not shown in the HUD holds without overtime", function()
	local timer = New({
		length = SHORT,
		showInHud = false,
	})
	timer:RoundSpawn(0)
	Expect(timer:Think(0.5, Q({ mayExpire = false })), {}, "held quietly")
	Expect(timer:Think(1, Q()), { "OnFinished" }, "finished")
end)

T.test("a won round pauses the timer", function()
	local timer = New()
	timer:RoundSpawn(0)
	Expect(timer:Think(10, Q({ roundWon = true })), {}, "nothing fires")
	T.eq(timer:Paused(), true, "paused")
	T.eq(timer:TimeRemaining(100), 260, "stopped")
end)

T.test("added time is capped by max_length and announced only by the HUD timer of a live round", function()
	local timer = New({
		length = 250,
		maxLength = 300,
	})
	timer:RoundSpawn(0)
	local serial = timer:Serial()
	local events, added = timer:AddSeconds(0, 100, RED, AddQ())
	Expect(events, { "length_changed", "time_added " .. RED .. " 50" }, "capped")
	T.eq(added, 50, "50 added")
	T.eq(timer:Serial(), serial + 1, "the serial bumps")
	T.eq(timer:TimeRemaining(0), 300, "at the cap")
	timer:SetMaxLength(0, 0)
	Expect((timer:AddSeconds(0, 10, RED, AddQ({ announces = false }))), { "length_changed" }, "KOTH is silent")
	Expect((timer:AddSeconds(0, 10, RED, AddQ({ isHud = false }))), { "length_changed" }, "not the HUD timer")
	Expect((timer:AddSeconds(0, 10, RED, AddQ({ roundWon = true }))), { "length_changed" }, "the round is won")
	events, added = timer:AddSeconds(0, 10, RED, AddQ({ inStalemate = true }))
	Expect(events, {}, "sudden death adds nothing")
	T.eq(added, 0, "nothing added")
	Expect((timer:AddSeconds(0, 10, RED, AddQ({ roundRunningOrWon = false }))), {}, "not while the round is not running")
	T.eq(timer:TimeRemaining(0), 330, "three adds")
end)

T.test("round spawn carries normal time into the next mini-round unless reset_time", function()
	local timer = New({ length = 600 })
	timer:RoundSpawn(0)
	timer:RoundSpawn(100)
	T.eq(timer:TimeRemaining(100), 500, "carried")
	local reset = New({
		length = 600,
		resetTime = true,
	})
	reset:RoundSpawn(0)
	reset:RoundSpawn(100)
	T.eq(reset:TimeRemaining(100), 600, "reset")

	local staged = New({
		length = 600,
		setupLength = 60,
	})
	staged:RoundSpawn(0)
	staged:Think(60, Q())
	staged:RoundSpawn(160)
	T.eq(staged:InSetup(), true, "setup again")
	T.eq(staged:TimeRemaining(160), 60, "setup's time")
	staged:FinishSetup(170)
	T.eq(staged:TimeRemaining(170), 500, "then the carried time")
end)

T.test("start_paused waits for Resume; pause and resume keep the time", function()
	local timer = New({ startPaused = true })
	timer:RoundSpawn(0)
	T.eq(timer:Paused(), true, "start paused")
	timer:Resume(10)
	T.eq(timer:TimeRemaining(20), 260, "running from 10")
	timer:Pause(20)
	T.eq(timer:TimeRemaining(50), 260, "paused")
	timer:Resume(50)
	T.eq(timer:TimeRemaining(60), 250, "running again")
end)

T.test("a disabled timer ignores its inputs until enabled", function()
	local timer = New()
	timer:RoundSpawn(0)
	timer:Disable(10)
	T.eq(timer:Disabled(), true, "disabled")
	T.eq(timer:Paused(), true, "and paused")
	Expect(timer:SetTimeRemaining(10, 30), {}, "no SetTime")
	timer:Resume(10)
	T.eq(timer:Paused(), true, "no Resume")
	Expect(timer:Think(300, Q()), {}, "no think")
	timer:Enable(20)
	T.eq(timer:Paused(), false, "enabling resumes")
	T.eq(timer:TimeRemaining(20), 260, "the time it had")
end)

T.test("inputs: SetTime, Restart, SetMaxTime, SetSetupTime, ShowInHUD, AutoCountdown", function()
	local timer = New({ setupLength = 60 })
	timer:RoundSpawn(0)
	Expect(timer:SetTimeRemaining(0, 45), { "length_changed" }, "set")
	T.eq(timer:TimeRemaining(0), 45, "45")
	Expect(timer:SetSetupLength(0, 20), { "length_changed" }, "setup time while in setup")
	T.eq(timer:TimeRemaining(0), 20, "20")
	Expect(timer:SetMaxLength(0, 10), { "length_changed" }, "clamped")
	T.eq(timer:TimeRemaining(0), 10, "10")
	timer:SetMaxLength(0, 0)
	Expect(timer:Restart(0), { "length_changed" }, "restart")
	T.eq(timer:TimeRemaining(0), 270, "the initial length")
	timer:SetShowInHud(false)
	T.eq(timer:ShowInHud(), false, "hidden")
	timer:SetAutoCountdown(false)
	T.eq(timer:AutoCountdown(), false, "silent")
end)

-- Client countdown (CalculateOutputMessages with the client's 2 s allowance)

T.test("the client arms with two seconds of slack above ten seconds", function()
	local armed = Timer.ArmClientWarnings(59)
	T.eq(armed[60], true)
	T.eq(armed[30], true)
	armed = Timer.ArmClientWarnings(57)
	T.eq(armed[60], false)
end)

T.test("the client does not pad short times", function()
	local armed = Timer.ArmClientWarnings(9)
	T.eq(armed[10], false)
	T.eq(armed[5], true)
end)

T.test("client warnings speak a second early, one per think", function()
	local armed = Timer.ArmClientWarnings(120)
	T.eq(Timer.NextClientWarning(armed, 61), 60)
	armed[60] = false
	T.eq(Timer.NextClientWarning(armed, 61), nil)
	T.eq(Timer.NextClientWarning(armed, 6), 30)
end)

-- SetActiveTimer

local function Timers(list)
	local timers = {}
	for i, t in ipairs(list) do
		timers[i] = {
			enabled = t[1],
			show = t[2],
		}
	end
	return timers
end

T.test("a newly active timer hides the other shown timers", function()
	local chosen, hide = Timer.ChooseActiveTimer(Timers({ { true, true }, { true, true }, { false, true } }), 2)
	T.eq(chosen, 2)
	T.eq(#hide, 1)
	T.eq(hide[1], 1)
end)

T.test("with none newly active the first enabled shown timer is chosen", function()
	local chosen, hide = Timer.ChooseActiveTimer(Timers({ { false, true }, { true, false }, { true, true } }), nil)
	T.eq(chosen, 3)
	T.eq(#hide, 0)
end)

T.test("no candidate chooses nothing", function()
	local chosen = Timer.ChooseActiveTimer(Timers({ { false, true } }), nil)
	T.eq(chosen, nil)
end)

T.finish()
