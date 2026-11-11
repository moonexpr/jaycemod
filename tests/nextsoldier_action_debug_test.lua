local T = dofile ("tests/harness.lua")

-- What the debug layer sees of a soldier the engine runs.
local Action = nextsoldier.behavior.action

local frames
local function Stack () return frames end
local ENT = { GetClass = function () return "player" end }
local function Frame (name, depth, suspended)
	return { name = name, depth = depth, suspended = suspended, started = true }
end

T.test ("its stack is the engine's, under its class", function ()
	frames = { Frame ("TacticalMonitor", 1), Frame ("FetchFlag", 2) }
	local name, shown = Action.DebugNpc (ENT, Stack):Stack ()
	T.eq (name, "player", "its class")
	T.eq (shown [1].name, "TacticalMonitor", "outermost first")
	T.eq (shown [2].depth, 2, "indented by the engine's depth")
end)

T.test ("it names its variant by its class", function ()
	T.eq (Action.DebugNpc (ENT, Stack).variant._NAME, "player", "as the layer lists it")
end)

T.test ("a watched stack logs each change to it", function ()
	local logged = {}
	local npc = Action.DebugNpc (ENT, Stack)
	npc:Watch ({ Event = function (_, text) logged [#logged + 1] = text end })
	frames = { Frame ("ScenarioMonitor", 1) }
	npc:Stack ()
	frames = { Frame ("ScenarioMonitor", 1, true), Frame ("DeliverFlag", 1) }
	npc:Stack ()
	npc:Stack ()
	T.eq (#logged, 2, "its first shape and its one change, not each look")
	T.eq (logged [2]:find ("DeliverFlag", 1, true) ~= nil, true, "what it went to")
	T.eq (logged [2]:find ("ScenarioMonitor (suspended)", 1, true) ~= nil, true, "and what it buried")
end)

T.test ("unwatched, nothing is logged", function ()
	local logged = 0
	local npc = Action.DebugNpc (ENT, Stack)
	npc:Watch ({ Event = function () logged = logged + 1 end })
	npc:Watch (nil)
	frames = { Frame ("Other", 1) }
	npc:Stack ()
	T.eq (logged, 0, "no log to write to")
end)

-- An engine as the behaviour sees it, recording what it is told.
local function Engine (frames)
	local told = {}
	return told,
	{
		Insert = function (ent, action, me) told.inserted = { ent, action, me } end,
		Event = function (ent, name, ...) told.event = { ent, name, ... } end,
		Query = function (ent, name, ...) told.query = { ent, name, ... } return "answered" end,
		Stack = function () return frames end,
		End = function (ent) told.ended = ent end
	}
end

T.test ("a behaviour on the engine goes in only when it is started", function ()
	local told, engine = Engine ({})
	local behavior = Action.EngineBehavior (ENT, "first", "actor", "KIND", engine)
	T.eq (told.inserted, nil, "not before the bot's own start")
	behavior:Start ()
	T.eq (told.inserted [1], ENT, "on the bot")
	T.eq (told.inserted [2], "first", "its first action")
	T.eq (told.inserted [3], "actor", "told to the actor, as the chart's are")
end)

T.test ("its events and queries are the engine's, the actor left to the engine", function ()
	local told, engine = Engine ({})
	local behavior = Action.EngineBehavior (ENT, "first", "actor", "KIND", engine)
	behavior:Event ("actor", "OnContact", "other")
	T.eq (told.event [2], "OnContact", "by name")
	T.eq (told.event [3], "other", "with what it was told")
	T.eq (behavior:Query ("actor", "ShouldHurry", 1), "answered", "the engine's answer")
	T.eq (told.query [3], 1, "with what it was asked")
end)

T.test ("the engine updates it: updating does nothing more", function ()
	local told, engine = Engine ({})
	Action.EngineBehavior (ENT, "first", "actor", "KIND", engine):Update ("actor", 0.1)
	T.eq (next (told), nil, "nothing told")
end)

T.test ("it is empty when only the engine's own root is left", function ()
	local _, none = Engine ({ { name = "CLuaBehaviour", depth = 1 } })
	T.eq (Action.EngineBehavior (ENT, "first", "actor", "KIND", none):IsEmpty (), true, "its root alone")
	local _, some = Engine ({ { name = "CLuaBehaviour", depth = 1 }, { name = "Attack", depth = 2 } })
	T.eq (Action.EngineBehavior (ENT, "first", "actor", "KIND", some):IsEmpty (), false, "an action on it")
end)

T.test ("destroying it ends its actions, while its bot is whole", function ()
	local told, engine = Engine ({})
	Action.EngineBehavior (ENT, "first", "actor", "KIND", engine):Destroy ()
	T.eq (told.ended, ENT, "the engine's would come too late")
end)

T.test ("it describes and shows itself by the engine's stack, under its kind", function ()
	local _, engine = Engine ({ { name = "CLuaBehaviour", depth = 1 }, { name = "Attack", depth = 2 } })
	local behavior = Action.EngineBehavior (ENT, "first", "actor", "KIND", engine)
	T.eq (behavior.name, "KIND", "its name")
	T.eq (behavior:Stack () [2].name, "Attack", "the engine's frames")
	T.eq (behavior:Describe ():find ("Attack", 1, true) ~= nil, true, "named")
end)

T.test ("where the binary is not bound, a variant is left to the chart", function ()
	T.eq (Action.EngineBehaviorFor (ENT, "actor", nil), nil, "no engine")
	T.eq (Action.EngineBehaviorFor (ENT, "actor", { refused = "why" }), nil, "refused")
end)

T.test ("where it is, a variant's behaviour is the engine's, telling its actions me", function ()
	local told, engine = Engine ({})
	local behavior = Action.EngineBehaviorFor (ENT, "actor", engine) ("first", "KIND")
	behavior:Start ()
	T.eq (told.inserted [3], "actor", "me")
	T.eq (behavior.name, "KIND", "its kind")
end)

T.test ("a paced behaviour is updated by whoever paces it, and not by the engine's own turn", function ()
	local told, engine = Engine ({})
	engine.Pace = function (ent) told.paced = ent end
	engine.Update = function (ent, interval) told.updated = { ent, interval } end
	local behavior = Action.EngineBehaviorFor (ENT, "actor", engine, true) ("first", "KIND")
	behavior:Start ()
	T.eq (told.paced, ENT, "taken off the engine's own turn as it starts")
	behavior:Update ("actor", 0.25)
	T.eq (told.updated [1], ENT, "run now, on the bot")
	T.eq (told.updated [2], 0.25, "for the time it was given")
end)

T.test ("an unpaced one is left to the engine", function ()
	local told, engine = Engine ({})
	engine.Pace = function (ent) told.paced = ent end
	engine.Update = function () told.updated = true end
	local behavior = Action.EngineBehaviorFor (ENT, "actor", engine) ("first", "KIND")
	behavior:Start ()
	behavior:Update ("actor", 0.25)
	T.eq (told.paced, nil, "not paced")
	T.eq (told.updated, nil, "not run")
end)

T.finish ()
