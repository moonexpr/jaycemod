-- A cfg file's text as the console commands it runs. GMod's exec reads only
-- garrysmod/cfg/, never an addon's cfg/ folder, so the addon runs its own
-- configs (addon/cfg/sandcastle_defaults.cfg) through this: one command per
-- line, `//` comments and blank lines skipped, a `//` inside quotes kept as
-- text. A line chaining commands with `;` outside quotes is refused, so a
-- config line can run one command and nothing more.
local sub = string.sub
module(...)

local QUOTE, SLASH, SEMICOLON = '"', "/", ";"

-- The line with its comment removed, and whether it chains commands.
local function Strip(line)
	local quoted = false
	for i = 1, #line do
		local c = sub(line, i, i)
		if c == QUOTE then
			quoted = not quoted
		elseif not quoted and c == SLASH and sub(line, i + 1, i + 1) == SLASH then
			return sub(line, 1, i - 1), false
		elseif not quoted and c == SEMICOLON then
			return line, true
		end
	end
	return line, false
end

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The commands, in order, and the lines refused for chaining commands.
function Commands(text)
	local commands, refused = {}, {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local stripped, chained = Strip((line:gsub("\r$", "")))
		local command = Trim(stripped)
		if chained then
			refused[#refused + 1] = command
		elseif command ~= "" then
			commands[#commands + 1] = command
		end
	end
	return commands, refused
end
