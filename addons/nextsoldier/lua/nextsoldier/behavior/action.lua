-- An action the engine runs (native/nextsoldier's Action<CLuaNextBot>): a class of
-- hooks, which the engine calls with the action, then the soldier and what the hook
-- is told. OnStart, Update, OnSuspend and OnResume answer a result, an event's hook
-- (OnInjured) a Try result, a query's (ShouldHurry) an answer. NextBotBehavior.h's.
local setmetatable = setmetatable
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
