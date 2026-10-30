-- wartactics.mission: a squad's mission from the tactics engine (what kind,
-- the way it goes, how many it should be, how long its leader waits for
-- them), the wait from the spawn waves, and when the squad must regroup:
-- heavy casualties, or no progress along its way.
local T = dofile("tests/harness.lua")
local Mission = wartactics.mission

local WAY = { { x = 0, y = 0, z = 0 }, { x = 500, y = 0, z = 0 } }

local function Valid(fields)
	local spec = { kind = Mission.ADVANCE, way = WAY, size = 4, wait = 10, issued = 100 }
	for k, v in pairs(fields or {}) do spec[k] = v end
	return spec
end

T.test("the tuning is defined", function()
	T.defined(Mission.WAIT_MAX, "WAIT_MAX")
	T.defined(Mission.STUCK_TIME, "STUCK_TIME")
	T.defined(Mission.PROGRESS_STEP, "PROGRESS_STEP")
	T.eq(Mission.CASUALTY_SHARE, 0.5, "heavy casualties: half the squad (settled with the operator)")
end)

T.test("a mission holds its kind, way, size, wait and when it was issued", function()
	local m = Mission.New(Valid())
	T.eq(m.kind, Mission.ADVANCE)
	T.eq(m.way, WAY)
	T.eq(m.size, 4)
	T.eq(m.wait, 10)
	T.eq(m.issued, 100)
end)

T.test("a mission is refused an unknown kind, an empty way, a size under 1 or a negative wait", function()
	T.eq(pcall(Mission.New, Valid({ kind = "picnic" })), false, "kind")
	T.eq(pcall(Mission.New, Valid({ way = {} })), false, "way")
	T.eq(pcall(Mission.New, Valid({ size = 0 })), false, "size")
	T.eq(pcall(Mission.New, Valid({ wait = -1 })), false, "wait")
end)

T.test("a mission cannot be changed once made", function()
	local m = Mission.New(Valid())
	T.eq(pcall(function() m.size = 9 end), false)
end)

T.test("the leader waits until the wait is over", function()
	local m = Mission.New(Valid())
	T.eq(Mission.Waited(m, 109.9), false)
	T.eq(Mission.Waited(m, 110), true)
end)

T.test("no one missing: no wait", function()
	T.eq(Mission.Wait({ missing = 0, nextWave = 130, now = 100, travel = 8 }), 0)
end)

T.test("after spawning, it waits for the next wave and its walk from spawn", function()
	T.eq(Mission.Wait({ missing = 2, nextWave = 112, now = 100, travel = 8 }), 20)
end)

T.test("a wave already due counts as now", function()
	T.eq(Mission.Wait({ missing = 2, nextWave = 90, now = 100, travel = 8 }), 8)
end)

T.test("after a regroup, it waits only for the living to walk to it, never for a wave", function()
	T.eq(Mission.Wait({ missing = 2, now = 100, travel = 6 }), 6)
end)

T.test("the wait is held to WAIT_MAX", function()
	T.eq(Mission.Wait({ missing = 2, nextWave = 100 + Mission.WAIT_MAX, now = 100, travel = 30 }), Mission.WAIT_MAX)
end)

T.test("heavy casualties: down to CASUALTY_SHARE of the mission's size or fewer", function()
	local m = Mission.New(Valid({ size = 4 }))
	T.eq(Mission.Casualties(m, 3), false)
	T.eq(Mission.Casualties(m, 2), true, "half")
	local odd = Mission.New(Valid({ size = 3 }))
	T.eq(Mission.Casualties(odd, 2), false)
	T.eq(Mission.Casualties(odd, 1), true)
end)

T.test("a squad that keeps getting PROGRESS_STEP nearer is progressing", function()
	local track = Mission.Track(1000, 0)
	for i = 1, 10 do
		T.eq(track:Stuck(1000 - i * Mission.PROGRESS_STEP, i * (Mission.STUCK_TIME - 1)), false, "step " .. i)
	end
end)

T.test("a squad no PROGRESS_STEP nearer in STUCK_TIME is stuck", function()
	local track = Mission.Track(1000, 0)
	T.eq(track:Stuck(1000 - Mission.PROGRESS_STEP / 2, Mission.STUCK_TIME - 0.1), false, "not yet")
	T.eq(track:Stuck(1000 - Mission.PROGRESS_STEP / 2, Mission.STUCK_TIME), true, "inching is not progress")
end)

T.test("progress made resets the clock", function()
	local track = Mission.Track(1000, 0)
	T.eq(track:Stuck(1000 - Mission.PROGRESS_STEP, Mission.STUCK_TIME - 1), false)
	T.eq(track:Stuck(1000 - Mission.PROGRESS_STEP, 2 * Mission.STUCK_TIME - 2), false, "counted from the progress")
	T.eq(track:Stuck(1000 - Mission.PROGRESS_STEP, 2 * Mission.STUCK_TIME - 1), true)
end)

T.finish()
