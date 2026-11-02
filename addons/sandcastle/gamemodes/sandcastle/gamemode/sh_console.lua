-- Shared helpers for console command completion.

function WS.CompleteOptions(command, arguments, choices, unique)
	arguments = arguments or ""
	local completed = {}
	for word in arguments:gmatch("%S+") do completed[#completed + 1] = word end

	local prefix = ""
	if arguments:match("%s$") then
		prefix = ""
	else
		prefix = table.remove(completed) or ""
	end

	local position = #completed + 1
	local options
	if type(choices) == "function" then
		options = choices(position, completed)
	else
		options = choices[position]
	end
	options = options or {}
	local used = {}
	if unique then
		for _, word in ipairs(completed) do used[string.lower(word)] = true end
	end

	local before = table.concat(completed, " ")
	local start = command .. (before ~= "" and " " .. before or "") .. " "
	local suggestions = {}
	local wanted = string.lower(prefix)
	for _, option in ipairs(options) do
		if (not unique or not used[string.lower(option)])
			and string.sub(string.lower(option), 1, #wanted) == wanted then
			suggestions[#suggestions + 1] = start .. option
		end
	end
	return suggestions
end

return WS.CompleteOptions
