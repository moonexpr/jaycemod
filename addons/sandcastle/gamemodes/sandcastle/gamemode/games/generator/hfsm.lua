-- NextBot's Action/Behavior engine (server/NextBot/NextBotBehavior.h): the
-- statechart of foundation.generator.state_chart, with stacks. An Action
-- may also suspend itself for another (SuspendFor), which goes on top and
-- buries it until done; a buried action hears events and queries after the
-- one covering it, and leaving or changing makes those above it stale. It
-- hands on NextBot's timers (games.timer.countdown, games.timer.interval) by
-- the names actions use. games.npc.nextbot runs its variants and NextSoldier's
-- orders on it.
--
-- Chart{ name, port, events?, queries?, initial } as state_chart's, its
-- states Actions, which may also define OnSuspend and OnResume.
local Class = require("foundation.core.class")
local StateChart = require("foundation.generator.state_chart")
local Countdown = require("games.timer.countdown")
local Interval = require("games.timer.interval")
local error, ipairs = error, ipairs
module(...)

-- ActionResultType
CONTINUE, CHANGE_TO, DONE, SUSTAIN = StateChart.CONTINUE, StateChart.CHANGE_TO, StateChart.DONE, StateChart.SUSTAIN
SUSPEND_FOR = 2

-- EventResultPriorityType
RESULT_NONE, RESULT_TRY, RESULT_IMPORTANT, RESULT_CRITICAL =
	StateChart.RESULT_NONE, StateChart.RESULT_TRY, StateChart.RESULT_IMPORTANT, StateChart.RESULT_CRITICAL

-- QueryResultType: an action answers a query by defining a method of the
-- query's name (ShouldAttack(me, them), ShouldHurry(me), ShouldRetreat(me)...).
ANSWER_NO, ANSWER_YES, ANSWER_UNDEFINED = StateChart.ANSWER_NO, StateChart.ANSWER_YES, StateChart.ANSWER_UNDEFINED

-- IntervalTimer::GetElapsedTime when unstarted.
INTERVAL_UNSTARTED = Interval.INTERVAL_UNSTARTED

local State, Root, Result = StateChart.State, StateChart.Root, StateChart.Result
local CONTINUE_RESULT, NO_EVENT_RESULT = StateChart.CONTINUE_RESULT, StateChart.NO_EVENT_RESULT

-------------------------------------------------------------------------------
-- Action: a state that can be buried under the one it suspends for

-- What the debug layer's notations need of a class (foundation.npc.debug's
-- Tdbn): a passthrough only contains the action that does the work, as a
-- monitor does, and a short name, when set, stands for the name there.
Action = Class.Extend(State, {
	name = "Action",
	passthrough = false,
	shortName = nil,
})

function Action:_Fields()
	local fields = State._Fields(self)
	fields._suspended = false
	return fields
end

-- Overridable, as state_chart's hooks are.
function Action:OnSuspend(me, interruptingAction) return CONTINUE_RESULT end
function Action:OnResume(me, interruptingAction) return CONTINUE_RESULT end

-- Action::SuspendFor clears any pending event transition, or the new action
-- would at once be out of scope.
function Action:SuspendFor(action, reason)
	self._eventResult = NO_EVENT_RESULT
	return Result(SUSPEND_FOR, action, reason, RESULT_TRY)
end

function Action:TrySuspendFor(action, priority, reason) return Result(SUSPEND_FOR, action, reason, priority or RESULT_TRY) end

function Action:GetActionBuriedUnderMe() return self._buried end
function Action:IsSuspended() return self._suspended end

function Action:_RequestsChange(result)
	local kind = result.type
	return kind == CHANGE_TO or kind == SUSPEND_FOR or kind == DONE
end

-- Action::IsOutOfScope: a buried action leaving or changing makes me stale.
function Action:_IsOutOfScope()
	local under = self._buried
	while under do
		local kind = under._eventResult.type
		if kind == CHANGE_TO or kind == DONE then return true end
		under = under._buried
	end
	return false
end

-- Action::ProcessPendingEvents: my own requested change first, then a
-- SUSPEND_FOR left on an action buried under me.
function Action:_ProcessPendingEvents()
	local own = State._ProcessPendingEvents(self)
	if own ~= CONTINUE_RESULT then return own end
	local under = self._buried
	while under do
		if under._eventResult.type == SUSPEND_FOR then
			local result = under._eventResult
			under._eventResult = NO_EVENT_RESULT
			return result
		end
		under = under._buried
	end
	return CONTINUE_RESULT
end

-- Action::InvokeOnStart: I cover the action buried under me.
function Action:_InvokeOnStart(me, behavior, priorAction, buriedUnderMe)
	self._buried = buriedUnderMe
	if buriedUnderMe then buriedUnderMe._covering = self end
	self._covering = nil
	return State._InvokeOnStart(self, me, behavior, priorAction)
end

-- Action::InvokeOnEnd: my children, top down, then me, then whatever covers me.
function Action:_InvokeOnEnd(me, behavior, nextAction)
	if not self._started then return end
	self._started = false
	local child = self._child
	while child do
		local nextChild = child._buried
		child:_InvokeOnEnd(me, behavior, nextAction)
		child = nextChild
	end
	self:OnEnd(me, nextAction)
	if self._covering then self._covering:_InvokeOnEnd(me, behavior, nextAction) end
end

-- Action::InvokeOnSuspend: returns the action now on top, which is my buried
-- one when OnSuspend asks to be Done instead.
function Action:_InvokeOnSuspend(me, behavior, interruptingAction)
	if self._child then
		self._child = self._child:_InvokeOnSuspend(me, behavior, interruptingAction)
	end
	self._suspended = true
	local result = self:OnSuspend(me, interruptingAction)
	if result.type == DONE then
		self:_InvokeOnEnd(me, behavior, nil)
		local buried = self._buried
		behavior:_DestroyAction(self)
		return buried
	end
	return self
end

-- Action::InvokeOnResume: skipped while a change from an event is pending.
function Action:_InvokeOnResume(me, behavior, interruptingAction)
	if not self._suspended then return CONTINUE_RESULT end
	if self:_RequestsChange(self._eventResult) then return CONTINUE_RESULT end
	self._suspended = false
	self._covering = nil
	if self._parent then self._parent._child = self end
	if self._child then
		self._child = self._child:_ApplyResult(me, behavior, self._child:_InvokeOnResume(me, behavior, interruptingAction))
	end
	return self:OnResume(me, interruptingAction)
end

local TRANSITIONS = {}

-- CHANGE_TO: the new action takes my parent and my buried action.
TRANSITIONS[CHANGE_TO] = function(self, me, behavior, result)
	local newAction = result.action
	if newAction == nil then
		error(self.name .. ": ChangeTo needs an action (" .. (result.reason or "no reason") .. ")", 0)
	end
	self:_InvokeOnEnd(me, behavior, newAction)
	local startResult = newAction:_InvokeOnStart(me, behavior, self, self._buried)
	if self ~= newAction then behavior:_DestroyAction(self) end
	return newAction:_ApplyResult(me, behavior, startResult)
end

-- SUSPEND_FOR: the new action always goes on top of the stack.
TRANSITIONS[SUSPEND_FOR] = function(self, me, behavior, result)
	local newAction = result.action
	local top = self
	while top._covering do top = top._covering end
	top = top:_InvokeOnSuspend(me, behavior, newAction)
	local startResult = newAction:_InvokeOnStart(me, behavior, top, top)
	return newAction:_ApplyResult(me, behavior, startResult)
end

-- DONE: resume the buried action, or leave the stack empty.
TRANSITIONS[DONE] = function(self, me, behavior, result)
	local resumed = self._buried
	self:_InvokeOnEnd(me, behavior, resumed)
	behavior:_DestroyAction(self)
	if resumed == nil then return nil end
	local resumeResult = resumed:_InvokeOnResume(me, behavior, self)
	return resumed:_ApplyResult(me, behavior, resumeResult)
end

Action.transitions = TRANSITIONS

-- PROCESS_EVENT: the event walks me and the actions buried under me while
-- each continues; the first other result is stored on the action that gave
-- it.
function Action:_HandleEvent(name, ...)
	local action, result = self, nil
	while action do
		local handler = action[name]
		if handler then
			result = handler(action, self._actor, ...)
		else
			result = CONTINUE_RESULT
		end
		if result.type ~= CONTINUE then break end
		action = action._buried
	end
	if action then action:_StorePendingEventResult(result) end
end

-- A query asks me, then the actions buried under me.
function Action:_AskHere(me, name, ...)
	local current = self
	while current do
		local answer = State._AskHere(current, me, name, ...)
		if answer ~= nil then return answer end
		current = current._buried
	end
	return nil
end

-------------------------------------------------------------------------------
-- Behavior: the root of an action stack

Behavior = Class.Extend(Root)

local function StackFrames(action, depth, frames)
	while action do
		frames[#frames + 1] = {
			name = action.name,
			short = action.shortName or action.name,
			depth = depth,
			suspended = action._suspended,
			passthrough = action.passthrough,
		}
		if action._child then StackFrames(action._child, depth + 1, frames) end
		action = action._buried
	end
	return frames
end

-- The whole action stack in Action::DebugString's order: each action, then
-- the actions it contains a level deeper, then the actions buried under it.
-- A list of { name, short, depth (1 outermost), suspended, passthrough }.
function Behavior:Stack()
	return StackFrames(self.action, 1, {})
end

-- ~Action unlinks a dead action: its parent's active child falls back to
-- its buried action, and its buried action is no longer covered.
function Behavior:_PurgeDeadActions()
	for _, dead in ipairs(self.dead) do
		if dead._parent and dead._parent._child == dead then
			dead._parent._child = dead._buried
		end
		if dead._buried then dead._buried._covering = nil end
	end
	self.dead = {}
end

-------------------------------------------------------------------------------
-- Timers: game's, by the names actions use.

CountdownTimer, IntervalTimer = Countdown.New, Interval.New

-------------------------------------------------------------------------------
-- Chart

Chart = StateChart.ChartsOf({
	state = Action,
	root = Behavior,
	lifecycle = { "OnStart", "OnEnd", "OnSuspend", "OnResume" },
})
