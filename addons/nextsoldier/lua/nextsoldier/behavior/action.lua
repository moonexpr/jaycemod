-- An action the engine runs (native/nextsoldier's Action<CLuaNextBot>): a class of
-- hooks, which the engine calls with the action, then the soldier and what the hook
-- is told. OnStart, Update, OnSuspend and OnResume answer a result, an event's hook
-- (OnInjured) a Try result, a query's (ShouldHurry) an answer. NextBotBehavior.h's.
local ipairs, setmetatable = ipairs, setmetatable
local concat = table.concat
module("nextsoldier.behavior.action")

CONTINUE, CHANGE_TO, SUSPEND_FOR, DONE = 0, 1, 2, 3
RESULT_TRY, RESULT_IMPORTANT, RESULT_CRITICAL = 1, 2, 3
ANSWER_NO, ANSWER_YES, ANSWER_UNDEFINED = 0, 1, 2

local Base = {}
Base.__index = Base

-- A class of action named for the engine's debug output and stack.
function Extend(name)
	local class = setmetatable({ name = name }, Base)
	class.__index = class
	return class
end

function Base:New(fields)
	return setmetatable(fields or {}, self)
end

function Base:Continue() return { type = CONTINUE } end
function Base:ChangeTo(action, reason) return { type = CHANGE_TO, action = action, reason = reason } end
function Base:SuspendFor(action, reason) return { type = SUSPEND_FOR, action = action, reason = reason } end
function Base:Done(reason) return { type = DONE, reason = reason } end

function Base:TryContinue() return { type = CONTINUE } end
function Base:TryChangeTo(action, priority, reason)
	return { type = CHANGE_TO, action = action, priority = priority, reason = reason }
end
function Base:TrySuspendFor(action, priority, reason)
	return { type = SUSPEND_FOR, action = action, priority = priority, reason = reason }
end
function Base:TryDone(priority, reason) return { type = DONE, priority = priority, reason = reason } end

local function Shape(frames)
	local parts = {}
	for i, frame in ipairs(frames) do
		parts[i] = frame.name .. (frame.suspended and " (suspended)" or "")
	end
	return concat(parts, " > ")
end

-- What the debug layer shows of ent, whose actions the engine runs: stack(ent) gives
-- them (engine.Stack). The engine tells nothing as it changes them, so a watched log
-- hears each change as the layer looks.
function DebugNpc(ent, stack)
	local log, shape
	local npc = { variant = { _NAME = ent:GetClass() } }
	function npc:Stack()
		local frames = stack(ent)
		local now = Shape(frames)
		if log and now ~= shape then log:Event(now) end
		shape = now
		return ent:GetClass(), frames
	end
	function npc:Watch(watching)
		log, shape = watching, nil
	end
	return npc
end

-- A behaviour the engine runs, answering what generator.state_chart's root does, so what
-- was written for the chart runs on it: me is told to its actions, and the bot's start
-- (Start) is the first moment a link under its CLuaBehaviour holds.
local EngineRoot = {}
EngineRoot.__index = EngineRoot

function EngineBehavior(ent, initial, me, kind, engine)
	return setmetatable({
		ent = ent,
		initial = initial,
		me = me,
		name = kind,
		engine = engine,
		debug = DebugNpc(ent, engine.Stack),
	}, EngineRoot)
end

function EngineRoot:Start() self.engine.Insert(self.ent, self.initial, self.me) end
function EngineRoot:Update() end
function EngineRoot:Event(_, name, ...) self.engine.Event(self.ent, name, ...) end
function EngineRoot:Query(_, name, ...) return self.engine.Query(self.ent, name, ...) end
function EngineRoot:Destroy() self.engine.End(self.ent) end
function EngineRoot:Watch(log) self.debug:Watch(log) end

function EngineRoot:Stack()
	local _, frames = self.debug:Stack()
	return frames
end

-- A bot's stack holds its own CLuaBehaviour under what it runs.
function EngineRoot:IsEmpty() return #self:Stack() <= 1 end

function EngineRoot:Describe()
	local frames = self:Stack()
	return Shape(frames)
end
