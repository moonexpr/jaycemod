-- Path-search measurements: how long the NextBots' path computes take, how
-- much of that is the Lua cost callback, and whether either is worth moving
-- off the main thread. The npc controller records one sample per
-- Path:Compute while a window is open; samples are
--   { label, seconds, costCalls, costSeconds, found }
-- with label the variant that asked. Times come from the caller's clock
-- (SysTime), so a sample includes the clock's own overhead.
--
-- A bench computes paths back to back, each goal once with the engine's own
-- cost (BENCH_ENGINE_LABEL) and once with the variant's Lua cost, so it
-- measures per-compute cost and the Lua overhead, not a share of play time.
local ceil, max, min = math.ceil, math.max, math.min
local format = string.format
local ipairs, setmetatable, sort = ipairs, setmetatable, table.sort
module(...)

-- The lines Verdict draws. Path work over TIME_SHARE of server time, or one
-- compute as long as a whole tick (a visible hitch), is worth offloading.
TIME_SHARE = 0.05
COST_SHARE = 0.5 -- over this share of compute time in the Lua callback, the callback is the problem

BENCH_ENGINE_LABEL = "engine cost"

VERDICT_NONE = "none"
VERDICT_KEEP = "keep"
VERDICT_COST = "cost"
VERDICT_SEARCH = "search"

local VERDICT_TEXT = {
	[VERDICT_NONE] = "no path was computed in the window; spawn NextBots or run ws_path_bench",
	[VERDICT_KEEP] = "below both thresholds: the engine's search with the Lua cost is cheap enough, keep it",
	[VERDICT_COST] = "over a threshold, mostly in the Lua cost callback: make the cost cheaper (or tabled) before offloading the search",
	[VERDICT_SEARCH] = "over a threshold, mostly in the engine's search: an off-thread search (a binary module) is the lever",
}

local Profile = {}
Profile.__index = Profile

function New(now, bench)
	return setmetatable({ started = now, bench = bench == true, samples = {} }, Profile)
end

function Profile:Record(sample)
	self.samples[#self.samples + 1] = sample
end

-- Nearest rank: the smallest value with at least fraction p of the values at
-- or below it.
local function Percentile(sorted, p)
	return sorted[max(1, min(#sorted, ceil(p * #sorted)))]
end

local function Labels(samples)
	local byLabel, list = {}, {}
	for _, s in ipairs(samples) do
		local entry = byLabel[s.label]
		if not entry then
			entry = { label = s.label, count = 0, totalSeconds = 0, max = 0 }
			byLabel[s.label] = entry
			list[#list + 1] = entry
		end
		entry.count = entry.count + 1
		entry.totalSeconds = entry.totalSeconds + s.seconds
		entry.max = max(entry.max, s.seconds)
	end
	for _, entry in ipairs(list) do entry.mean = entry.totalSeconds / entry.count end
	sort(list, function(a, b)
		if a.totalSeconds ~= b.totalSeconds then return a.totalSeconds > b.totalSeconds end
		return a.label < b.label
	end)
	return list
end

-- The window's summary at `now`.
function Profile:Report(now)
	local samples = self.samples
	local window = now - self.started
	local report = {
		window = window,
		bench = self.bench,
		count = #samples,
		failed = 0,
		totalSeconds = 0,
		costCalls = 0,
		costSeconds = 0,
		max = 0,
		labels = Labels(samples),
	}
	local durations = {}
	for i, s in ipairs(samples) do
		durations[i] = s.seconds
		report.totalSeconds = report.totalSeconds + s.seconds
		report.costCalls = report.costCalls + s.costCalls
		report.costSeconds = report.costSeconds + s.costSeconds
		report.max = max(report.max, s.seconds)
		if not s.found then report.failed = report.failed + 1 end
	end
	if report.count == 0 then return report end
	sort(durations)
	report.mean = report.totalSeconds / report.count
	report.p50 = Percentile(durations, 0.5)
	report.p95 = Percentile(durations, 0.95)
	report.costShare = report.totalSeconds > 0 and report.costSeconds / report.totalSeconds or 0
	report.perSecond = window > 0 and report.count / window or 0
	report.frameShare = window > 0 and report.totalSeconds / window or 0
	return report
end

function Verdict(report, tickInterval)
	if report.count == 0 then return VERDICT_NONE end
	if report.frameShare < TIME_SHARE and report.max < tickInterval then return VERDICT_KEEP end
	if report.costShare >= COST_SHARE then return VERDICT_COST end
	return VERDICT_SEARCH
end

local function Ms(seconds)
	return format("%.3f ms", seconds * 1000)
end

local function Percent(fraction)
	return format("%.0f%%", fraction * 100)
end

-- A bench's paired difference: the mean Lua-cost compute less the mean
-- engine-cost compute, or nil without both.
local function LuaOverhead(labels)
	local engine, luaTotal, luaCount = nil, 0, 0
	for _, entry in ipairs(labels) do
		if entry.label == BENCH_ENGINE_LABEL then
			engine = entry.mean
		else
			luaTotal, luaCount = luaTotal + entry.totalSeconds, luaCount + entry.count
		end
	end
	if engine == nil or luaCount == 0 then return nil end
	return luaTotal / luaCount - engine
end

local function Common(report, tickInterval, title)
	return {
		format("%s: %d computes in %.1f s (%.1f/s), %d found no path",
			title, report.count, report.window, report.perSecond, report.failed),
		format("  compute: mean %s, p50 %s, p95 %s, max %s (a tick is %s)",
			Ms(report.mean), Ms(report.p50), Ms(report.p95), Ms(report.max), Ms(tickInterval)),
		format("  Lua cost callback: %d calls (%.0f per compute), %s of compute time",
			report.costCalls, report.costCalls / report.count, Percent(report.costShare)),
	}
end

local function AddLabels(lines, report)
	for _, entry in ipairs(report.labels) do
		lines[#lines + 1] = format("  %s: %d computes, mean %s, max %s, %s total",
			entry.label, entry.count, Ms(entry.mean), Ms(entry.max), Ms(entry.totalSeconds))
	end
end

local function FormatBench(report, tickInterval)
	local lines = Common(report, tickInterval, "path bench")
	AddLabels(lines, report)
	local overhead = LuaOverhead(report.labels)
	if overhead then
		lines[#lines + 1] = format("  the Lua cost adds %s per compute over the engine's own cost", Ms(overhead))
	end
	lines[#lines + 1] = "  a bench measures single computes; run ws_path_profile during play for their share of server time"
	return lines
end

-- The report as console lines.
function Format(report, tickInterval)
	if report.bench and report.count > 0 then return FormatBench(report, tickInterval) end
	local verdict = Verdict(report, tickInterval)
	if report.count == 0 then return { "path profile: " .. VERDICT_TEXT[verdict] } end
	local lines = Common(report, tickInterval, "path profile")
	lines[#lines + 1] = format("  path work: %s per second of server time (%s)",
		Ms(report.frameShare), Percent(report.frameShare))
	AddLabels(lines, report)
	lines[#lines + 1] = format("  thresholds: %s of server time, or one compute of a whole tick; callback-bound over %s",
		Percent(TIME_SHARE), Percent(COST_SHARE))
	lines[#lines + 1] = "  verdict: " .. VERDICT_TEXT[verdict]
	return lines
end
