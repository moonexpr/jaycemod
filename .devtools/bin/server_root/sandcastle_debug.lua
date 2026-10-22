-- Breakpoints, stacks and Lua errors on the dedicated server (server_root.py),
-- for the sandcastle MCP server's debug tools (.devtools/bin/gmod_mcp.py),
-- which reach it through luadev_socket.lua's ops.
--
-- A breakpoint is a file and a line, optionally a condition (a Lua expression
-- over the frame's locals and upvalues). A line hook (debug.sethook, as
-- Thomasims/NetDebug does) looks each line up by number first and asks for its
-- source only on a match, so an armed server pays a table lookup per line; the
-- hook is on only while a breakpoint is active, and LuaJIT runs interpreted
-- under it. Two modes:
--   snapshot  capture the stack, its locals and upvalues, and go on (default)
--   pause     stop the whole server inside the hook, answering the socket's
--             ops (eval, step, continue) from there, until told to go on or
--             the pause limit passes; clients time out after about 30 s
-- Each hit, pause and error is also a line of the watch log
-- (sandcastle_watch.lua's format), so a follower wakes on it.
--
-- The hook is set per thread: the main one, coroutines created while armed,
-- and running NextBots' behaviour threads (BehaveThread).
--
-- Three rings keep the newest of what the server did, each push O(1) and
-- the oldest overwritten: Lua errors (OnLuaError, ERRORS_KEPT distinct
-- messages: a repeat counts on its entry, found by message, instead of
-- taking a place), game events (GAME_EVENTS_KEPT, from the event library's
-- WSGameEventFired) and console lines (CONSOLE_KEPT, what print and
-- the Msg family wrote).
--
-- Paths are matched on their tail, after "addons/<addon>/" and "@" come off, so
-- the repo's addons/sandcastle/gamemodes/sandcastle/gamemode/games/gameplay/rounds.lua, the game's
-- gamemodes/sandcastle/gamemode/games/gameplay/rounds.lua and games/gameplay/rounds.lua
-- all name the same file.
local MAX_FRAMES = 12
local SNAPSHOTS_KEPT = 20 -- per breakpoint, the newest
local DEFAULT_HITS = 5
local TABLE_KEYS = 8 -- a table value shows this many of its pairs
local TABLE_DEPTH = 2 -- levels of a table value shown; deeper ones show their size
local KEYS_COUNTED = 100 -- a table past this many keys shows as "100+ keys"
local ERRORS_KEPT = 50 -- distinct messages; a repeat counts on its entry
local GAME_EVENTS_KEPT = 200
local CONSOLE_KEPT = 500 -- lines
local DEFAULT_PAUSE_LIMIT = 60 -- seconds
local MODES = { snapshot = true, pause = true }
local STEPS = { ["continue"] = true, ["in"] = true, over = true, out = true } -- GLua reserves continue

local D = {}

-- A ring of `capacity` items: a push overwrites the oldest and hands it back,
-- each item gets a rising id, and Since reads the newer ones oldest first.
local Ring = {}
Ring.__index = Ring

local function NewerThan(item, id) return item.id > id end

function D.Ring(capacity)
	return setmetatable({ capacity = capacity, items = {}, head = 0, pushed = 0 }, Ring)
end

function Ring:Push(item)
	self.pushed = self.pushed + 1
	item.id = self.pushed
	self.head = self.head % self.capacity + 1
	local evicted = self.items[self.head]
	self.items[self.head] = item
	return evicted
end

function Ring:Since(id, keep)
	keep = keep or NewerThan
	local out = {}
	local held = math.min(self.pushed, self.capacity)
	for back = held - 1, 0, -1 do
		local item = self.items[(self.head - back - 1) % self.capacity + 1]
		if keep(item, id) then out[#out + 1] = item end
	end
	return out
end

local Debugger = {}
Debugger.__index = Debugger

local function Normalize(path)
	return (path:gsub("\\", "/"):gsub("^@", ""):gsub("^.*/addons/[^/]+/", ""):gsub("^addons/[^/]+/", ""):lower())
end

local function Show(value)
	local ok, text = pcall(tostring, value)
	return ok and text or "<tostring failed>"
end

-- A table's pairs, `depth` levels down; below that, how many keys it has.
local function Inner(value, depth)
	if type(value) ~= "table" then return Show(value) end
	if depth == 0 then
		local n = 0
		for _ in pairs(value) do
			n = n + 1
			if n > KEYS_COUNTED then return "{" .. KEYS_COUNTED .. "+ keys}" end
		end
		return "{" .. n .. (n == 1 and " key}" or " keys}")
	end
	local parts = {}
	for k, v in pairs(value) do
		if #parts == TABLE_KEYS then
			parts[#parts + 1] = "..."
			break
		end
		parts[#parts + 1] = Show(k) .. "=" .. Inner(v, depth - 1)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- A value as text: a table by its address, then its pairs TABLE_DEPTH levels down.
local function Describe(value)
	if type(value) ~= "table" then return Show(value) end
	return Show(value) .. " " .. Inner(value, TABLE_DEPTH)
end

-- One frame `level` above the caller: what it shows, and its raw values.
local function Frame(level)
	local info = debug.getinfo(level + 1, "Snlf")
	if not info then return nil end
	local frame = {
		source = (info.source:gsub("^@", "")),
		line = info.currentline,
		name = info.name or (info.what == "main" and "main chunk" or "function at line " .. info.linedefined),
		locals = {},
		upvalues = {},
	}
	local raw = { locals = {}, upvalues = {}, func = info.func }
	for i = 1, math.huge do
		local name, value = debug.getlocal(level + 1, i)
		if name == nil then break end
		if name:sub(1, 1) ~= "(" then
			frame.locals[#frame.locals + 1] = { name = name, value = Describe(value) }
			raw.locals[name] = value
		end
	end
	if info.func then
		for i = 1, math.huge do
			local name, value = debug.getupvalue(info.func, i)
			if name == nil then break end
			frame.upvalues[#frame.upvalues + 1] = { name = name, value = Describe(value) }
			raw.upvalues[name] = value
		end
	end
	return frame, raw
end

-- The stack from `level` above the caller down.
local function Stack(level)
	local frames, raws = {}, {}
	for k = 0, MAX_FRAMES - 1 do
		local frame, raw = Frame(level + 1 + k)
		if not frame then break end
		frames[#frames + 1] = frame
		raws[#raws + 1] = raw
	end
	return frames, raws
end

-- How many frames lie from `level` above the caller to the bottom.
local function Depth(level)
	local i = level + 1
	while debug.getinfo(i, "l") do i = i + 1 end
	return i - level - 1
end

-- An environment where a frame's locals shadow its upvalues, then its globals.
local function FrameEnv(raw)
	local globals = raw.func and getfenv(raw.func) or _G
	return setmetatable({}, {
		__index = function(_, name)
			local v = raw.locals[name]
			if v ~= nil then return v end
			v = raw.upvalues[name]
			if v ~= nil then return v end
			return globals[name]
		end,
	})
end

local function Compile(code, name)
	local fn = CompileString(code, name, false)
	if type(fn) == "string" then return nil, fn end
	return fn
end

-- deps: emit(name, kind, text) writes a watch line; now() the time.
function D.New(deps)
	local self = setmetatable({
		emit = deps.emit,
		now = deps.now,
		breakpoints = {}, -- id -> breakpoint
		byLine = {}, -- line -> { breakpoint, ... } of the active ones
		nextId = 1,
		errors = D.Ring(ERRORS_KEPT),
		errorByMessage = {}, -- message -> its entry while the ring holds it
		errorChanges = 0, -- each error, new or repeated, is the next change
		gameEvents = D.Ring(GAME_EVENTS_KEPT),
		console = D.Ring(CONSOLE_KEPT),
		pending = "", -- a console line Msg has begun
		paused = nil, -- { bp, frames, raws, limit, resume }
		stepping = nil, -- { kind, depth, limit }
		pause = nil, -- set by the wiring: ctx -> "continue" | "in" | "over" | "out"
	}, Debugger)
	return self
end

function Debugger:Index()
	for line in pairs(self.byLine) do self.byLine[line] = nil end
	for _, bp in pairs(self.breakpoints) do
		if bp.state == "active" then
			local list = self.byLine[bp.line] or {}
			list[#list + 1] = bp
			self.byLine[bp.line] = list
		end
	end
end

function Debugger:Set(args)
	local file, line, mode = args.file, tonumber(args.line), args.mode or "snapshot"
	if type(file) ~= "string" or file == "" then error("a breakpoint needs a file", 0) end
	if not line or line < 1 or line % 1 ~= 0 then error("a breakpoint needs a positive whole line", 0) end
	if not MODES[mode] then error("mode is snapshot or pause, not " .. tostring(mode), 0) end
	local condition
	if args.condition and args.condition ~= "" then
		local fn, err = Compile("return (" .. args.condition .. ")", "breakpoint condition")
		if not fn then error("the condition does not compile: " .. err, 0) end
		condition = fn
	end
	local bp = {
		id = self.nextId,
		file = Normalize(file),
		line = line,
		mode = mode,
		conditionText = args.condition,
		condition = condition,
		max = tonumber(args.hits) or DEFAULT_HITS,
		pauseLimit = tonumber(args.pause_limit) or DEFAULT_PAUSE_LIMIT,
		n = 0,
		state = "active",
		snapshots = {},
		matches = {}, -- source -> whether it names bp.file
	}
	self.nextId = self.nextId + 1
	self.breakpoints[bp.id] = bp
	self:Index()
	return self:View(bp)
end

function Debugger:View(bp)
	return {
		id = bp.id,
		file = bp.file,
		line = bp.line,
		mode = bp.mode,
		condition = bp.conditionText,
		state = bp.state,
		hits = bp.n,
		max = bp.max,
	}
end

function Debugger:List()
	local list = {}
	for _, bp in pairs(self.breakpoints) do list[#list + 1] = self:View(bp) end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

function Debugger:Clear(id)
	if id == nil then
		self.breakpoints = {}
	else
		if not self.breakpoints[id] then error("no breakpoint " .. tostring(id), 0) end
		self.breakpoints[id] = nil
	end
	self:Index()
end

function Debugger:Hits(id, since)
	local bp = self.breakpoints[id]
	if not bp then error("no breakpoint " .. tostring(id), 0) end
	local hits = {}
	for _, snapshot in ipairs(bp.snapshots) do
		if snapshot.n > (since or 0) then hits[#hits + 1] = snapshot end
	end
	return hits
end

function Debugger:Armed()
	return next(self.byLine) ~= nil or self.stepping ~= nil
end

-- The function debug.sethook calls on each line, the same one every time.
function Debugger:Hook()
	if not self.hook then
		local byLine = self.byLine
		self.hook = function(_, line)
			if self.stepping == nil and byLine[line] == nil then return end
			self:OnLine(line)
		end
	end
	return self.hook
end

local function Matches(bp, source)
	local known = bp.matches[source]
	if known == nil then
		local path = Normalize(source)
		known = path == bp.file or path:sub(-#bp.file - 1) == "/" .. bp.file
		bp.matches[source] = known
	end
	return known
end

function Debugger:Finish(bp, state, text)
	bp.state = state
	self:Index()
	self.emit("bp" .. bp.id, state, text)
end

-- From the hook: level 1 here, 2 the hook, 3 the function on that line.
function Debugger:OnLine(line)
	local stepping = self.stepping
	if stepping then
		local depth = Depth(3)
		if stepping.kind == "in" or (stepping.kind == "over" and depth <= stepping.depth)
			or (stepping.kind == "out" and depth < stepping.depth) then
			self.stepping = nil
			local frames, raws = Stack(3)
			self:Pause({ frames = frames, raws = raws, limit = stepping.limit }, depth)
			return
		end
	end
	local bps = self.byLine[line]
	if not bps then return end
	local source = debug.getinfo(3, "S").source
	for _, bp in ipairs(bps) do
		if bp.state == "active" and Matches(bp, source) then
			local frames, raws = Stack(3)
			local hit = true
			if bp.condition then
				local ok, result = pcall(setfenv(bp.condition, FrameEnv(raws[1])))
				if not ok then
					self:Finish(bp, "error", "condition: " .. tostring(result))
					hit = false
				else
					hit = result and true or false
				end
			end
			if hit then
				bp.n = bp.n + 1
				local snapshots = bp.snapshots
				snapshots[#snapshots + 1] = { n = bp.n, time = self.now(), frames = frames }
				if #snapshots > SNAPSHOTS_KEPT then table.remove(snapshots, 1) end
				self.emit("bp" .. bp.id, "hit", string.format("%s:%d (%d/%d)", frames[1].source, frames[1].line, bp.n, bp.max))
				if bp.n >= bp.max then self:Finish(bp, "done", bp.n .. " hits") end
				if bp.mode == "pause" then
					self:Pause({ bp = bp, frames = frames, raws = raws, limit = bp.pauseLimit }, Depth(3))
					return
				end
			end
		end
	end
end

function Debugger:Pause(ctx, depth)
	self.paused = ctx
	local answer = self.pause(ctx)
	self.paused = nil
	if answer ~= "continue" then
		self.stepping = { kind = answer, depth = depth, limit = ctx.limit }
	end
end

-- While paused: answer the pause with a step or continue.
function Debugger:Resume(kind)
	if not self.paused then error("not paused", 0) end
	if not STEPS[kind] then error("resume with continue, in, over or out, not " .. tostring(kind), 0) end
	self.paused.resume = kind
end

-- An expression's values, shown; in the paused frame `frame` (1 the top)
-- while paused, else in the global scope. A statement runs too.
function Debugger:Eval(expr, frame)
	local env = _G
	if self.paused then
		local raw = self.paused.raws[frame or 1]
		if not raw then error("no frame " .. tostring(frame), 0) end
		env = FrameEnv(raw)
	end
	local fn = Compile("return " .. expr, "debug eval")
	if not fn then
		local err
		fn, err = Compile(expr, "debug eval")
		if not fn then error(err, 0) end
	end
	local results = { pcall(setfenv(fn, env)) }
	if not results[1] then error(tostring(results[2]), 0) end
	local shown = {}
	for i = 2, table.maxn(results) do shown[#shown + 1] = Describe(results[i]) end
	return table.concat(shown, ", ")
end

-- From OnLuaError: kept with its stack in the ring. A message the ring
-- holds already counts on its entry (found through errorByMessage) instead
-- of taking a place, so one error repeating every tick never pushes the
-- others out; it is reported once, when it is new.
function Debugger:Error(message, realm, stack, addon)
	self.errorChanges = self.errorChanges + 1
	local now = self.now()
	local entry = self.errorByMessage[message]
	if entry then
		entry.count = entry.count + 1
		entry.last = now
		entry.seq = self.errorChanges
		return
	end
	entry = { error = message, realm = realm, addon = addon, stack = stack, count = 1,
		time = now, last = now, seq = self.errorChanges }
	local evicted = self.errors:Push(entry)
	if evicted then self.errorByMessage[evicted.error] = nil end
	self.errorByMessage[message] = entry
	self.emit("lua_error", "error", message)
end

local function ChangedSince(entry, seq) return entry.seq > seq end

-- The errors new or repeated since change `since` (an entry's seq), oldest first.
function Debugger:Errors(since)
	return self.errors:Since(since, ChangedSince)
end

-- From the game event library (ws/sh_events.lua's WSGameEventFired).
function Debugger:GameEvent(name, fields, players)
	local shown = {}
	for k, v in pairs(fields) do shown[#shown + 1] = { name = Show(k), value = Describe(v) } end
	table.sort(shown, function(a, b) return a.name < b.name end)
	self.gameEvents:Push({ name = name, fields = shown, players = players, time = self.now() })
end

function Debugger:GameEvents(since, name)
	if not name then return self.gameEvents:Since(since) end
	return self.gameEvents:Since(since, function(event, id) return event.id > id and event.name == name end)
end

-- What print, Msg, MsgN and MsgC wrote: fragments join until a newline.
function Debugger:Write(text)
	local buffered = self.pending .. text
	local from = 1
	for line, stop in buffered:gmatch("([^\n]*)\n()") do
		self.console:Push({ text = line, time = self.now() })
		from = stop
	end
	self.pending = buffered:sub(from)
end

-- Console lines since id `since`, those holding `pattern` (plain text) if given.
function Debugger:Console(since, pattern)
	if not pattern then return self.console:Since(since) end
	return self.console:Since(since, function(line, id)
		return line.id > id and line.text:find(pattern, 1, true) ~= nil
	end)
end

if not SERVER then return D end

-- The server's wiring: the watch log, the hook on each thread, the socket's
-- ops, the pause loop and OnLuaError.
local LOG = "sandcastle_watch.txt" -- sandcastle_watch.lua's
local PAUSE_POLL = 0.05 -- seconds the paused loop waits on the socket at a time

local function Line(name, kind, text)
	local line = string.format("%.2f %s %s %s", CurTime(), name, kind, tostring(text))
	file.Append(LOG, line:gsub("\n", " ") .. "\n")
end

-- the coroutine library as GMod made it, whatever an earlier load of this file swapped in
SANDCASTLE_RAW_COROUTINE = SANDCASTLE_RAW_COROUTINE or { create = coroutine.create, wrap = coroutine.wrap }
local raw = SANDCASTLE_RAW_COROUTINE

if SandcastleDebugger and SandcastleDebugger.disarm then SandcastleDebugger.disarm() end
local dbg = D.New({ emit = Line, now = CurTime })
SandcastleDebugger = dbg

local on, hooked = false, setmetatable({}, { __mode = "k" })

local function HookThread(co, fn)
	debug.sethook(co, fn, "l")
	hooked[co] = true
end

-- From the main thread (an op, run in Think): the hook on every thread.
local function Arm()
	if on then return end
	on = true
	local fn = dbg:Hook()
	if jit then jit.flush() end -- compiled traces skip the hook
	debug.sethook(fn, "l")
	coroutine.create = function(body)
		local co = raw.create(body)
		HookThread(co, fn)
		return co
	end
	coroutine.wrap = function(body)
		local co = coroutine.create(body)
		return function(...)
			local results = { coroutine.resume(co, ...) }
			if not results[1] then error(results[2], 0) end
			return unpack(results, 2, table.maxn(results))
		end
	end
	for _, ent in ipairs(ents.GetAll()) do
		local thread = ent.BehaveThread
		if type(thread) == "thread" and coroutine.status(thread) == "suspended" then HookThread(thread, fn) end
	end
end

-- From the main thread too: a hook can end in a coroutine, where
-- debug.sethook() would reach only that one.
local function Disarm()
	if not on then return end
	on = false
	debug.sethook()
	coroutine.create, coroutine.wrap = raw.create, raw.wrap
	for co in pairs(hooked) do
		if coroutine.status(co) ~= "dead" then debug.sethook(co) end
	end
	hooked = setmetatable({}, { __mode = "k" })
end
dbg.disarm = Disarm

hook.Add("Think", "SandcastleDebug", function()
	if on and not dbg:Armed() then Disarm() end
end)

dbg.pause = function(ctx)
	local top = ctx.frames[1]
	local name = ctx.bp and ("bp" .. ctx.bp.id) or "debug"
	Line(name, "paused", top.source .. ":" .. top.line)
	local sock = SANDCASTLE_SOCKET
	local deadline = SysTime() + ctx.limit
	sock.listener:settimeout(PAUSE_POLL)
	while not ctx.resume and SysTime() < deadline do
		local client = sock.listener:accept()
		if client then sock.serve(client) end
	end
	sock.listener:settimeout(0)
	if ctx.resume then return ctx.resume end
	Line(name, "resumed", "the pause limit (" .. ctx.limit .. " s) passed")
	return "continue"
end

hook.Add("OnLuaError", "SandcastleDebug", function(message, realm, stack, addon)
	dbg:Error(message, realm, stack, addon)
end)

hook.Add("WSGameEventFired", "SandcastleDebug", function(name, fields, players)
	dbg:GameEvent(name, fields, players)
end)

-- The console ring: print and the Msg family, wrapped once (a refresh of
-- this file finds them wrapped already) and writing to whichever debugger
-- is current. What the engine prints itself never passes through Lua: that
-- is in the console log on disk (gmod_mcp.py's console_log).
local function Joined(separator, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) ~= "table" then parts[#parts + 1] = Show(v) end -- MsgC's colors are tables
	end
	return table.concat(parts, separator)
end

if not SANDCASTLE_RAW_PRINT then
	SANDCASTLE_RAW_PRINT = { print = print, Msg = Msg, MsgN = MsgN, MsgC = MsgC }
	local rawPrint = SANDCASTLE_RAW_PRINT
	function print(...)
		rawPrint.print(...)
		SandcastleDebugger:Write(Joined("\t", ...) .. "\n")
	end
	function Msg(...)
		rawPrint.Msg(...)
		SandcastleDebugger:Write(Joined("", ...))
	end
	function MsgN(...)
		rawPrint.MsgN(...)
		SandcastleDebugger:Write(Joined("", ...) .. "\n")
	end
	function MsgC(...)
		rawPrint.MsgC(...)
		SandcastleDebugger:Write(Joined("", ...))
	end
end

SANDCASTLE_OPS = SANDCASTLE_OPS or {}
local ops = SANDCASTLE_OPS
function ops.bp_set(args)
	local bp = dbg:Set(args)
	Arm()
	return bp
end
function ops.bp_list() return dbg:List() end
function ops.bp_clear(args)
	dbg:Clear(args.id)
	return dbg:List()
end
function ops.bp_hits(args) return dbg:Hits(args.id, args.since) end
function ops.debug_state()
	local paused = dbg.paused
	return {
		armed = dbg:Armed(),
		paused = paused and { bp = paused.bp and paused.bp.id, frames = paused.frames } or false,
	}
end
function ops.debug_eval(args) return dbg:Eval(args.expr, args.frame) end
function ops.debug_resume(args)
	dbg:Resume(args.kind or "continue")
	return args.kind or "continue"
end
function ops.lua_errors(args) return dbg:Errors(args.since or 0) end
function ops.game_events(args) return dbg:GameEvents(args.since or 0, args.name) end
function ops.console_messages(args) return dbg:Console(args.since or 0, args.grep) end

return D
