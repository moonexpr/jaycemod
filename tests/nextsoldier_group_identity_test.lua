-- nextsoldier.behavior.group_identity: the tree beside a soldier's main one, as L4D2's legs
-- beside its survivors' behaviour. The engine runs it on a server (native/nextsoldier).
local T = dofile("tests/harness.lua")
local Action = nextsoldier.behavior.action
local GroupIdentity = nextsoldier.behavior.group_identity

T.test("its root is the engine's own, holding what it does first", function()
	local given
	local engine = { GroupIdentityBehavior = function(config) given = config return { name = "root" } end }
	local root = GroupIdentity.InitialAction(engine)
	T.eq(root.name, "root", "what the engine made")
	T.eq(given.initial.name, "LegsWait", "it starts by waiting")
end)

T.test("with no group to be part of, it waits", function()
	local wait = GroupIdentity.LegsWait:New()
	T.eq(wait:Update({}).type, Action.CONTINUE, "stays")
end)

T.test("it is given to a soldier beside its main tree", function()
	local placed
	local engine = {
		GroupIdentityBehavior = function() return "root" end,
		InsertGroup = function(ent, action, me) placed = { ent, action, me } end,
	}
	GroupIdentity.Give("ent", engine, "me")
	T.eq(placed[1], "ent", "on it")
	T.eq(placed[2], "root", "its root")
	T.eq(placed[3], "me", "told to whoever it is told to")
end)

T.test("where the binary lacks it, a soldier goes without", function()
	T.eq(GroupIdentity.Give("ent", {}, "me"), false, "nothing given")
	T.eq(GroupIdentity.Give("ent", nil, "me"), false, "nor with no engine")
end)

local ENT = { GetClass = function() return "player" end }

T.test("the debug layer shows both trees, the group's after the main's", function()
	local npc = Action.DebugNpc(ENT, function() return { { name = "Main", depth = 1 } } end, function()
		return { { name = "GroupIdentityBehavior", depth = 1 }, { name = "LegsWait", depth = 2 } }
	end)
	local _, frames = npc:Stack()
	T.eq(#frames, 3, "all of them")
	T.eq(frames[1].name, "Main", "its main tree first")
	T.eq(frames[3].name, "LegsWait", "then the group's")
end)

T.test("a change in the group's tree is logged as one in its main's is", function()
	local legs = "LegsWait"
	local logged = {}
	local npc = Action.DebugNpc(ENT, function() return { { name = "Main", depth = 1 } } end, function()
		return { { name = legs, depth = 1 } }
	end)
	npc:Watch({ Event = function(_, text) logged[#logged + 1] = text end })
	npc:Stack()
	legs = "LegsFollow"
	npc:Stack()
	T.eq(logged[2]:find("LegsFollow", 1, true) ~= nil, true, "what it went to")
end)

T.test("an engine behaviour counts as empty by its main tree alone", function()
	local engine = {
		Stack = function() return { { name = "Root", depth = 1 } } end,
		GroupStack = function() return { { name = "GroupIdentityBehavior", depth = 1 }, { name = "LegsWait", depth = 2 } } end,
	}
	T.eq(Action.EngineBehavior(ENT, "first", "actor", "KIND", engine):IsEmpty(), true, "the group's tree does not keep it going")
end)

T.finish()
