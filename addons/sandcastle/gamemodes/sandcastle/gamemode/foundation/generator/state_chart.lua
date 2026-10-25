-- A hierarchical statechart: NextBot's Action/Behavior engine
-- (server/NextBot/NextBotBehavior.h) without its stacks. A State may contain
-- a child state, changes to another (ChangeTo) or ends (Done); the engine
-- owns every transition and calls the state's hooks (a template method), so
-- a state only answers them. Events are stored by priority and acted on at
-- the next update; queries are asked from the innermost state out.
--
-- A Chart is the seam a machine is built on. It declares, before any state
-- exists, what its states may see and answer:
--   port     a foundation.core.port: the only actor methods a state can call
--            (states get a facade, never the actor itself)
--   events   the On<Event> names its states handle and Event accepts
--   queries  the names Query accepts
--   initial  initial(states) -> the first state, one of the chart's own
-- chart:State(name) makes a state class that refuses an On* method that is
-- neither a lifecycle hook nor a declared event, and chart:New(actor, states)
-- refuses an actor missing a port method.
--
-- An engine with more (a stack of suspended states) extends State and Root,
-- fills the transitions table and the hooks named _ below, and makes its
-- charts with ChartsOf{ state, root, lifecycle }.
-- Core-rule exception: stays Lua. Its states are Lua hooks; nothing to gain
-- natively.
local Class = core.class
local Port = core.port
local error, ipairs, setmetatable, tostring, type =
	error, ipairs, setmetatable, tostring, type
local concat, find = table.concat, string.find
module(...)

-- ActionResultType, in NextBot's numbers (2 is a stack's SUSPEND_FOR).
CONTINUE, CHANGE_TO, DONE, SUSTAIN = 0, 1, 3, 4

-- EventResultPriorityType
RESULT_NONE, RESULT_TRY, RESULT_IMPORTANT, RESULT_CRITICAL = 0, 1, 2, 3

-- QueryResultType (NextBotContextualQueryInterface.h). A state answers a
-- query by defining a method of the query's name (ShouldAttack(me, them));
-- one without it is undefined. An answer is anything but nil or
-- ANSWER_UNDEFINED.
ANSWER_NO, ANSWER_YES, ANSWER_UNDEFINED = 0, 1, 2

function Result(kind, state, reason, priority)
	return {
		type = kind,
		action = state,
		reason = reason,
		priority = priority,
	}
end

CONTINUE_RESULT = Result(CONTINUE, nil, nil, RESULT_TRY)
NO_EVENT_RESULT = Result(CONTINUE, nil, nil, RESULT_NONE)

-------------------------------------------------------------------------------
-- State

State = {}
State.__index = State
State.name = "State"

-- A subclass named for Describe(); its instances come from :New(...).
function State:Extend(name)
	return Class.Extend(self, { name = name })
end

function State:New(...)
	local state = Class.New(self, self:_Fields())
	state:Init(...)
	return state
end

-- A new state's own fields; an engine with more extends them.
function State:_Fields()
	return {
		_started = false,
		_eventResult = NO_EVENT_RESULT,
	}
end

-- Overridable. Every result-returning hook must return one of the results
-- below.
function State:Init() end
function State:InitialContainedAction(me) return nil end
function State:OnStart(me, priorState) return CONTINUE_RESULT end
function State:Update(me, interval) return CONTINUE_RESULT end
function State:OnEnd(me, nextState) end

-- Results of OnStart and Update.
function State:Continue() return CONTINUE_RESULT end
function State:ChangeTo(state, reason) return Result(CHANGE_TO, state, reason, RESULT_TRY) end
function State:Done(reason) return Result(DONE, nil, reason, RESULT_TRY) end

-- Results of event handlers (On<Event>).
function State:TryContinue(priority) return Result(CONTINUE, nil, nil, priority or RESULT_TRY) end
function State:TryChangeTo(state, priority, reason) return Result(CHANGE_TO, state, reason, priority or RESULT_TRY) end
function State:TryDone(priority, reason) return Result(DONE, nil, reason, priority or RESULT_TRY) end
function State:TryToSustain(priority, reason) return Result(SUSTAIN, nil, reason, priority or RESULT_TRY) end

function State:GetName() return self.name end
function State:GetActor() return self._actor end
function State:GetActiveChildAction() return self._child end
function State:GetParentAction() return self._parent end

-- My lineage, outermost first.
function State:GetFullName()
	local names = {}
	local state = self
	while state do
		names[#names + 1] = state.name
		state = state._parent
	end
	local ordered = {}
	for i = #names, 1, -1 do ordered[#ordered + 1] = names[i] end
	return concat(ordered, "/")
end

-- Whether a result changes the state that gave it.
function State:_RequestsChange(result)
	local kind = result.type
	return kind == CHANGE_TO or kind == DONE
end

-- Whether I am stale before I update; never, without a stack.
function State:_IsOutOfScope()
	return false
end

-- The change an event left on me, once.
function State:_ProcessPendingEvents()
	if self:_RequestsChange(self._eventResult) then
		local result = self._eventResult
		self._eventResult = NO_EVENT_RESULT
		return result
	end
	return CONTINUE_RESULT
end

-- A result of equal or greater priority replaces the stored one; the latest
-- wins a tie.
function State:_StorePendingEventResult(result)
	if result.type == CONTINUE then return end
	if result.priority >= self._eventResult.priority then
		self._eventResult = result
	end
end

-- The child starts before my own OnStart.
function State:_InvokeOnStart(me, root, priorState)
	self._started = true
	self._actor = me
	if priorState then self._parent = priorState._parent end
	if self._parent then self._parent._child = self end
	local child = self:InitialContainedAction(me)
	self._child = child
	if child then
		child._parent = self
		self._child = child:_ApplyResult(me, root, self:ChangeTo(child, "Starting child Action"))
	end
	return self:OnStart(me, priorState)
end

-- Scope, pending events, the child, then myself.
function State:_InvokeUpdate(me, root, interval)
	if self:_IsOutOfScope() then return self:Done("Out of scope") end
	if not self._started then return self:ChangeTo(self, "Starting Action") end
	local eventResult = self:_ProcessPendingEvents()
	if eventResult.type ~= CONTINUE then return eventResult end
	if self._child then
		self._child = self._child:_ApplyResult(me, root, self._child:_InvokeUpdate(me, root, interval))
	end
	return self:Update(me, interval)
end

-- My child, then me.
function State:_InvokeOnEnd(me, root, nextState)
	if not self._started then return end
	self._started = false
	if self._child then self._child:_InvokeOnEnd(me, root, nextState) end
	self:OnEnd(me, nextState)
end

-- result type -> function(state, me, root, result) -> the state now in its
-- place. CONTINUE and SUSTAIN change nothing.
local TRANSITIONS = {}

-- CHANGE_TO: the new state takes my parent.
TRANSITIONS[CHANGE_TO] = function(self, me, root, result)
	local newState = result.action
	if newState == nil then
		error(self.name .. ": ChangeTo needs a state (" .. (result.reason or "no reason") .. ")", 0)
	end
	self:_InvokeOnEnd(me, root, newState)
	local startResult = newState:_InvokeOnStart(me, root, self)
	if self ~= newState then root:_DestroyAction(self) end
	return newState:_ApplyResult(me, root, startResult)
end

-- DONE: nothing takes my place.
TRANSITIONS[DONE] = function(self, me, root, result)
	self:_InvokeOnEnd(me, root, nil)
	root:_DestroyAction(self)
	return nil
end

State.transitions = TRANSITIONS

-- The state now active in my place. A root's watcher (Root:Watch) hears of
-- each change first.
function State:_ApplyResult(me, root, result)
	local apply = self.transitions[result.type]
	if apply == nil then return self end
	local watcher = root.watcher
	if watcher then
		local nextState = result.action
		watcher:Transition(result.type, self.name, nextState and nextState.name, result.reason, nextState == self)
	end
	return apply(self, me, root, result)
end

-- An event's handler on me, its result stored as my pending change.
function State:_HandleEvent(name, ...)
	local handler = self[name]
	if handler then self:_StorePendingEventResult(handler(self, self._actor, ...)) end
end

-- An unstarted state ignores events. I handle it, then my active child.
function State:_ProcessEvent(name, ...)
	if not self._started then return end
	self:_HandleEvent(name, ...)
	if self._child then self._child:_ProcessEvent(name, ...) end
end

-- My answer to a query, or nil.
function State:_AskHere(me, name, ...)
	local handler = self[name]
	if handler then
		local answer = handler(self, me, ...)
		if answer ~= nil and answer ~= ANSWER_UNDEFINED then return answer end
	end
	return nil
end

-- From the innermost state out to stop (exclusive), the first answer.
local function AskOutward(state, stop, me, name, ...)
	while state._child do state = state._child end
	while state and state ~= stop do
		local answer = state:_AskHere(me, name, ...)
		if answer ~= nil then return answer end
		state = state._parent
	end
	return ANSWER_UNDEFINED
end

-- The same query, asked only of the states this one contains (a monitor
-- asking what it runs, as CTFBotTacticalMonitor asks ShouldRetreat).
function State:QueryBelow(me, name, ...)
	if self._child == nil then return ANSWER_UNDEFINED end
	return AskOutward(self._child, self, me, name, ...)
end

-------------------------------------------------------------------------------
-- Root: what runs the outermost state

Root = {}
Root.__index = Root

function Root:New(state, name)
	return Class.New(self, {
		action = state,
		name = name,
		me = nil,
		dead = {},
		watcher = nil,
	})
end

-- A debugger's watcher, or nil to stop: watcher:Transition(resultType,
-- fromName, toName, reason, starting) before each change of state
-- (starting: a state starting itself), and watcher:Event(name) for each
-- event.
function Root:Watch(watcher)
	self.watcher = watcher
end

local function StackFrames(state, depth, frames)
	frames[#frames + 1] = {
		name = state.name,
		depth = depth,
	}
	if state._child then StackFrames(state._child, depth + 1, frames) end
	return frames
end

-- The states, outermost first: a list of { name, depth (1 outermost) }.
function Root:Stack()
	if self.action == nil then return {} end
	return StackFrames(self.action, 1, {})
end

function Root:IsEmpty()
	return self.action == nil
end

function Root:Update(me, interval)
	if self.action == nil then return end
	self.me = me
	self.action = self.action:_ApplyResult(me, self, self.action:_InvokeUpdate(me, self, interval))
	self:_PurgeDeadActions()
end

-- The outermost state takes an event, and hands it in.
function Root:Event(me, name, ...)
	if self.action == nil then return end
	if self.watcher then self.watcher:Event(name) end
	self.action:_ProcessEvent(name, ...)
end

-- A contextual query (NextBotBehavior.h): from the innermost active state
-- out, the first answer that is not undefined.
function Root:Query(me, name, ...)
	if self.action == nil then return ANSWER_UNDEFINED end
	return AskOutward(self.action, nil, me, name, ...)
end

-- The states end, if the machine ever ran.
function Root:Destroy()
	if self.me and self.action then
		self.action:_InvokeOnEnd(self.me, self, nil)
	end
	self.action = nil
end

-- The full name of the innermost active state, e.g. "Watch/Look".
function Root:Describe()
	local state = self.action
	if state == nil then return "" end
	while state._child do state = state._child end
	return state:GetFullName()
end

-- A state's deletion waits for the end of Update; then a dead state is no
-- longer its parent's active child.
function Root:_DestroyAction(state)
	self.dead[#self.dead + 1] = state
end

function Root:_PurgeDeadActions()
	for _, dead in ipairs(self.dead) do
		if dead._parent and dead._parent._child == dead then
			dead._parent._child = nil
		end
	end
	self.dead = {}
end

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

local EVENT_NAME = "^On%u"

-- The guard on a chart's state classes: an On* name must be a lifecycle
-- hook or one of the chart's events.
local function StateGuard(chart)
	return function(key)
		if type(key) == "string" and find(key, EVENT_NAME) and not chart.lifecycle[key] and not chart.events[key] then
			return chart.name .. ": " .. key .. " is not a lifecycle hook or an event of the chart"
		end
	end
end

-- The Chart function of an engine: its state class, its root class, and the
-- On* hooks its states may define.
function ChartsOf(engine)
	local lifecycle = NameSet(engine.lifecycle)
	return function(spec)
		local name = Name(spec.name, "a chart")
		if not Port.Is(spec.port) then error("chart " .. name .. " needs a Port", 2) end
		if type(spec.initial) ~= "function" then error("chart " .. name .. " needs initial(states)", 2) end
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
			lifecycle = lifecycle,
			root = engine.root,
		}, ChartClass)
		chart.base = Class.Guard(engine.state:Extend(name), StateGuard(chart))
		return chart
	end
end

-- Chart{ name, port, events?, queries?, initial }.
Chart = ChartsOf({
	state = State,
	root = Root,
	lifecycle = { "OnStart", "OnEnd" },
})

-- A new state class of this chart; extend it further with :Extend(name).
function ChartClass:State(name)
	return self.base:Extend(Name(name, "a state"))
end

function ChartClass:Owns(state)
	return Class.IsA(state, self.base)
end

-- A machine running this chart over the actor; states is what initial reads.
function ChartClass:New(actor, states)
	local me = self.port:Facade(self.port:Check(actor))
	local first = self.initial(states)
	if not self:Owns(first) then
		error("chart " .. self.name .. ": initial gave a state of another chart", 2)
	end
	return setmetatable({
		chart = self,
		me = me,
		root = self.root:New(first, self.name),
	}, MachineClass)
end

-------------------------------------------------------------------------------
-- Machine: one actor's running chart

function MachineClass:Update(interval) self.root:Update(self.me, interval) end

function MachineClass:Event(name, ...)
	if not self.chart.events[name] then error("chart " .. self.chart.name .. " has no event " .. tostring(name), 2) end
	self.root:Event(self.me, name, ...)
end

function MachineClass:Query(name, ...)
	if not self.chart.queries[name] then error("chart " .. self.chart.name .. " has no query " .. tostring(name), 2) end
	return self.root:Query(self.me, name, ...)
end

function MachineClass:Describe() return self.root:Describe() end
function MachineClass:IsEmpty() return self.root:IsEmpty() end
function MachineClass:Stack() return self.root:Stack() end
function MachineClass:Watch(watcher) self.root:Watch(watcher) end
function MachineClass:Destroy() self.root:Destroy() end
