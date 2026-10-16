-- The server's analytics (foundation.core.analytics): any code may time its
-- work with WS.Analytics:Start()/Stop(name, started) or :Time(name, fn, ...),
-- and count with :Count(name). While ws_analytics is on, each tick is
-- closed as a frame against the tick interval and Lua memory is sampled;
-- off, nothing runs per tick. ws_analytics_print and
-- ws_analytics_reset need the server options privilege.
local Analytics = WS.require("foundation.core.analytics")
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
