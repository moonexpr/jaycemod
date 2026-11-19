-- The dev workbench's reading of the engine's VProf, through HolyLib's vprof library
-- (https://holylib.raphaelit7.com/vprof), handed in as `lib` so it is tested on a fake:
--   Nodes(lib[, limit]) -> the root's tree as a flat list, depth first: { name, group, depth,
--     calls, totalMs, selfMs, peakMs }, and whether `limit` nodes cut it short
--   ByName(nodes) -> the nodes merged by name and budget group (a scope reached from several
--     parents is one row), most self time first
--   ByGroup(nodes) -> self time by budget group, most first: where the server thread's time went,
--     engine and Lua alike
--   Read(lib[, opts]) -> a report: { enabled, frames, sampledMs, groups, top[, nodes], truncated };
--     opts.rows (top rows, default ROWS), opts.limit (nodes walked, default LIMIT), opts.tree (the
--     flat tree too)
--   Format(report) -> the report as lines of text
--   Scoped(lib, name, group, fn) -> fn wrapped in a scope of its own on the main thread: entered,
--     and left even when fn raises (raised again after); a coroutine's call is left unscoped, since
--     a yield would leave its scope open under whatever the engine runs next
-- Times are milliseconds, as VProf counts them; per frame is per tick on a server.
local error, ipairs, pcall = error, ipairs, pcall
local coroutine_running = coroutine.running
local format = string.format
local max, min = math.max, math.min
local sort = table.sort
module (...)

ROWS         = 25
LIMIT        = 4000
DETAIL_LEVEL = 0 -- VProf's own scopes are level 0, recorded at any detail level

local function GroupName (lib, node)
	local id = node:GetBudgetGroupID ()
	return id and lib.GetBudgetGroupName (id) or "?"
end

function Nodes (lib, limit)
	limit = limit or LIMIT
	local nodes, truncated = {}, false
	local function Walk (node, depth)
		while node do
			if #nodes >= limit then
				truncated = true
				return
			end
			nodes [#nodes + 1] =
			{
				name    = node:GetName (),
				group   = GroupName (lib, node),
				depth   = depth,
				calls   = node:GetTotalCalls (),
				totalMs = node:GetTotalTime (),
				selfMs  = node:GetTotalTimeLessChildren (),
				peakMs  = node:GetPeakTime ()
			}
			Walk (node:GetChild (), depth + 1)
			node = node:GetSibling ()
		end
	end
	Walk (lib.GetRoot ():GetChild (), 1)
	return nodes, truncated
end

local function BySelf (a, b)
	if a.selfMs ~= b.selfMs then return a.selfMs > b.selfMs end
	return a.name < b.name
end

function ByName (nodes)
	local rows, byKey = {}, {}
	for _, node in ipairs (nodes) do
		local key = node.group .. "\0" .. node.name
		local row = byKey [key]
		if not row then
			row =
			{
				name    = node.name,
				group   = node.group,
				calls   = 0,
				totalMs = 0,
				selfMs  = 0,
				peakMs  = 0
			}
			byKey [key] = row
			rows [#rows + 1] = row
		end
		row.calls  = row.calls + node.calls
		row.selfMs = row.selfMs + node.selfMs
		row.peakMs = max (row.peakMs, node.peakMs)
		-- a scope nested in itself would count its time twice: its outermost alone is its total
		if not node.nestedIn then row.totalMs = row.totalMs + node.totalMs end
	end
	sort (rows, BySelf)
	return rows
end

function ByGroup (nodes)
	local rows, byName = {}, {}
	for _, node in ipairs (nodes) do
		local row = byName [node.group]
		if not row then
			row = { name = node.group, selfMs = 0 }
			byName [node.group] = row
			rows [#rows + 1] = row
		end
		row.selfMs = row.selfMs + node.selfMs
	end
	sort (rows, BySelf)
	return rows
end

-- Marks each node nested under a node of the same name and group, whose total holds its own.
local function MarkNested (nodes)
	local open = {}
	for _, node in ipairs (nodes) do
		for depth = #open, node.depth, -1 do open [depth] = nil end
		for depth = 1, node.depth - 1 do
			local above = open [depth]
			if above and above.name == node.name and above.group == node.group then
				node.nestedIn = depth
				break
			end
		end
		open [node.depth] = node
	end
end

local function Head (list, n)
	local head = {}
	for i = 1, min (n, #list) do head [i] = list [i] end
	return head
end

function Read (lib, opts)
	opts = opts or {}
	local nodes, truncated = Nodes (lib, opts.limit)
	MarkNested (nodes)
	local frames, sampledMs = lib.NumFramesSampled (), lib.GetTotalTimeSampled ()
	local perFrame = frames > 0 and frames or 1
	local function Shares (rows)
		for _, row in ipairs (rows) do
			row.perFrameMs = row.selfMs / perFrame
			row.share      = sampledMs > 0 and row.selfMs / sampledMs or 0
		end
		return rows
	end
	local report =
	{
		enabled   = lib.IsEnabled (),
		frames    = frames,
		sampledMs = sampledMs,
		groups    = Shares (ByGroup (nodes)),
		top       = Shares (Head (ByName (nodes), opts.rows or ROWS)),
		truncated = truncated
	}
	if opts.tree then
		for _, node in ipairs (nodes) do node.nestedIn = nil end
		report.nodes = nodes
	end
	return report
end

function Format (report)
	local frames = max (report.frames, 1)
	local lines =
	{
		format ("vprof: %d frames, %.1f ms sampled (%.3f ms/frame)%s%s", report.frames, report.sampledMs,
			report.sampledMs / frames, report.enabled and ", still running" or "",
			report.truncated and ", tree cut short" or "")
	}
	lines [#lines + 1] = "-- by budget group (self ms/frame, share of the time sampled)"
	for _, row in ipairs (report.groups) do
		lines [#lines + 1] = format ("%9.3f ms %6.1f%%  %s", row.perFrameMs, row.share * 100, row.name)
	end
	lines [#lines + 1] = "-- by scope (self ms/frame, total ms/frame, calls/frame, peak ms)"
	for _, row in ipairs (report.top) do
		lines [#lines + 1] = format ("%9.3f ms %9.3f ms %8.1f %8.2f ms  [%s] %s", row.perFrameMs,
			row.totalMs / frames, row.calls / frames, row.peakMs, row.group, row.name)
	end
	return lines
end

local function Leave (lib, ok, ...)
	lib.ExitScope ()
	if not ok then error ((...), 0) end
	return ...
end

function Scoped (lib, name, group, fn)
	local EnterScope = lib.EnterScope
	return function (...)
		if coroutine_running () then return fn (...) end
		EnterScope (name, DETAIL_LEVEL, group)
		return Leave (lib, pcall (fn, ...))
	end
end
