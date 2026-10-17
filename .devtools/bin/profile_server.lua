-- A function profiler for the dedicated server, run through server_lua.py:
--
--   server_lua.py -f .devtools/bin/profile_server.lua      defines WSProfile
--   server_lua.py 'WSProfile.Start(60)'                     wrap, measure 60 s, unwrap
--   server_lua.py 'WSProfile.Start(60, WSProfile.COARSE)'   hooks and entities only
--   server_lua.py 'WSProfile.Start(60, WSProfile.ACTIONS)'  and NS actions, events, queries
--   server_lua.py 'WSProfile.Start(20, WSProfile.COARSE, { alloc = true })'
--                                                           and what each allocates
--   server_lua.py 'return WSProfile.Report(40)'             the most demanding functions
--
-- It wraps, in place, every hook, the methods of every scripted entity class
-- with a live instance (and its base classes), the functions and class
-- methods of every loaded foundation.* and features.* module, and the NS
-- action engine's per-action update, event and query, keyed by the action's
-- or event's name. Each wrapper records calls, inclusive time, and self time
-- (inclusive less its wrapped callees'), per coroutine, so a NextBot's
-- behaviour coroutine keeps its own stack. Each tick, the time spent in
-- outermost wrapped calls over the tick interval is its pressure, and Lua
-- memory is sampled. Everything is
-- unwrapped when the window ends; the wrappers add about two SysTime calls
-- per call, which inflates tiny, hot functions.
--
-- A wrapped function that yields across ticks would count the time it was
-- suspended; such entries stand out as a few calls with huge times.
--
-- With { alloc = true } the collector is stopped for the window (memory
-- grows by what Lua allocates; it restarts when the window ends), so the
-- change in collectgarbage("count") across a call is exactly what it
-- allocated. Only outermost calls on the main thread are measured: a
-- coroutine's call can yield, and other code's garbage would land in its
-- reading, and a nested call's would be counted again by its caller. A
-- NextBot's behaviour coroutine is measured whole, by the entity method that
-- resumes it.
WSProfile = WSProfile or {}
local P = WSProfile

local SysTime, coroutine_running, pairs, type = SysTime, coroutine.running, pairs, type
local MODULE_PREFIXES = { "^foundation%.", "^features%." }
-- Never wrap the profiler's own clock and bookkeeping paths.
local SKIP_MODULES = { ["foundation.core.analytics"] = true }

local stats, stacks, restore
local topSeconds = 0
local allocating = false
local collectgarbage = collectgarbage

local function Stat(name)
	local s = stats[name]
	if not s then
		s = {
			calls = 0,
			incl = 0,
			self = 0,
			max = 0, -- the longest single call, inclusive

		}
		stats[name] = s
	end
	return s
end

local MAIN = {}

local function Finish(name, stack, depth, started, kb, ...)
	local spent = SysTime() - started
	local s = Stat(name)
	if kb then
		s.kb = (s.kb or 0) + collectgarbage("count") - kb
		s.measured = (s.measured or 0) + 1
	end
	s.calls = s.calls + 1
	s.incl = s.incl + spent
	if spent > s.max then s.max = spent end
	s.self = s.self + spent - stack[depth]
	stack[depth] = nil
	stack.n = depth - 1
	if depth > 1 then
		stack[depth - 1] = stack[depth - 1] + spent
	else
		topSeconds = topSeconds + spent
	end
	return ...
end

local function Wrap(name, fn)
	return function(...)
		local key = coroutine_running() or MAIN
		local stack = stacks[key]
		if not stack then
			stack = { n = 0 }
			stacks[key] = stack
		end
		local depth = stack.n + 1
		stack.n = depth
		stack[depth] = 0
		local kb = allocating and depth == 1 and key == MAIN and collectgarbage("count")
		return Finish(name, stack, depth, SysTime(), kb, fn(...))
	end
end

-- Replace t[key] with a wrapper named name, remembering the original.
local function Replace(t, key, name)
	local fn = rawget(t, key)
	if type(fn) ~= "function" then return end
	restore[#restore + 1] = { t, key, fn }
	rawset(t, key, Wrap(name, fn))
end

local function WrapTable(t, prefix, seen)
	if seen[t] then return end
	seen[t] = true
	for key, value in pairs(t) do
		if type(key) == "string" then
			if type(value) == "function" then
				Replace(t, key, prefix .. key)
			elseif type(value) == "table" and rawget(value, "__index") == value then
				-- a class: its methods, once
				WrapTable(value, prefix .. key .. ":", seen)
			end
		end
	end
end

local function WrapHooks()
	for event, byId in pairs(hook.GetTable()) do
		for id, fn in pairs(byId) do
			if type(id) == "string" and type(fn) == "function" then
				restore[#restore + 1] = { "hook", event, id, fn }
				hook.Add(event, id, Wrap("hook " .. event .. "/" .. id, fn))
			end
		end
	end
end

local function WrapEntities(seen)
	local classes = {}
	for _, ent in ipairs(ents.GetAll()) do classes[ent:GetClass()] = true end
	for class in pairs(classes) do
		local stored = scripted_ents.GetStored(class)
		local t = stored and stored.t
		while t and not seen[t] do
			WrapTable(t, "ent " .. (t.ClassName or class) .. ":", seen)
			t = t.BaseClass
		end
	end
end

local function WrapModules(seen)
	for name, module in pairs(package.loaded) do
		if type(module) == "table" and not SKIP_MODULES[name] then
			for _, prefix in ipairs(MODULE_PREFIXES) do
				if name:match(prefix) then WrapTable(module, name .. ".", seen) end
			end
		end
	end
end

-- The action engine, by action: what each Update costs with its children,
-- each event and query by name.
local function WrapActions(seen)
	local Hfsm = package.loaded["foundation.core.hfsm"]
	if not Hfsm then return end
	local Action, Behavior = Hfsm.Action, Hfsm.Behavior
	seen[Action], seen[Behavior] = true, true
	local update, event, query = Action._InvokeUpdate, Action._ProcessEvent, Behavior.Query
	restore[#restore + 1] = { Action, "_InvokeUpdate", update }
	restore[#restore + 1] = { Action, "_ProcessEvent", event }
	restore[#restore + 1] = { Behavior, "Query", query }
	local wrappers = {}
	local function Named(kind, name, fn)
		local byName = wrappers[kind]
		if not byName then
			byName = {}
			wrappers[kind] = byName
		end
		local w = byName[name]
		if not w then
			w = Wrap(kind .. " " .. tostring(name), fn)
			byName[name] = w
		end
		return w
	end
	Action._InvokeUpdate = function(self, ...) return Named("action", self.name, update)(self, ...) end
	Action._ProcessEvent = function(self, name, ...) return Named("event", name, event)(self, name, ...) end
	Behavior.Query = function(self, me, name, ...) return Named("query", name, query)(self, me, name, ...) end
end

local FRAME_HOOK = "ws_profile_frame"

function P.Unwrap()
	for i = #restore, 1, -1 do
		local r = restore[i]
		if r[1] == "hook" then
			if hook.GetTable()[r[2]] and hook.GetTable()[r[2]][r[3]] then hook.Add(r[2], r[3], r[4]) end
		else
			rawset(r[1], r[2], r[3])
		end
	end
	restore = {}
	hook.Remove("Tick", FRAME_HOOK)
	if allocating then
		allocating = false
		collectgarbage("restart")
	end
	P.running = false
end

-- scope: P.FINE (the default) wraps everything above; P.COARSE only hooks
-- and entity methods, whose overhead is negligible, for trustworthy totals.
-- P.ACTIONS adds the NS action engine's per-action breakdown and the
-- methods of the loaded feature controllers (WS.Feature tables) to COARSE,
-- still without the hot, tiny module functions.
P.FINE, P.COARSE, P.ACTIONS = "fine", "coarse", "actions"

function P.Start(seconds, scope, options)
	if P.running then P.Unwrap() end
	options = options or {}
	stats, stacks, restore = {}, setmetatable({}, { __mode = "k" }), {}
	P.stats = stats
	local seen = {}
	if scope ~= P.COARSE then
		WrapActions(seen)
		for _, name in ipairs(WS.FeatureLoader:Loaded()) do
			local controller = WS.Feature(name)
			if type(controller) == "table" then WrapTable(controller, "feature " .. name .. ":", seen) end
		end
	end
	if scope == nil or scope == P.FINE then WrapModules(seen) end
	WrapEntities(seen)
	WrapHooks()
	local pressures, memory = {}, {}
	P.pressures, P.memory = pressures, memory
	topSeconds = 0
	hook.Add("Tick", FRAME_HOOK, function()
		-- a stack left open by an error starts over each tick
		stacks[MAIN] = nil
		pressures[#pressures + 1] = topSeconds / engine.TickInterval()
		topSeconds = 0
		memory[#memory + 1] = collectgarbage("count")
	end)
	P.running, P.startedAt, P.seconds, P.wrapped = true, SysTime(), seconds, #restore
	P.alloc = options.alloc == true
	if P.alloc then
		collectgarbage("stop")
		allocating = true
	end
	timer.Create("ws_profile_window", seconds, 1, P.Unwrap)
	return string.format("profiling %d wrapped functions for %d s", #restore, seconds)
end

local MS = 1000

function P.Report(n)
	n = n or 30
	local elapsed = P.running and SysTime() - P.startedAt or P.seconds
	local rows = {}
	for name, s in pairs(P.stats or {}) do rows[#rows + 1] = { name = name, s = s } end
	local lines = {
		string.format("window %.1f s, %d wrapped, %d functions called%s",
			elapsed, P.wrapped or 0, #rows, P.running and " (still running)" or ""),
	}
	local function Section(title, field)
		table.sort(rows, function(a, b) return a.s[field] > b.s[field] end)
		lines[#lines + 1] = title
		for i = 1, math.min(n, #rows) do
			local s = rows[i].s
			lines[#lines + 1] = string.format("%8.1f ms/s self %8.1f ms/s incl %8d calls %7.1f us/call  %s",
				s.self * MS / elapsed, s.incl * MS / elapsed, s.calls, s.incl / s.calls * 1e6, rows[i].name)
		end
	end
	Section("-- by self time (ms of CPU per second of play)", "self")
	Section("-- by inclusive time", "incl")
	if P.alloc then
		local allocated = {}
		for _, row in ipairs(rows) do
			if row.s.kb then allocated[#allocated + 1] = row end
		end
		table.sort(allocated, function(a, b) return a.s.kb > b.s.kb end)
		lines[#lines + 1] = "-- allocation by outermost call on the main thread (GC stopped for the window)"
		for i = 1, math.min(n, #allocated) do
			local s = allocated[i].s
			lines[#lines + 1] = string.format("%8.1f KB/s %8.2f KB/call %8d calls  %s",
				s.kb / elapsed, s.kb / s.measured, s.measured, allocated[i].name)
		end
	end
	table.sort(rows, function(a, b) return a.s.max > b.s.max end)
	lines[#lines + 1] = "-- worst single calls (hitches)"
	for i = 1, math.min(n, #rows) do
		lines[#lines + 1] = string.format("%8.1f ms  %s", rows[i].s.max * MS, rows[i].name)
	end
	local pressures, sum, peak, over = P.pressures or {}, 0, 0, 0
	for _, v in ipairs(pressures) do
		sum, peak = sum + v, math.max(peak, v)
		if v > 1 then over = over + 1 end
	end
	local sorted = table.Copy(pressures)
	table.sort(sorted)
	lines[#lines + 1] = string.format("tick pressure (wrapped Lua / tick interval): mean %.0f%%, p95 %.0f%%, peak %.0f%%, %d of %d ticks over budget",
		sum / math.max(1, #pressures) * 100, (sorted[math.max(1, math.ceil(#sorted * 0.95))] or 0) * 100, peak * 100, over, #pressures)
	local mem = P.memory or {}
	if #mem > 0 then
		local least, most = math.huge, 0
		for _, kb in ipairs(mem) do least, most = math.min(least, kb), math.max(most, kb) end
		lines[#lines + 1] = string.format("Lua memory %.0f kB now (least %.0f, most %.0f), range %.0f kB/s of the window",
			mem[#mem], least, most, (most - least) / math.max(elapsed, 1))
	end
	return table.concat(lines, "\n")
end
