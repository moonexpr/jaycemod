local T = dofile("tests/harness.lua")
local Fortune = T.require("foundation.holiday.fortune")
local Teams = T.require("games.gameplay.teams")

local STEP = 0.01 -- the test's server tick
local TOLERANCE = STEP + 1e-6
local RED_SPOT, BLUE_SPOT = "fortune_teleport_red", "fortune_teleport_blue"

-- The timeline as the map sees it: one line per effect, with the tick it
-- came on.
local Run = {}
Run.__index = Run

local function NewRun(spawnTime)
	return setmetatable({
		fortune = Fortune.New({
			redTeleport = RED_SPOT,
			blueTeleport = BLUE_SPOT,
		}, spawnTime),
		spawnTime = spawnTime,
		ticks = 0,
		now = spawnTime,
		log = {},
	}, Run)
end

local LABEL = {
	[Fortune.OUTPUT] = function(e) return e.name end,
	[Fortune.BROADCAST] = function(e) return "sound " .. e.sound end,
	[Fortune.TELEPORT] = function(e) return "teleport " .. e.team .. " " .. e.target end,
}

function Run:Record(effects)
	for _, e in ipairs(effects) do
		self.log[#self.log + 1] = {
			at = self.now,
			what = LABEL[e.kind](e),
		}
	end
end

function Run:Input(name)
	self:Record(self.fortune:Input(name, self.now))
end

-- Ticks every STEP up to `time`, counting ticks so the clock does not drift.
function Run:Until(time)
	while self.spawnTime + (self.ticks + 1) * STEP <= time + TOLERANCE / 2 do
		self.ticks = self.ticks + 1
		self.now = self.spawnTime + self.ticks * STEP
		self:Record(self.fortune:Tick(self.now))
	end
end

-- The log must be exactly `expected`: { { at, what }, ... }.
function Run:Expect(expected)
	T.eq(#self.log, #expected, "effects (" .. self:Describe() .. ")")
	for i, e in ipairs(expected) do
		T.eq(self.log[i].what, e[2], "effect " .. i)
		T.near(self.log[i].at, e[1], TOLERANCE, e[2] .. " time")
	end
end

function Run:Describe()
	local parts = {}
	for _, e in ipairs(self.log) do parts[#parts + 1] = string.format("%.2f %s", e.at, e.what) end
	return table.concat(parts, "; ")
end

local WARNING, TOLD, CURSE, END = Fortune.OUTPUT_WARNING, Fortune.OUTPUT_TOLD, Fortune.OUTPUT_CURSE, Fortune.OUTPUT_END
local SPIN = "sound " .. Fortune.SPIN_SOUND
local TELEPORT_RED = "teleport " .. Teams.RED .. " " .. RED_SPOT
local TELEPORT_BLUE = "teleport " .. Teams.BLUE .. " " .. BLUE_SPOT

-- One fortune whose spin starts at `told`.
local function OneFortune(told)
	local teleport = told + Fortune.TELL_DELAY
	return {
		{ told, TOLD },
		{ told, SPIN },
		{ teleport, TELEPORT_RED },
		{ teleport, TELEPORT_BLUE },
		{ teleport + Fortune.CURSE_DELAY, CURSE },
	}
end

local function Concat(...)
	local all = {}
	for _, list in ipairs({ ... }) do
		for _, e in ipairs(list) do all[#all + 1] = e end
	end
	return all
end

local ENABLE, DISABLE = Fortune.INPUT_ENABLE, Fortune.INPUT_DISABLE
local START, STOP = Fortune.INPUT_START, Fortune.INPUT_END
local WARN_AT = Fortune.INTERVAL - Fortune.WARNING_TIME

T.test("a teller never enabled tells nothing (CTFHalloweenFortuneTeller starts without its timer)", function()
	local run = NewRun(0)
	run:Until(2 * Fortune.INTERVAL + Fortune.DURATION)
	run:Expect({})
end)

T.test("the timeline over two intervals", function()
	local run = NewRun(0)
	run:Input(ENABLE)
	run:Until(2 * Fortune.INTERVAL + 2 * (Fortune.TELL_DELAY + Fortune.CURSE_DELAY + Fortune.DURATION) + 1)
	local ended = Fortune.INTERVAL + Fortune.TELL_DELAY + Fortune.CURSE_DELAY + Fortune.DURATION
	local secondTold = ended + Fortune.INTERVAL
	run:Expect(Concat(
		{ { WARN_AT, WARNING } },
		OneFortune(Fortune.INTERVAL),
		{ { ended, END } },
		{ { ended + WARN_AT, WARNING } },
		OneFortune(secondTold),
		{ { secondTold + Fortune.TELL_DELAY + Fortune.CURSE_DELAY + Fortune.DURATION, END } }
	))
end)

T.test("Disable pauses the countdown and Enable resumes it where it stopped", function()
	local run = NewRun(0)
	run:Input(ENABLE)
	local paused, resumed = 50, 200
	run:Until(paused)
	run:Input(DISABLE)
	run:Until(resumed)
	run:Input(ENABLE)
	local warning = resumed + WARN_AT - paused
	local told = warning + Fortune.WARNING_TIME
	run:Until(told + Fortune.TELL_DELAY + Fortune.CURSE_DELAY)
	run:Expect({ { warning, WARNING }, unpack(OneFortune(told)) })
end)

T.test("the countdown starts from the Enable, not from the spawn", function()
	local run = NewRun(0)
	local enabled = 30
	run:Until(enabled)
	run:Input(ENABLE)
	run:Until(enabled + WARN_AT)
	run:Expect({ { enabled + WARN_AT, WARNING } })
end)

T.test("a second Enable does not restart the countdown", function()
	local run = NewRun(0)
	run:Input(ENABLE)
	run:Until(50)
	run:Input(ENABLE)
	run:Until(WARN_AT)
	run:Expect({ { WARN_AT, WARNING } })
end)

T.test("Disable during the spin cancels the teleport; Enable spins again at once", function()
	local run = NewRun(0)
	run:Input(ENABLE)
	local paused, resumed = Fortune.INTERVAL + 3, 200
	run:Until(paused)
	run:Input(DISABLE)
	run:Until(resumed)
	run:Input(ENABLE)
	run:Until(resumed + Fortune.TELL_DELAY + Fortune.CURSE_DELAY)
	run:Expect(Concat(
		{ { WARN_AT, WARNING } },
		{ { Fortune.INTERVAL, TOLD }, { Fortune.INTERVAL, SPIN } },
		OneFortune(resumed)
	))
end)

-- PauseTimer cancels the tell and the end, not the curse already queued.
T.test("Disable between the teleport and the curse still curses, but never ends", function()
	local run = NewRun(0)
	run:Input(ENABLE)
	local paused = Fortune.INTERVAL + Fortune.TELL_DELAY + 1
	run:Until(paused)
	run:Input(DISABLE)
	run:Until(paused + Fortune.INTERVAL)
	run:Expect(Concat({ { WARN_AT, WARNING } }, OneFortune(Fortune.INTERVAL)))
end)

T.test("StartFortuneTelling spins now; with no timer the curse never ends by itself", function()
	local run = NewRun(0)
	local started = 10
	run:Until(started)
	run:Input(START)
	run:Until(started + Fortune.INTERVAL)
	run:Expect(OneFortune(started))
end)

T.test("EndFortuneTelling ends now and cancels a pending teleport", function()
	local run = NewRun(0)
	run:Input(START)
	local stopped = 2
	run:Until(stopped)
	run:Input(STOP)
	run:Until(Fortune.TELL_DELAY + 1)
	run:Expect({
		{ 0, TOLD },
		{ 0, SPIN },
		{ stopped, END },
	})
end)

T.test("the teller takes its four inputs; Kill and AddOutput are the engine's", function()
	local fortune = Fortune.New({}, 0)
	for _, input in ipairs({ ENABLE, DISABLE, START, STOP }) do T.eq(fortune:Accepts(input), true, input) end
	T.eq(fortune:Accepts("kill"), false, "kill")
	T.eq(fortune:Accepts("addoutput"), false, "addoutput")
end)

-- A shuffle that reverses: RandomInt(1, i) always answers 1.
local function First(lo, hi) return lo end

T.test("teleports shuffle the team and hand out the named spots in turn", function()
	local moves = Fortune.Teleports({ "a", "b", "c" }, { "s1", "s2", "s3" }, First)
	local where = {}
	for _, m in ipairs(moves) do where[m.player] = m.spot end
	T.eq(#moves, 3, "everyone")
	T.eq(where.a ~= where.b and where.b ~= where.c and where.a ~= where.c, true, "one spot each")
end)

T.test("players beyond the spots stay where they are", function()
	local moves = Fortune.Teleports({ "a", "b", "c" }, { "s1" }, First)
	T.eq(#moves, 1, "one spot, one player")
	T.eq(moves[1].spot, "s1", "the spot")
	T.eq(#Fortune.Teleports({ "a" }, {}, First), 0, "no spots")
end)

T.finish()
