-- The system feature's server controller: the console's completion for
-- con_spew, the logging subsystems the gamemode's logger (logging.lua)
-- knows.
local function Complete(command, arguments)
	local unquoted = (arguments or ""):gsub('^%s*"', ""):gsub('"$', "")
	local suggestions = WS.CompleteOptions(command, unquoted, function() return WS.LOGGING_SUBSYSTEMS end, true)
	for i, suggestion in ipairs(suggestions) do
		local value = suggestion:match("^%S+%s+(.+)$") or ""
		suggestions[i] = command .. ' "' .. value .. '"'
	end
	return suggestions
end

concommand.Add("con_spew", function() end, Complete,
	"Set the space-separated server logging subsystems to print")

return { Logger = WS.Logger }
