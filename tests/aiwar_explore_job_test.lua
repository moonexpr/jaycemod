-- Exploring is every scenario's job, so an admin can send soldiers
-- exploring by hand (the slots panel's Job menu, ns_jobs_assign) on any
-- map: every doctrine has it, and every scenario keeps the exploration
-- board (foundation.aiwar.explore) its explorers go by.
local T = dofile("tests/harness.lua")
local FS = dofile("tests/fake_soldier.lua")
local FP = dofile("tests/fake_points.lua")
local AiWar = T.require("foundation.aiwar")
local Orders = T.require("foundation.aiwar.orders")
local CP = T.require("foundation.aiwar.scenario.control_points")
local Koth = T.require("foundation.aiwar.scenario.koth")
local Arena = T.require("foundation.aiwar.scenario.arena")
local Freeform = T.require("foundation.aiwar.scenario.freeform")
local Teams = T.require("foundation.teams")

local RED = Teams.RED
local P = FS.Point

T.test("every doctrine has the explore job", function()
	for name, doctrine in pairs({
		payload = Orders.PAYLOAD,
		control_points = CP.DOCTRINE,
		arena = Arena.DOCTRINE,
		freeform = Freeform.DOCTRINE,
	}) do
		T.eq(doctrine.ROLES[AiWar.EXPLORE] ~= nil, true, name)
	end
end)

T.test("a soldier sent exploring on a control point map makes for a waypoint", function()
	local battle = FP.Battle(CP.Scenario)
	battle:Enlist(RED, 2)
	local waypoints = { P(1000, 0), P(-3000, 2000) }
	local function Field()
		local field = FP.Field({ points = { FP.Point({ rank = 0, at = P(0, 0) }) }, waypoints = waypoints })
		field.now = battle.now
		return field
	end
	battle:Start(Field())
	local member = battle.soldiers[1].member
	battle.war:SetRole(member, AiWar.EXPLORE)
	local field = Field()
	battle:Command(field)
	local goal = CP.DOCTRINE.ROLES[AiWar.EXPLORE].Goal(field, member)
	T.eq(goal ~= nil and (goal.x == 1000 or goal.x == -3000), true, "a waypoint")
end)

T.finish()
