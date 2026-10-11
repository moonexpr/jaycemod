-- foundation.aiwar.scenario.koth: King of the Hill, the control point
-- scenario with one hill always a target, and stances read from the team
-- clocks; then whole battles of tests/fake_soldier.lua soldiers
-- (tests/fake_points.lua).
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local FP = dofile("tests/fake_points.lua")
local N = T.require("foundation.npc")
local AiWar = T.require("foundation.aiwar")
local Orders = T.require("foundation.aiwar.orders")
local Scenario = T.require("foundation.aiwar.scenario")
local CP = T.require("foundation.aiwar.scenario.control_points")
local Koth = T.require("foundation.aiwar.scenario.koth")
local Teams = T.require("foundation.teams")

local RED, BLUE = Teams.RED, Teams.BLUE
local P = FS.Point

local HILL_AT = P(0, 0)

local function Hill(t)
	t.rank = 0
	t.at = HILL_AT
	return FP.Point(t)
end

local function Field(hill, clocks, t)
	t = t or {}
	t.points = { hill }
	t.clocks = clocks
	return FP.Field(t)
end

local function Brief(field, now, scenario)
	scenario = scenario or Koth.Scenario:New()
	scenario:Brief(field, now or 0)
	return field, scenario
end

local function Shares(stance)
	local shares = {}
	for i, share in ipairs(stance) do shares[i] = share.role .. ":" .. share.weight end
	return table.concat(shares, " ")
end

T.test("the King of the Hill variant is the rounds mode's, extends control points, and guards all round", function()
	T.eq(Scenario.For("koth"), Koth.Scenario, "chosen by the mode's NAME")
	T.eq(Koth.Scenario.NAME, Koth.MODE, "named for it")
	T.eq(getmetatable(Koth.Scenario), CP.Scenario, "a control point scenario")
	T.eq(Koth.Scenario.GUARDS_ALL_ROUND, true, "guards anywhere round the hill")
	T.eq(Brief(Field(Hill({}), FP.Clocks(180, 180))).doctrine, CP.DOCTRINE, "the point doctrine")
end)

T.test("the hill is always a target to the team without it, even locked; its owner defends it", function()
	local locked = Brief(Field(Hill({ locked = true }), FP.Clocks(180, 180)))
	for _, team in ipairs({ RED, BLUE }) do
		local o = locked.objectives[team]
		T.eq(#o.attack, 1, "locked: attacked")
		T.eq(o.target ~= nil, true, "the target")
		T.eq(o.staging, o.target, "and where it stages while locked")
	end
	local held = Brief(Field(Hill({ owner = RED }), FP.Clocks(100, 180)))
	T.eq(#held.objectives[RED].attack, 0, "its owner does not attack it")
	T.eq(held.objectives[RED].guard ~= nil, true, "it guards it, whatever mayCapture says")
	T.eq(held.objectives[BLUE].target ~= nil, true, "BLU attacks it")
	T.eq(held.objectives[BLUE].staging, nil, "unlocked: no staging")
end)

T.test("the time left is the enemy's clock, and urgency follows it", function()
	local field = Brief(Field(Hill({ owner = RED }), FP.Clocks(CP.MUST_PUSH_TIME - 1, 170)))
	T.eq(field.objectives[BLUE].timeLeft, CP.MUST_PUSH_TIME - 1, "BLU reads RED's clock")
	T.eq(field.objectives[BLUE].urgent, true, "RED's clock is short: BLU must push")
	T.eq(field.objectives[RED].timeLeft, 170, "RED reads BLU's")
	field = Brief(Field(Hill({ owner = RED }), FP.Clocks(170, 170)))
	T.eq(field.objectives[BLUE].urgent, false, "time enough")
	field = Brief(Field(Hill({ owner = RED }), FP.Clocks(170, 170), { overtime = true }))
	T.eq(field.objectives[BLUE].urgent, true, "overtime")
end)

-- B11: the clock-aware stances ------------------------------------------------------

T.test("stances by the hill's state for the team", function()
	local function Entries(hill, clocks, t)
		local field, scenario = Brief(Field(hill, clocks, t))
		return scenario:Stances(field, 0)
	end
	local e = Entries(Hill({ locked = true }), FP.Clocks(180, 180))
	T.eq(e[RED].key, Koth.LOCKED, "locked")
	T.eq(Shares(e[RED].stance), "capture:4 assault:3 raid:2 support:1", "locked weights")
	e = Entries(Hill({}), FP.Clocks(180, 180))
	T.eq(e[BLUE].key, Koth.OPEN, "open")
	T.eq(Shares(e[BLUE].stance), "capture:5 assault:3 raid:1 support:1", "open weights")
	local defense
	e, defense = Entries(Hill({ owner = RED }), FP.Clocks(100, 180))
	T.eq(e[RED].key, Koth.HELD, "held")
	T.eq(Shares(e[RED].stance), "hold:3 defend:4 raid:2 support:1", "held weights")
	T.eq(defense[RED], 1, "the holder defends")
	T.eq(defense[BLUE], 0, "the other attacks")
	e = Entries(Hill({ owner = RED }), FP.Clocks(Koth.KOTH_TURTLE_TIME, 180))
	T.eq(e[RED].key, Koth.TURTLE, "turtling at the end of its clock")
	T.eq(Shares(e[RED].stance), "hold:4 defend:5 support:1", "no raid")
	e = Entries(Hill({ owner = RED, capping = BLUE, progress = CP.CRITICAL_PROGRESS - 0.1 }), FP.Clocks(100, 180))
	T.eq(e[RED].key, Koth.CAPPED, "the enemy capping")
	T.eq(Shares(e[RED].stance), "hold:6 defend:3 support:1", "capped weights")
	T.eq(e[RED].critical, false, "not yet critical")
	e = Entries(Hill({ owner = RED, capping = BLUE, progress = CP.CRITICAL_PROGRESS }), FP.Clocks(100, 180))
	T.eq(e[RED].critical, true, "critical")
end)

T.test("lost: aggression rises as the enemy's clock runs down, then the last stand", function()
	local cases = {
		{
			clock = 170,
			key = "lost:0",
			critical = false,
			weights = "capture:30 assault:40 raid:20 support:10",
		},
		{
			clock = 100,
			key = "lost:2",
			critical = false,
			weights = "capture:38 assault:36 raid:16 support:10",
		},
		{
			clock = 60,
			key = "lost:5",
			critical = false,
			weights = "capture:50 assault:30 raid:10 support:10",
		},
		{
			clock = 25,
			key = Koth.LAST_STAND,
			critical = true,
			weights = "capture:8 assault:1 support:1",
		},
	}
	for _, case in ipairs(cases) do
		local field, scenario = Brief(Field(Hill({ owner = RED }), FP.Clocks(case.clock, 180)))
		local e = scenario:Stances(field, 0)[BLUE]
		T.eq(e.key, case.key, "clock " .. case.clock)
		T.eq(e.critical, case.critical, "clock " .. case.clock .. " critical")
		T.eq(Shares(e.stance), case.weights, "clock " .. case.clock .. " weights")
	end
	local field, scenario = Brief(Field(Hill({ owner = RED }), FP.Clocks(170, 180), { overtime = true }))
	T.eq(scenario:Stances(field, 0)[BLUE].key, Koth.LAST_STAND, "overtime")
	field, scenario = Brief(Field(Hill({ owner = RED }), FP.Clocks(0, 180)))
	T.eq(Shares(scenario:Stances(field, 0)[BLUE].stance), "capture:8 assault:1 support:1", "no raid at the very end")
end)

T.test("the allocated capturers rise with the enemy's clock falling; the last stand applies at once", function()
	local war = AiWar.War.New()
	war:SetOffRoles({}) -- the shares as the scenario makes them, every role on
	for i = 1, 10 do war:Enlist("blue" .. i, BLUE, true) end
	local scenario = Koth.Scenario:New()
	local now, last = 0, 0
	local function Capturers()
		local n = 0
		for _, member in pairs(war.members) do
			if member.role == AiWar.CAPTURE then n = n + 1 end
		end
		return n
	end
	for _, clock in ipairs({ 170, 100, 60 }) do
		scenario:Command(war, Field(Hill({ owner = RED }), FP.Clocks(clock, 180)), now)
		now = now + Scenario.ALLOCATION_HOLD
		scenario:Command(war, Field(Hill({ owner = RED }), FP.Clocks(clock, 180)), now)
		local n = Capturers()
		T.eq(n >= last, true, "clock " .. clock .. ": " .. n .. " capturers, " .. last .. " before")
		last = n
		now = now + 1
	end
	scenario:Command(war, Field(Hill({ owner = RED }), FP.Clocks(25, 180)), now)
	T.eq(scenario.current[BLUE].key, Koth.LAST_STAND, "at once")
	T.eq(Capturers() > last, true, "more capturers: " .. Capturers())
	T.eq(Capturers(), 8, "eight of ten")
	scenario:Command(war, Field(Hill({ owner = RED }), FP.Clocks(25, 180), { overtime = true }), now + 0.25)
	T.eq(Capturers(), 8, "overtime keeps them")
end)

-- Full stack -----------------------------------------------------------------------

local SOLDIERS = 8

-- B10.
T.test("a locked hill: capturers stage outside it on their own side, then take it when it unlocks", function()
	local hill = Hill({ locked = true })
	local battle = FP.Battle(Koth.Scenario)
	battle:Enlist(RED, SOLDIERS)
	battle:Enlist(BLUE, SOLDIERS)
	local field = Field(hill, FP.Clocks(180, 180))
	battle:Start(field)
	battle:Tick(field, 35)
	for _, team in ipairs({ RED, BLUE }) do
		local capturers = battle:Of(team, AiWar.CAPTURE)
		T.eq(#capturers > 0, true, team .. " has capturers")
		for _, s in ipairs(capturers) do
			local name = s.member.handle
			T.eq(FP.InZone(s.me.pos, hill), false, name .. " outside the zone")
			T.eq((s.me.pos.x - HILL_AT.x) * (FP.BASES[team].x - HILL_AT.x) > 0, true, name .. " on its own side")
			T.eq(FS.Distance(s.me.pos, HILL_AT) < hill.zone.radius + CP.STAGE_DISTANCE + CP.STAGE_SPREAD + 1, true, name .. " near it")
		end
	end
	hill.locked = false
	-- the "open" stance, with a capturer more, waits ALLOCATION_HOLD; then
	-- the new capturer comes too
	battle:Tick(field, Scenario.ALLOCATION_HOLD / FP.TICK + 15)
	T.eq(battle.scenario.current[BLUE].key, Koth.OPEN, "open")
	for _, team in ipairs({ RED, BLUE }) do
		for _, s in ipairs(battle:Of(team, AiWar.CAPTURE)) do
			T.eq(FP.InZone(s.me.pos, hill), true, s.member.handle .. " on the hill")
		end
	end
end)

T.test("capturers and holders set out from base behind their squad's leader", function()
	local hill = Hill({ owner = BLUE })
	local battle = FP.Battle(Koth.Scenario)
	battle:Enlist(RED, SOLDIERS)
	battle:Enlist(BLUE, SOLDIERS)
	local field = Field(hill, FP.Clocks(150, 150))
	battle:Start(field)
	battle:Tick(field, 2)
	for _, job in ipairs({ { RED, AiWar.CAPTURE }, { BLUE, AiWar.HOLD } }) do
		local followers = 0
		for _, s in ipairs(battle:Of(job[1], job[2])) do
			local _, squadRole = Orders.JobOf(s.npc:Describe())
			if squadRole == "SquadMember" then
				T.eq(s.npc:State().tactic, "following its leader", s.member.handle)
				followers = followers + 1
			end
		end
		T.eq(followers > 0, true, job[2] .. " has squad members")
	end
end)

-- B12.
T.test("the enemy holds the hill with 20 s left: capturers rush it, will not retreat, and occupy it", function()
	local hill = Hill({ owner = RED })
	local battle = FP.Battle(Koth.Scenario)
	battle.war:SetOffRoles({}) -- the shares as the scenario makes them, every role on
	battle:Enlist(BLUE, SOLDIERS)
	local field = Field(hill, FP.Clocks(20, 180))
	battle:Start(field)
	battle:Tick(field, 2)
	T.eq(battle.scenario.current[BLUE].key, Koth.LAST_STAND, "the last stand")
	local capturers = battle:Of(BLUE, AiWar.CAPTURE)
	T.eq(#capturers, 6, "most of the team capturing")
	for _, s in ipairs(capturers) do
		T.eq(s.me.gait, Orders.RUSH, s.member.handle .. " rushes")
		T.eq(s.npc:Query("ShouldRetreat"), N.ANSWER_NO, s.member.handle .. " will not retreat")
	end
	battle:Tick(field, 35)
	for _, s in ipairs(capturers) do
		T.eq(FP.InZone(s.me.pos, hill), true, s.member.handle .. " on the hill")
		T.eq(s.npc:State().inZone, true, s.member.handle .. " occupying it")
	end
end)

-- B13.
T.test("holding the hill: holders ring it, go onto it when the enemy caps, and raid leaves when the clock is nearly out", function()
	local hill = Hill({ owner = BLUE })
	local battle = FP.Battle(Koth.Scenario)
	battle:Enlist(BLUE, SOLDIERS)
	local field = Field(hill, FP.Clocks(150, 150))
	battle:Start(field)
	battle:Tick(field, 40)
	T.eq(battle.scenario.current[BLUE].key, Koth.HELD, "held")
	local holders = battle:Of(BLUE, AiWar.HOLD)
	T.eq(#holders > 0, true, "BLU has holders")
	for _, s in ipairs(holders) do
		T.eq(FP.InZone(s.me.pos, hill), false, s.member.handle .. " rings the hill")
		T.eq(FS.Distance(s.me.pos, HILL_AT) <= hill.zone.radius + CP.HOLD_RING + CP.HOLD_ARRIVE, true, s.member.handle .. " near it")
	end
	hill.capping, hill.progress = RED, 0.1
	battle:Tick(field, 10)
	for _, s in ipairs(holders) do
		T.eq(FP.InZone(s.me.pos, hill), true, s.member.handle .. " on the hill against the capture")
	end
	hill.capping, hill.progress = Teams.UNASSIGNED, 0
	field.clocks = FP.Clocks(150, Koth.KOTH_TURTLE_TIME - 5)
	battle:Tick(field, Scenario.ALLOCATION_HOLD / FP.TICK + 1)
	T.eq(battle.scenario.current[BLUE].key, Koth.TURTLE, "turtling")
	T.eq(battle:Count(BLUE, AiWar.RAID), 0, "no raiders left")
end)

T.finish()
