-- A hierarchical state machine: a port of NextBot's Action/Behavior engine
-- (server/NextBot/NextBotBehavior.h), handing on its timers
-- (foundation.core.timers) by the names actions use.
-- An Action is a state (the State pattern) that may contain a child state
-- and bury the states it suspends; the engine owns every transition and
-- calls the state's hooks (a template method), so a state only answers
-- them. foundation.npc runs its variants and NextSoldier's orders on it.
--
-- A Chart is the seam a new machine is built on. It declares, before any
-- state exists, what its states may see and answer:
--   port     a foundation.core.meta.port: the only actor methods a state can call
--            (states get a facade, never the actor itself)
--   events   the On<Event> names its states handle and Event accepts
--   queries  the names Query accepts
--   initial  initial(state) -> the first Action, one of the chart's own
-- chart:State(name) makes a state class that refuses an On* method that is
-- neither a lifecycle hook nor a declared event, and chart:New(actor, state)
-- refuses an actor missing a port method. So each state does one job behind
-- one contract, new states extend the chart without editing it, and states
-- depend on the port the composition root fills, not on an entity.
local Class = require("foundation.core.meta.class")
local Port = require("foundation.core.meta.port")
local Timers = require("foundation.core.timers")
local error, ipairs, setmetatable, tostring, type =
	error, ipairs, setmetatable, tostring, type
local concat, find = table.concat, string.find
module(...)

-- ActionResultType
CONTINUE, CHANGE_TO, SUSPEND_FOR, DONE, SUSTAIN = 0, 1, 2, 3, 4

-- EventResultPriorityType
RESULT_NONE, RESULT_TRY, RESULT_IMPORTANT, RESULT_CRITICAL = 0, 1, 2, 3

-- QueryResultType (NextBotContextualQueryInterface.h). An action answers a
-- query by defining a method of the query's name (ShouldAttack(me, them),
-- ShouldHurry(me), ShouldRetreat(me)...); one without it is undefined.
ANSWER_NO, ANSWER_YES, ANSWER_UNDEFINED = 0, 1, 2

-- IntervalTimer::GetElapsedTime when unstarted.
INTERVAL_UNSTARTED = Timers.INTERVAL_UNSTARTED

local function Result(kind, action, reason, priority)
	return {
		type = kind,
		action = action,
		reason = reason,
		priority = priority,
	}
end

local CONTINUE_RESULT = Result(CONTINUE, nil, nil, RESULT_TRY)
local NO_EVENT_RESULT = Result(CONTINUE, nil, nil, RESULT_NONE)

local function IsRequestingChange(result)
	local kind = result.type
	return kind == CHANGE_TO or kind == SUSPEND_FOR or kind == DONE
end

-------------------------------------------------------------------------------
-- Action

Action = {}
Action.__index = Action
Action.name = "Action"
-- What the debug layer's notations need of a class (foundation.npc.debug's
-- Tdbn): a passthrough only contains the action that does the work, as a
-- monitor does, and a short name, when set, stands for the name there.
Action.passthrough = false
Action.shortName = nil

-- A subclass named for Describe(); its instances come from :New(...).
function Action:Extend(name)
	return Class.Extend(self, { name = name })
end

function Action:New(...)
	local action = Class.New(self, {
		_parent = nil,
		_child = nil,
		_buried = nil,
		_covering = nil,
		_actor = nil,
		_started = false,
		_suspended = false,
		_eventResult = NO_EVENT_RESULT,
	})
	action:Init(...)
	return action
end

-- Overridable. Every result-returning hook must return one of the results
-- below.
function Action:Init() end
function Action:InitialContainedAction(me) return nil end
function Action:OnStart(me, priorAction) return CONTINUE_RESULT end
function Action:Update(me, interval) return CONTINUE_RESULT end
function Action:OnEnd(me, nextAction) end
function Action:OnSuspend(me, interruptingAction) return CONTINUE_RESULT end
function Action:OnResume(me, interruptingAction) return CONTINUE_RESULT end

-- Results of OnStart, Update, OnSuspend and OnResume.
function Action:Continue() return CONTINUE_RESULT end
function Action:ChangeTo(action, reason) return Result(CHANGE_TO, action, reason, RESULT_TRY) end
function Action:Done(reason) return Result(DONE, nil, reason, RESULT_TRY) end

-- Action::SuspendFor clears any pending event transition, or the new action
-- would at once be out of scope.
function Action:SuspendFor(action, reason)
	self._eventResult = NO_EVENT_RESULT
	return Result(SUSPEND_FOR, action, reason, RESULT_TRY)
end

-- Results of event handlers (On<Event>).
function Action:TryContinue(priority) return Result(CONTINUE, nil, nil, priority or RESULT_TRY) end
function Action:TryChangeTo(action, priority, reason) return Result(CHANGE_TO, action, reason, priority or RESULT_TRY) end
function Action:TrySuspendFor(action, priority, reason) return Result(SUSPEND_FOR, action, reason, priority or RESULT_TRY) end
function Action:TryDone(priority, reason) return Result(DONE, nil, reason, priority or RESULT_TRY) end
function Action:TryToSustain(priority, reason) return Result(SUSTAIN, nil, reason, priority or RESULT_TRY) end

function Action:GetName() return self.name end
function Action:GetActor() return self._actor end
function Action:GetActiveChildAction() return self._child end
function Action:GetParentAction() return self._parent end
function Action:GetActionBuriedUnderMe() return self._buried end
function Action:IsSuspended() return self._suspended end

-- Action::GetFullName: my lineage, outermost first.
function Action:GetFullName()
	local names = {}
	local action = self
	while action do
		names[#names + 1] = action.name
		action = action._parent
	end
	local ordered = {}
	for i = #names, 1, -1 do ordered[#ordered + 1] = names[i] end
	return concat(ordered, "/")
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
	if IsRequestingChange(self._eventResult) then
		local result = self._eventResult
		self._eventResult = NO_EVENT_RESULT
		return result
	end
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

-- Action::StorePendingEventResult: a result of equal or greater priority
-- replaces the stored one; the latest wins a tie.
function Action:_StorePendingEventResult(result)
	if result.type == CONTINUE then return end
	if result.priority >= self._eventResult.priority then
		self._eventResult = result
	end
end

-- Action::InvokeOnStart: the child starts before my own OnStart.
function Action:_InvokeOnStart(me, behavior, priorAction, buriedUnderMe)
	self._started = true
	self._actor = me
	if priorAction then self._parent = priorAction._parent end
	if self._parent then self._parent._child = self end
	self._buried = buriedUnderMe
	if buriedUnderMe then buriedUnderMe._covering = self end
	self._covering = nil
	local child = self:InitialContainedAction(me)
	self._child = child
	if child then
		child._parent = self
		self._child = child:_ApplyResult(me, behavior, self:ChangeTo(child, "Starting child Action"))
	end
	return self:OnStart(me, priorAction)
end

-- Action::InvokeUpdate: scope, pending events, the child, then myself.
function Action:_InvokeUpdate(me, behavior, interval)
	if self:_IsOutOfScope() then return self:Done("Out of scope") end
	if not self._started then return self:ChangeTo(self, "Starting Action") end
	local eventResult = self:_ProcessPendingEvents()
	if eventResult.type ~= CONTINUE then return eventResult end
	if self._child then
		self._child = self._child:_ApplyResult(me, behavior, self._child:_InvokeUpdate(me, behavior, interval))
	end
	return self:Update(me, interval)
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
	if IsRequestingChange(self._eventResult) then return CONTINUE_RESULT end
	self._suspended = false
	self._covering = nil
	if self._parent then self._parent._child = self end
	if self._child then
		self._child = self._child:_ApplyResult(me, behavior, self._child:_InvokeOnResume(me, behavior, interruptingAction))
	end
	return self:OnResume(me, interruptingAction)
end

local APPLY = {}

-- CHANGE_TO: the new action takes my parent and my buried action.
APPLY[CHANGE_TO] = function(self, me, behavior, result)
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
APPLY[SUSPEND_FOR] = function(self, me, behavior, result)
	local newAction = result.action
	local top = self
	while top._covering do top = top._covering end
	top = top:_InvokeOnSuspend(me, behavior, newAction)
	local startResult = newAction:_InvokeOnStart(me, behavior, top, top)
	return newAction:_ApplyResult(me, behavior, startResult)
end

-- DONE: resume the buried action, or leave the stack empty.
APPLY[DONE] = function(self, me, behavior, result)
	local resumed = self._buried
	self:_InvokeOnEnd(me, behavior, resumed)
	behavior:_DestroyAction(self)
	if resumed == nil then return nil end
	local resumeResult = resumed:_InvokeOnResume(me, behavior, self)
	return resumed:_ApplyResult(me, behavior, resumeResult)
end

-- Action::ApplyResult: returns the action now active in my place. A
-- Behavior's watcher (Behavior:Watch) hears of each change first.
function Action:_ApplyResult(me, behavior, result)
	local apply = APPLY[result.type]
	if apply == nil then return self end -- CONTINUE and SUSTAIN
	local watcher = behavior.watcher
	if watcher then
		local nextAction = result.action
		watcher:Transition(result.type, self.name, nextAction and nextAction.name, result.reason, nextAction == self)
	end
	return apply(self, me, behavior, result)
end

-- PROCESS_EVENT: an unstarted action ignores events. The event walks me and
-- the actions buried under me while each continues; the first other result
-- is stored on the action that gave it. Then it goes to my active child.
function Action:_ProcessEvent(name, ...)
	if not self._started then return end
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
	if self._child then self._child:_ProcessEvent(name, ...) end
end

-------------------------------------------------------------------------------
-- Behavior: the root of an action stack

Behavior = {}
Behavior.__index = Behavior

function Behavior:New(action, name)
	return setmetatable({
		action = action,
		name = name,
		me = nil,
		dead = {},
		watcher = nil,
	}, Behavior)
end

-- A debugger's watcher, or nil to stop: watcher:Transition(resultType,
-- fromName, toName, reason, starting) before each change of action
-- (starting: an action starting itself), and watcher:Event(name) for each
-- event, as nb_debug BEHAVIOR prints them.
function Behavior:Watch(watcher)
	self.watcher = watcher
end

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

function Behavior:IsEmpty()
	return self.action == nil
end

-- Behavior::Update
function Behavior:Update(me, interval)
	if self.action == nil then return end
	self.me = me
	self.action = self.action:_ApplyResult(me, self, self.action:_InvokeUpdate(me, self, interval))
	self:_PurgeDeadActions()
end

-- Behavior's event responder: the top action of the stack takes it.
function Behavior:Event(me, name, ...)
	if self.action == nil then return end
	if self.watcher then self.watcher:Event(name) end
	self.action:_ProcessEvent(name, ...)
end

-- Behavior's contextual query (NextBotBehavior.h): from the innermost
-- active child, ask each action and the actions buried under it, then move
-- out to the containing action and do the same; the first answer that is
-- not undefined wins. An answer is anything but nil or ANSWER_UNDEFINED
-- (SelectMoreDangerousThreat answers with a threat).
function Behavior:Query(me, name, ...)
	local action = self.action
	if action == nil then return ANSWER_UNDEFINED end
	while action._child do action = action._child end
	while action do
		local container = action._parent
		local current = action
		while current do
			local handler = current[name]
			if handler then
				local answer = handler(current, me, ...)
				if answer ~= nil and answer ~= ANSWER_UNDEFINED then return answer end
			end
			current = current._buried
		end
		action = container
	end
	return ANSWER_UNDEFINED
end

-- The same query, asked only of the actions this one contains: from its
-- innermost active child out, stopping before this action itself (a
-- monitor asking what it runs, as CTFBotTacticalMonitor asks ShouldRetreat).
function Action:QueryBelow(me, name, ...)
	local action = self._child
	if action == nil then return ANSWER_UNDEFINED end
	while action._child do action = action._child end
	while action and action ~= self do
		local container = action._parent
		local current = action
		while current do
			local handler = current[name]
			if handler then
				local answer = handler(current, me, ...)
				if answer ~= nil and answer ~= ANSWER_UNDEFINED then return answer end
			end
			current = current._buried
		end
		action = container
	end
	return ANSWER_UNDEFINED
end

-- ~Behavior: the actions end, if the behavior ever ran.
function Behavior:Destroy()
	if self.me and self.action then
		self.action:_InvokeOnEnd(self.me, self, nil)
	end
	self.action = nil
end

-- The full name of the innermost active action, e.g. "ZombieBehavior/Attack".
function Behavior:Describe()
	local action = self.action
	if action == nil then return "" end
	while action._child do action = action._child end
	return action:GetFullName()
end

-- Behavior::DestroyAction defers deletion to the end of Update. ~Action then
-- unlinks the dead action: its parent's active child falls back to its
-- buried action, and its buried action is no longer covered.
function Behavior:_DestroyAction(action)
	self.dead[#self.dead + 1] = action
end

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
-- Timers: core's, by the names actions use.

CountdownTimer, IntervalTimer = Timers.CountdownTimer, Timers.IntervalTimer

-------------------------------------------------------------------------------
-- Names a chart declares

local function NameList(names, what)
	if type(names) ~= "table" then error(what .. " must be a list of names", 3) end
	for _, name in ipairs(names) do
		if type(name) ~= "string" then error(what .. " has a non-name: " .. tostring(name), 3) end
	end
	return names
end

local function NameSet(names)
	local set = {}
	for _, name in ipairs(names) do set[name] = true end
	return set
end

local function Name(value, what)
	if type(value) ~= "string" or value == "" then error(what .. " needs a name", 3) end
	return value
end

-------------------------------------------------------------------------------
-- Chart: a statechart's contract, and the factory of its states and machines

local ChartClass, MachineClass = {}, {}
ChartClass.__index = ChartClass
MachineClass.__index = MachineClass

local LIFECYCLE = NameSet({ "OnStart", "OnEnd", "OnSuspend", "OnResume" })
local EVENT_NAME = "^On%u"

-- The guard on a chart's state classes: an On* name must be a lifecycle
-- hook or one of the chart's events.
local function StateGuard(chart)
	return function(key)
		if type(key) == "string" and find(key, EVENT_NAME) and not LIFECYCLE[key] and not chart.events[key] then
			return chart.name .. ": " .. key .. " is not a lifecycle hook or an event of the chart"
		end
	end
end

-- Chart{ name, port, events?, queries?, initial }.
function Chart(spec)
	local name = Name(spec.name, "a chart")
	if not Port.Is(spec.port) then error("chart " .. name .. " needs a Port", 2) end
	if type(spec.initial) ~= "function" then error("chart " .. name .. " needs initial(state)", 2) end
	local events = NameList(spec.events or {}, "chart " .. name .. "'s events")
	for _, event in ipairs(events) do
		if not find(event, EVENT_NAME) then error("chart " .. name .. ": event " .. event .. " must start On", 2) end
	end
	local chart = setmetatable({
		name = name,
		port = spec.port,
		events = NameSet(events),
		queries = NameSet(NameList(spec.queries or {}, "chart " .. name .. "'s queries")),
		initial = spec.initial,
	}, ChartClass)
	chart.base = Class.Guard(Action:Extend(name), StateGuard(chart))
	return chart
end

-- A new state class of this chart; extend it further with :Extend(name).
function ChartClass:State(name)
	return self.base:Extend(Name(name, "a state"))
end

function ChartClass:Owns(action)
	return Class.IsA(action, self.base)
end

-- A machine running this chart over the actor; state is what initial reads.
function ChartClass:New(actor, state)
	local me = self.port:Facade(self.port:Check(actor))
	local first = self.initial(state)
	if not self:Owns(first) then
		error("chart " .. self.name .. ": initial gave a state of another chart", 2)
	end
	return setmetatable({
		chart = self,
		me = me,
		behavior = Behavior:New(first, self.name),
	}, MachineClass)
end

-------------------------------------------------------------------------------
-- Machine: one actor's running chart


function MachineClass:Update(interval) self.behavior:Update(self.me, interval) end

function MachineClass:Event(name, ...)
	if not self.chart.events[name] then error("chart " .. self.chart.name .. " has no event " .. tostring(name), 2) end
	self.behavior:Event(self.me, name, ...)
end

function MachineClass:Query(name, ...)
	if not self.chart.queries[name] then error("chart " .. self.chart.name .. " has no query " .. tostring(name), 2) end
	return self.behavior:Query(self.me, name, ...)
end

function MachineClass:Describe() return self.behavior:Describe() end
function MachineClass:IsEmpty() return self.behavior:IsEmpty() end
function MachineClass:Stack() return self.behavior:Stack() end
function MachineClass:Watch(watcher) self.behavior:Watch(watcher) end
function MachineClass:Destroy() self.behavior:Destroy() end

