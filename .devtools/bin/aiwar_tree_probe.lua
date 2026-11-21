-- What a soldier's behaviour tree costs, by action and method, for a window and then put back,
-- run through dt lua:
--
--   dt lua -f .devtools/bin/aiwar_tree_probe.lua    defines TreeProbe
--   dt lua 'return TreeProbe.Start(15)'             every registered action's methods timed 15 s
--   dt lua 'return TreeProbe.Report(25)'            the most demanding, and the engine's share
--
-- The engine (nextsoldier.engine) calls an action's methods one after another, never one inside
-- another, so each method's time is its own. engine.Update is timed around them all: what it
-- spends beyond them is the engine's walk of the stacks.
TreeProbe = TreeProbe or {}
local P = TreeProbe
local SysTime = SysTime

local function Stat () return { calls = 0, spent = 0, worst = 0 } end

local function Timed (fn, stat)
	return function (...)
		local started = SysTime ()
		local a, b, c, d, e, f = fn (...)
		local spent = SysTime () - started
		stat.calls, stat.spent = stat.calls + 1, stat.spent + spent
		if spent > stat.worst then stat.worst = spent end
		return a, b, c, d, e, f
	end
end

function P.Start (seconds)
	if P.running then return "running" end
	local stats, wrapped = {}, {}
	for name, class in pairs (action_registry.GetAll ()) do
		for key, fn in pairs (class) do
			if isfunction (fn) and isstring (key) and key:match ("^%u") then
				local stat = Stat ()
				stats [name .. ":" .. key] = stat
				wrapped [#wrapped + 1] = { class, key, fn }
				rawset (class, key, Timed (fn, stat))
			end
		end
	end
	local engine = nextsoldier.engine
	local update = engine.Update
	P.engineStat = Stat ()
	engine.Update = Timed (update, P.engineStat)
	P.stats, P.seconds, P.running = stats, seconds, true
	timer.Simple (seconds, function ()
		for _, w in ipairs (wrapped) do rawset (w [1], w [2], w [3]) end
		engine.Update = update
		P.running = false
	end)
	return string.format ("measuring %d s: %d methods", seconds, #wrapped)
end

function P.Report (rows)
	if P.running then return "measuring" end
	if not P.stats then return "nothing measured" end
	local lines, actions = {}, 0
	for _, stat in pairs (P.stats) do actions = actions + stat.spent end
	local engine = P.engineStat
	lines [1] = string.format ("engine.Update %6.1f ms/s, %d calls, %.0f us each; the actions' methods %6.1f ms/s",
		engine.spent * 1000 / P.seconds, engine.calls, engine.spent * 1e6 / math.max (engine.calls, 1),
		actions * 1000 / P.seconds)
	local order = {}
	for key, stat in pairs (P.stats) do
		if stat.calls > 0 then order [#order + 1] = key end
	end
	table.sort (order, function (a, b) return P.stats [a].spent > P.stats [b].spent end)
	for i = 1, math.min (rows or 25, #order) do
		local stat = P.stats [order [i]]
		lines [#lines + 1] = string.format ("%-48s %6.1f ms/s n=%6d %7.1f us worst %6.2f ms", order [i],
			stat.spent * 1000 / P.seconds, stat.calls, stat.spent * 1e6 / stat.calls, stat.worst * 1000)
	end
	return table.concat (lines, "\n")
end
