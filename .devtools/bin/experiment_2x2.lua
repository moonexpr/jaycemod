-- A 2x2 experiment on the dedicated server: two treatments switched by
-- convars, each condition measured in blocks of BLOCK seconds in a
-- counterbalanced order (ABBA), the first WARMUP seconds of each block left
-- out. Run through server_lua.py:
--
--   server_lua.py -f .devtools/bin/experiment_2x2.lua        defines WSExperiment
--   server_lua.py 'return WSExperiment.Start()'               runs every block
--   server_lua.py 'return WSExperiment.Report()'              the results, by condition
--
-- The treatments: A, mp_aiwar_revive_enabled (respawn waves revive fallen
-- soldiers); B, ws_jit_enabled 0 (LuaJIT's compiler off). Per block: the
-- ticks' wall times, each AI war draft (revived or created) and wave, the
-- deaths, and, when the wsprofile module is loaded, the Lua VM's share of
-- the server thread (samples outside the hook dispatcher's own frame).
WSExperiment = WSExperiment or {}
local E = WSExperiment

E.BLOCK, E.WARMUP = 60, 10
local DISPATCHER = "hook.lua:98" -- the frame samples outside Lua are charged to
local LONG_TICK = 0.05

local CONDITIONS = {
	control = { revive = "0", jit = "1" },
	A = { revive = "1", jit = "1" },
	B = { revive = "0", jit = "0" },
	AB = { revive = "1", jit = "0" },
}
E.ORDER = { "control", "A", "B", "AB", "AB", "B", "A", "control" }

local function Percentile(sorted, p)
	if #sorted == 0 then return 0 end
	return sorted[math.max(1, math.ceil(#sorted * p))]
end

local current, lastTick
local restore = {}

local function Wrap(controller, name, record)
	local fn = controller[name]
	restore[#restore + 1] = { controller, name, fn }
	controller[name] = function(self, ...)
		local started = SysTime()
		local a, b = fn(self, ...)
		if current and current.measuring then record(current, SysTime() - started, a) end
		return a, b
	end
end

local function Instrument()
	local aw = WS.Feature("aiwar")
	Wrap(aw, "Draft", function(block, seconds)
		block.drafts[#block.drafts + 1] = seconds
	end)
	Wrap(aw, "Revive", function(block, _, ent)
		if ent ~= nil then block.revived = block.revived + 1 end
	end)
	Wrap(aw, "Reinforce", function(block, seconds)
		if seconds > block.worstWave then block.worstWave = seconds end
	end)
	hook.Add("OnNPCKilled", "ws_experiment", function()
		if current and current.measuring then current.deaths = current.deaths + 1 end
	end)
	hook.Add("Tick", "ws_experiment", function()
		local now = SysTime()
		if current and current.measuring and lastTick then current.ticks[#current.ticks + 1] = now - lastTick end
		lastTick = now
	end)
end

local function Uninstrument()
	for i = #restore, 1, -1 do restore[i][1][restore[i][2]] = restore[i][3] end
	restore = {}
	hook.Remove("OnNPCKilled", "ws_experiment")
	hook.Remove("Tick", "ws_experiment")
end

local function Apply(condition)
	local c = CONDITIONS[condition]
	RunConsoleCommand("mp_aiwar_revive_enabled", c.revive)
	RunConsoleCommand("ws_jit_enabled", c.jit)
end

local function StartBlock(i)
	if i > #E.ORDER then
		current = nil
		Uninstrument()
		Apply("control")
		E.running = false
		return
	end
	Apply(E.ORDER[i])
	current = {
		condition = E.ORDER[i],
		measuring = false,
		ticks = {},
		drafts = {},
		revived = 0,
		deaths = 0,
		worstWave = 0,
	}
	E.blocks[i] = current
	local block = current
	timer.Simple(E.WARMUP, function()
		block.measuring = true
		block.started = CurTime()
		if wsprofile then wsprofile.Start("fi1", "F;", -2) end
	end)
	timer.Simple(E.BLOCK, function()
		block.measuring = false
		if wsprofile then block.sampled = wsprofile.Stop() end
		StartBlock(i + 1)
	end)
end

function E.Start()
	if E.running then return "already running" end
	E.running, E.blocks = true, {}
	if not wsprofile and util.IsBinaryModuleInstalled("wsprofile") then require("wsprofile") end
	Instrument()
	StartBlock(1)
	return string.format("%d blocks of %d s: %s", #E.ORDER, E.BLOCK, table.concat(E.ORDER, ", "))
end

-- One block's figures.
local function Measure(block)
	local ticks = {}
	for i, t in ipairs(block.ticks) do ticks[i] = t end
	table.sort(ticks)
	local long, sum = 0, 0
	for _, t in ipairs(ticks) do
		sum = sum + t
		if t > LONG_TICK then long = long + 1 end
	end
	local drafts, draftSum, draftMax = block.drafts, 0, 0
	for _, t in ipairs(drafts) do draftSum, draftMax = draftSum + t, math.max(draftMax, t) end
	local lua, states = nil, {}
	local sampled = block.sampled
	if sampled and sampled.samples > 0 then
		local outside = 0
		for stack, n in pairs(sampled.stacks) do
			if stack == DISPATCHER or stack == DISPATCHER .. ";" then outside = outside + n end
		end
		lua = 1 - outside / sampled.samples
		for state, n in pairs(sampled.states) do states[state] = n / sampled.samples end
	end
	return {
		p50 = Percentile(ticks, 0.5),
		p95 = Percentile(ticks, 0.95),
		p99 = Percentile(ticks, 0.99),
		max = ticks[#ticks] or 0,
		long = long,
		ticks = #ticks,
		drafts = #drafts,
		revived = block.revived,
		draftMean = #drafts > 0 and draftSum / #drafts or 0,
		draftMax = draftMax,
		worstWave = block.worstWave,
		deaths = block.deaths,
		lua = lua,
		states = states,
	}
end

local MS = 1000

function E.Report()
	local lines = { string.format("%s; blocks done: %d of %d", E.running and "running" or "finished", #(E.blocks or {}), #E.ORDER) }
	lines[#lines + 1] = "block condition  tick p50/p95/p99/max ms   >50ms  deaths  drafts(revived)  draft mean/max ms  worst wave ms  Lua share  interp/compiled/compiler/gc"
	for i, block in ipairs(E.blocks or {}) do
		if block.started then
			local m = Measure(block)
			local s = m.states
			lines[#lines + 1] = string.format("%5d %-9s %5.1f/%5.1f/%5.1f/%6.1f  %5d  %6d  %6d(%d)  %7.1f/%6.1f  %8.1f  %8s  %s",
				i, block.condition, m.p50 * MS, m.p95 * MS, m.p99 * MS, m.max * MS, m.long, m.deaths, m.drafts, m.revived,
				m.draftMean * MS, m.draftMax * MS, m.worstWave * MS,
				m.lua and string.format("%.1f%%", m.lua * 100) or "-",
				m.lua and string.format("%.0f/%.0f/%.0f/%.0f%%", (s.interpreted or 0) * 100, (s.compiled or 0) * 100, (s.compiler or 0) * 100, (s.gc or 0) * 100) or "-")
		end
	end
	return table.concat(lines, "\n")
end
