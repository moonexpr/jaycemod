-- foundation.npc.probe: a path follower stripped of the war (ns_lanes_probe's
-- probes): it walks a list of points in order, and where it stalls it says
-- so, after the soldier's own remedies, then goes on to the next point.
local T = dofile("tests/harness.lua")
local Probe = T.require("foundation.npc.probe")

local function P(x, y, z) return { x = x, y = y, z = z or 0 } end

local POINTS = { P(100, 0), P(200, 0), P(300, 0) }

-- A probe stepped from pos at now; returns the command.
local function Step(probe, pos, now) return probe:Step(pos, now) end

T.test("a probe walks its points in order and is done past the last", function()
	local probe = Probe.New(POINTS, 0)
	local command = Step(probe, P(0, 0), 0)
	T.eq(command.kind, Probe.MOVE, "moves")
	T.eq(command.to, POINTS[1], "to the first point")
	command = Step(probe, P(100 - Probe.ARRIVE + 1, 0), 1)
	T.eq(command.to, POINTS[2], "arrived: on to the next")
	Step(probe, P(200, 0), 2)
	command = Step(probe, P(300, 0), 3)
	T.eq(command.kind, Probe.DONE, "done")
	T.eq(probe:Reached(), 3, "every point reached")
	T.eq(#probe:Findings(), 0, "nothing found")
end)

T.test("a point is reached only within ARRIVE across the ground and HEIGHT", function()
	local probe = Probe.New({ P(100, 0, 200) }, 0)
	local command = Step(probe, P(100, 0, 0), 0)
	T.eq(command.kind, Probe.MOVE, "under it is not at it")
	command = Step(probe, P(100, 0, 200 - Probe.HEIGHT), 1)
	T.eq(command.kind, Probe.DONE, "within HEIGHT of it")
end)

T.test("stalled, it plans its path afresh, then hops, then records the point and goes on", function()
	local probe = Probe.New(POINTS, 0)
	local at = P(50, 10)
	Step(probe, at, 0)
	local t = Probe.STUCK_TIME + 0.1
	local command = Step(probe, at, t)
	T.eq(command.kind, Probe.REPATH, "a fresh path first")
	t = t + Probe.STUCK_TIME + 0.1
	command = Step(probe, at, t)
	T.eq(command.kind, Probe.HOP, "then a hop")
	T.eq(command.to, POINTS[1], "toward the point")
	t = t + Probe.STUCK_TIME + 0.1
	command = Step(probe, at, t)
	T.eq(command.kind, Probe.MOVE, "then on")
	T.eq(command.to, POINTS[2], "to the next point")
	local findings = probe:Findings()
	T.eq(#findings, 3, "each remedy and the failure found")
	T.eq(findings[1].kind, Probe.REPATH, "the fresh path")
	T.eq(findings[2].kind, Probe.HOP, "the hop")
	T.eq(findings[3].kind, Probe.STUCK, "then stuck")
	T.eq(findings[3].index, 1, "at the first point")
	T.eq(findings[3].at, at, "where it stood")
	T.eq(probe:Reached(), 0, "not reached")
end)

T.test("moving on resets the stall, and a remedy that worked leaves only itself found", function()
	local probe = Probe.New(POINTS, 0)
	Step(probe, P(0, 0), 0)
	local command = Step(probe, P(0, 0), Probe.STUCK_TIME + 0.1)
	T.eq(command.kind, Probe.REPATH, "a fresh path")
	command = Step(probe, P(Probe.PROGRESS + 1, 0), Probe.STUCK_TIME + 1)
	T.eq(command.kind, Probe.MOVE, "going again")
	command = Step(probe, P(Probe.PROGRESS + 1, 0), 2 * Probe.STUCK_TIME + 1.2)
	T.eq(command.kind, Probe.REPATH, "a new stall starts from the first remedy")
	T.eq(#probe:Findings(), 2, "two fresh paths, no failure")
end)

T.test("a leg that moves but never arrives within LEG_TIME is recorded slow, and skipped", function()
	local probe = Probe.New(POINTS, 0)
	local t, x = 0, 0
	local command
	while t <= Probe.LEG_TIME do
		x = x == 0 and Probe.PROGRESS + 1 or 0 -- pacing back and forth, never there
		command = Step(probe, P(x, 50), t)
		t = t + 1
	end
	T.eq(command.to, POINTS[2], "on to the next point")
	local findings = probe:Findings()
	T.eq(findings[#findings].kind, Probe.SLOW, "recorded slow")
	T.eq(findings[#findings].index, 1, "at the first point")
end)

T.test("off the mesh for OFF_MESH_TIME, it is put back where it last stood on it, and that is found", function()
	local probe = Probe.New(POINTS, 0)
	Step(probe, P(10, 0), 0)
	probe:Step(P(20, 0), 1, true)
	local command = probe:Step(P(40, 0), 2, false)
	T.eq(command.kind, Probe.MOVE, "not yet")
	command = probe:Step(P(41, 0), 2 + Probe.OFF_MESH_TIME, false)
	T.eq(command.kind, Probe.RECOVER, "put back")
	T.eq(command.to.x, 20, "where it last stood on the mesh")
	local findings = probe:Findings()
	T.eq(findings[#findings].kind, Probe.OFFMESH, "found")
	T.eq(findings[#findings].at.x, 41, "where it was")
	command = probe:Step(P(20, 0), 3 + Probe.OFF_MESH_TIME, true)
	T.eq(command.kind, Probe.MOVE, "and on")
end)

T.test("the tuning is defined", function()
	T.defined(Probe.ARRIVE, "ARRIVE")
	T.defined(Probe.HEIGHT, "HEIGHT")
	T.defined(Probe.PROGRESS, "PROGRESS")
	T.defined(Probe.STUCK_TIME, "STUCK_TIME")
	T.defined(Probe.LEG_TIME, "LEG_TIME")
	T.defined(Probe.OFF_MESH_TIME, "OFF_MESH_TIME")
end)

T.finish()
