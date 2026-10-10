-- The dedicated server's sandcastle_debug.lua (.devtools/bin/server_root/):
-- breakpoints that capture the stack with its locals (snapshot) or stop the
-- server until told to go on (pause), and the Lua errors the server raised.
-- Run here under LuaJIT's own debug library: a test arms a breakpoint, runs a
-- function from a chunk named like a gamemode file, and reads what was caught.
local T = dofile("tests/harness.lua")

local SOURCE = "@gamemodes/sandcastle/gamemode/foundation/sample.lua"

-- A chunk "loaded from" SOURCE: line numbers below are the chunk's own.
local SAMPLE = [[
local bonus = 10
function Sample(a, b)
	local sum = a + b
	local scaled = sum * 2
	return scaled + bonus
end
function Outer(x)
	local y = Sample(x, 1)
	return y
end
function Loop(n)
	local total = 0
	for i = 1, n do
		total = total + i
	end
	return total
end
]]

local function Load()
	local events = {}
	local env = setmetatable({
		CompileString = function(code, name)
			local fn, err = loadstring(code, name)
			return fn or err
		end,
	}, { __index = _G })
	local chunk = assert(loadfile(".devtools/bin/server_root/sandcastle_debug.lua"))
	local D = setfenv(chunk, env)()
	local dbg = D.New({
		emit = function(name, kind, text) events[#events + 1] = name .. " " .. kind .. " " .. text end,
		now = function() return 12.5 end,
	})
	local sample = setfenv(assert(loadstring(SAMPLE, SOURCE)), setmetatable({}, { __index = _G }))
	sample()
	local g = getfenv(sample)
	return dbg, g, events
end

-- Runs fn with dbg's hook armed on this thread.
local function Armed(dbg, fn)
	debug.sethook(dbg:Hook(), "l")
	local ok, err = pcall(fn)
	debug.sethook()
	assert(ok, err)
end

local function Local(frame, name)
	for _, v in ipairs(frame.locals) do
		if v.name == name then return v.value end
	end
end

T.test("a snapshot breakpoint captures the stack with locals and upvalues, and the function goes on", function()
	local dbg, g, events = Load()
	local bp = dbg:Set({ file = "addon/gamemodes/sandcastle/gamemode/foundation/sample.lua", line = 4 })
	local result
	Armed(dbg, function() result = g.Outer(5) end)
	T.eq(result, 22, "the function ran on")
	local hits = dbg:Hits(bp.id)
	T.eq(#hits, 1, "one hit")
	local top = hits[1].frames[1]
	T.eq(top.source, "gamemodes/sandcastle/gamemode/foundation/sample.lua")
	T.eq(top.line, 4)
	T.eq(top.name, "Sample")
	T.eq(Local(top, "a"), "5")
	T.eq(Local(top, "sum"), "6")
	T.eq(top.upvalues[1].name, "bonus")
	T.eq(top.upvalues[1].value, "10")
	T.eq(hits[1].frames[2].name, "Outer", "the caller is the next frame")
	T.eq(hits[1].frames[2].line, 8)
	T.eq(events[1], "bp" .. bp.id .. " hit gamemodes/sandcastle/gamemode/foundation/sample.lua:4 (1/5)")
end)

T.test("a breakpoint matches on the path's tail, so a short path will do", function()
	local dbg, g = Load()
	local bp = dbg:Set({ file = "foundation/sample.lua", line = 4 })
	Armed(dbg, function() g.Outer(1) end)
	T.eq(#dbg:Hits(bp.id), 1)
end)

T.test("a breakpoint elsewhere never catches this file", function()
	local dbg, g = Load()
	local bp = dbg:Set({ file = "foundation/other_sample.lua", line = 4 })
	Armed(dbg, function() g.Outer(1) end)
	T.eq(#dbg:Hits(bp.id), 0)
end)

T.test("a condition sees the frame's locals and upvalues, and only true hits count", function()
	local dbg, g = Load()
	local bp = dbg:Set({ file = "foundation/sample.lua", line = 14, condition = "i == 3 and total == 3" })
	Armed(dbg, function() g.Loop(5) end)
	local hits = dbg:Hits(bp.id)
	T.eq(#hits, 1)
	T.eq(Local(hits[1].frames[1], "i"), "3")
end)

T.test("a breakpoint stops capturing after its hits, and says it is done", function()
	local dbg, g, events = Load()
	local bp = dbg:Set({ file = "foundation/sample.lua", line = 14, hits = 2 })
	Armed(dbg, function() g.Loop(5) end)
	T.eq(#dbg:Hits(bp.id), 2)
	T.eq(dbg:List()[1].state, "done")
	T.eq(dbg:Armed(), false, "nothing left to catch: the hook can come off")
	T.eq(events[#events], "bp" .. bp.id .. " done 2 hits")
end)

T.test("a condition that errors is reported once and the breakpoint stops", function()
	local dbg, g, events = Load()
	local bp = dbg:Set({ file = "foundation/sample.lua", line = 14, condition = "nope.field" })
	Armed(dbg, function() g.Loop(3) end)
	T.eq(#dbg:Hits(bp.id), 0)
	T.eq(dbg:List()[1].state, "error")
	T.eq(#events, 1, "reported once")
	assert(events[1]:find("^bp" .. bp.id .. " error condition: "), events[1])
end)

T.test("a condition that does not compile is refused when set", function()
	local dbg = Load()
	local ok, err = pcall(dbg.Set, dbg, { file = "foundation/sample.lua", line = 3, condition = "a ==" })
	T.eq(ok, false)
	assert(tostring(err):find("condition"), err)
end)

T.test("a breakpoint needs a file and a positive line", function()
	local dbg = Load()
	T.eq(pcall(dbg.Set, dbg, { line = 3 }), false, "no file")
	T.eq(pcall(dbg.Set, dbg, { file = "x.lua", line = 0 }), false, "line 0")
	T.eq(pcall(dbg.Set, dbg, { file = "x.lua", line = 3, mode = "stop" }), false, "unknown mode")
end)

T.test("clearing one breakpoint leaves the others; clearing with no id clears them all", function()
	local dbg = Load()
	local a = dbg:Set({ file = "a.lua", line = 1 })
	dbg:Set({ file = "b.lua", line = 2 })
	dbg:Clear(a.id)
	T.eq(#dbg:List(), 1)
	dbg:Clear()
	T.eq(#dbg:List(), 0)
	T.eq(dbg:Armed(), false)
end)

T.test("hits since a count return only the newer ones", function()
	local dbg, g = Load()
	local bp = dbg:Set({ file = "foundation/sample.lua", line = 14, hits = 5 })
	Armed(dbg, function() g.Loop(4) end)
	local newer = dbg:Hits(bp.id, 2)
	T.eq(#newer, 2)
	T.eq(newer[1].n, 3)
end)

T.test("a table value is shown with its keys, and a hit is caught before its line errors", function()
	local dbg, g = Load()
	local bp = dbg:Set({ file = "foundation/sample.lua", line = 3 })
	Armed(dbg, function() pcall(g.Sample, { k = 1 }, 0) end)
	local value = Local(dbg:Hits(bp.id)[1].frames[1], "a")
	assert(value:find("^table: .* {k=1}$"), value)
end)

T.test("a pause breakpoint hands the paused stack to the pause handler and goes on as it answers", function()
	local dbg, g, events = Load()
	local seen
	dbg.pause = function(ctx)
		seen = ctx
		return "continue"
	end
	local bp = dbg:Set({ file = "foundation/sample.lua", line = 4, mode = "pause" })
	local result
	Armed(dbg, function() result = g.Outer(5) end)
	T.eq(result, 22)
	T.eq(seen.frames[1].line, 4)
	T.eq(seen.bp.id, bp.id)
end)

T.test("eval while paused sees the paused frame's locals", function()
	local dbg, g = Load()
	local answer
	dbg.pause = function(ctx)
		answer = dbg:Eval("sum * 100 + bonus", 1)
		return "continue"
	end
	dbg:Set({ file = "foundation/sample.lua", line = 4, mode = "pause" })
	Armed(dbg, function() g.Outer(5) end)
	T.eq(answer, "610")
end)

T.test("eval in a caller's frame sees that frame's locals", function()
	local dbg, g = Load()
	local answer
	dbg.pause = function()
		answer = dbg:Eval("x", 2)
		return "continue"
	end
	dbg:Set({ file = "foundation/sample.lua", line = 4, mode = "pause" })
	Armed(dbg, function() g.Outer(7) end)
	T.eq(answer, "7")
end)

T.test("step over stops on the next line of the same function", function()
	local dbg, g = Load()
	local lines, answers = {}, { "over", "continue" }
	dbg.pause = function(ctx)
		lines[#lines + 1] = ctx.frames[1].line
		return table.remove(answers, 1)
	end
	dbg:Set({ file = "foundation/sample.lua", line = 8, mode = "pause" })
	Armed(dbg, function() g.Outer(1) end)
	T.eq(lines[1], 8)
	T.eq(lines[2], 9, "over the call to Sample, to the next line")
end)

T.test("step in stops inside the called function", function()
	local dbg, g = Load()
	local frames, answers = {}, { "in", "continue" }
	dbg.pause = function(ctx)
		frames[#frames + 1] = ctx.frames[1]
		return table.remove(answers, 1)
	end
	dbg:Set({ file = "foundation/sample.lua", line = 8, mode = "pause" })
	Armed(dbg, function() g.Outer(1) end)
	T.eq(frames[2].name, "Sample")
	T.eq(frames[2].line, 3)
end)

T.test("step out stops back in the caller", function()
	local dbg, g = Load()
	local frames, answers = {}, { "out", "continue" }
	dbg.pause = function(ctx)
		frames[#frames + 1] = ctx.frames[1]
		return table.remove(answers, 1)
	end
	dbg:Set({ file = "foundation/sample.lua", line = 4, mode = "pause" })
	Armed(dbg, function() g.Outer(1) end)
	T.eq(frames[2].name, "Outer")
	T.eq(frames[2].line, 9)
end)

T.test("eval when not paused runs in the global scope", function()
	local dbg = Load()
	T.eq(dbg:Eval("1 + 2"), "3")
end)

T.test("an eval that errors raises the error", function()
	local dbg = Load()
	local ok, err = pcall(dbg.Eval, dbg, "nope.field")
	T.eq(ok, false)
	assert(tostring(err):find("nope"), err)
end)

-- The rings: fixed capacity, the oldest overwritten, read back oldest first.

local function Ids(items)
	local ids = {}
	for i, item in ipairs(items) do ids[i] = item.id end
	return table.concat(ids, ",")
end

T.test("a ring keeps its newest items, oldest first, each with a rising id", function()
	local D = setfenv(assert(loadfile(".devtools/bin/server_root/sandcastle_debug.lua")), setmetatable({}, { __index = _G }))()
	local ring = D.Ring(3)
	for i = 1, 5 do ring:Push({ n = i }) end
	T.eq(Ids(ring:Since(0)), "3,4,5")
	T.eq(ring:Since(0)[1].n, 3)
	T.eq(Ids(ring:Since(4)), "5", "since an id: only the newer")
end)

T.test("a ring pushed past its capacity hands back the item it overwrote", function()
	local D = setfenv(assert(loadfile(".devtools/bin/server_root/sandcastle_debug.lua")), setmetatable({}, { __index = _G }))()
	local ring = D.Ring(2)
	T.eq(ring:Push({ n = 1 }), nil)
	ring:Push({ n = 2 })
	T.eq(ring:Push({ n = 3 }).n, 1)
end)

T.test("an empty ring reads back nothing", function()
	local D = setfenv(assert(loadfile(".devtools/bin/server_root/sandcastle_debug.lua")), setmetatable({}, { __index = _G }))()
	T.eq(#D.Ring(4):Since(0), 0)
end)

local STACK = { { File = "gamemodes/sandcastle/gamemode/foundation/x.lua", Function = "Boom", Line = 9 } }

T.test("a Lua error is kept with its stack and reported once", function()
	local dbg, _, events = Load()
	dbg:Error("x.lua:9: boom", "server", STACK, "sandcastle")
	local errors = dbg:Errors(0)
	T.eq(#errors, 1)
	T.eq(errors[1].count, 1)
	T.eq(errors[1].stack[1].Line, 9)
	T.eq(events[1], "lua_error error x.lua:9: boom")
end)

T.test("a repeated error counts on its entry, however far apart, and takes no new place in the ring", function()
	local dbg, _, events = Load()
	dbg:Error("x.lua:9: boom", "server", STACK, "sandcastle")
	dbg:Error("y.lua:1: other", "server", {}, "sandcastle")
	dbg:Error("x.lua:9: boom", "server", STACK, "sandcastle")
	local errors = dbg:Errors(0)
	T.eq(#errors, 2, "two messages, two entries")
	T.eq(errors[1].error, "x.lua:9: boom")
	T.eq(errors[1].count, 2)
	T.eq(#events, 2, "a repeat is not reported again")
end)

T.test("errors since a change number include an old error that happened again", function()
	local dbg = Load()
	dbg:Error("x.lua:9: boom", "server", STACK, "sandcastle")
	dbg:Error("y.lua:1: other", "server", {}, "sandcastle")
	local seen = dbg:Errors(0)[2].seq
	T.eq(#dbg:Errors(seen), 0, "nothing new")
	dbg:Error("x.lua:9: boom", "server", STACK, "sandcastle")
	local again = dbg:Errors(seen)
	T.eq(#again, 1)
	T.eq(again[1].error, "x.lua:9: boom")
	T.eq(again[1].count, 2)
end)

T.test("an error the ring let go of is new again when it recurs", function()
	local dbg, _, events = Load()
	local kept = dbg.errors.capacity
	dbg:Error("first", "server", {}, "sandcastle")
	for i = 1, kept do dbg:Error("filler " .. i, "server", {}, "sandcastle") end
	dbg:Error("first", "server", {}, "sandcastle")
	local errors = dbg:Errors(0)
	T.eq(#errors, kept, "the ring stays full")
	T.eq(errors[#errors].error, "first")
	T.eq(errors[#errors].count, 1, "a fresh entry, not the evicted one's count")
	T.eq(events[#events], "lua_error error first", "and reported again")
end)

T.test("a game event is kept with its fields shown and its recipient count", function()
	local dbg = Load()
	dbg:GameEvent("nav_progress", { stage = 2, areas = 0 }, 3)
	dbg:GameEvent("server_convars", { convars = { { name = "a" } } }, 1)
	local kept = dbg:GameEvents(0)
	T.eq(#kept, 2)
	T.eq(kept[1].name, "nav_progress")
	T.eq(kept[1].players, 3)
	T.eq(kept[1].time, 12.5)
	local fields = {}
	for _, f in ipairs(kept[1].fields) do fields[f.name] = f.value end
	T.eq(fields.stage, "2")
	T.eq(fields.areas, "0")
end)

T.test("a nested table shows its inner values a level down, and deeper ones by their size", function()
	local dbg = Load()
	dbg:GameEvent("server_convars", { convars = { { name = "a", deep = { x = { y = 1 } } } } }, 1)
	local value = dbg:GameEvents(0)[1].fields[1].value
	assert(value:find("^table: [^{]*{1={"), value)
	assert(value:find("name=a", 1, true), value)
	assert(value:find("deep={1 key}", 1, true), value)
end)

T.test("game events filter by name and by id", function()
	local dbg = Load()
	dbg:GameEvent("a", {}, 0)
	dbg:GameEvent("b", {}, 0)
	dbg:GameEvent("a", {}, 0)
	T.eq(#dbg:GameEvents(0, "a"), 2)
	T.eq(#dbg:GameEvents(dbg:GameEvents(0)[2].id), 1)
end)

T.test("console lines are kept whole; fragments join until their newline", function()
	local dbg = Load()
	dbg:Write("[Sandcastle] ")
	dbg:Write("loaded 3 ")
	dbg:Write("features\nsecond line\npart")
	dbg:Write("ial\n")
	local lines = dbg:Console(0)
	T.eq(#lines, 3)
	T.eq(lines[1].text, "[Sandcastle] loaded 3 features")
	T.eq(lines[2].text, "second line")
	T.eq(lines[3].text, "partial")
	T.eq(lines[1].time, 12.5)
end)

T.test("console lines filter by a plain substring", function()
	local dbg = Load()
	dbg:Write("ns_squads 4\nother\nns_lanes 2\n")
	local found = dbg:Console(0, "ns_")
	T.eq(#found, 2)
	T.eq(found[2].text, "ns_lanes 2")
end)

T.finish()
