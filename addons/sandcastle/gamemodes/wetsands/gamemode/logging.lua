-- The gamemode's logging, on both realms: lines filtered by subsystem, the
-- realm's con_spew naming those to print (space-separated; empty: none).
-- shared.lua runs it before anything else, so even the load can log; the
-- server's console completion for con_spew is the system feature's
-- (features/system/sv.lua).
--
-- The boot subsystem traces the load itself (each file, index, module and
-- feature as it loads, then the gamemode's Initialize and InitPostEntity),
-- and also prints while the engine's developer is 1 or more: a client
-- cannot set con_spew before the gamemode has loaded and made it, but can
-- join with +developer 1, and -condebug keeps its console in console.log,
-- whose last boot line is where a hung load stopped.
WS = WS or {}

local COLORS =
{
	boot = 250,
	capture = 208,
	defuse = 197,
	flag = 221,
	gamerules = 45,
	hostage = 82,
	payload = 33,
	rounds = 117
}

local SUBSYSTEMS = {}
for name in pairs (COLORS) do SUBSYSTEMS [#SUBSYSTEMS + 1] = name end
table.sort (SUBSYSTEMS)

local SPEW = CreateConVar ("con_spew", "", FCVAR_ARCHIVE,
	"Space-separated logging subsystems to print; empty disables logging")
local DEVELOPER = GetConVar ("developer")

local function Parse (value)
	local enabled = {}
	for name in value:gmatch ("%S+") do enabled [name] = true end
	return enabled
end

local enabled = Parse (SPEW:GetString ())
cvars.AddChangeCallback ("con_spew", function (_, _, value)
	enabled = Parse (value)
end, "ws_logging")

local function Enabled (subsystem)
	return enabled [subsystem] or (subsystem == "boot" and DEVELOPER ~= nil and DEVELOPER:GetInt () > 0)
end

-- The server's console takes colours as terminal codes; a client's prints
-- them as text, so its lines are plain.
local function Print (subsystem, text)
	if SERVER then
		Msg (string.format ("\27[38;5;%dm[%s]\27[0m %s\n", COLORS [subsystem], subsystem, text))
	else
		Msg (string.format ("[%s] %s\n", subsystem, text))
	end
end

-- A subsystem's logger: log(message) or log(format, ...).
function WS.Logger (subsystem)
	if not COLORS [subsystem] then error ("unknown logging subsystem " .. tostring (subsystem), 2) end
	return function (message, ...)
		if not Enabled (subsystem) then return end
		if select ("#", ...) == 0 then
			Print (subsystem, tostring (message))
		else
			Print (subsystem, string.format (message, ...))
		end
	end
end

WS.LOGGING_SUBSYSTEMS = SUBSYSTEMS

local Boot = WS.Logger ("boot")
hook.Add ("Initialize", "ws_boot", function () Boot ("Initialize") end)
hook.Add ("InitPostEntity", "ws_boot", function () Boot ("InitPostEntity: the load is done") end)

return WS.Logger
