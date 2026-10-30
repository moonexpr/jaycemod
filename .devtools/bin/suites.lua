-- The test suites grouped by major system: tests/suites.lua names each
-- group's tests (an exact name, or a prefix ending in *) and the source
-- paths it covers (a folder ending in /, or a path prefix). A test belongs
-- to the group whose pattern names it most closely, an exact name before
-- any prefix; a changed file to the groups whose sources claim it most
-- closely. check_lua.sh runs through it:
--
--   luajit .devtools/bin/suites.lua list             the groups, a line each
--   luajit .devtools/bin/suites.lua tests GROUP...   their test files
--   luajit .devtools/bin/suites.lua files GROUP...   the Lua files to compile
--   luajit .devtools/bin/suites.lua changed          the groups the changes touch:
--     uncommitted, staged, untracked, and committed since the upstream
--
-- dofile'd (no arguments), it returns the module: New(manifest, tests).
local M = {}

local Suites = {}
Suites.__index = Suites

local EXACT = 1e6

-- How closely pattern names test: the exact name scores above any prefix,
-- a longer prefix above a shorter; nil when it does not name it.
local function Closeness(pattern, test)
	local prefix = pattern:match("^(.*)%*$")
	if not prefix then return pattern == test and EXACT or nil end
	return test:sub(1, #prefix) == prefix and #prefix or nil
end

local function Best(patterns, subject, closeness)
	local best
	for _, pattern in ipairs(patterns) do
		local score = closeness(pattern, subject)
		if score and (not best or score > best) then best = score end
	end
	return best
end

-- How closely source claims path: a folder or a path prefix, by its length.
local function Claim(source, path)
	return path:sub(1, #source) == source and #source or nil
end

function M.New(manifest, tests)
	local self = setmetatable({ groups = {}, order = {}, groupOf = {}, members = {} }, Suites)
	for _, group in ipairs(manifest) do
		self.groups[group.name] = group
		self.order[#self.order + 1] = group.name
		self.members[group.name] = {}
	end
	for _, test in ipairs(tests) do
		local best, owners = nil, {}
		for _, group in ipairs(manifest) do
			local score = Best(group.tests, test, Closeness)
			if score and (not best or score > best) then
				best, owners = score, { group.name }
			elseif score and score == best then
				owners[#owners + 1] = group.name
			end
		end
		if #owners == 0 then error("no group in tests/suites.lua names test " .. test, 2) end
		if #owners > 1 then error("test " .. test .. " is named as closely by " .. table.concat(owners, " and "), 2) end
		self.groupOf[test] = owners[1]
		table.insert(self.members[owners[1]], test)
	end
	for _, list in pairs(self.members) do table.sort(list) end
	return self
end

function Suites:Names()
	return self.order
end

function Suites:About(name)
	return self.groups[name].about
end

function Suites:GroupOf(test)
	return self.groupOf[test]
end

function Suites:Check(names)
	for _, name in ipairs(names) do
		if not self.groups[name] then
			error("no group " .. tostring(name) .. "; the groups: " .. table.concat(self.order, ", "), 2)
		end
	end
end

-- The test files of the named groups, group by group, each in name order.
function Suites:Tests(names)
	self:Check(names)
	local paths = {}
	for _, name in ipairs(names) do
		for _, test in ipairs(self.members[name]) do paths[#paths + 1] = "tests/" .. test .. "_test.lua" end
	end
	return paths
end

-- The groups that claim path: a test file its own group; any other file
-- the groups whose sources claim it most closely (all of them on a tie).
function Suites:Owners(path)
	local test = path:match("^tests/(.+)_test%.lua$")
	if test and self.groupOf[test] then return { self.groupOf[test] } end
	local best, owners = nil, {}
	for _, name in ipairs(self.order) do
		local score = Best(self.groups[name].sources, path, Claim)
		if score and (not best or score > best) then
			best, owners = score, { name }
		elseif score and score == best then
			owners[#owners + 1] = name
		end
	end
	return owners
end

-- The groups the changed paths touch, in the manifest's order.
function Suites:Changed(paths)
	local touched = {}
	for _, path in ipairs(paths) do
		for _, name in ipairs(self:Owners(path)) do touched[name] = true end
	end
	local names = {}
	for _, name in ipairs(self.order) do
		if touched[name] then names[#names + 1] = name end
	end
	return names
end

-- Command line ----------------------------------------------------------------

local function Lines(command)
	local pipe, lines = assert(io.popen(command)), {}
	for line in pipe:lines() do
		if line ~= "" then lines[#lines + 1] = line end
	end
	pipe:close()
	return lines
end

local function Load()
	local tests = {}
	for _, path in ipairs(Lines("ls tests/*_test.lua")) do tests[#tests + 1] = path:match("^tests/(.+)_test%.lua$") end
	return M.New(dofile("tests/suites.lua"), tests)
end

local function Print(list)
	for _, line in ipairs(list) do print(line) end
end

-- The Lua files the named groups own: their sources' and their tests'.
function Suites:Files(names)
	self:Check(names)
	local wanted, files, seen = {}, {}, {}
	for _, name in ipairs(names) do wanted[name] = true end
	for _, name in ipairs(names) do
		for _, source in ipairs(self.groups[name].sources) do
			local command = source:sub(-1) == "/" and ("find " .. source .. " -name '*.lua'")
				or ("ls -d " .. source .. "* 2>/dev/null")
			for _, path in ipairs(Lines(command)) do
				if path:match("%.lua$") and not seen[path] then
					for _, owner in ipairs(self:Owners(path)) do
						if wanted[owner] then
							seen[path] = true
							files[#files + 1] = path
							break
						end
					end
				end
			end
		end
	end
	for _, path in ipairs(self:Tests(names)) do files[#files + 1] = path end
	return files
end

local function ChangedPaths()
	local paths = {}
	for _, command in ipairs({
		"git diff --name-only HEAD",
		"git ls-files --others --exclude-standard",
		"git rev-parse --verify -q @{u} >/dev/null && git diff --name-only @{u}...HEAD",
	}) do
		for _, path in ipairs(Lines(command .. " 2>/dev/null")) do paths[#paths + 1] = path end
	end
	return paths
end

local function Main(command, ...)
	local suites, names = Load(), { ... }
	if command == "list" then
		for _, name in ipairs(suites:Names()) do
			print(string.format("%-12s %3d tests  %s", name, #suites:Tests({ name }), suites:About(name)))
		end
	elseif command == "tests" then
		Print(suites:Tests(names))
	elseif command == "files" then
		Print(suites:Files(names))
	elseif command == "changed" then
		Print(suites:Changed(ChangedPaths()))
	else
		io.stderr:write("usage: suites.lua list | tests GROUP... | files GROUP... | changed\n")
		os.exit(2)
	end
end

if select("#", ...) == 0 then return M end
local ok, err = pcall(Main, ...)
if not ok then
	io.stderr:write(tostring(err):gsub("^[^:]+:%d+: ", "") .. "\n")
	os.exit(2)
end
