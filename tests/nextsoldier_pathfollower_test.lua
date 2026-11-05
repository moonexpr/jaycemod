-- nextsoldier.behavior.pathfollower: the path follower's bench as the engine's Actions. The
-- engine runs them on a server; here each answers a fake soldier.
local T = dofile("tests/harness.lua")
local Action = nextsoldier.behavior.action
local PathFollower = nextsoldier.behavior.pathfollower

local function Me(fields)
	local me = { wanted = "Idle", may = true, tool = 0, errands = 0 }
	for key, value in pairs(fields or {}) do me[key] = value end
	function me:NSMayAct() return self.may end
	function me:NSWantedBehavior() return self.wanted end
	function me:NSUpdateToolBehavior() self.tool = self.tool + 1 end
	function me:NSUpdateErrand() self.errands = self.errands + 1 end
	return me
end

T.test("a tool's follower starts idle and a console's on its errand", function()
	T.eq(PathFollower.InitialAction(true).name, "Idle", "waits to be sent")
	T.eq(PathFollower.InitialAction(false).name, "Errand", "the bench's")
end)

T.test("sent, an idle follower travels", function()
	local result = PathFollower.Idle:New():Update(Me({ wanted = "Travel" }))
	T.eq(result.type, Action.CHANGE_TO, "changes")
	T.eq(result.action.name, "Travel", "to its travel")
end)

T.test("told to stop, a traveller goes idle", function()
	local result = PathFollower.Travel:New():Update(Me({ wanted = "Idle" }))
	T.eq(result.type, Action.CHANGE_TO, "changes")
	T.eq(result.action.name, "Idle", "to idle")
end)

T.test("each keeps its follower's steering going while it stays", function()
	local me = Me()
	T.eq(PathFollower.Idle:New():Update(me).type, Action.CONTINUE, "stays idle")
	T.eq(me.tool, 1, "holds it still")
	me.wanted = "Travel"
	T.eq(PathFollower.Travel:New():Update(me).type, Action.CONTINUE, "stays travelling")
	T.eq(me.tool, 2, "steers it")
	T.eq(PathFollower.Errand:New():Update(me).type, Action.CONTINUE, "stays on its errand")
	T.eq(me.errands, 1, "runs it")
end)

T.test("a body that may not act, scrambling or disabled, is left alone", function()
	local me = Me({ may = false })
	PathFollower.Idle:New():Update(me)
	PathFollower.Errand:New():Update(me)
	T.eq(me.tool + me.errands, 0, "an engine action runs whatever its body is doing")
end)

T.finish()
