-- wartactics.monitors: the tactical, squad and scenario monitors a soldier
-- runs under its mode's strategy, built here on a chart of the test's own and
-- driven by a mode of its own, with NextSoldier out of reach: what they need
-- is a chart (Build's kit), the behaviours a mode gives them by name, and its
-- host (wartactics.monitors.HOST).
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
nextsoldier = setmetatable({}, { __index = function(_, key) error("read nextsoldier." .. key, 2) end })
local N = npc.nextbot
local Monitors = wartactics.monitors

local Chart = generator.state_chart.Chart({
	name = "Monitors under test",
	port = core.port.New("a soldier under test", { "Now" }),
	events = { "OnInjured" },
	queries = { "ShouldRetreat", "SelectMoreDangerousThreat" },
	initial = function(first) return first end,
})

local function Holding(name, contains)
	local class = Chart:State(name)
	function class:Init(state) self.state = state end
	function class:InitialContainedAction(me) return contains(self.state) end
	return class
end

local Tree = Monitors.Build({
	Monitor = Holding,
	Passthrough = function(name, contains)
		local class = Holding(name, contains)
		class.passthrough = true
		return class
	end,
})

local TICK = 0.25

local function Standing(name)
	local class = Chart:State(name)
	function class:Init(state) self.state = state end
	return class
end

local Side = Standing("Side")
local OwnMonitor = Standing("OwnMonitor")
local BEHAVIORS = (function()
	local behaviors = { OwnMonitor = OwnMonitor }
	for _, name in ipairs({ "Humiliated", "SeekAndDestroy", "RetreatToCover", "CallMedic", "OpenDoor" }) do
		behaviors[name] = Standing(name)
	end
	return {
		Get = function(_, name)
			return behaviors[name] or error("no behaviour " .. tostring(name) .. " is registered", 2)
		end,
	}
end)()

-- A mode: its host answers from t, its soldiers start at the tactical monitor.
local function Soldier(t)
	local host = {
		Sides = function(state) return Side:New(state) end,
		Hunting = function() return t.hunting == true end,
		Treated = function() return t.treated == true end,
		Scenario = function() return t.scenario end,
	}
	local mode = {
		NewState = function(config) return { member = config.member, behaviors = config.behaviors, host = host } end,
		InitialAction = function(state) return Tree.TacticalMonitor:New(state) end,
	}
	local me = FS.Soldier(t)
	me.disarmed, me.health = t.disarmed, t.health
	local soldier = N.Npc.New(mode, { member = t.member or {}, behaviors = t.behaviors or BEHAVIORS }, me)
	soldier:Update(TICK)
	return me, soldier
end

local function Runs(soldier, name)
	return soldier:Describe():find(name, 1, true) ~= nil
end

T.test("the monitors load without the war's feature", function()
	T.eq(package.loaded["features.aiwar.ns_behaviors"], nil, "orders")
	T.eq(package.loaded["features.aiwar.model"], nil, "model")
end)

T.test("the tree runs tactical, squad, a role, scenario, then the mode's side", function()
	local _, soldier = Soldier({})
	T.eq(soldier:Describe(), "TacticalMonitor/SquadMonitor/Solo/ScenarioMonitor/Side")
end)

T.test("a scenario's own monitor runs in place of the side, and leaves with it", function()
	local t = { scenario = { name = "holdout", monitor = "OwnMonitor" } }
	local me, soldier = Soldier(t)
	T.eq(Runs(soldier, "ScenarioMonitor/OwnMonitor"), true, soldier:Describe())
	t.scenario = { name = "plain" }
	me:Advance(TICK)
	soldier:Update(TICK)
	me:Advance(TICK)
	soldier:Update(TICK)
	T.eq(Runs(soldier, "ScenarioMonitor/Side"), true, soldier:Describe())
end)

T.test("a scenario naming a behaviour never registered is refused, naming it", function()
	local ok, why = pcall(Soldier, { scenario = { name = "holdout", monitor = "Nowhere" } })
	T.eq(ok, false, "refused")
	T.eq(tostring(why):find("Nowhere", 1, true) ~= nil, true, tostring(why))
end)

T.test("a member follows its squad's kind", function()
	local member = {}
	local me, soldier = Soldier({ member = member })
	T.eq(Runs(soldier, "/Solo/"), true, soldier:Describe())
	local other = {}
	member.fireTeam = { members = { other, member }, leader = other }
	T.eq(wartactics.squad.Kind(member), "member", "the fake fire team makes it a member")
	me:Advance(TICK)
	soldier:Update(TICK)
	me:Advance(TICK)
	soldier:Update(TICK)
	T.eq(Runs(soldier, "/SquadMember/"), true, soldier:Describe())
end)

T.test("a disarmed soldier is humiliated first", function()
	local me, soldier = Soldier({ disarmed = true, hunting = true })
	me:Advance(TICK)
	soldier:Update(TICK)
	T.eq(Runs(soldier, "Humiliated"), true, soldier:Describe())
end)

T.test("a hunting soldier seeks and destroys", function()
	local me, soldier = Soldier({ hunting = true })
	me:Advance(TICK)
	soldier:Update(TICK)
	T.eq(Runs(soldier, "SeekAndDestroy"), true, soldier:Describe())
end)

T.test("a soldier badly hurt retreats", function()
	local me, soldier = Soldier({ health = Monitors.RETREAT_HEALTH * 100 - 1 })
	me:Advance(TICK)
	soldier:Update(TICK)
	T.eq(Runs(soldier, "RetreatToCover"), true, soldier:Describe())
end)

T.test("hurt enough, a soldier a medic is not treating calls for one", function()
	local health = (Monitors.RETREAT_HEALTH + Monitors.CALL_MEDIC_HEALTH) / 2 * 100
	local me, soldier = Soldier({ health = health })
	me:Advance(TICK)
	soldier:Update(TICK)
	T.eq(Runs(soldier, "CallMedic"), true, soldier:Describe())
	local treatedMe, treated = Soldier({ health = health, treated = true })
	treatedMe:Advance(TICK)
	treated:Update(TICK)
	T.eq(Runs(treated, "CallMedic"), false, treated:Describe())
end)

T.test("a soldier at an unlocked door opens it", function()
	local me, soldier = Soldier({})
	me.doorToOpen = {}
	me:Advance(TICK)
	soldier:Update(TICK)
	T.eq(Runs(soldier, "OpenDoor"), true, soldier:Describe())
end)

T.test("a host missing a part is refused, naming it", function()
	local ok, why = pcall(function() return Monitors.HOST:Check({ Sides = function() end }) end)
	T.eq(ok, false, "refused")
	T.eq(tostring(why):find("Hunting", 1, true) ~= nil, true, tostring(why))
end)

T.finish()
