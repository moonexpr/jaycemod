-- Valve's KeyValues text: quoted or bare strings, { and } around a block
-- under the key before it, `//` comments, and in quoted strings the escapes
-- \n, \t, \" and \\ (any other escaped character is itself) and line breaks.
--
-- Read(text, visit) calls visit(path, key, value) for each pair in order,
-- path the keys of the blocks it is in, outermost first, as written (""
-- for a block with no key before it). The path is reused: copy it to keep it.
-- Core-rule exception: stays Lua. Read visits each key through the caller's
-- function, and its callers (localization, kill icons) read a file once, on
-- the client; native/foundation is a server module, so a client caller
-- cannot gain from it.
local byte, concat, sub = string.byte, table.concat, string.sub
module(...)

local ESCAPES = {
	n = "\n",
	t = "\t",
	['"'] = '"',
	["\\"] = "\\",
}

local QUOTE, BACKSLASH, SLASH, OPEN, CLOSE = 34, 92, 47, 123, 125

-- The next item from position i: "{", "}", or a string (quoted, with its
-- escapes, or bare); nil at the end. Returns the item and the position after.
local function NextItem(text, i)
	local length = #text
	while i <= length do
		local c = byte(text, i)
		if c == SLASH and byte(text, i + 1) == SLASH then
			while i <= length and byte(text, i) ~= 10 do i = i + 1 end
		elseif c <= 32 then
			i = i + 1
		else
			break
		end
	end
	if i > length then return nil, i end
	local c = byte(text, i)
	if c == OPEN then return "{", i + 1 end
	if c == CLOSE then return "}", i + 1 end
	if c == QUOTE then
		local parts, start = {}, i + 1
		i = start
		while i <= length do
			local d = byte(text, i)
			if d == QUOTE then
				parts[#parts + 1] = sub(text, start, i - 1)
				return concat(parts), i + 1
			end
			if d == BACKSLASH then
				parts[#parts + 1] = sub(text, start, i - 1)
				local e = sub(text, i + 1, i + 1)
				parts[#parts + 1] = ESCAPES[e] or e
				i = i + 2
				start = i
			else
				i = i + 1
			end
		end
		parts[#parts + 1] = sub(text, start)
		return concat(parts), i
	end
	local start = i
	while i <= length do
		local d = byte(text, i)
		if d <= 32 or d == QUOTE or d == OPEN or d == CLOSE then break end
		i = i + 1
	end
	return sub(text, start, i - 1), i
end

function Read(text, visit)
	local path, key = {}, nil
	local item, i = NextItem(text, 1)
	while item do
		if item == "{" then
			path[#path + 1] = key or ""
			key = nil
		elseif item == "}" then
			path[#path] = nil
			key = nil
		elseif key == nil then
			key = item
		else
			visit(path, key, item)
			key = nil
		end
		item, i = NextItem(text, i)
	end
end
