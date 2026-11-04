local T = dofile("tests/harness.lua")

-- What the debug layer sees of a soldier the engine runs.
local Action = nextsoldier.behavior.action

local frames
local function Stack() return frames end
local ENT = { GetClass = function() return "player" end }
local function Frame(name, depth, suspended)
	return { name = name, depth = depth, suspended = suspended, started = true }
end

T.test("its stack is the engine's, under its class", function()
	frames = { Frame("TacticalMonitor", 1), Frame("FetchFlag", 2) }
	local name, shown = Action.DebugNpc(ENT, Stack):Stack()
	T.eq(name, "player", "its class")
	T.eq(shown[1].name, "TacticalMonitor", "outermost first")
	T.eq(shown[2].depth, 2, "indented by the engine's depth")
end)

T.test("it names its variant by its class", function()
	T.eq(Action.DebugNpc(ENT, Stack).variant._NAME, "player", "as the layer lists it")
end)

T.test("a watched stack logs each change to it", function()
	local logged = {}
	local npc = Action.DebugNpc(ENT, Stack)
	npc:Watch({ Event = function(_, text) logged[#logged + 1] = text end })
	frames = { Frame("ScenarioMonitor", 1) }
	npc:Stack()
	frames = { Frame("ScenarioMonitor", 1, true), Frame("DeliverFlag", 1) }
	npc:Stack()
	npc:Stack()
	T.eq(#logged, 2, "its first shape and its one change, not each look")
	T.eq(logged[2]:find("DeliverFlag", 1, true) ~= nil, true, "what it went to")
	T.eq(logged[2]:find("ScenarioMonitor (suspended)", 1, true) ~= nil, true, "and what it buried")
end)

T.test("unwatched, nothing is logged", function()
	local logged = 0
	local npc = Action.DebugNpc(ENT, Stack)
	npc:Watch({ Event = function() logged = logged + 1 end })
	npc:Watch(nil)
	frames = { Frame("Other", 1) }
	npc:Stack()
	T.eq(logged, 0, "no log to write to")
end)

T.finish()
