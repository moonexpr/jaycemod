-- The nbdebug feature's two ends and its command file agree: the view
-- reads the net messages and field widths the controller writes, and every
-- command the realm file registers has a handler.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local CONTROLLER = ROOT .. "features/nbdebug/sv.lua"
local VIEW = ROOT .. "features/nbdebug/cl.lua"
local COMMANDS = ROOT .. "wetsand/sv_nbdebug.lua"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- name -> value of each `local NAME = "..."` or `local NAME = <number>`
-- whose name ends in `suffix`.
local function Constants(text, suffix)
	local found = {}
	for name, value in text:gmatch("\nlocal ([%u_]+" .. suffix .. ") = ([^\n%-]+)") do
		found[name] = value:gsub("%s+$", "")
	end
	return found
end

local controller, view = ReadFile(CONTROLLER), ReadFile(VIEW)

T.test("the view reads every net message the controller sends, by the same name", function()
	local sent, read = Constants(controller, "_NET"), Constants(view, "_NET")
	local count = 0
	for name, value in pairs(sent) do
		count = count + 1
		T.eq(read[name], value, name)
		T.eq(view:find("net.Receive(" .. name .. ",", 1, true) ~= nil, true, "a receiver for " .. name)
	end
	T.eq(count >= 6, true, "the messages were found")
end)

T.test("the net messages are named wetsand_nb_debug_<subject>_<event>", function()
	for name, value in pairs(Constants(controller, "_NET")) do
		T.eq(value:match('^"wetsand_nb_debug_[a-z]+_[a-z]+"$') ~= nil, true, name .. " = " .. value)
	end
end)

T.test("both ends use the same field widths", function()
	local written, read = Constants(controller, "_BITS"), Constants(view, "_BITS")
	for name, value in pairs(written) do
		T.eq(read[name], value, name)
	end
end)

T.test("every command the realm file registers has a handler in the controller", function()
	local commands = ReadFile(COMMANDS)
	local count = 0
	for name in commands:gmatch('name = "(wetsand_nb_[%a_]+)"') do
		count = count + 1
		T.eq(controller:find("COMMANDS." .. name .. " = function", 1, true) ~= nil, true, name)
	end
	T.eq(count, 4, "four commands")
end)

T.finish()
