-- No gamemode file calls a local function above its declaration: Lua reads
-- such a call as a global, nil at run time, so it fails only when that line
-- runs (features/npc/sv_routes.lua called AreasOf before declaring it, and
-- every finished route search died, leaving the AI war without lanes). A
-- forward declaration (`local Name` above both) is the way to call one
-- declared later.
local T = dofile("tests/harness.lua")

local function ReadLines(path)
	local lines = {}
	for line in io.lines(path) do lines[#lines + 1] = line end
	return lines
end

-- Calls of name on a line: not a method or field (a.name, a:name), nor
-- part of a longer name, nor in a comment.
local function Calls(line, name)
	local code = line:gsub("%-%-.*$", "")
	for at in code:gmatch("()" .. name .. "%s*%(") do
		local before = at > 1 and code:sub(at - 1, at - 1) or ""
		if not before:match("[%w_%.:]") then return true end
	end
	return false
end

-- Whether the line declares name: a local (or local function), a
-- function's parameter, or a for loop's variable.
local function Declares(line, name)
	local code = line:gsub("%-%-.*$", "")
	local function Lists(list)
		return list and ("," .. list:gsub("%s", "") .. ","):find("," .. name .. ",", 1, true) ~= nil
	end
	if code:match("local%s+function%s+" .. name .. "[^%w_]") then return true end
	if Lists(code:match("local%s+([%w_,%s]-)%s*=")) or Lists(code:match("local%s+([%w_,%s]+)%s*$")) then return true end
	for params in code:gmatch("function%s*[%w_%.:]*%s*%(([^)]*)%)") do
		if Lists(params) then return true end
	end
	return Lists(code:match("for%s+([%w_,%s]-)%s+in%s")) or Lists(code:match("for%s+([%w_]+)%s*="))
end

-- "path:line calls Name, declared local at line N" for each call above the
-- declaration that no earlier declaration of the name explains.
local function Misuses(path)
	local lines, found = ReadLines(path), {}
	for at, line in ipairs(lines) do
		local name = line:match("^%s*local%s+function%s+([%a_][%w_]*)")
		if name then
			local declared = false
			for i = 1, at - 1 do
				declared = declared or Declares(lines[i], name)
				if not declared and Calls(lines[i], name) then
					found[#found + 1] = string.format("%s:%d calls %s, declared local at line %d", path, i, name, at)
				end
			end
		end
	end
	return found
end

T.test("no file calls a local function above its declaration", function()
	local list = assert(io.popen("find " .. T.ROOT .. " " .. T.ROOT .. "../entities -name '*.lua'"))
	local files, misuses = 0, {}
	for path in list:lines() do
		files = files + 1
		for _, misuse in ipairs(Misuses(path)) do misuses[#misuses + 1] = misuse end
	end
	list:close()
	T.eq(files > 100, true, "the gamemode's files were found: " .. files)
	T.eq(table.concat(misuses, "\n"), "")
end)

T.finish()
