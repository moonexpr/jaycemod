-- The dev workbench's index (.claude/rules/live-server.md) against its
-- code, both ways: every dev.* function the workbench defines, and every
-- console command it registers, is named in the index; and every dev.*
-- name or command the index names is one the workbench has. An agent reads
-- the index instead of the source, so a name missing from it is never
-- found, and a name it keeps after the code drops it is a wrong turn.
local T = dofile("tests/harness.lua")

local INDEX = ".claude/rules/live-server.md"
local WORKBENCH = "addons/sandcastle_dev/lua/sandcastle_dev/"
-- dev.load and dev.require: the dev server's mount defines them
local MOUNT = ".devtools/bin/server_root/sandcastle_dev.lua"

-- dev.harness's and dev.scenario's functions are defined on these locals
local TABLES = { H = "dev.harness", S = "dev.scenario" }

local function ReadFile(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

local function Sources()
	local paths = {}
	local list = assert(io.popen("ls -1 " .. WORKBENCH))
	for name in list:lines() do
		if name:match("%.lua$") then paths[#paths + 1] = WORKBENCH .. name end
	end
	list:close()
	paths[#paths + 1] = MOUNT
	return paths
end

local function Sorted(set)
	local list = {}
	for key in pairs(set) do list[#list + 1] = key end
	table.sort(list)
	return list
end

-- What the workbench has: functions (dev.reload, dev.harness.pause), the
-- other values it sets on dev (dev.SCHEMA, dev.last_reload), its console
-- commands, and every console name it holds (its convar among them).
local functions, values, commands, consoleNames = {}, {}, {}, {}
for _, path in ipairs(Sources()) do
	local text = ReadFile(path)
	for name in text:gmatch("function (dev%.[%w_]+)%(") do functions[name] = true end
	for local_, name in text:gmatch("function (%u)%.([%w_]+)%(") do
		if TABLES[local_] then functions[TABLES[local_] .. "." .. name] = true end
	end
	for name in text:gmatch("(dev%.[%w_]+)%s*=") do values[name] = true end
	for name in text:gmatch('dev%.Command%(%s*"([%w_]+)"') do commands[name] = true end
	for name in text:gmatch('"((%l+)_[%w_]+)"') do consoleNames[name] = true end
end

local index = ReadFile(INDEX)

T.test("the workbench defines functions and commands to index", function()
	T.eq(#Sorted(functions) > 0 and #Sorted(commands) > 0, true, "found")
end)

T.test("every dev.* function the workbench defines is in the index", function()
	local missing = {}
	for _, name in ipairs(Sorted(functions)) do
		if not index:find("`" .. name .. "(", 1, true) then missing[#missing + 1] = name end
	end
	T.eq(table.concat(missing, ", "), "", "functions not indexed as `name(...)`")
end)

T.test("every console command the workbench registers is in the index", function()
	local missing = {}
	for _, name in ipairs(Sorted(commands)) do
		if not index:find("`" .. name .. "[` ]") then missing[#missing + 1] = name end
	end
	T.eq(table.concat(missing, ", "), "", "commands not indexed")
end)

T.test("every dev.* name the index gives is the workbench's", function()
	local stale = {}
	for name in index:gmatch("`(dev%.[%w_%.]+)") do
		name = name:gsub("%.$", "")
		if not functions[name] and not values[name] then stale[#stale + 1] = name end
	end
	table.sort(stale)
	T.eq(table.concat(stale, ", "), "", "names the workbench lacks")
end)

T.test("every console name the index gives is the workbench's", function()
	local stale = {}
	for name in index:gmatch("`((dev)_[%w_]+)") do
		if not consoleNames[name] then stale[#stale + 1] = name end
	end
	for name in index:gmatch("`((scenario)_[%w_]+)") do
		if not consoleNames[name] then stale[#stale + 1] = name end
	end
	table.sort(stale)
	T.eq(table.concat(stale, ", "), "", "console names the workbench lacks")
end)

T.finish()
