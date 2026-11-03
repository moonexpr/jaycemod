-- wartactics.monitors: the tactical, squad and scenario monitors a soldier
-- runs under its mode's strategy, driven here by a mode of the test's own, so
-- they stand without the AI war: what they need of a mode is the behaviours
-- it registered and its host (wartactics.monitors.HOST).
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local N = npc.nextbot
local Chart = nextsoldier.chart.CHART
local Monitors = wartactics.monitors

local TICK = 0.25

local function Standing(name)
	local class = Chart:State(name)
	function class:Init(state) self.state = state end
	return class
end

local Side = Standing("Side")
local OwnMonitor = Standing("OwnMonitor")
local BEHAVIORS = (function()
	local registry = nextsoldier.behaviors.New()
	for _, name in ipairs({ "Humiliated", "SeekAndDestroy", "RetreatToCover", "CallMedic", "OpenDoor" }) do
		registry:Register({ name = name, behavior = Standing(name) })
	end
	registry:Register({ name = "OwnMonitor", behavior = OwnMonitor })
	return registry:Compile()
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
		InitialAction = function(state) return Monitors.TacticalMonitor:New(state) end,
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
	T.eq(package.loaded["features.aiwar.orders"], nil, "orders")
	T.eq(package.loaded["features.aiwar.model"], nil, "model")
end)

T.test("the three monitors are registered with NextSoldier", function()
	local compiled = nextsoldier.behaviors.Shared:Compile()
	T.eq(compiled:Get("TacticalMonitor"), Monitors.TacticalMonitor, "tactical")
	T.eq(compiled:Get("SquadMonitor"), Monitors.SquadMonitor, "squad")
	T.eq(compiled:Get("ScenarioMonitor"), Monitors.ScenarioMonitor, "scenario")
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
