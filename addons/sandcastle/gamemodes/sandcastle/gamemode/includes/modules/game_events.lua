-- Game events, on net2 (docs/net2.md): code fires and hears events as if
-- both realms were one.
--
--   game_events.Fire(name, fields[, options])  runs this realm's listeners at
--                                              once, in the order added, then
--                                              net2 carries it to the other
--   game_events.Listen(name, id, fn)           fn(fields[, ply]); an id again
--                                              replaces that listener in place
--   game_events.Ignore(name, id)
--   game_events.Accept(name, rate)             server: clients may fire this
--
-- options are net2.Send's. Fields the wire cannot carry are refused before
-- any listener runs. A predicted event (options.predicted) runs on a client
-- the first time its code is predicted, and is never sent from one: the
-- server fires its own, to every client but the one predicting it.
--
-- game_events.New(port) makes one over a port (Send, Receive, Accept,
-- FirstTimePredicted, Report), net2's for the gamemode.
local debug, error, ipairs, net2, setmetatable, tostring, type, xpcall =
	debug, error, ipairs, net2, setmetatable, tostring, type, xpcall
local CLIENT, ErrorNoHalt, IsFirstTimePredicted = CLIENT, ErrorNoHalt, IsFirstTimePredicted
module("game_events")

local Events = {}
Events.__index = Events

function New(port)
	return setmetatable({ port = port, listeners = {} }, Events)
end

function Events:Dispatch(name, fields, ply)
	local entry = self.listeners[name]
	if not entry then return end

	-- the list is replaced, never changed, so a listener may add or remove one
	for _, id in ipairs(entry.order) do
		local fn = entry.fns[id]
		local ok, err = true, nil
		if fn then ok, err = xpcall(fn, debug.traceback, fields, ply) end
		if not ok then self.port.Report("listener " .. tostring(id) .. " of " .. name .. ": " .. tostring(err)) end
	end
end

function Events:Fire(name, fields, options)
	local port = self.port
	local predicted = options and options.predicted
	if predicted and port.FirstTimePredicted and not port.FirstTimePredicted() then return end

	-- first, so that fields the wire cannot carry stop the event whole
	port.Send(name, fields, options)
	self:Dispatch(name, fields, nil)
end

function Events:Listen(name, id, fn)
	if type(name) ~= "string" or id == nil or type(fn) ~= "function" then
		error("game_events: Listen takes a name, an id and a function", 2)
	end

	local entry = self.listeners[name]
	if not entry then
		entry = { order = {}, fns = {} }
		self.listeners[name] = entry
		self.port.Receive(name, function(fields, ply) self:Dispatch(name, fields, ply) end)
	end

	if entry.fns[id] == nil then
		local order = {}
		for i, other in ipairs(entry.order) do order[i] = other end
		order[#order + 1] = id
		entry.order = order
	end
	entry.fns[id] = fn
end

function Events:Ignore(name, id)
	local entry = self.listeners[name]
	if not entry or entry.fns[id] == nil then return end

	local order = {}
	for _, other in ipairs(entry.order) do
		if other ~= id then order[#order + 1] = other end
	end
	entry.order = order
	entry.fns[id] = nil
end

function Events:Accept(name, rate)
	self.port.Accept(name, rate)
end

-- The gamemode's, over net2 (none under plain LuaJIT, where a test makes its own).
if net2 and net2.realm then
	local events = New({
		Send = net2.Send,
		Receive = net2.Receive,
		Accept = net2.Accept,
		FirstTimePredicted = CLIENT and IsFirstTimePredicted or nil,
		Report = function(text) ErrorNoHalt("game_events: " .. text .. "\n") end,
	})

	function Fire(name, fields, options)
		return events:Fire(name, fields, options)
	end

	function Listen(name, id, fn)
		return events:Listen(name, id, fn)
	end

	function Ignore(name, id)
		return events:Ignore(name, id)
	end

	function Accept(name, rate)
		return events:Accept(name, rate)
	end
end
