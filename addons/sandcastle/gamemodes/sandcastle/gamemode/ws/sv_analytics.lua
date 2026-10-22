-- The server's analytics (foundation.analysis.analytics): any code may time its
-- work with WS.Analytics:Start()/Stop(name, started) or :Time(name, fn, ...),
-- and count with :Count(name). While ws_analytics is on, each tick is
-- closed as a frame against the tick interval and Lua memory is sampled;
-- off, nothing runs per tick. ws_analytics_print and
-- ws_analytics_reset need the server options privilege, as does
-- ws_analytics_memory, the estimated memory each loaded foundation module holds.
local Analytics = WS.require("foundation.analysis.analytics")
local MemoryReport = WS.require("foundation.analysis.memory")
local Permissions = WS.require("foundation.permissions")

local Clock = {}
function Clock:Now() return SysTime() end

local Memory = {}
function Memory:Kilobytes() return collectgarbage("count") end

WS.Analytics = WS.Analytics or Analytics.New(Clock, Memory)

local ENABLED = CreateConVar("ws_analytics", "0", FCVAR_ARCHIVE,
	"Sample each tick's pressure and Lua memory for ws_analytics_print", 0, 1)

local FRAME_HOOK = "ws_analytics_frame"

local function Apply(on)
	if on then
		hook.Add("Tick", FRAME_HOOK, function() WS.Analytics:Frame(engine.TickInterval()) end)
	else
		hook.Remove("Tick", FRAME_HOOK)
	end
end

cvars.AddChangeCallback("ws_analytics", function(_, _, value) Apply(value == "1") end, FRAME_HOOK)
Apply(ENABLED:GetBool())

local function Admin(ply)
	return WS.Can(ply, Permissions.SERVER_OPTIONS) == true
end

local function Tell(ply, lines)
	for _, line in ipairs(lines) do
		print(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	end
end

concommand.Add("ws_analytics_print", function(ply)
	if not Admin(ply) then return end
	Tell(ply, Analytics.Format(WS.Analytics:Report()))
end, nil, "Print the timers, counters, tick pressure and Lua memory measured so far")

concommand.Add("ws_analytics_reset", function(ply)
	if not Admin(ply) then return end
	WS.Analytics:Reset()
	Tell(ply, { "analytics: reset" })
end, nil, "Forget every measurement so far")

local MEMORY_ROWS_DEFAULT = 25
local FOUNDATION_PREFIX = "^foundation%."

concommand.Add("ws_analytics_memory", function(ply, _, args)
	if not Admin(ply) then return end
	local names = {}
	for name in pairs(package.loaded) do
		if string.find(name, FOUNDATION_PREFIX) then names[#names + 1] = name end
	end
	table.sort(names)
	local roots = {}
	for i, name in ipairs(names) do roots[i] = { name, package.loaded[name] } end
	Tell(ply, MemoryReport.Format(MemoryReport.Measure(roots), tonumber(args[1]) or MEMORY_ROWS_DEFAULT))
end, nil, "Print the estimated Lua memory each loaded foundation module holds, largest first")

-- LuaJIT's sampling profiler through the server's binary module wsprofile
-- (native/ws_profile): every function's share of the Lua running, with no
-- wrappers, and the VM's state while it ran (compiled, interpreted, in C,
-- collecting garbage, compiling). Servers without the module say so.
local SAMPLE_SECONDS_DEFAULT, SAMPLE_SECONDS_MAX = 30, 600
local SAMPLE_ROWS = 25
local SAMPLE_MODE = "fi1" -- by function, every millisecond
local SAMPLE_FORMAT = "F;" -- function names with their modules, outermost first
local SAMPLE_DEPTH = -12
local SAMPLE_TIMER = "ws_analytics_sample"

local function Profiler()
	if wsprofile then return wsprofile end
	if not util.IsBinaryModuleInstalled("wsprofile") then return nil end
	require("wsprofile")
	return wsprofile
end

concommand.Add("ws_analytics_sample", function(ply, _, args)
	if not Admin(ply) then return end
	local profiler = Profiler()
	if not profiler then
		Tell(ply, { "analytics: the wsprofile module is not installed on this server" })
		return
	end
	local seconds = math.Clamp(tonumber(args[1]) or SAMPLE_SECONDS_DEFAULT, 1, SAMPLE_SECONDS_MAX)
	local started, why = profiler.Start(SAMPLE_MODE, SAMPLE_FORMAT, SAMPLE_DEPTH)
	if not started then
		Tell(ply, { "analytics: " .. why })
		return
	end
	Tell(ply, { string.format("analytics: sampling the Lua VM for %d s", seconds) })
	timer.Create(SAMPLE_TIMER, seconds, 1, function()
		Tell(ply, Analytics.FormatSamples(Analytics.SampleReport(profiler.Stop(), SAMPLE_ROWS)))
	end)
end, nil, "Sample the Lua VM for N seconds (default 30) with LuaJIT's profiler and print where it runs")
