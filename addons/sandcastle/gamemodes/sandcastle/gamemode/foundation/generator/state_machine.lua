-- A classical finite state machine: one flat state at a time, as the
-- gamerules' round states (State_Transition, State_Enter, State_Leave,
-- State_Think in teamplayroundbased_gamerules.cpp) and the Sandbox/Gameplay
-- mode run. For states that nest or suspend each other, use
-- foundation.core.hfsm.
--
-- Define(spec) parses a machine's definition once and keeps its own copy:
--   name         what errors call it
--   states       the list of its states (any values but nil), no repeats
--   transitions  optional: state -> the list of states it may go to; when
--                given, any other move is refused
--   enter, leave, think  optional: state -> fn(...)
--   changing     optional: fn(from, to, ...), the transition action every
--                move runs once the state is set, before the enter handler
-- Every state named anywhere must be declared, so a mistyped state is an
-- error at load, not a machine stuck at run time. definition:New(initial)
-- makes a machine; its handlers get whatever its caller passes along.
local Sets = require("foundation.map.sets")
local error, ipairs, pairs, setmetatable, tostring, type = error, ipairs, pairs, setmetatable, tostring, type
module(...)

local HANDLER_KINDS = { "enter", "leave", "think" }

local Definition = {}
Definition.__index = Definition

local Machine = {}
Machine.__index = Machine

local function Refuse(name, why)
	error("state machine " .. tostring(name) .. ": " .. why, 3)
end

local function Declared(def, state, where)
	if not def.states:Has(state) then Refuse(def.name, where .. " names undeclared state " .. tostring(state)) end
	return state
end

local function Handlers(def, kind, given)
	local handlers = {}
	for state, fn in pairs(given or {}) do
		Declared(def, state, kind)
		if type(fn) ~= "function" then Refuse(def.name, kind .. " for " .. tostring(state) .. " is not a function") end
		handlers[state] = fn
	end
	return handlers
end

local function Edges(def, given)
	if given == nil then return nil end
	local edges = {}
	for from, targets in pairs(given) do
		Declared(def, from, "transitions")
		edges[from] = {}
		for _, to in ipairs(targets) do edges[from][Declared(def, to, "transitions from " .. tostring(from))] = true end
	end
	return edges
end

function Define(spec)
	local name = spec.name
	if type(name) ~= "string" or name == "" then Refuse(name, "needs a name") end
	if type(spec.states) ~= "table" or #spec.states == 0 then Refuse(name, "declares no states") end
	local def = setmetatable({
		name = name,
		states = Sets.Named("state machine " .. name, spec.states),
	}, Definition)
	def.edges = Edges(def, spec.transitions)
	for _, kind in ipairs(HANDLER_KINDS) do def[kind] = Handlers(def, kind, spec[kind]) end
	if spec.changing ~= nil and type(spec.changing) ~= "function" then Refuse(name, "changing is not a function") end
	def.changing = spec.changing
	return def
end

function Definition:New(initial)
	return setmetatable({
		def = self,
		current = Declared(self, initial, "the initial state"),
	}, Machine)
end

function Machine:State() return self.current end
function Machine:Is(state) return self.current == state end

-- Whether the machine may move from its state to state.
function Machine:Can(state)
	local def = self.def
	if not def.states:Has(state) then return false end
	return def.edges == nil or (def.edges[self.current] ~= nil and def.edges[self.current][state] == true)
end

-- State_Enter: into state without leaving the current one's handler.
function Machine:Enter(state, ...)
	if not self:Can(state) then
		Refuse(self.def.name, "no transition from " .. tostring(self.current) .. " to " .. tostring(state))
	end
	local from = self.current
	self.current = state
	local changing = self.def.changing
	if changing then changing(from, state, ...) end
	local enter = self.def.enter[state]
	if enter then enter(...) end
end

-- State_Transition: leave the current state, then enter state.
function Machine:Transition(state, ...)
	if not self:Can(state) then
		Refuse(self.def.name, "no transition from " .. tostring(self.current) .. " to " .. tostring(state))
	end
	local leave = self.def.leave[self.current]
	if leave then leave(...) end
	self:Enter(state, ...)
end

-- Back into a saved state (foundation.core.snapshot): set as it was, with no
-- handler run and no edge required, as the state was reached once already.
function Machine:Restore(state)
	self.current = Declared(self.def, state, "a restored state")
end

-- State_Think: the current state's think handler, if it has one.
function Machine:Think(...)
	local think = self.def.think[self.current]
	if think then think(...) end
end
