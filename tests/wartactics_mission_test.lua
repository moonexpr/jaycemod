-- wartactics.mission: a squad's mission from the tactics engine (what kind,
-- the way it goes, how many it should be, how long its leader waits for
-- them), the wait from the spawn waves, and when the squad must regroup:
-- heavy casualties, or no progress along its way.
local T = dofile("tests/harness.lua")
local Mission = wartactics.mission

local WAY = { kind = "direct", points = { { x = 0, y = 0, z = 0 }, { x = 500, y = 0, z = 0 } } }

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
	T.eq(m.alpha, false, "no alpha unless made one")
	T.eq(Mission.New(Valid({ alpha = true })).alpha, true)
	T.eq(m.kind, Mission.ADVANCE)
	T.eq(m.way, WAY)
	T.eq(m.size, 4)
	T.eq(m.wait, 10)
	T.eq(m.issued, 100)
end)

T.test("a mission is refused an unknown kind, an empty way, a size under 1 or a negative wait", function()
	T.eq(pcall(Mission.New, Valid({ kind = "picnic" })), false, "kind")
	T.eq(pcall(Mission.New, Valid({ way = { kind = "direct", points = {} } })), false, "way")
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

T.test("heavy casualties: down to CASUALTY_SHARE of the squad that led out, or fewer", function()
	T.eq(Mission.Casualties(4, 3), false)
	T.eq(Mission.Casualties(4, 2), true, "half")
	T.eq(Mission.Casualties(3, 2), false)
	T.eq(Mission.Casualties(3, 1), true)
	T.eq(Mission.Casualties(2, 2), false, "a squad led out short is not a casualty of its own size")
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

-- Regrouping: whether a squad out on its mission must regroup.
T.test("the regroup tuning is defined", function()
	T.defined(Mission.ARRIVED, "ARRIVED")
end)

local function Judge(t)
	return Mission.Regroup(t.track or Mission.Track(t.remaining or 1000, 0), 4, t.alive or 4, t.remaining or 1000,
		t.now or 0, t.fighting or false)
end

T.test("heavy casualties call a regroup, even in a fight", function()
	T.eq(Judge({ alive = 2, fighting = true }), Mission.CASUALTIES)
	T.eq(Judge({ alive = 3 }), nil)
end)

T.test("no progress along the way calls a regroup", function()
	local track = Mission.Track(1000, 0)
	T.eq(Judge({ track = track, remaining = 1000, now = Mission.STUCK_TIME }), Mission.STUCK)
end)

T.test("a fight is no lack of progress: the clock starts again after it", function()
	local track = Mission.Track(1000, 0)
	T.eq(Judge({ track = track, remaining = 1000, now = Mission.STUCK_TIME, fighting = true }), nil, "fighting")
	T.eq(Judge({ track = track, remaining = 1000, now = 2 * Mission.STUCK_TIME - 1 }), nil, "counted from the fight")
	T.eq(Judge({ track = track, remaining = 1000, now = 2 * Mission.STUCK_TIME }), Mission.STUCK)
end)

T.test("a squad within ARRIVED of its way's end has no progress to make", function()
	local track = Mission.Track(Mission.ARRIVED, 0)
	T.eq(Judge({ track = track, remaining = Mission.ARRIVED, now = 10 * Mission.STUCK_TIME }), nil)
end)

T.test("a squad recalled to regroup leads no more and musters afresh, keeping its mission until a new one", function()
	local m = Mission.New(Valid())
	local squad = { mission = m, missionLed = true, musterAt = { x = 1, y = 2, z = 3 }, musterArrived = 5, missionTrack = {} }
	Mission.Recall(squad, Mission.STUCK)
	T.eq(squad.regrouping, Mission.STUCK, "why")
	T.eq(squad.missionLed, nil)
	T.eq(squad.musterAt, nil, "a hiding spot to find")
	T.eq(squad.musterArrived, nil)
	T.eq(squad.missionTrack, nil)
	T.eq(squad.mission, m, "kept meanwhile")
end)

-- Issuing: the tactics engine's answer to a squad leader's request.
local Lanes = wartactics.lanes
local Transaction = transaction

local function Lane(kind, x) return { kind = kind, points = { { x = 0, y = 0, z = 0 }, { x = x, y = 0, z = 0 } } } end

local function TeamLanes()
	return { key = "plan1", Lane(Lanes.DIRECT, 100), Lane(Lanes.FLANK, 200), Lane(Lanes.FLANK, 300), Lane(Lanes.TOUR, 400) }
end

local function Ask(fireTeam, fireTeams, lanes, extra)
	local spec = { fireTeam = fireTeam, fireTeams = fireTeams, lanes = lanes, now = 100, nextWave = 110, travel = 5,
		missing = 1, size = 4 }
	for k, v in pairs(extra or {}) do spec[k] = v end
	return Mission.Issue(spec)
end

T.test("with no lanes yet the request is declined, NO_LANES", function()
	local squad = { team = 2, role = "escort" }
	local ok, err = pcall(Ask, squad, { squad }, { key = "none" })
	T.eq(ok, false)
	T.eq(Transaction.IsRefusal(err, { [Mission.NO_LANES] = true }), true)
end)

T.test("the first squad of a team to ask is its alpha, on the direct lane", function()
	local lanes = TeamLanes()
	local squad = { team = 2, role = "escort" }
	local m = Ask(squad, { squad }, lanes)
	T.eq(m.alpha, true)
	T.eq(m.way, lanes[1])
	T.eq(m.kind, Mission.ADVANCE)
	T.eq(m.size, 4)
	T.eq(m.wait, 15, "the wave in 10 s and a 5 s walk")
	T.eq(m.issued, 100)
end)

T.test("while the alpha is out, another squad is no alpha and takes another lane of its job", function()
	local lanes = TeamLanes()
	local alpha = { team = 2, role = "escort" }
	alpha.mission = Ask(alpha, { alpha }, lanes)
	local second = { team = 2, role = "escort" }
	local m = Ask(second, { alpha, second }, lanes)
	T.eq(m.alpha, false)
	T.eq(m.way, lanes[2], "the first flank: the direct lane is taken")
	local raider = { team = 2, role = "raid" }
	T.eq(Ask(raider, { alpha, second, raider }, lanes).way, lanes[4], "a raider tours")
end)

T.test("the enemy's alpha is not this team's", function()
	local lanes = TeamLanes()
	local theirs = { team = 3, role = "escort" }
	theirs.mission = Ask(theirs, { theirs }, lanes)
	local ours = { team = 2, role = "escort" }
	T.eq(Ask(ours, { theirs, ours }, lanes).alpha, true)
end)

T.test("an alpha that regroups, or is gone, leaves the alpha to the next squad to ask", function()
	local lanes = TeamLanes()
	local alpha = { team = 2, role = "escort" }
	alpha.mission = Ask(alpha, { alpha }, lanes)
	alpha.regrouping = true
	local next = { team = 2, role = "escort" }
	T.eq(Ask(next, { alpha, next }, lanes).alpha, true, "regrouping")
	T.eq(Ask(next, { next }, lanes).alpha, true, "gone")
end)

T.test("a squad asking again, still the alpha, stays the alpha", function()
	local lanes = TeamLanes()
	local alpha = { team = 2, role = "escort" }
	alpha.mission = Ask(alpha, { alpha }, lanes)
	T.eq(Ask(alpha, { alpha }, lanes).alpha, true)
end)

T.test("an alpha with no direct lane planned takes the first lane", function()
	local lanes = { key = "p", Lane(Lanes.FLANK, 200), Lane(Lanes.FLANK, 300) }
	local squad = { team = 2, role = "escort" }
	T.eq(Ask(squad, { squad }, lanes).way, lanes[1])
end)

T.test("after a regroup it waits only for the living to walk to it", function()
	local lanes = TeamLanes()
	local squad = { team = 2, role = "escort" }
	T.eq(Ask(squad, { squad }, lanes, { regrouped = true, travel = 6 }).wait, 6)
end)

T.test("raiders are never the alpha: they tour, even with no alpha out", function()
	local lanes = TeamLanes()
	local raider = { team = 2, role = "raid" }
	local m = Ask(raider, { raider }, lanes)
	T.eq(m.alpha, false)
	T.eq(m.way, lanes[4])
end)

-- Promoting: a team with no alpha out takes one of its squads out on
-- another mission off it, to be its alpha.
local function Out(team, role, alpha)
	local squad = { team = team, role = role, missionLed = true }
	squad.mission = Mission.New(Valid({ alpha = alpha }))
	return squad
end

T.test("a team with no alpha out promotes a squad out on another mission whose job comes at the objective", function()
	local raider, escort = Out(2, "raid", false), Out(2, "escort", false)
	T.eq(Mission.Promote({ raider, escort }, 2), escort)
end)

T.test("no promotion while the alpha is out, nor of raiders, nor of squads not out, nor across teams", function()
	local alpha, other = Out(2, "escort", true), Out(2, "escort", false)
	T.eq(Mission.Promote({ alpha, other }, 2), nil, "the alpha is out")
	T.eq(Mission.Promote({ Out(2, "raid", false) }, 2), nil, "raiders")
	local waiting = Out(2, "escort", false)
	waiting.missionLed = nil
	T.eq(Mission.Promote({ waiting }, 2), nil, "not out yet: it asks for itself")
	T.eq(Mission.Promote({ Out(3, "escort", false) }, 2), nil, "the other team's")
	local regrouping = Out(2, "escort", false)
	regrouping.regrouping = Mission.STUCK
	T.eq(Mission.Promote({ regrouping }, 2), nil, "regrouping")
end)

T.test("an alpha regrouping is not out: another squad is promoted", function()
	local alpha, other = Out(2, "escort", true), Out(2, "escort", false)
	alpha.regrouping = Mission.CASUALTIES
	T.eq(Mission.Promote({ alpha, other }, 2), other)
end)

T.test("a squad of a job that takes no lanes asking is our bug", function()
	local squad = { team = 2, role = "guard" }
	T.eq(pcall(Ask, squad, { squad }, TeamLanes()), false)
end)

T.finish()
