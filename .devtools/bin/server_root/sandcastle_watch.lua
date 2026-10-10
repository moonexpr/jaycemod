-- Events the dedicated server pushes to a watcher (server_watch.py, under
-- Claude Code's Monitor) instead of being polled from the shell. Each is one
-- line appended to data/sandcastle_watch.txt: "<time> <name> <kind> <text>",
-- the kind one of event, changed, met, timeout or error. Set up from
-- server_lua.py (a heredoc), with the global Watch:
--   Watch.Emit(name, text)                     one event
--   Watch.Every(name, seconds, fn)             fn's answer, each time it changes
--   Watch.Until(name, seconds, timeout, check) check() -> ok, report: "met" once
--                                              ok, else "timeout" after timeout
--                                              seconds, with the last report
--   Watch.On(hookName, name, fn)               fn(...)'s answer as the hook runs
--   Watch.Stop(name)
-- A function that errors is reported (error) and its watch stops: silence
-- is never a failure hiding.
local LOG = "sandcastle_watch.txt" -- GMod writes data/ files only with its own extensions: .log is dropped
local TIMER_PREFIX = "sandcastle_watch_"
local HOOK_PREFIX = "sandcastle_watch_"

Watch = Watch or {}
local hooked = Watch.hooked or {} -- name -> the hook it listens to
Watch.hooked = hooked

local function Line(name, kind, text)
	local line = string.format("%.2f %s %s %s", CurTime(), name, kind, tostring(text))
	file.Append(LOG, line:gsub("\n", " ") .. "\n")
end

function Watch.Emit(name, text)
	Line(name, "event", text)
end

function Watch.Stop(name)
	timer.Remove(TIMER_PREFIX .. name)
	if hooked[name] then
		hook.Remove(hooked[name], HOOK_PREFIX .. name)
		hooked[name] = nil
	end
end

-- Runs fn(); an error is reported and stops the watch. Returns ok, results...
local function Guarded(name, fn, ...)
	local results = { pcall(fn, ...) }
	if not results[1] then
		Watch.Stop(name)
		Line(name, "error", results[2])
	end
	return unpack(results)
end

function Watch.Every(name, seconds, fn)
	Watch.Stop(name)
	local last
	timer.Create(TIMER_PREFIX .. name, seconds, 0, function()
		local ok, answer = Guarded(name, fn)
		if not ok then return end
		answer = tostring(answer)
		if answer ~= last then
			last = answer
			Line(name, "changed", answer)
		end
	end)
end

function Watch.Until(name, seconds, timeout, check)
	Watch.Stop(name)
	local deadline = CurTime() + timeout
	timer.Create(TIMER_PREFIX .. name, seconds, 0, function()
		local ok, met, report = Guarded(name, check)
		if not ok then return end
		if met then
			Watch.Stop(name)
			Line(name, "met", report)
		elseif CurTime() >= deadline then
			Watch.Stop(name)
			Line(name, "timeout", report)
		end
	end)
end

function Watch.On(hookName, name, fn)
	Watch.Stop(name)
	hooked[name] = hookName
	hook.Add(hookName, HOOK_PREFIX .. name, function(...)
		local ok, answer = Guarded(name, fn, ...)
		if ok then Line(name, "event", answer) end
	end)
end
