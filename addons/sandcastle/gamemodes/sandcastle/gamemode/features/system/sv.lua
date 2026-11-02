-- The system feature's server controller: shared server logging facilities.
local COLORS = {
	capture = 208,
	defuse = 197,
	flag = 221,
	gamerules = 45,
	hostage = 82,
	payload = 33,
	rounds = 117,
}

local SUBSYSTEMS = {}
for name in pairs(COLORS) do SUBSYSTEMS[#SUBSYSTEMS + 1] = name end
table.sort(SUBSYSTEMS)

local SPEW = CreateConVar("con_spew", "", FCVAR_ARCHIVE,
	"Space-separated server logging subsystems to print; empty disables logging")

local function Parse(value)
	local enabled = {}
	for name in value:gmatch("%S+") do enabled[name] = true end
	return enabled
end

local enabled = Parse(SPEW:GetString())
cvars.AddChangeCallback("con_spew", function(_, _, value)
	enabled = Parse(value)
end, "ws_logging")

local function Complete(command, arguments)
	local unquoted = (arguments or ""):gsub('^%s*"', ""):gsub('"$', "")
	local suggestions = WS.CompleteOptions(command, unquoted, function() return SUBSYSTEMS end, true)
	for i, suggestion in ipairs(suggestions) do
		local value = suggestion:match("^%S+%s+(.+)$") or ""
		suggestions[i] = command .. ' "' .. value .. '"'
	end
	return suggestions
end

concommand.Add("con_spew", function() end, Complete,
	"Set the space-separated server logging subsystems to print")

local function Logger(subsystem)
	local color = COLORS[subsystem]
	if not color then error("unknown logging subsystem " .. tostring(subsystem), 2) end
	return function(message, ...)
		if not enabled[subsystem] then return end
		local text
		if select("#", ...) == 0 then
			text = tostring(message)
		else
			text = string.format(message, ...)
		end
		Msg(string.format("\27[38;5;%dm[%s]\27[0m %s\n", color, subsystem, text))
	end
end

WS.Logger = Logger

return { Logger = Logger }
