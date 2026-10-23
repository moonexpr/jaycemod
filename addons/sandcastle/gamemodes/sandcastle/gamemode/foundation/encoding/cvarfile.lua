-- Convar values saved as cfg text, one `name "value"` a line, and read back
-- (through parsers.consolecfg: comments skipped, chained commands refused)
-- only for the names asked for, so a file edited by hand sets nothing else.
local concat, format, ipairs, match = table.concat, string.format, ipairs, string.match
local ConsoleCfg = encoding.consolecfg
module(...)

-- names: the order to write in; values: name -> its value, a string.
function Write(names, values)
	local lines = {}
	for i, name in ipairs(names) do lines[i] = format('%s "%s"\n', name, values[name]) end
	return concat(lines)
end

-- A command line's name and its value, quoted or not.
local function Split(command)
	local name, rest = match(command, "^(%S+)%s*(.-)$")
	return name, match(rest, '^"(.*)"$') or rest
end

-- name -> value for each of names the text sets.
function Read(text, names)
	local wanted, values = {}, {}
	for _, name in ipairs(names) do wanted[name] = true end
	for _, command in ipairs(ConsoleCfg.Commands(text)) do
		local name, value = Split(command)
		if wanted[name] then values[name] = value end
	end
	return values
end
