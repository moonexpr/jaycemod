-- What the AI war costs the server thread, measured for a window and then
-- taken off again, run through server_lua.py:
--
--   server_lua.py -f .devtools/bin/aiwar_tick_probe.lua   defines WarProbe
--   server_lua.py 'return WarProbe.Start(60)'             wrap, measure 60 s, unwrap
--   server_lua.py 'return WarProbe.Summary()'             the war's share, with its interval
--   server_lua.py 'return WarProbe.Hooks()'               each of its hooks
--   server_lua.py 'return WarProbe.Methods(30)'           the controller's most demanding methods
--   server_lua.py 'return WarProbe.Start(30, true)'       hooks alone, no method wrapped (the bench's)
--   server_lua.py 'return WarProbe.Data()'                the window's figures as JSON (aiwar_bench.py)
--
-- It wraps the aiwar controller's methods, the bot soldier's (BotSoldier.*)
-- and its navigator's (Navigator.*), and the war's hooks (inclusive time, calls, worst call). Each tick it notes the
-- time the war's hooks took and the tick's own length, so a hitch shows as a
-- long tick and as the war's share of it. The war's time is also summed
-- over one-second batches: their mean with a 95 % interval (batch means) is
-- the figure to compare runs by, and their lag-1 autocorrelation says
-- whether a second is long enough a batch (near 0: it is).
--
-- The wrappers add about two SysTime calls a call, which inflates tiny, hot
-- methods (ShutDoorIn). A method that yields is not wrapped rightly; the
-- controller's do not.
WarProbe = WarProbe or {}
local P = WarProbe

local SysTime, unpack, maxn = SysTime, unpack, table.maxn

local WAR_HOOKS =
{
	{ "Think", "ws_aiwar" },
	{ "Think", "ws_aiwar_bots" },
	{ "Think", "ws_aiwar_intel" },
	{ "Think", "ws_aiwar_greetings" },
	{ "Think", "ws_aiwar_idle_chatter" },
	{ "Think", "ws_aiwar_celebrations" },
	{ "Tick", "ws_aiwar_move" },
	{ "StartCommand", "ws_aiwar_bots" }
}
-- Timed beside the war, outside its share: the route searches it asks for.
local OTHER_HOOKS =
{
	{ "Think", "ws_npc_spawners" }
}
local TICK_HOOK, WINDOW_TIMER = "war_probe_tick", "war_probe_window"
local BATCH_SECONDS = 1
-- Student's t at 95 %, two-sided, by degrees of freedom; 1.96 beyond.
local T95 = { 12.71, 4.30, 3.18, 2.78, 2.57, 2.45, 2.36, 2.31, 2.26, 2.23, 2.20, 2.18, 2.16, 2.14, 2.13,
	2.12, 2.11, 2.10, 2.09, 2.09, 2.08, 2.07, 2.07, 2.06, 2.06, 2.06, 2.05, 2.05, 2.05, 2.04 }

local function Stat () return { n = 0, t = 0, worst = 0 } end

local function Timed (fn, stat, also)
	return function (...)
		local started = SysTime ()
		local results = { fn (...) }
		local took = SysTime () - started
		stat.n = stat.n + 1
		stat.t = stat.t + took
		if took > stat.worst then stat.worst = took end
		if also then also.now = also.now + took end
		return unpack (results, 1, maxn (results))
	end
end

local function WrapHooks (run, list, tick)
	for _, h in ipairs (list) do
		local event, id = h [1], h [2]
		local fn = hook.GetTable () [event] and hook.GetTable () [event] [id]
		if fn then
			local stat = Stat ()
			run.hooks [event .. "/" .. id] = stat
			run.hooked [#run.hooked + 1] = { event, id, fn }
			hook.Add (event, id, Timed (fn, stat, tick))
		end
	end
end

function P.Unwrap ()
	local run = P.run
	if not run or run.done then return end
	for key, fn in pairs (run.methods) do run.controller [key] = fn end
	for _, c in ipairs (run.classed) do c [1] [c [2]] = c [3] end
	for _, h in ipairs (run.hooked) do hook.Add (h [1], h [2], h [3]) end
	hook.Remove ("Tick", TICK_HOOK)
	timer.Remove (WINDOW_TIMER)
	run.elapsed = SysTime () - run.started
	run.done = true
end

function P.Start (seconds, hooksOnly)
	if P.run and not P.run.done then return "a window is open" end
	local controller = WS.Feature ("aiwar")
	if not controller.war then return "no war is running" end
	local run =
	{
		controller = controller,
		methods = {},
		classed = {},
		stats = {},
		hooks = {},
		hooked = {},
		started = SysTime (),
		tick = { now = 0 },
		search = { now = 0 },
		warTicks = {},
		searchTicks = {},
		tickLengths = {},
		batches = {}
	}
	P.run = run
	for key, fn in pairs (hooksOnly and {} or controller) do
		if type (fn) == "function" then
			run.methods [key], run.stats [key] = fn, Stat ()
			controller [key] = Timed (fn, run.stats [key])
		end
	end
	-- the bot soldier's own methods, and its navigator's plan: where a look's steering goes
	local navigator = scripted_ents.GetStored ("ws_bot_navigator")
	local classes = hooksOnly and {} or { BotSoldier = controller.BotSoldier, Navigator = navigator and navigator.t }
	for prefix, class in pairs (classes) do
		for key, fn in pairs (class) do
			if type (fn) == "function" then
				local name = prefix .. "." .. key
				run.stats [name] = Stat ()
				run.classed [#run.classed + 1] = { class, key, fn }
				class [key] = Timed (fn, run.stats [name])
			end
		end
	end
	WrapHooks (run, WAR_HOOKS,   run.tick)
	WrapHooks (run, OTHER_HOOKS, run.search)
	local last, batchStarted, batch = SysTime (), SysTime (), 0
	hook.Add ("Tick", TICK_HOOK, function ()
		local now = SysTime ()
		run.warTicks [#run.warTicks + 1] = run.tick.now
		run.searchTicks [#run.searchTicks + 1] = run.search.now
		run.tickLengths [#run.tickLengths + 1] = now - last
		batch = batch + run.tick.now
		run.tick.now, run.search.now, last = 0, 0, now
		if now - batchStarted >= BATCH_SECONDS then
			run.batches [#run.batches + 1] = batch / (now - batchStarted)
			batch, batchStarted = 0, now
		end
	end)
	timer.Create (WINDOW_TIMER, seconds, 1, P.Unwrap)
	local soldiers = 0
	for _ in pairs (controller.soldiers) do soldiers = soldiers + 1 end
	run.soldiers, run.map = soldiers, game.GetMap ()
	return string.format ("measuring %d s: %d soldiers on %s", seconds, soldiers, run.map)
end

local function Percentile (sorted, p)
	return sorted [math.max (1, math.ceil (#sorted * p))]
end

local function Sorted (list)
	local copy = {}
	for i, v in ipairs (list) do copy [i] = v end
	table.sort (copy)
	return copy
end

local function Finished ()
	local run = P.run
	if not run then return nil, "no window was measured" end
	if not run.done then return nil, string.format ("measuring: %.0f s left", timer.TimeLeft (WINDOW_TIMER) or 0) end
	return run
end

function P.Summary ()
	local run, why = Finished ()
	if not run then return why end
	local batches, n = run.batches, #run.batches
	local mean = 0
	for _, v in ipairs (batches) do mean = mean + v end
	mean = mean / n
	local variance, lag = 0, 0
	for i, v in ipairs (batches) do
		variance = variance + (v - mean) ^ 2
		if batches [i + 1] then lag = lag + (v - mean) * (batches [i + 1] - mean) end
	end
	local half = (T95 [n - 1] or 1.96) * math.sqrt (variance / (n - 1) / n)
	local war, lengths = Sorted (run.warTicks), Sorted (run.tickLengths)
	local interval = engine.TickInterval ()
	local long = 0
	for _, v in ipairs (run.tickLengths) do
		if v > interval * 2 then long = long + 1 end
	end
	return table.concat (
		{
			string.format ("%s, %d soldiers at the start, %.1f s, %d ticks", run.map, run.soldiers, run.elapsed, #run.warTicks),
			string.format ("war: %.1f +- %.1f ms/s (95 %%, %d batches, lag-1 %.2f)", mean * 1000, half * 1000, n,
				lag / variance),
			string.format ("war per tick: p50 %.2f  p95 %.2f  p99 %.2f  max %.2f ms", Percentile (war, 0.5) * 1000,
				Percentile (war, 0.95) * 1000, Percentile (war, 0.99) * 1000, war [#war] * 1000),
			string.format ("tick length: p50 %.1f  p95 %.1f  p99 %.1f  max %.1f ms; %d of %d over twice the interval (%.1f ms)",
				Percentile (lengths, 0.5) * 1000, Percentile (lengths, 0.95) * 1000, Percentile (lengths, 0.99) * 1000,
				lengths [#lengths] * 1000, long, #lengths, interval * 2000)
		}, "\n")
end

local function Rows (stats, elapsed, limit)
	local rows = {}
	for name, stat in pairs (stats) do
		if stat.n > 0 then rows [#rows + 1] = { name = name, stat = stat } end
	end
	table.sort (rows, function (a, b) return a.stat.t > b.stat.t end)
	local lines = {}
	for i = 1, math.min (#rows, limit) do
		local stat = rows [i].stat
		lines [i] = string.format ("%-28s %8.2f ms/s  n=%-7d mean %8.1f us  worst %7.2f ms", rows [i].name,
			stat.t * 1000 / elapsed, stat.n, stat.t / stat.n * 1e6, stat.worst * 1000)
	end
	return table.concat (lines, "\n")
end

function P.Hooks ()
	local run, why = Finished ()
	if not run then return why end
	return Rows (run.hooks, run.elapsed, 20)
end

function P.Methods (limit)
	local run, why = Finished ()
	if not run then return why end
	return Rows (run.stats, run.elapsed, limit or 30)
end

-- One window's figures, seconds throughout: what aiwar_bench.py compares replications by. `both` is
-- the war and its route searches together in a tick, what the tick's budget is judged on.
function P.Data ()
	local run, why = Finished ()
	if not run then return util.TableToJSON ({ error = why }) end
	local both = {}
	for i, v in ipairs (run.warTicks) do both [i] = v + run.searchTicks [i] end
	local war, search, sum = Sorted (run.warTicks), Sorted (run.searchTicks), Sorted (both)
	local function Total (list)
		local t = 0
		for _, v in ipairs (list) do t = t + v end
		return t
	end
	local function Tail (sorted)
		return
		{
			p50 = Percentile (sorted, 0.5),
			p99 = Percentile (sorted, 0.99),
			max = sorted [#sorted]
		}
	end
	local interval, over = engine.TickInterval (), 0
	for _, v in ipairs (both) do
		if v > interval then over = over + 1 end
	end
	return util.TableToJSON (
		{
			map = run.map,
			soldiers = run.soldiers,
			elapsed = run.elapsed,
			ticks = #run.warTicks,
			interval = interval,
			war = { rate = Total (run.warTicks) / run.elapsed, tail = Tail (war) },
			search = { rate = Total (run.searchTicks) / run.elapsed, tail = Tail (search) },
			both = { rate = Total (both) / run.elapsed, tail = Tail (sum), over = over }
		}
	)
end
