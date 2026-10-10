-- The dedicated server's sandcastle_watch.lua (.devtools/bin/server_root/):
-- events the server pushes to a watcher (server_watch.py) instead of being
-- polled. Each is one line in data/sandcastle_watch.txt: "<time> <name>
-- <kind> <text>". Timers, hooks and the clock are stubbed here.
local T = dofile("tests/harness.lua")

-- A server with a hand-driven clock: Advance(seconds) runs every timer due.
local function Load()
	local now, timers, hooks, lines = 0, {}, {}, {}
	local env = setmetatable({
		CurTime = function() return now end,
		file = {
			Append = function(path, text)
				T.eq(path, "sandcastle_watch.txt", "the log's path in data/")
				for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
			end,
		},
		timer = {
			Create = function(name, delay, reps, fn) timers[name] = { delay = delay, next = now + delay, fn = fn } end,
			Remove = function(name) timers[name] = nil end,
		},
		hook = {
			Add = function(event, id, fn) hooks[event] = hooks[event] or {}; hooks[event][id] = fn end,
			Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
		},
	}, { __index = _G })
	setfenv(assert(loadfile(".devtools/bin/server_root/sandcastle_watch.lua")), env)()
	local server = { Watch = env.Watch, lines = lines }
	function server.Advance(seconds)
		local stop = now + seconds
		while true do
			local name, due
			for n, t in pairs(timers) do
				if t.next <= stop and (not due or t.next < due.next) then name, due = n, t end
			end
			if not due then break end
			now = due.next
			due.next = now + due.delay
			due.fn()
		end
		now = stop
	end
	function server.Fire(event, ...)
		for _, fn in pairs(hooks[event] or {}) do fn(...) end
	end
	return server
end

T.test("an event is one line: time, name, kind, text", function()
	local s = Load()
	s.Watch.Emit("cart", "passed c_1")
	T.eq(s.lines[1], "0.00 cart event passed c_1")
end)

T.test("Until reports met once its check passes, with the check's report, and stops", function()
	local s = Load()
	local passes = false
	s.Watch.Until("stage3", 1, 30, function() return passes, "dist=-7" end)
	s.Advance(5)
	T.eq(#s.lines, 0, "nothing while it waits")
	passes = true
	s.Advance(1)
	T.eq(s.lines[1], "6.00 stage3 met dist=-7")
	s.Advance(10)
	T.eq(#s.lines, 1, "it stopped")
end)

-- Silence is not success: a wait that never passes says so.
T.test("Until reports timeout with the last report when its check never passes", function()
	local s = Load()
	s.Watch.Until("stage3", 1, 10, function() return false, "dist=-1973" end)
	s.Advance(12)
	T.eq(s.lines[1], "10.00 stage3 timeout dist=-1973")
	T.eq(#s.lines, 1, "once")
end)

T.test("a check that errors is reported and stops", function()
	local s = Load()
	s.Watch.Until("broken", 1, 10, function() error("no train") end)
	s.Advance(3)
	T.eq(s.lines[1]:match("^1%.00 broken error .*no train$") ~= nil, true, s.lines[1])
	T.eq(#s.lines, 1)
end)

T.test("Every reports what its function returns, only when it changes", function()
	local s = Load()
	local speed = 0
	s.Watch.Every("speed", 1, function() return speed end)
	s.Advance(3)
	speed = 90
	s.Advance(2)
	T.eq(table.concat(s.lines, "|"), "1.00 speed changed 0|4.00 speed changed 90")
end)

T.test("On reports a hook as it runs, and Stop ends any watch", function()
	local s = Load()
	s.Watch.On("WSRoundWin", "win", function(team) return "team " .. team end)
	s.Fire("WSRoundWin", 3)
	s.Watch.Stop("win")
	s.Fire("WSRoundWin", 2)
	T.eq(table.concat(s.lines, "|"), "0.00 win event team 3")
end)

T.test("a watch started again under its name replaces the old one", function()
	local s = Load()
	s.Watch.Every("x", 1, function() return "old" end)
	s.Watch.Every("x", 1, function() return "new" end)
	s.Advance(1)
	T.eq(table.concat(s.lines, "|"), "1.00 x changed new")
end)

T.test("a Task reports its progress as it changes, then met with done's report, and stops", function()
	local s = Load()
	local stage, finished = "opening", false
	s.Watch.Task("nav", {
		every = 1,
		timeout = 100,
		progress = function() return stage end,
		done = function() return finished, "412 areas" end,
	})
	s.Advance(3)
	stage = "generating"
	s.Advance(2)
	finished = true
	s.Advance(1)
	T.eq(s.lines[1], "1.00 nav progress opening")
	T.eq(s.lines[2], "4.00 nav progress generating")
	T.eq(s.lines[3], "6.00 nav met 412 areas")
	s.Advance(5)
	T.eq(#s.lines, 3, "nothing after it ends")
end)

T.test("a Task times out with its last progress", function()
	local s = Load()
	s.Watch.Task("nav", { every = 1, timeout = 5, progress = function() return "generating" end, done = function() return false end })
	s.Advance(10)
	T.eq(s.lines[#s.lines], "5.00 nav timeout generating")
	T.eq(#s.lines, 2)
end)

T.test("a Task whose function errors reports it and stops", function()
	local s = Load()
	s.Watch.Task("nav", { every = 1, timeout = 5, progress = function() error("no navmesh") end, done = function() return false end })
	s.Advance(3)
	T.eq(#s.lines, 1)
	assert(s.lines[1]:find("^1.00 nav error .*no navmesh"), s.lines[1])
end)

T.test("a Task needs only done: progress and the timings have defaults", function()
	local s = Load()
	local finished = false
	s.Watch.Task("quick", { done = function() return finished, "ok" end })
	finished = true
	s.Advance(1)
	T.eq(s.lines[1], "1.00 quick met ok")
end)

T.finish()
