-- Runtime analytics: how much CPU time named work takes, how often things
-- happen, how much Lua memory is held, and the pressure on each tick's
-- budget.
--
--   timers    a:Start() -> started; a:Stop(name, started), or a:Time(name,
--             fn, ...). Each keeps count, total, mean, min, max, last, and a
--             95th percentile over its last WINDOW samples.
--   counters  a:Count(name[, n])
--   frames    a:Frame(budget) closes a tick: its pressure is the seconds
--             timed in it over budget (the tick interval), so 1 is a full
--             tick; spans inside other spans count once. Each frame also
--             samples memory.
--
-- Time and memory come through ports: clock:Now() in seconds (SysTime, which
-- reads CPU-side wall time at sub-millisecond resolution) and
-- memory:Kilobytes() (collectgarbage("count")). Recording allocates only a
-- name's first sample, so a timer can wrap per-tick work.
local error, ipairs, pairs, setmetatable, unpack = error, ipairs, pairs, setmetatable, unpack
local ceil, huge, max, min = math.ceil, math.huge, math.max, math.min
local format, gmatch = string.format, string.gmatch
local sort = table.sort
module(...)

-- Samples a timer, the pressure and memory keep for their recent figures.
WINDOW = 128
PERCENTILE = 0.95

local MS_PER_SECOND = 1000
local PERCENT = 100

-- A ring of the last WINDOW values.
local function Ring()
	return {
		values = {},
		next = 1,
		size = 0,
	}
end

local function Push(ring, value)
	ring.values[ring.next] = value
	ring.next = ring.next % WINDOW + 1
	ring.size = min(ring.size + 1, WINDOW)
end

-- The ring's values, oldest first.
local function Ordered(ring)
	local list = {}
	local start = ring.size < WINDOW and 1 or ring.next
	for i = 0, ring.size - 1 do list[#list + 1] = ring.values[(start + i - 1) % WINDOW + 1] end
	return list
end

local function Mean(list)
	if #list == 0 then return 0 end
	local sum = 0
	for _, v in ipairs(list) do sum = sum + v end
	return sum / #list
end

local function Percentile(list, p)
	if #list == 0 then return 0 end
	local sorted = { unpack(list) }
	sort(sorted)
	return sorted[max(1, ceil(p * #sorted))]
end

local Analytics = {}
Analytics.__index = Analytics

function New(clock, memory)
	local a = setmetatable({
		clock = clock,
		memory = memory,
	}, Analytics)
	a:Reset()
	return a
end

function Analytics:Reset()
	self.timers = {}
	self.counters = {}
	self.depth = 0
	self.frameSeconds = 0
	self.frames = 0
	self.overBudget = 0
	self.pressure = Ring()
	self.pressurePeak = 0
	self.memoryTimes = Ring()
	self.memoryKb = Ring()
	self.memoryMin = huge
	self.memoryPeak = 0
end

function Analytics:Start()
	self.depth = self.depth + 1
	return self.clock:Now()
end

function Analytics:Stop(name, started)
	if self.depth == 0 then error("analytics: " .. name .. " stopped with no span started", 2) end
	local seconds = self.clock:Now() - started
	self.depth = self.depth - 1
	if self.depth == 0 then self.frameSeconds = self.frameSeconds + seconds end
	local timer = self.timers[name]
	if not timer then
		timer = {
			count = 0,
			total = 0,
			min = huge,
			max = 0,
			last = 0,
			samples = Ring(),
		}
		self.timers[name] = timer
	end
	timer.count = timer.count + 1
	timer.total = timer.total + seconds
	timer.min = min(timer.min, seconds)
	timer.max = max(timer.max, seconds)
	timer.last = seconds
	Push(timer.samples, seconds)
end

local function Finish(self, name, started, ...)
	self:Stop(name, started)
	return ...
end

function Analytics:Time(name, fn, ...)
	return Finish(self, name, self:Start(), fn(...))
end

function Analytics:Count(name, n)
	self.counters[name] = (self.counters[name] or 0) + (n or 1)
end

-- Close the tick whose budget (seconds) has passed, and sample memory.
function Analytics:Frame(budget)
	local pressure = self.frameSeconds / budget
	self.frameSeconds = 0
	self.frames = self.frames + 1
	if pressure > 1 then self.overBudget = self.overBudget + 1 end
	self.pressurePeak = max(self.pressurePeak, pressure)
	Push(self.pressure, pressure)
	local kb = self.memory:Kilobytes()
	Push(self.memoryTimes, self.clock:Now())
	Push(self.memoryKb, kb)
	self.memoryMin = min(self.memoryMin, kb)
	self.memoryPeak = max(self.memoryPeak, kb)
end

-- A snapshot: { timers = name -> { count, total, mean, min, max, last, p95 },
-- counters = name -> n, pressure = { frames, last, mean, peak, overBudget },
-- memory = { kb, min, peak, growthPerSecond } (kb nil before a frame) }.
function Analytics:Report()
	local timers = {}
	for name, t in pairs(self.timers) do
		timers[name] = {
			count = t.count,
			total = t.total,
			mean = t.total / t.count,
			min = t.min,
			max = t.max,
			last = t.last,
			p95 = Percentile(Ordered(t.samples), PERCENTILE),
		}
	end
	local counters = {}
	for name, n in pairs(self.counters) do counters[name] = n end
	local pressures = Ordered(self.pressure)
	local times, kbs = Ordered(self.memoryTimes), Ordered(self.memoryKb)
	local memory = { growthPerSecond = 0 }
	if #kbs > 0 then
		memory.kb, memory.min, memory.peak = kbs[#kbs], self.memoryMin, self.memoryPeak
		local elapsed = times[#times] - times[1]
		if elapsed > 0 then memory.growthPerSecond = (kbs[#kbs] - kbs[1]) / elapsed end
	end
	return {
		timers = timers,
		counters = counters,
		pressure = {
			frames = self.frames,
			last = pressures[#pressures] or 0,
			mean = Mean(pressures),
			peak = self.pressurePeak,
			overBudget = self.overBudget,
		},
		memory = memory,
	}
end

local function SortedKeys(map, before)
	local keys = {}
	for key in pairs(map) do keys[#keys + 1] = key end
	sort(keys, before)
	return keys
end

-- A report as console lines: pressure, memory, then timers by total time,
-- slowest first, then counters by name.
function Format(report)
	local p, m = report.pressure, report.memory
	local lines = {
		format("pressure: %d frames, last %.1f%%, mean %.1f%%, peak %.1f%%, %d over budget",
			p.frames, p.last * PERCENT, p.mean * PERCENT, p.peak * PERCENT, p.overBudget),
	}
	if m.kb then
		lines[#lines + 1] = format("memory: %.0f kB (least %.0f, most %.0f), %+.1f kB/s",
			m.kb, m.min, m.peak, m.growthPerSecond)
	else
		lines[#lines + 1] = "memory: no frame sampled yet"
	end
	local timers = report.timers
	for _, name in ipairs(SortedKeys(timers, function(a, b) return timers[a].total > timers[b].total end)) do
		local t = timers[name]
		lines[#lines + 1] = format("  %s: %d calls, %.3f ms total, mean %.3f, p95 %.3f, max %.3f ms",
			name, t.count, t.total * MS_PER_SECOND, t.mean * MS_PER_SECOND, t.p95 * MS_PER_SECOND,
			t.max * MS_PER_SECOND)
	end
	for _, name in ipairs(SortedKeys(report.counters)) do
		lines[#lines + 1] = format("  %s: %d", name, report.counters[name])
	end
	return lines
end

-------------------------------------------------------------------------------
-- Sampling: a report of what LuaJIT's sampling profiler counted (the
-- server's wsprofile module): { samples, states = state -> n, stacks =
-- "outer;...;leaf" -> n }.

-- Frames in a stack, outermost first.
local FRAME = "[^;]+"

local function Rows(counts, total, n)
	local rows = {}
	for name, count in pairs(counts) do
		rows[#rows + 1] = {
			name = name,
			count = count,
			share = total > 0 and count / total or 0,
		}
	end
	sort(rows, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	for i = #rows, n + 1, -1 do rows[i] = nil end
	return rows
end

-- The report's lists, each { name, count, share } largest first, the top
-- n of each: states (the VM's: compiled, interpreted, c, gc, compiler),
-- self (the leaf frame: the function running), inclusive (every function
-- on the stack, once per stack) and stacks (whole stacks).
function SampleReport(sampled, n)
	local total = sampled.samples
	local leaves, inclusive = {}, {}
	for stack, count in pairs(sampled.stacks) do
		local seen, leaf = {}, nil
		for frame in gmatch(stack, FRAME) do
			if not seen[frame] then
				seen[frame] = true
				inclusive[frame] = (inclusive[frame] or 0) + count
			end
			leaf = frame
		end
		if leaf then leaves[leaf] = (leaves[leaf] or 0) + count end
	end
	return {
		samples = total,
		states = Rows(sampled.states, total, n),
		self = Rows(leaves, total, n),
		inclusive = Rows(inclusive, total, n),
		stacks = Rows(sampled.stacks, total, n),
	}
end

local function Section(lines, title, rows)
	lines[#lines + 1] = title
	for _, row in ipairs(rows) do
		lines[#lines + 1] = format("%6.1f%% %7d  %s", row.share * PERCENT, row.count, row.name)
	end
end

function FormatSamples(report)
	local lines = { format("samples: %d", report.samples) }
	Section(lines, "-- VM state", report.states)
	Section(lines, "-- self (the function running)", report.self)
	Section(lines, "-- inclusive (on the stack)", report.inclusive)
	Section(lines, "-- stacks", report.stacks)
	return lines
end
