-- foundation.aiwar.scenario: the war's scenario as a Strategy chosen from the
-- rounds mode, the Commander's damped tick, and the payload variant, which
-- must allocate exactly as the controller did before it.
local T = dofile("tests/harness.lua")
local AiWar = T.require("foundation.aiwar")
local Orders = T.require("foundation.aiwar.orders")
local Scenario = T.require("foundation.aiwar.scenario")
local Payload = T.require("foundation.aiwar.scenario.payload")
local Track = T.require("foundation.math.polyline")
local Teams = T.require("foundation.teams")

local RED, BLUE = Teams.RED, Teams.BLUE

local function P(x, y) return { x = x, y = y, z = 0 } end

-- Choosing the variant ------------------------------------------------------

T.test("the variant comes from the rounds mode's name; any other is freeform", function()
	T.eq(Scenario.For("payload"), Payload.Scenario, "payload")
	-- a mode the war does not know, or none, is fought freeform (aiwar_freeform_test.lua)
	T.eq(Scenario.For("none"), T.require("foundation.aiwar.scenario.freeform").Scenario, "an unknown mode")
	T.eq(Scenario.For(nil), T.require("foundation.aiwar.scenario.freeform").Scenario, "no rounds")
	T.eq(Scenario.For(T.require("features.mvm.model").Mode.NAME), T.require("foundation.aiwar.scenario.mvm").Scenario, "MvM")
	T.eq(Payload.Scenario.NAME, Payload.MODE, "the payload variant is named for its mode")
end)

T.test("the variants are keyed by the rounds modes' NAMEs", function()
	local names = {}
	for _, path in ipairs({ "foundation.rounds.payload", "foundation.rounds.control_points", "features.koth.model", "foundation.rounds.arena", "features.flag.model", "features.mvm.model" }) do
		names[T.require(path).Mode.NAME] = true
	end
	names[T.require("foundation.rounds").DEATHMATCH] = true
	for name in pairs(Scenario.VARIANTS) do T.eq(names[name], true, name .. " is a rounds mode") end
	for name in pairs(names) do T.eq(Scenario.VARIANTS[name] ~= nil, true, name .. " has a variant") end
end)

T.test("the base leaves the scenario's parts to its variants", function()
	local base = Scenario.Scenario:New()
	for _, name in ipairs({ "Brief", "Stances", "Front", "SetupAttacks" }) do
		local ok, err = pcall(base[name], base, {}, 0)
		T.eq(ok, false, name .. " raises")
		T.eq(tostring(err):find("not implemented", 1, true) ~= nil, true, name .. ": " .. tostring(err))
	end
end)

-- The Commander's damping, with a variant whose stances the test sets -------

local Probe = Scenario.Scenario:Extend("probe")
function Probe:Brief(field, now) field.briefed = now end
function Probe:Stances(field, now) return field.stances, field.defense end

local function Stance(role)
	return { {
		role = role,
		weight = 1,
	} }
end

local HOLDING, CAPTURING, ASSAULTING = Stance(AiWar.HOLD), Stance(AiWar.CAPTURE), Stance(AiWar.ASSAULT)

local function Entry(stance, key, critical)
	return {
		stance = stance,
		key = key,
		critical = critical == true,
	}
end

local function Tick(scenario, war, now, redEntry, defense)
	local field = {
		stances = { [RED] = redEntry },
		defense = { [RED] = defense },
	}
	scenario:Command(war, field, now)
	return field
end

-- The allocation mechanics, with every role on (AiWar.OFF_ROLES aside).
local function ProbeWar()
	local war = AiWar.War.New()
	war:SetOffRoles({})
	war:Enlist("r1", RED, true)
	return war, war:Member("r1")
end

T.test("the Command tick briefs, then allocates", function()
	local war = ProbeWar()
	local field = Tick(Probe:New(), war, 7, Entry(HOLDING, "hold"), 1)
	T.eq(field.briefed, 7, "briefed at the tick")
	T.eq(war.stances[RED], HOLDING, "allocated")
end)

T.test("a team's first stance applies at once; a new one waits ALLOCATION_HOLD", function()
	local war, member = ProbeWar()
	local scenario = Probe:New()
	Tick(scenario, war, 0, Entry(HOLDING, "hold"), 1)
	T.eq(member.role, AiWar.HOLD, "the first at once")
	T.eq(war.defense[RED], 1, "with its share")
	Tick(scenario, war, 1, Entry(CAPTURING, "capture"), 0)
	T.eq(member.role, AiWar.HOLD, "a new key waits")
	T.eq(war.defense[RED], 1, "and so does its share")
	Tick(scenario, war, 1 + Scenario.ALLOCATION_HOLD - 0.1, Entry(CAPTURING, "capture"), 0)
	T.eq(member.role, AiWar.HOLD, "still waiting just short of the hold")
	Tick(scenario, war, 1 + Scenario.ALLOCATION_HOLD, Entry(CAPTURING, "capture"), 0)
	T.eq(member.role, AiWar.CAPTURE, "held long enough: applied")
	T.eq(war.defense[RED], 0, "with its share")
end)

T.test("a critical stance applies at once", function()
	local war, member = ProbeWar()
	local scenario = Probe:New()
	Tick(scenario, war, 0, Entry(HOLDING, "hold"), 1)
	Tick(scenario, war, 0.5, Entry(CAPTURING, "laststand", true), 0)
	T.eq(member.role, AiWar.CAPTURE, "no wait")
end)

T.test("a key that flickers back restarts the wait", function()
	local war, member = ProbeWar()
	local scenario = Probe:New()
	Tick(scenario, war, 0, Entry(HOLDING, "hold"), 1)
	Tick(scenario, war, 1, Entry(CAPTURING, "capture"), 0)
	Tick(scenario, war, 2, Entry(HOLDING, "hold"), 1)
	Tick(scenario, war, 3, Entry(CAPTURING, "capture"), 0)
	Tick(scenario, war, 1 + Scenario.ALLOCATION_HOLD, Entry(CAPTURING, "capture"), 0)
	T.eq(member.role, AiWar.HOLD, "the wait counts from the last change")
	Tick(scenario, war, 3 + Scenario.ALLOCATION_HOLD, Entry(CAPTURING, "capture"), 0)
	T.eq(member.role, AiWar.CAPTURE, "then applies")
end)

T.test("a pending key replaced by another waits for the new one", function()
	local war, member = ProbeWar()
	local scenario = Probe:New()
	Tick(scenario, war, 0, Entry(HOLDING, "hold"), 1)
	Tick(scenario, war, 1, Entry(CAPTURING, "capture"), 0)
	Tick(scenario, war, 2, Entry(ASSAULTING, "assault"), 0)
	Tick(scenario, war, 1 + Scenario.ALLOCATION_HOLD, Entry(ASSAULTING, "assault"), 0)
	T.eq(member.role, AiWar.HOLD, "assault seen only since 2")
	Tick(scenario, war, 2 + Scenario.ALLOCATION_HOLD, Entry(ASSAULTING, "assault"), 0)
	T.eq(member.role, AiWar.ASSAULT, "then applies")
end)

T.test("a nil stance leaves the team as it is", function()
	local war, member = ProbeWar()
	local scenario = Probe:New()
	Tick(scenario, war, 0, Entry(HOLDING, "hold"), 1)
	Tick(scenario, war, 10, nil, nil)
	T.eq(member.role, AiWar.HOLD, "unchanged")
	T.eq(war.defense[RED], 1, "its share too")
	T.eq(war.stances[BLUE], nil, "BLU, never given one, untouched")
end)

T.test("a reset (a new round) forgets the current and pending stances", function()
	local war, member = ProbeWar()
	local scenario = Probe:New()
	Tick(scenario, war, 0, Entry(HOLDING, "hold"), 1)
	Tick(scenario, war, 1, Entry(CAPTURING, "capture"), 0)
	scenario:Reset()
	Tick(scenario, war, 1.5, Entry(ASSAULTING, "assault"), 0)
	T.eq(member.role, AiWar.ASSAULT, "the first stance of the round applies at once")
end)

-- The payload variant -------------------------------------------------------

-- A straight track along +x from 0 to 4000, its next checkpoint at 3000.
local function Cart(distance)
	local track = Track.New({ P(0, 0), P(4000, 0) })
	return {
		track = track,
		distance = distance,
		pos = track:PointAt(distance),
		nextCheckpoint = 3000,
	}
end

local function PayloadField(carts)
	return {
		phase = AiWar.PHASES.running,
		carts = carts,
	}
end

-- What the controller's CartTeams gave war:Assign.
local function Expected(carts, close)
	local teams = {}
	for team, cart in pairs(carts) do
		teams[team] = {
			close = close[team],
			progress = cart.distance / cart.track:Length(),
		}
	end
	return teams
end

local function Roles(war)
	local roles = {}
	for _, member in ipairs(war:Members()) do roles[#roles + 1] = member.handle .. "=" .. member.role .. member.slot end
	return table.concat(roles, " ")
end

local function TwoWars()
	local ours, theirs = AiWar.War.New(), AiWar.War.New()
	for _, war in ipairs({ ours, theirs }) do
		for i = 1, 8 do war:Enlist("r" .. i, RED, true) end
		for i = 1, 8 do war:Enlist("b" .. i, BLUE, true) end
	end
	return ours, theirs
end

T.test("the payload variant briefs the payload doctrine", function()
	local field = PayloadField({ [BLUE] = Cart(1000) })
	Payload.Scenario:New():Brief(field, 0)
	T.eq(field.doctrine, Orders.PAYLOAD, "the doctrine")
end)

T.test("the payload variant allocates a race as war:Assign(CartTeams) did, tick by tick, with the close hysteresis", function()
	local ours, theirs = TwoWars()
	local scenario = Payload.Scenario:New()
	-- BLU's cart moves on toward its checkpoint at 3000 and back: remaining
	-- 1500 (far), 1000 (close), 1300 (still close), 1500 (far again)
	local steps = {
		{ blue = 1500, close = false },
		{ blue = 2000, close = true },
		{ blue = 1700, close = true },
		{ blue = 1500, close = false },
	}
	for i, step in ipairs(steps) do
		local carts = {
			[RED] = Cart(1200),
			[BLUE] = Cart(step.blue),
		}
		scenario:Command(ours, PayloadField(carts), i)
		theirs:Assign(Expected(carts, {
			[RED] = false,
			[BLUE] = step.close,
		}))
		T.eq(scenario.memory.cartClose[BLUE], step.close, "step " .. i .. ": BLU's cart close")
		T.eq(Roles(ours), Roles(theirs), "step " .. i .. ": the same roles")
		T.eq(ours.defense[RED], theirs.defense[RED], "step " .. i .. ": RED's share")
		T.eq(ours.defense[BLUE], theirs.defense[BLUE], "step " .. i .. ": BLU's share")
	end
end)

T.test("a cart first seen past CLOSE_RANGE is not close", function()
	local scenario = Payload.Scenario:New()
	local teams = scenario:CartTeams({ [BLUE] = Cart(1700) })
	T.eq(teams[BLUE].close, false, "remaining 1300, never close before")
	T.near(teams[BLUE].progress, 1700 / 4000, 1e-9, "its progress")
end)

T.test("a new round keeps the carts' close memory, as the controller did", function()
	local scenario = Payload.Scenario:New()
	scenario:CartTeams({ [BLUE] = Cart(2000) })
	scenario:Reset()
	T.eq(scenario:CartTeams({ [BLUE] = Cart(1700) })[BLUE].close, true, "still close")
end)

T.test("a payload team's lanes lead to its own cart, else the enemy's", function()
	local scenario = Payload.Scenario:New()
	local field = PayloadField({ [BLUE] = Cart(1000) })
	T.eq(scenario:Front(field, BLUE), field.carts[BLUE].pos, "BLU's own")
	T.eq(scenario:Front(field, RED), field.carts[BLUE].pos, "RED to BLU's")
	T.eq(scenario:Front(PayloadField({}), RED), nil, "no cart: no front")
end)

T.test("a team with a cart the enemy lacks comes out through setup gates, heading for its next checkpoint", function()
	local scenario = Payload.Scenario:New()
	local attacks = scenario:SetupAttacks(PayloadField({ [BLUE] = Cart(1000) }))
	T.eq(attacks[BLUE].x, 3000, "BLU heads for its checkpoint")
	T.eq(attacks[RED], nil, "RED defends")
	local last = Cart(1000)
	last.nextCheckpoint = nil
	T.eq(scenario:SetupAttacks(PayloadField({ [BLUE] = last }))[BLUE].x, 4000, "after the last checkpoint: the track's end")
	local race = scenario:SetupAttacks(PayloadField({
		[RED] = Cart(1000),
		[BLUE] = Cart(1000),
	}))
	T.eq(next(race), nil, "a race has no attacker")
end)

-- A whole field: the parts each variant's Brief reads ----------------------

local ControlPoints = T.require("foundation.aiwar.scenario.control_points")
local Koth = T.require("foundation.aiwar.scenario.koth")

local function Parts(t)
	local both = function(value)
		return {
			[RED] = value,
			[BLUE] = value,
		}
	end
	return {
		points = t.points,
		bases = t.bases ~= false and both(P(0, 0)) or {},
		clocks = t.clocks and both({
			left = 180,
			running = false,
		}) or nil,
	}
end

local ONE_POINT = { { rank = 0 } }

T.test("every scenario needs both teams' bases on the map", function()
	for _, variant in ipairs({ Payload.Scenario, ControlPoints.Scenario, Koth.Scenario }) do
		T.eq(variant:MapLacks(Parts({
			bases = false,
			points = ONE_POINT,
		})), Scenario.BASES, variant.NAME)
	end
	local oneBase = Parts({ points = ONE_POINT })
	oneBase.bases[BLUE] = nil
	T.eq(ControlPoints.Scenario:MapLacks(oneBase), Scenario.BASES, "one team's base")
end)

T.test("payload needs no points or clocks", function()
	T.eq(Payload.Scenario:MapLacks(Parts({})), nil, "may start")
	T.eq(Payload.Scenario:Lacks(Parts({})), nil, "whole")
end)

T.test("the point scenarios need points on the map: at least one", function()
	for _, variant in ipairs({ ControlPoints.Scenario, Koth.Scenario }) do
		T.eq(variant:MapLacks(Parts({})), Scenario.POINTS, variant.NAME .. ": none")
		T.eq(variant:MapLacks(Parts({ points = {} })), Scenario.POINTS, variant.NAME .. ": an empty list")
		T.eq(variant:MapLacks(Parts({ points = ONE_POINT })), nil, variant.NAME .. ": may start")
	end
	T.eq(ControlPoints.Scenario:Lacks(Parts({ points = ONE_POINT })), nil, "a CP field is whole without clocks")
end)

T.test("KOTH may start without clocks, but its field is whole only with both teams'", function()
	local sandbox = Parts({ points = ONE_POINT })
	T.eq(Koth.Scenario:MapLacks(sandbox), nil, "may start")
	T.eq(Koth.Scenario:Lacks(sandbox), Scenario.CLOCKS, "waits for the clocks")
	local round = Parts({
		points = ONE_POINT,
		clocks = true,
	})
	T.eq(Koth.Scenario:Lacks(round), nil, "whole")
	round.clocks[RED] = nil
	T.eq(Koth.Scenario:Lacks(round), Scenario.CLOCKS, "one clock")
end)

-- A tied match's deathmatch is fought as arena's round before its point
-- opens: every squad explores and hunts, whatever objective the map has.
T.test("a deathmatch is fought as arena's shut round: all explore, with no point needed", function()
	local Deathmatch = T.require("foundation.aiwar.scenario.deathmatch")
	T.eq(Scenario.For(T.require("foundation.rounds").DEATHMATCH), Deathmatch.Scenario, "its own variant")
	local field = {
		bases = { [RED] = P(0, 0), [BLUE] = P(4000, 0) },
		waypoints = { P(1000, 0), P(2000, 0) },
		now = 0,
	}
	local scenario = Deathmatch.Scenario:New()
	T.eq(scenario:MapLacks(field), nil, "bases and waypoints are enough")
	scenario:Brief(field, 0)
	local entries = scenario:Stances(field, 0)
	T.eq(#entries[RED].stance, 1, "one job")
	T.eq(entries[RED].stance[1].role, AiWar.EXPLORE, "explore")
	T.eq(entries[BLUE].stance[1].role, AiWar.EXPLORE, "both sides")
end)

T.finish()
