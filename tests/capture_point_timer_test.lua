-- foundation.capture.point_timer: tf_logic_cp_timer (CCPTimerLogic,
-- tf_gamerules.cpp), on cp_degrootkeep's timer: 60 s for BLU once BLU may
-- capture control_point_3, thought every 0.15 s on a fake clock.
local T = dofile("tests/harness.lua")
local PointTimer = T.require("foundation.capture.point_timer")
local Teams = T.require("foundation.teams")

local BLU = Teams.BLUE
local STEP = PointTimer.THINK_INTERVAL
local DEGROOT_LENGTH = 60 -- cp_degrootkeep's timer_length
local START = 100

local MAY_CAP = true
local MAY_NOT_CAP = false
local CAPPING = true
local NOBODY_CAPPING = false
local ROUND_WON = true
local ROUND_PLAYING = false

local function Degroot()
	return PointTimer.New({
		length = DEGROOT_LENGTH,
		team = BLU,
	})
end

local function Q(teamMayCapture, capping, roundWon)
	return {
		teamMayCapture = teamMayCapture,
		capping = capping,
		roundWon = roundWon,
	}
end

local function Kinds(events)
	local out = {}
	for _, e in ipairs(events) do out[#out + 1] = e.kind end
	return table.concat(out, ",")
end

-- Thinks from `from` to `to` (inclusive) every STEP with q, collecting events.
local function Run(pt, from, to, q)
	local all = {}
	local now = from
	while now <= to + 1e-9 do
		for _, e in ipairs(pt:Think(now, q)) do all[#all + 1] = e end
		now = now + STEP
	end
	return all
end

T.test("the defaults are CCPTimerLogic's: 60 s for BLU", function()
	local pt = PointTimer.New({})
	T.eq(PointTimer.LENGTH_DEFAULT, DEGROOT_LENGTH, "LENGTH_DEFAULT")
	T.eq(PointTimer.TEAM_DEFAULT, BLU, "TEAM_DEFAULT")
	T.eq(pt:Team(), BLU, "team")
	T.eq(pt:EndTime(), nil, "idle")
	T.eq(PointTimer.THINK_INTERVAL, 0.15, "think interval")
end)

T.test("BLU able to cap the point starts the countdown once", function()
	local pt = Degroot()
	T.eq(Kinds(pt:Think(START, Q(MAY_NOT_CAP, NOBODY_CAPPING, ROUND_PLAYING))), "", "idle while BLU may not cap")
	local events = pt:Think(START + STEP, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	T.eq(Kinds(events), PointTimer.START, "OnCountdownStart")
	T.eq(events[1].endTime, START + STEP + DEGROOT_LENGTH, "the HUD's end time")
	T.eq(pt:EndTime(), START + STEP + DEGROOT_LENGTH, "EndTime")
	T.eq(Kinds(Run(pt, START + 2 * STEP, START + 30, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))), "", "no second start")
	T.eq(pt:MayExpire(MAY_CAP), false, "holds the round timer while BLU may cap")
	T.eq(pt:MayExpire(MAY_NOT_CAP), true, "lets it expire otherwise")
end)

T.test("at expiry it waits for the capture to finish, then ends once and resets", function()
	local pt = Degroot()
	pt:Think(START, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	local expiry = START + DEGROOT_LENGTH
	T.eq(Kinds(pt:Think(expiry, Q(MAY_CAP, CAPPING, ROUND_PLAYING))), "", "not elapsed at the end time itself")
	T.eq(Kinds(Run(pt, expiry + STEP, expiry + 5, Q(MAY_CAP, CAPPING, ROUND_PLAYING))), "", "waits while BLU caps")
	T.eq(pt:EndTime(), expiry, "still counting")
	T.eq(Kinds(pt:Think(expiry + 5 + STEP, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))), PointTimer.END, "OnCountdownEnd")
	T.eq(pt:EndTime(), nil, "reset")
	-- The map's relay hands A and B back to RED; until it lands, BLU may
	-- still cap and a new countdown starts, as in TF2.
	local again = pt:Think(expiry + 5 + 2 * STEP, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	T.eq(Kinds(again), PointTimer.START, "a fresh countdown")
	T.eq(again[1].endTime, expiry + 5 + 2 * STEP + DEGROOT_LENGTH, "from now")
end)

T.test("a team that may no longer cap leaves it idle without an end", function()
	local pt = Degroot()
	pt:Think(START, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	T.eq(Kinds(pt:Think(START + 20, Q(MAY_NOT_CAP, NOBODY_CAPPING, ROUND_PLAYING))), "", "no end")
	T.eq(pt:EndTime(), nil, "idle")
	T.eq(Kinds(Run(pt, START + 20 + STEP, START + 200, Q(MAY_NOT_CAP, NOBODY_CAPPING, ROUND_PLAYING))), "", "stays idle")
end)

T.test("an elapsed countdown whose team may no longer cap goes idle without an end", function()
	local pt = Degroot()
	pt:Think(START, Q(MAY_CAP, CAPPING, ROUND_PLAYING))
	T.eq(Kinds(pt:Think(START + DEGROOT_LENGTH + 1, Q(MAY_NOT_CAP, NOBODY_CAPPING, ROUND_PLAYING))), "", "no end")
	T.eq(pt:EndTime(), nil, "idle")
end)

T.test("a round won invalidates it", function()
	local pt = Degroot()
	pt:Think(START, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	T.eq(Kinds(pt:Think(START + 10, Q(MAY_NOT_CAP, NOBODY_CAPPING, ROUND_WON))), "", "no end on the win")
	T.eq(pt:EndTime(), nil, "invalidated")
end)

-- CCPTimerLogic::Think invalidates on GR_STATE_TEAM_WIN and carries on, so a
-- team that may still cap starts it again on the same think.
T.test("a round won while the team may still cap restarts it at once", function()
	local pt = Degroot()
	pt:Think(START, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	local events = pt:Think(START + 70, Q(MAY_CAP, NOBODY_CAPPING, ROUND_WON))
	T.eq(Kinds(events), PointTimer.START, "restarted, never ended")
	T.eq(events[1].endTime, START + 70 + DEGROOT_LENGTH, "from the win")
end)

T.test("the 15, 10 and 5 second marks fire nothing", function()
	local pt = Degroot()
	pt:Think(START, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	local marks = Run(pt, START + DEGROOT_LENGTH - 16, START + DEGROOT_LENGTH - STEP, Q(MAY_CAP, NOBODY_CAPPING, ROUND_PLAYING))
	T.eq(Kinds(marks), "", "no events before expiry")
	T.eq(pt:EndTime(), START + DEGROOT_LENGTH, "still counting")
end)

-- Seam checks, read as text.
local ENTITIES = "addon/gamemodes/sandcastle/entities/entities/"
local CONTROLLER = T.ROOT .. "features/capture/sv.lua"

local function Read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

T.test("the tf_logic_cp_timer binding requires no foundation module", function()
	T.eq(Read(ENTITIES .. "tf_logic_cp_timer.lua"):find('require("foundation.', 1, true), nil, "tf_logic_cp_timer")
end)

T.test("the capture controller defines every method the binding calls", function()
	local text = Read(CONTROLLER)
	for _, name in ipairs({ "BindPointTimer", "UnbindPointTimer", "PointTimerThink", "PointTimerInput" }) do
		T.eq(text:find("function Controller:" .. name .. "(", 1, true) ~= nil, true, name)
	end
end)

T.finish()
