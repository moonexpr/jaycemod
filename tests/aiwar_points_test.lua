-- foundation.aiwar.scenario.control_points: the war over control points,
-- symmetric and attack/defend: each team's objectives read from the capture
-- HUD's points (TF2's CollectCapturePoints and CollectDefendPoints), its
-- stance from them, and the point doctrine's jobs; then whole battles of
-- tests/fake_soldier.lua soldiers (tests/fake_points.lua).
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local FP = dofile("tests/fake_points.lua")
local N = T.require("foundation.npc")
local Debug = T.require("foundation.npc.debug")
local AiWar = T.require("foundation.aiwar")
local Orders = T.require("foundation.aiwar.orders")
local Tactics = T.require("foundation.wartactics")
local Geometry = T.require("foundation.math.geometry")
local Lanes = T.require("foundation.aiwar.lanes")
local Scenario = T.require("foundation.aiwar.scenario")
local CP = T.require("foundation.aiwar.scenario.control_points")
local Teams = T.require("foundation.teams")

local RED, BLUE = Teams.RED, Teams.BLUE
local P = FS.Point

local function Near(p, q, what)
	T.eq(FS.Distance(p, q) < 1e-6, true, string.format("%s: (%g, %g) vs (%g, %g)", what, p.x, p.y, q.x, q.y))
end

-- The ranks of a list of points, "0,2".
local function Ranks(points)
	local ranks = {}
	for i, point in ipairs(points) do ranks[i] = point.rank end
	return table.concat(ranks, ",")
end

local function RankOf(point) return point and point.rank end

-- A field of these points, briefed at now by a new scenario (or the one given).
local function Brief(t, now, scenario)
	local field = FP.Field(t)
	field.now = now or 0 -- as the controller's field carries it
	scenario = scenario or CP.Scenario:New()
	scenario:Brief(field, field.now)
	return field, scenario
end

-- Roles of a stance, "capture:40 assault:30".
local function Shares(stance)
	local shares = {}
	for i, share in ipairs(stance) do shares[i] = share.role .. ":" .. share.weight end
	return table.concat(shares, " ")
end

T.test("the control point variant is the rounds mode's", function()
	T.eq(Scenario.For("control_points"), CP.Scenario, "chosen by the mode's NAME")
	T.eq(CP.Scenario.NAME, CP.MODE, "named for it")
	T.eq(CP.Scenario.GUARDS_ALL_ROUND, false, "guards keep to their side of the point")
end)

-- B1: objectives ------------------------------------------------------------------

T.test("attack and defend reproduce CollectCapturePoints and CollectDefendPoints", function()
	local field = Brief({ points = {
		FP.Point({ rank = 0, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true } }),
		FP.Point({ rank = 1, at = P(0, 0), mayCapture = { [RED] = true, [BLUE] = true } }),
		FP.Point({ rank = 2, at = P(1000, 0), owner = BLUE }),
		FP.Point({ rank = 3, at = P(500, 500), mayCapture = { [RED] = true }, inRound = false }),
		FP.Point({ rank = 4, at = P(500, -500), mayCapture = { [RED] = true }, hidden = true }),
		FP.Point({ rank = 5, at = P(600, 0), mayCapture = { [RED] = true }, radius = false }),
		FP.Point({ rank = 6, at = P(-500, 500), owner = RED, mayCapture = { [BLUE] = true }, inRound = false }),
	} })
	local red, blue = field.objectives[RED], field.objectives[BLUE]
	T.eq(Ranks(red.attack), "1", "RED attacks what it may capture, in round, zoned and shown")
	T.eq(Ranks(red.defend), "0", "RED defends its own the enemy may capture")
	T.eq(Ranks(blue.attack), "0,1", "BLU attacks RED's point and the neutral one")
	T.eq(Ranks(blue.defend), "", "BLU's point RED may not capture is not defended")
end)

-- B2: target and staging --------------------------------------------------------

T.test("the target is the point we are capping, else the nearest to our base", function()
	local near = FP.Point({ rank = 0, at = P(-1000, 0), mayCapture = { [RED] = true } })
	local far = FP.Point({ rank = 1, at = P(1000, 0), mayCapture = { [RED] = true } })
	T.eq(RankOf(Brief({ points = { far, near } }).objectives[RED].target), 0, "nearest RED's base")
	T.eq(RankOf(Brief({ points = { far, near } }).objectives[BLUE].target), nil, "BLU may capture neither")
	far.capping = RED
	local o = Brief({ points = { near, far } }).objectives[RED]
	T.eq(RankOf(o.target), 1, "the one we cap")
	T.eq(o.capping, true, "capping")
	T.eq(RankOf(o.focus), 1, "the focus is the target")
end)

T.test("staging is the locked point not ours nearest our base, only with nothing to attack", function()
	local points = {
		FP.Point({ rank = 0, at = P(-2000, 0), owner = RED, locked = true }),
		FP.Point({ rank = 1, at = P(1500, 0), owner = BLUE, locked = true }),
		FP.Point({ rank = 2, at = P(500, 0), locked = true }),
	}
	local o = Brief({ points = points }).objectives[RED]
	T.eq(RankOf(o.staging), 2, "the nearest locked point not ours")
	T.eq(o.target, nil, "no target")
	T.eq(RankOf(o.focus), 2, "the focus is where it stages")
	points[1].mayCapture[BLUE] = true
	points[3].locked, points[3].mayCapture[RED] = false, true
	o = Brief({ points = points }).objectives[RED]
	T.eq(o.staging, nil, "a point to attack: no staging")
	T.eq(RankOf(o.target), 2, "the target")
	T.eq(RankOf(o.guard), 0, "and a guard")
	T.eq(RankOf(o.focus), 2, "offense is the focus")
end)

T.test("the guard is a threatened point first, else the one nearest the enemy's base", function()
	local points = {
		FP.Point({ rank = 0, at = P(-2000, 0), owner = RED, mayCapture = { [BLUE] = true } }),
		FP.Point({ rank = 1, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true } }),
	}
	T.eq(RankOf(Brief({ points = points }).objectives[RED].guard), 1, "the forward one")
	points[1].capping = BLUE
	local o = Brief({ points = points }).objectives[RED]
	T.eq(RankOf(o.guard), 0, "the one being capped")
	T.eq(o.threatened, true, "threatened")
	T.eq(RankOf(o.focus), 0, "defense is the focus without offense")
end)

-- B3: threat memory -------------------------------------------------------------

T.test("a point contested at t stays threatened until t + CONTESTED_MEMORY", function()
	local point = FP.Point({ rank = 0, at = P(0, 0), owner = RED, mayCapture = { [BLUE] = true }, capping = BLUE })
	local field, scenario = Brief({ points = { point } }, 10)
	T.eq(field.objectives[RED].threatened, true, "being capped")
	point.capping = Teams.UNASSIGNED
	T.eq(Brief({ points = { point } }, 10 + CP.CONTESTED_MEMORY - 0.1, scenario).objectives[RED].threatened, true, "just after")
	T.eq(Brief({ points = { point } }, 10 + CP.CONTESTED_MEMORY, scenario).objectives[RED].threatened, false, "forgotten")
	point.blocked = true
	T.eq(Brief({ points = { point } }, 20, scenario).objectives[RED].threatened, true, "a blocked capture is a contest")
end)

T.test("a point we owned turning enemy is justLost for JUST_LOST_TIME; a reset is no loss", function()
	local a = FP.Point({ rank = 0, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true } })
	local b = FP.Point({ rank = 1, at = P(-2000, 0), owner = RED })
	local _, scenario = Brief({ points = { a, b } }, 0)
	a.owner, a.mayCapture[BLUE], b.mayCapture[BLUE] = BLUE, false, true
	local o = Brief({ points = { a, b } }, 5, scenario).objectives[RED]
	T.eq(o.justLost, true, "just lost")
	T.eq(RankOf(o.guard), 1, "falls back to the next")
	T.eq(o.threatened, true, "which is threatened")
	T.eq(Brief({ points = { a, b } }, 5 + CP.JUST_LOST_TIME - 0.1, scenario).objectives[RED].justLost, true, "a while")
	T.eq(Brief({ points = { a, b } }, 5 + CP.JUST_LOST_TIME, scenario).objectives[RED].justLost, false, "then over")
	T.eq(Brief({ points = { a, b } }, 30, scenario).objectives[BLUE].justLost, false, "the winner lost nothing")
	a.owner = RED
	Brief({ points = { a, b } }, 40, scenario)
	scenario:Reset()
	a.owner = BLUE
	T.eq(Brief({ points = { a, b } }, 41, scenario).objectives[RED].justLost, false, "a new round's owners are no loss")
end)

T.test("a neutral point taken is no loss to anyone", function()
	local mid = FP.Point({ rank = 0, at = P(0, 0), mayCapture = { [RED] = true, [BLUE] = true } })
	local _, scenario = Brief({ points = { mid } }, 0)
	mid.owner = BLUE
	local field = Brief({ points = { mid } }, 1, scenario)
	T.eq(field.objectives[RED].justLost, false, "RED never had it")
end)

T.test("urgency: overtime, the round's clock under MUST_PUSH_TIME, or capping", function()
	local point = FP.Point({ rank = 0, at = P(0, 0), mayCapture = { [RED] = true } })
	T.eq(Brief({ points = { point }, timeLeft = CP.MUST_PUSH_TIME + 1 }).objectives[RED].urgent, false, "time enough")
	T.eq(Brief({ points = { point }, timeLeft = CP.MUST_PUSH_TIME + 1 }).objectives[RED].timeLeft, CP.MUST_PUSH_TIME + 1, "the round's clock")
	T.eq(Brief({ points = { point }, timeLeft = CP.MUST_PUSH_TIME - 1 }).objectives[RED].urgent, true, "short of time")
	T.eq(Brief({ points = { point }, overtime = true }).objectives[RED].urgent, true, "overtime")
	point.capping = RED
	T.eq(Brief({ points = { point } }).objectives[RED].urgent, true, "capping")
end)

-- B4: stances --------------------------------------------------------------------

local function Stances(t, now, scenario)
	local field
	field, scenario = Brief(t, now, scenario)
	local entries, defense = scenario:Stances(field, now or 0)
	return entries, defense, field
end

-- A/D: BLU attacks A and B, RED defends them.
local function AttackDefend()
	return {
		FP.Point({ rank = 0, at = P(-500, 0), owner = RED, mayCapture = { [BLUE] = true } }),
		FP.Point({ rank = 1, at = P(-500, 1000), owner = RED, mayCapture = { [BLUE] = true } }),
		FP.Point({ rank = 2, at = P(-2000, 0), owner = RED, locked = true }),
	}
end

T.test("TDBN names a control point defender's job, its side by short name, and its squad role, and no monitor", function()
	local battle = FP.Battle(CP.Scenario)
	battle:Enlist(RED, 1)
	battle:Start(FP.Field({ points = AttackDefend() }))
	local s = battle.soldiers[1]
	local _, frames = s.npc:Stack()
	local job, role = Orders.JobOf(s.npc:Describe())
	T.eq(Debug.Tdbn(frames), job .. " ( CPDefender ( NextSoldier::" .. role .. " ) )", s.npc:Describe())
end)

T.test("A/D: attackers take only offense roles, defenders only defense roles", function()
	local entries, defense = Stances({ points = AttackDefend() })
	T.eq(Shares(entries[BLUE].stance), "capture:40 assault:30 raid:20 support:10", "BLU attacks")
	T.eq(entries[BLUE].key, "0", "key")
	T.eq(defense[BLUE], 0, "no defense")
	T.eq(Shares(entries[RED].stance), "defend:50 hold:20 raid:20 support:10", "RED defends")
	T.eq(entries[RED].key, "10", "key")
	T.eq(defense[RED], 1, "all defense")
	T.eq(entries[RED].critical, false, "nothing critical")
end)

T.test("only a staging point: the attack-only stance; nothing at all: no stance", function()
	local entries = Stances({ points = { FP.Point({ rank = 0, at = P(0, 0), locked = true }) } })
	T.eq(entries[RED].key, "0", "RED stages")
	T.eq(entries[BLUE].key, "0", "and BLU")
	entries = Stances({ points = { FP.Point({ rank = 0, at = P(0, 0), owner = RED }) } })
	T.eq(entries[RED], nil, "RED: nothing to take or hold")
	T.eq(entries[BLUE], nil, "BLU: nothing it may capture")
end)

-- 5CP: RED owns 0 and 1, BLU 2 to 4; RED may take 2 back, BLU may take 1.
local function FiveCP()
	return {
		FP.Point({ rank = 0, at = P(-2000, 0), owner = RED }),
		FP.Point({ rank = 1, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true } }),
		FP.Point({ rank = 2, at = P(0, 0), owner = BLUE, mayCapture = { [RED] = true } }),
		FP.Point({ rank = 3, at = P(1000, 0), owner = BLUE }),
		FP.Point({ rank = 4, at = P(2000, 0), owner = BLUE }),
	}
end

T.test("5CP with both: the share follows the points held, the threat, and our capping", function()
	local entries, defense = Stances({ points = FiveCP() })
	T.eq(entries[RED].key, "6", "a point behind: 0.5 + 0.1")
	T.eq(defense[RED], 0.6, "the share")
	T.eq(Shares(entries[RED].stance), "defend:30 hold:12 capture:16 assault:12 raid:20 support:10", "defense first from half")
	local points = FiveCP()
	points[3].capping = RED
	entries = Stances({ points = points })
	T.eq(entries[RED].key, "4", "capping: less defense")
	T.eq(Shares(entries[RED].stance), "capture:24 assault:18 defend:20 hold:8 raid:20 support:10", "offense first under half")
end)

T.test("threatened, hold and defend swap; critical once the enemy's progress reaches CRITICAL_PROGRESS", function()
	local points = FiveCP()
	points[2].capping, points[2].progress = BLUE, CP.CRITICAL_PROGRESS - 0.1
	local entries = Stances({ points = points })
	T.eq(entries[RED].key, "8t", "threatened: more defense, hot")
	T.eq(Shares(entries[RED].stance), "hold:40 defend:16 capture:8 assault:6 raid:20 support:10", "holders first")
	T.eq(entries[RED].critical, false, "not yet critical")
	points[2].progress = CP.CRITICAL_PROGRESS
	T.eq(Stances({ points = points })[RED].critical, true, "critical")
end)

T.test("the share keeps within the war's DEFENSE_MIN and DEFENSE_MAX", function()
	-- RED down to one point with the enemy on it: 0.5 + 0.1 * 3 + 0.2 clamps
	local four = {
		FP.Point({ rank = 0, at = P(-2000, 0), owner = RED, mayCapture = { [BLUE] = true }, capping = BLUE }),
		FP.Point({ rank = 1, at = P(-1000, 0), owner = BLUE, mayCapture = { [RED] = true } }),
		FP.Point({ rank = 2, at = P(0, 0), owner = BLUE }),
		FP.Point({ rank = 3, at = P(1000, 0), owner = BLUE }),
		FP.Point({ rank = 4, at = P(2000, 0), owner = BLUE }),
	}
	T.eq(Stances({ points = four })[RED].key, tostring(AiWar.DEFENSE_MAX * 10) .. "t", "clamped to the most")
end)

T.test("the same situation is the same stance table", function()
	local a = Stances({ points = FiveCP() })
	local b = Stances({ points = FiveCP() })
	T.eq(a[RED].stance, b[RED].stance, "memoised")
end)

-- B5: the point doctrine's goals -------------------------------------------------

local function Member(team, job, slot, pos)
	return {
		handle = "member", -- as every war member has
		team = team,
		role = job,
		slot = slot or 1,
		pos = pos,
	}
end

-- RED targets mid (0, 0) and guards point 1 (-1000, 0).
local function Goals(t)
	t.points = t.points or {
		FP.Point({ rank = 1, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true } }),
		FP.Point({ rank = 2, at = P(0, 0), mayCapture = { [RED] = true, [BLUE] = true } }),
	}
	-- the nav mesh's, for explorers
	t.waypoints = t.waypoints or { P(1500, 1500) }
	return Brief(t)
end

local BASE_R, BASE_B = FP.BASES[RED], FP.BASES[BLUE]
local R = FP.RADIUS

T.test("the point doctrine is named, and has every job with its describe name", function()
	T.eq(CP.DOCTRINE.NAME, "points", "named")
	local names = {
		[AiWar.CAPTURE] = "CapturePoint",
		[AiWar.ASSAULT] = "Assault",
		[AiWar.HOLD] = "HoldPoint",
		[AiWar.DEFEND] = "DefendPoint",
		[AiWar.RAID] = "Raid",
		[AiWar.SUPPORT] = "Support",
		[AiWar.MEDIC] = "Medic",
	}
	for job, name in pairs(names) do T.eq(CP.DOCTRINE.ROLES[job].name, name, job) end
	T.eq(Goals({}).doctrine, CP.DOCTRINE, "briefed")
end)

T.test("capture: a ring on the unlocked target's zone, which it occupies", function()
	local field = Goals({})
	local member = Member(RED, AiWar.CAPTURE)
	Near(Orders.Goal(field, member), Orders.Ring(P(0, 0), 1, R * CP.CAPTURE_SPREAD), "in the zone")
	local center, radius = CP.DOCTRINE.ROLES[AiWar.CAPTURE].Zone(field, member)
	Near(center, P(0, 0), "the zone's center")
	T.eq(radius, R, "and radius")
end)

T.test("capture: a locked target or a staging point is waited for outside, on our side", function()
	local stage = Orders.Ring(Geometry.Toward(P(0, 0), BASE_R, R + CP.STAGE_DISTANCE), 1, CP.STAGE_SPREAD)
	local staging = Goals({ points = { FP.Point({ rank = 2, at = P(0, 0), locked = true }) } })
	local member = Member(RED, AiWar.CAPTURE)
	Near(Orders.Goal(staging, member), stage, "staging")
	T.eq(CP.DOCTRINE.ROLES[AiWar.CAPTURE].Zone(staging, member), nil, "no zone to occupy")
	-- a map without caplinear lets a locked point be captured: a locked target
	local locked = Goals({ points = { FP.Point({ rank = 2, at = P(0, 0), locked = true, mayCapture = { [RED] = true } }) } })
	T.eq(RankOf(locked.objectives[RED].target), 2, "a locked target")
	Near(Orders.Goal(locked, member), stage, "waited for the same way")
end)

T.test("capture is urgent when the objectives are, or within NEAR_POINT of the target", function()
	local capture = CP.DOCTRINE.ROLES[AiWar.CAPTURE]
	local field = Goals({})
	T.eq(capture.Urgent(field, Member(RED, AiWar.CAPTURE, 1, P(-CP.NEAR_POINT - 1, 0))), false, "far and in time")
	T.eq(capture.Urgent(field, Member(RED, AiWar.CAPTURE, 1, P(-CP.NEAR_POINT, 0))), true, "near")
	T.eq(capture.Urgent(field, Member(RED, AiWar.CAPTURE, 1, nil)), false, "nowhere yet")
	T.eq(capture.Urgent(Goals({ overtime = true }), Member(RED, AiWar.CAPTURE, 1, P(-2500, 0))), true, "overtime")
end)

T.test("hold: a ring round the guard's zone, onto it while threatened or in setup", function()
	local hold = CP.DOCTRINE.ROLES[AiWar.HOLD]
	local member = Member(RED, AiWar.HOLD)
	local field = Goals({})
	Near(Orders.Goal(field, member), Orders.Ring(P(-1000, 0), 1, R + CP.HOLD_RING), "round it")
	T.eq(hold.Zone(field, member), nil, "no zone")
	T.eq(hold.Urgent(field, member), false, "not urgent")
	local threatened = Goals({ points = {
		FP.Point({ rank = 1, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true }, capping = BLUE }),
	} })
	Near(Orders.Goal(threatened, member), Orders.Ring(P(-1000, 0), 1, R * CP.CAPTURE_SPREAD), "on it")
	Near(hold.Zone(threatened, member), P(-1000, 0), "occupying it")
	T.eq(hold.Urgent(threatened, member), true, "urgent")
	local setup = Goals({ setup = true })
	Near(Orders.Goal(setup, member), Orders.Ring(P(-1000, 0), 1, R * CP.CAPTURE_SPREAD), "on it in setup")
	Near(hold.Zone(setup, member), P(-1000, 0), "occupying it in setup")
end)

T.test("assault: the way into a sphere short of the target, on our side", function()
	local field = Goals({})
	local center = Geometry.Toward(P(0, 0), BASE_R, CP.ASSAULT_STANDOFF)
	local from = P(-2500, 0)
	Near(Orders.Goal(field, Member(RED, AiWar.ASSAULT, 1, from)), Orders.EntryPoint(center, CP.ASSAULT_SPHERE, from), "the entry")
	local sphere, radius = CP.DOCTRINE.ROLES[AiWar.ASSAULT].Sphere(field, Member(RED, AiWar.ASSAULT))
	Near(sphere, center, "the sphere")
	T.eq(radius, CP.ASSAULT_SPHERE, "its radius")
	T.eq(Lanes.JOBS[AiWar.ASSAULT], true, "assault squads take lanes")
end)

T.test("defend: posts round the guard, else a ring toward the enemy's base; gate spots in setup", function()
	local member = Member(RED, AiWar.DEFEND)
	Near(Orders.Goal(Goals({}), member), Orders.Ring(Geometry.Toward(P(-1000, 0), BASE_B, CP.DEFEND_RING), 1, CP.DEFEND_SPREAD), "the ring")
	local posts = { [RED] = { P(-1100, 300), P(-1100, -300) } }
	Near(Orders.Goal(Goals({ posts = posts }), member), posts[RED][2], "its post by slot")
	local gates = { [BLUE] = { {
		pos = P(500, 0),
		dir = {
			x = -1,
			y = 0,
		},
	} } }
	local setup = Goals({ setup = true, gates = gates, posts = posts })
	Near(Orders.Goal(setup, member), Orders.GateSpot(setup, member, 0), "at the attackers' gate")
end)

T.test("raid: round the target's line from our base on offense, the guard's from theirs on defense", function()
	local raid = CP.DOCTRINE.ROLES[AiWar.RAID]
	local offense = Goals({ points = { FP.Point({ rank = 2, at = P(0, 0), mayCapture = { [RED] = true } }) } })
	local member = Member(RED, AiWar.RAID, 1)
	local line, from = raid.Line(offense, member)
	Near(line, P(0, 0), "the target")
	Near(from, BASE_R, "from our base")
	Near(Orders.Goal(offense, member), Tactics.FlankPoint(BASE_R, P(0, 0), -1), "round it, by slot parity")
	Near(Orders.Goal(offense, Member(RED, AiWar.RAID, 2)), Tactics.FlankPoint(BASE_R, P(0, 0), 1), "the other side")
	Near(raid.Cleared(offense, member), Orders.Ring(P(0, 0), 9, R * CP.CAPTURE_SPREAD), "then onto the point")
	local defense = Goals({ points = { FP.Point({ rank = 1, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true } }) } })
	line, from = raid.Line(defense, member)
	Near(line, P(-1000, 0), "the guard")
	Near(from, BASE_B, "from their base")
	Near(raid.Cleared(defense, member), Geometry.Toward(P(-1000, 0), BASE_B, CP.RAID_INTERCEPT), "then intercepts")
end)

T.test("raid and support split over the defense share by the golden ratio", function()
	local field = Goals({})
	local focus = {}
	for slot = 0, 9 do
		local line = CP.DOCTRINE.ROLES[AiWar.RAID].Line(field, Member(RED, AiWar.RAID, slot))
		focus[#focus + 1] = line.x == 0 and "o" or "d"
	end
	local defense = select(2, table.concat(focus):gsub("d", ""))
	T.eq(defense, field.defense[RED] * 10, "the share on defense: " .. table.concat(focus))
end)

T.test("support stands behind the focus on our side, spread sideways; a medic with it", function()
	local field = Goals({ points = { FP.Point({ rank = 2, at = P(0, 0), mayCapture = { [RED] = true } }) } })
	local spot = Geometry.Toward(P(0, 0), BASE_R, R + Orders.SUPPORT_BEHIND)
	Near(Orders.Goal(field, Member(RED, AiWar.SUPPORT, 0)), spot, "slot 0 on the line")
	Near(Orders.Goal(field, Member(RED, AiWar.SUPPORT, 1)), Orders.Across(BASE_R, spot, Orders.Lateral(1)), "slot 1 aside")
	Near(Orders.Goal(field, Member(RED, AiWar.MEDIC, 1)), Orders.Goal(field, Member(RED, AiWar.SUPPORT, 1)), "the medic")
	T.eq(CP.DOCTRINE.ROLES[AiWar.MEDIC].heals, true, "heals")
end)

T.test("in setup the defenders' raiders and support line up at the gates too", function()
	local gates = { [BLUE] = { {
		pos = P(500, 0),
		dir = {
			x = -1,
			y = 0,
		},
	} } }
	local field = Goals({ setup = true, gates = gates })
	Near(Orders.Goal(field, Member(RED, AiWar.RAID)), Orders.GateSpot(field, Member(RED, AiWar.RAID), 0), "raid")
	Near(Orders.Goal(field, Member(RED, AiWar.SUPPORT)), Orders.GateSpot(field, Member(RED, AiWar.SUPPORT), Orders.GATE_ROW * 2), "support")
end)

T.test("every job falls back: capture to hold, hold to capture, assault to defend, defend to assault", function()
	local defending = Goals({ points = { FP.Point({ rank = 1, at = P(-1000, 0), owner = RED, mayCapture = { [BLUE] = true } }) } })
	Near(Orders.Goal(defending, Member(RED, AiWar.CAPTURE)), Orders.Goal(defending, Member(RED, AiWar.HOLD)), "no target: hold's goal")
	Near(Orders.Goal(defending, Member(RED, AiWar.ASSAULT, 1, P(-2500, 0))), Orders.Goal(defending, Member(RED, AiWar.DEFEND)), "no target: defend's goal")
	local attacking = Goals({ points = { FP.Point({ rank = 2, at = P(0, 0), mayCapture = { [RED] = true } }) } })
	Near(Orders.Goal(attacking, Member(RED, AiWar.HOLD)), Orders.Goal(attacking, Member(RED, AiWar.CAPTURE)), "no guard: capture's goal")
	local from = P(-2500, 0)
	Near(Orders.Goal(attacking, Member(RED, AiWar.DEFEND, 1, from)), Orders.Goal(attacking, Member(RED, AiWar.ASSAULT, 1, from)), "no guard: assault's goal")
	local nothing = Goals({ points = { FP.Point({ rank = 0, at = P(0, 0), owner = BLUE }) } })
	for _, job in ipairs({ AiWar.CAPTURE, AiWar.ASSAULT, AiWar.HOLD, AiWar.DEFEND, AiWar.RAID, AiWar.SUPPORT, AiWar.MEDIC }) do
		T.eq(Orders.Goal(nothing, Member(RED, job, 1, from)), nil, job .. ": nothing at all, no goal")
	end
end)

T.test("no point job reads carts", function()
	local field = Goals({})
	T.eq(field.carts, nil, "a point field has none")
	for job in pairs(CP.DOCTRINE.ROLES) do
		T.eq(Orders.Goal(field, Member(RED, job, 1, P(-2500, 0))) ~= nil, true, job .. " has a goal")
	end
end)

T.test("the doctrine's setup wait, chase anchor and patrol mark", function()
	local doctrine = CP.DOCTRINE
	local setup = Goals({ setup = true, points = AttackDefend() })
	T.eq(doctrine.WaitsForSetup(setup, Member(BLUE, AiWar.CAPTURE)), true, "the attackers wait")
	T.eq(doctrine.WaitsForSetup(setup, Member(RED, AiWar.HOLD)), false, "the defenders do not")
	local field = Goals({ points = AttackDefend() })
	T.eq(doctrine.WaitsForSetup(field, Member(BLUE, AiWar.CAPTURE)), false, "not after setup")
	Near(doctrine.ChaseAnchor(field, Member(BLUE, AiWar.CAPTURE)), P(-500, 0), "BLU's focus: its target")
	Near(doctrine.ChaseAnchor(field, Member(RED, AiWar.DEFEND)), P(-500, 0), "RED's: its guard")
	Near(doctrine.Threat(field, Member(BLUE, AiWar.CAPTURE)), P(-500, 0), "BLU watches its target")
	Near(doctrine.Threat(field, Member(RED, AiWar.DEFEND)), P(-500, 0), "RED watches its guard")
	local mark = doctrine.PatrolMark(field, Member(RED, AiWar.DEFEND))
	T.eq(doctrine.PatrolHolds(mark, field, Member(RED, AiWar.DEFEND)), true, "the same guard, unthreatened")
	local points = AttackDefend()
	points[1].capping = BLUE
	local threatened = Goals({ points = points })
	T.eq(doctrine.PatrolHolds(mark, threatened, Member(RED, AiWar.DEFEND)), false, "threatened")
	points = AttackDefend()
	points[1].mayCapture[BLUE], points[2].mayCapture[BLUE] = false, false
	points[3].locked, points[3].mayCapture[BLUE] = false, true
	T.eq(doctrine.PatrolHolds(mark, Goals({ points = points }), Member(RED, AiWar.DEFEND)), false, "another guard")
end)

T.test("the doctrine's sides: capturers and assaulters attack, holders and defenders defend", function()
	local doctrine = CP.DOCTRINE
	local field = Goals({ points = AttackDefend() })
	T.eq(doctrine.SIDES.attack, "ControlPointAttacker")
	T.eq(doctrine.SIDES.defend, "ControlPointDefender")
	T.eq(doctrine.Side(field, Member(BLUE, AiWar.CAPTURE)), "attack", "capture")
	T.eq(doctrine.Side(field, Member(BLUE, AiWar.ASSAULT)), "attack", "assault")
	T.eq(doctrine.Side(field, Member(RED, AiWar.HOLD)), "defend", "hold")
	T.eq(doctrine.Side(field, Member(RED, AiWar.DEFEND)), "defend", "defend")
	T.eq(doctrine.Side(field, Member(BLUE, AiWar.RAID)), "attack", "BLU's raider attacks: it guards nothing")
	T.eq(doctrine.Side(field, Member(RED, AiWar.RAID)), "defend", "RED's raider defends: it attacks nothing")
end)

T.test("the front is the focus; setup attackers come out toward their target", function()
	local scenario = CP.Scenario:New()
	local field = FP.Field({ points = AttackDefend(), setup = true })
	scenario:Brief(field, 0)
	Near(scenario:Front(field, BLUE), P(-500, 0), "BLU's target")
	Near(scenario:Front(field, RED), P(-500, 0), "RED's guard")
	local attacks = scenario:SetupAttacks(field)
	Near(attacks[BLUE], P(-500, 0), "BLU attacks")
	T.eq(attacks[RED], nil, "RED defends")
	field = FP.Field({ points = { FP.Point({ rank = 0, at = P(0, 0), owner = BLUE }) } })
	scenario:Brief(field, 0)
	T.eq(scenario:Front(field, RED), nil, "nothing: no front")
end)

-- B9: mini-rounds ------------------------------------------------------------------

T.test("points out of the mini-round are never targeted or guarded", function()
	local field = Brief({ points = {
		FP.Point({ rank = 0, at = P(-500, 0), owner = RED, mayCapture = { [BLUE] = true }, inRound = false }),
		FP.Point({ rank = 1, at = P(0, 0), mayCapture = { [RED] = true, [BLUE] = true }, inRound = false }),
		FP.Point({ rank = 2, at = P(500, 0), owner = BLUE, mayCapture = { [RED] = true }, locked = true, inRound = false }),
		FP.Point({ rank = 3, at = P(2000, 0), owner = RED, mayCapture = { [BLUE] = true } }),
	} })
	local red, blue = field.objectives[RED], field.objectives[BLUE]
	T.eq(red.target, nil, "RED targets nothing out of round")
	T.eq(red.staging, nil, "nor stages there")
	T.eq(RankOf(red.guard), 3, "RED guards only the round's point")
	T.eq(RankOf(blue.target), 3, "BLU targets only it")
	T.eq(blue.guard, nil, "BLU guards nothing out of round")
end)

-- Full stack ------------------------------------------------------------------------

local SOLDIERS = 8

-- B6: 5CP.
T.test("5CP: both sides take mid and shuffle on it; once BLU has it, RED defends point 1 at its posts and holds it", function()
	local points = {
		FP.Point({ rank = 0, at = P(-2000, 0), owner = RED }),
		FP.Point({ rank = 1, at = P(-1000, 0), owner = RED }),
		FP.Point({ rank = 2, at = P(0, 0), mayCapture = { [RED] = true, [BLUE] = true } }),
		FP.Point({ rank = 3, at = P(1000, 0), owner = BLUE }),
		FP.Point({ rank = 4, at = P(2000, 0), owner = BLUE }),
	}
	local mid = points[3]
	local spots = { P(50, 50), P(-60, 20), P(30, -70), P(-40, -40), P(70, 0), P(0, 80) }
	local battle = FP.Battle(CP.Scenario)
	local function Soldier(i)
		return { patrolSpots = spots }
	end
	battle:Enlist(RED, SOLDIERS, Soldier)
	battle:Enlist(BLUE, SOLDIERS, Soldier)
	local field = FP.Field({ points = points })
	battle:Start(field)
	T.eq(battle.scenario.current[RED].key, "0", "RED attacks only")
	local capturers = battle:Of(RED, AiWar.CAPTURE)
	T.eq(#capturers > 0, true, "RED has capturers")
	battle:Tick(field, 40)
	for _, s in ipairs(capturers) do
		T.eq(FP.InZone(s.me.pos, mid), true, s.member.handle .. " inside mid")
		T.eq(s.npc:State().inZone, true, s.member.handle .. " knows it")
	end
	local s = capturers[1]
	local seen = {}
	for _, move in ipairs(s.me.moves) do
		if FP.InZone(move, mid) then seen[move.x .. "," .. move.y] = true end
	end
	local distinct = 0
	for _ in pairs(seen) do distinct = distinct + 1 end
	T.eq(distinct >= 3, true, "shuffling from spot to spot on it: " .. distinct)
	for _, b in ipairs(battle:Of(BLUE, AiWar.CAPTURE)) do T.eq(FP.InZone(b.me.pos, mid), true, b.member.handle .. " of BLU on mid too") end
	-- BLU takes mid: RED's point 1 is now BLU's to capture, and BLU caps it
	mid.owner, mid.mayCapture[BLUE] = BLUE, false
	points[2].mayCapture[BLUE], points[2].capping, points[2].progress = true, BLUE, CP.CRITICAL_PROGRESS
	field.posts = { [RED] = { P(-900, 400), P(-900, -400), P(-700, 300) } }
	battle:Tick(field, 1)
	T.eq(battle.scenario.current[RED].key, "8t", "RED splits, holders first")
	local defenders, holders = battle:Of(RED, AiWar.DEFEND), battle:Of(RED, AiWar.HOLD)
	T.eq(#defenders > 0 and #holders > 0, true, "RED has defenders and holders")
	for _, d in ipairs(defenders) do
		Near(Orders.Goal(field, d.member), field.posts[RED][d.member.slot + 1], d.member.handle .. " at its post")
	end
	battle:Tick(field, 30)
	for _, h in ipairs(holders) do
		T.eq(FP.InZone(h.me.pos, points[2]), true, h.member.handle .. " stands on point 1")
	end
end)

-- B7 and B8: A/D.
local function DustbowlGates()
	return { [BLUE] = { {
		pos = P(1000, 0),
		dir = {
			x = -1,
			y = 0,
		},
	} } }
end

T.test("A/D setup: BLU wanders, RED lines up at the gates and holds A; after setup BLU goes for A, its assault leaders on lanes", function()
	local a = FP.Point({ rank = 0, at = P(-500, 0), owner = RED, mayCapture = { [BLUE] = true } })
	local b = FP.Point({ rank = 1, at = P(-1500, 0), owner = RED })
	local battle = FP.Battle(CP.Scenario)
	battle.war:SetOffRoles({}) -- assault squads on lanes: every role on
	battle:Enlist(RED, SOLDIERS, function(i) return { pos = P(-1000, 0) } end)
	battle:Enlist(BLUE, SOLDIERS, function(i) return { pos = P(2500, 0) } end)
	local lane = {
		ids = { 1, 2, 3 },
		points = { P(2000, 800), P(1000, 800), P(0, 600) },
		length = 2600,
	}
	local field = FP.Field({
		points = { a, b },
		setup = true,
		gates = DustbowlGates(),
		lanes = { [BLUE] = {
			key = "plan",
			lane,
		} },
	})
	battle:Start(field)
	battle:Tick(field, 30)
	for _, s in ipairs(battle.soldiers) do
		if s.member.team == BLUE then T.eq(s.npc:State().wandering, true, s.member.handle .. " wanders") end
	end
	local defenders = battle:Of(RED, AiWar.DEFEND)
	T.eq(#defenders > 0, true, "RED has defenders")
	for _, d in ipairs(defenders) do
		T.eq(FS.Distance(d.me.pos, Orders.GateSpot(field, d.member, 0)) <= Orders.DEFEND_ARRIVE, true, d.member.handle .. " at its gate spot")
	end
	local holders = battle:Of(RED, AiWar.HOLD)
	T.eq(#holders > 0, true, "RED has holders")
	for _, h in ipairs(holders) do T.eq(FP.InZone(h.me.pos, a), true, h.member.handle .. " in A's zone") end
	field.setup = false
	battle:Tick(field, 2)
	local leaders = 0
	for _, s in ipairs(battle:Of(BLUE, AiWar.ASSAULT)) do
		if s.npc:State().onLane then leaders = leaders + 1 end
	end
	T.eq(leaders > 0, true, "an assault leader walks its lane")
	battle:Tick(field, 40)
	local capturers = battle:Of(BLUE, AiWar.CAPTURE)
	T.eq(#capturers > 0, true, "BLU has capturers")
	for _, s in ipairs(capturers) do T.eq(FP.InZone(s.me.pos, a), true, s.member.handle .. " reached A") end
end)

T.test("A/D fall back: A lost, RED's guard is B at once, and its holders reach B within 20 ticks", function()
	local a = FP.Point({ rank = 0, at = P(-500, 0), owner = RED, mayCapture = { [BLUE] = true } })
	local b = FP.Point({ rank = 1, at = P(-1300, 0), owner = RED })
	local battle = FP.Battle(CP.Scenario)
	battle:Enlist(RED, SOLDIERS, function(i) return { pos = P(-800, 0) } end)
	local field = FP.Field({ points = { a, b } })
	battle:Start(field)
	battle:Tick(field, 20)
	T.eq(battle.scenario.current[RED].key, "10", "RED defends A")
	a.owner, a.mayCapture[BLUE], a.capping = BLUE, false, Teams.UNASSIGNED
	b.mayCapture[BLUE] = true
	battle:Tick(field, 1)
	T.eq(RankOf(field.objectives[RED].guard), 1, "the guard is B")
	T.eq(field.objectives[RED].justLost, true, "A just lost")
	T.eq(battle.scenario.current[RED].key, "10t", "the hot stance, undamped")
	T.eq(battle.scenario.current[RED].critical, true, "critical")
	battle:Tick(field, 19)
	local holders = battle:Of(RED, AiWar.HOLD)
	T.eq(#holders > 0, true, "RED has holders")
	for _, h in ipairs(holders) do T.eq(FP.InZone(h.me.pos, b), true, h.member.handle .. " on B") end
end)

T.finish()
