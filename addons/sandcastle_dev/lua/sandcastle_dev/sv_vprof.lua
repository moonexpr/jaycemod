-- The engine's own profiler, VProf, read as data through HolyLib's vprof library
-- (https://holylib.raphaelit7.com/vprof): where the server thread's time goes by budget group and
-- by scope, the engine's C++ (NextBots, physics, networking) beside the Lua the gamemode runs. It
-- answers what the LuaJIT sampler (wsprofile, ws_analytics_sample) cannot: the sampler charges
-- every sample taken outside Lua to the next Lua entry point, the hook dispatcher, and VProf names
-- that time. HolyLib's vprof module scopes GMod's own calls into Lua (CLuaGamemode::Call (<hook>),
-- CScriptedEntity::Call (...)) in the budget group GMOD, and, with holylib_vprof_trackscripts 1,
-- every script GMod calls into, by its line and source; profile_server.lua's { vprof = true }
-- scopes the functions it wraps, in the group WSProfile.
--
-- Needs HolyLib on the server with its vprof module on (holylib_enable_vprof); without it each
-- function refuses, saying so. The report is read from the tree, not HolyLib's text export
-- (holylib_vprof_exportreport), which its x86-64 build does not capture.
local VProf = dev.require ("sandcastle_dev_vprof")

local V = {}
dev.vprof = V

local WINDOW_TIMER = "sandcastle_dev_vprof_window"
local WINDOW_SECONDS_MAX = 600
-- the LuaJIT sampler's settings, as ws_analytics_sample's
local SAMPLE_MODE, SAMPLE_FORMAT, SAMPLE_DEPTH = "fi1", "F;", -12
-- what the window running started, which its end or a cancel stops
local windowSampler, windowStartedVProf = nil, false

local function Library ()
	if not vprof then
		dev.Fail ("HolyLib's vprof library is not loaded: install HolyLib on this server "
			.. "(its .vdf in addons/, its gmsv_holylib binary in lua/bin) and set holylib_enable_vprof 1")
	end
	return vprof
end

local function ConVarValue (name)
	local convar = GetConVar (name)
	return convar and convar:GetString () or nil
end

-- The wsprofile binary module, when the server has it.
local function Sampler ()
	if wsprofile then return wsprofile end
	if not util.IsBinaryModuleInstalled ("wsprofile") then return nil end
	require ("wsprofile")
	return wsprofile
end

function V.status ()
	local lib = vprof
	local status =
	{
		loaded       = lib ~= nil,
		window       = timer.Exists (WINDOW_TIMER),
		trackscripts = ConVarValue ("holylib_vprof_trackscripts"),
		exportreport = ConVarValue ("holylib_vprof_exportreport")
	}
	if lib then
		status.enabled     = lib.IsEnabled ()
		status.frames      = lib.NumFramesSampled ()
		status.sampledMs   = lib.GetTotalTimeSampled ()
		status.lastFrameMs = lib.GetTimeLastFrame ()
		status.peakFrameMs = lib.GetPeakFrameTime ()
		status.counters    = lib.GetNumCounters ()
	end
	return status
end

-- opts.scripts: a scope for every script GMod calls into (holylib_vprof_trackscripts), which
-- stays as set; opts.keep: add to what VProf has, not reset it first.
function V.start (opts)
	opts = opts or {}
	local lib = Library ()
	if opts.scripts ~= nil then RunConsoleCommand ("holylib_vprof_trackscripts", opts.scripts and "1" or "0") end
	if not opts.keep then lib.Reset () end
	if not lib.IsEnabled () then lib.Start () end
	return V.status ()
end

function V.stop (opts)
	local lib = Library ()
	if lib.IsEnabled () then lib.Stop () end
	return V.report (opts)
end

-- opts.rows, opts.limit, opts.tree as sandcastle_dev_vprof's Read; opts.text adds its lines.
function V.report (opts)
	opts = opts or {}
	local report = VProf.Read (Library (), opts)
	if opts.text then report.text = VProf.Format (report) end
	return report
end

function V.reset ()
	local lib = Library ()
	lib.Reset ()
	lib.ResetPeaks ()
	return V.status ()
end

function V.counters ()
	local lib = Library ()
	local counters = {}
	for i = 0, lib.GetNumCounters () - 1 do
		local counter = lib.GetCounter (i)
		if counter then counters [#counters + 1] = { name = counter:GetName (), value = counter:Get () } end
	end
	return { counters = counters }
end

-- VProf run for `seconds` from nothing, then stopped and read into dev.last_vprof; opts as
-- start's and report's, and opts.sample: the LuaJIT sampler over the same window (its report in
-- dev.last_vprof.lua), so the Lua's own breakdown stands beside the engine's. Asynchronous.
function V.window (seconds, opts)
	opts = opts or {}
	seconds = tonumber (seconds)
	if not seconds or seconds <= 0 or seconds > WINDOW_SECONDS_MAX then
		dev.Fail ("a window is 0 to " .. WINDOW_SECONDS_MAX .. " seconds, not " .. tostring (seconds))
	end
	local lib = Library ()
	local sampler = opts.sample and Sampler ()
	if opts.sample and not sampler then dev.Fail ("the wsprofile module is not installed on this server") end
	if timer.Exists (WINDOW_TIMER) then V.cancel () end
	if sampler then
		local started, why = sampler.Start (SAMPLE_MODE, SAMPLE_FORMAT, SAMPLE_DEPTH)
		if not started then dev.Fail ("wsprofile: " .. tostring (why)) end
	end
	windowSampler, windowStartedVProf = sampler or nil, not lib.IsEnabled ()
	V.start (opts)
	dev.last_vprof = nil
	local began = SysTime ()
	timer.Create (WINDOW_TIMER, seconds, 1, function ()
		if windowStartedVProf and lib.IsEnabled () then lib.Stop () end
		windowSampler, windowStartedVProf = nil, false
		local report = VProf.Read (lib, opts)
		report.seconds = SysTime () - began
		if opts.text then report.text = VProf.Format (report) end
		if sampler then
			local Analytics = analysis and analysis.analytics
			local samples = sampler.Stop ()
			report.lua = Analytics and Analytics.SampleReport (samples, opts.rows or VProf.ROWS) or samples
		end
		dev.last_vprof = report
	end)
	return { seconds = seconds, sample = sampler ~= nil, result = "dev.last_vprof" }
end

-- Ends a window early, stopping what it started, and leaves dev.last_vprof unset.
function V.cancel ()
	timer.Remove (WINDOW_TIMER)
	if windowSampler then windowSampler.Stop () end
	if windowStartedVProf and vprof and vprof.IsEnabled () then vprof.Stop () end
	windowSampler, windowStartedVProf = nil, false
	return V.status ()
end

-- The words a command takes: numbers as rows or seconds, "scripts", "sample", "tree", "keep".
local function Options (args, first)
	local opts = { text = true }
	for i = first, #args do
		local word = args [i]
		if tonumber (word) then
			opts.rows = tonumber (word)
		elseif word == "scripts" or word == "sample" or word == "tree" or word == "keep" then
			opts [word] = true
		else
			dev.Fail ("unknown option " .. word .. ": rows (a number), scripts, sample, tree or keep")
		end
	end
	return opts
end

dev.Command ("dev_vprof_status", function ()
	return V.status ()
end, "dev_vprof_status: whether HolyLib's vprof is loaded and running, and what it has sampled")

dev.Command ("dev_vprof_start", function (args)
	return V.start (Options (args, 1))
end, "dev_vprof_start [scripts] [keep]: start VProf, reset unless keep; scripts scopes every script GMod calls")

dev.Command ("dev_vprof_stop", function (args)
	return V.stop (Options (args, 1))
end, "dev_vprof_stop [rows] [tree]: stop VProf and print its report")

dev.Command ("dev_vprof_report", function (args)
	return V.report (Options (args, 1))
end, "dev_vprof_report [rows] [tree]: VProf's time by budget group and by scope, per tick")

dev.Command ("dev_vprof_reset", function ()
	return V.reset ()
end, "dev_vprof_reset: forget what VProf has sampled, and its peaks")

dev.Command ("dev_vprof_counters", function ()
	return V.counters ()
end, "dev_vprof_counters: VProf's counters, by name")

dev.Command ("dev_vprof_window", function (args)
	if not args [1] then dev.Fail ("dev_vprof_window <seconds> [rows] [scripts] [sample]") end
	return V.window (args [1], Options (args, 2))
end, "dev_vprof_window <seconds> [rows] [scripts] [sample]: VProf (and the LuaJIT sampler) over a window, "
	.. "into dev.last_vprof")

dev.Command ("dev_vprof_cancel", function ()
	return V.cancel ()
end, "dev_vprof_cancel: end a window early, stopping what it started, leaving dev.last_vprof unset")
