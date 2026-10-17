-- The nbdebug feature's two ends and its command file agree: the view
-- listens to the game events the controllers fire, the feature's shared
-- part defines them (their fields and widths, for both realms), and every
-- command the realm file registers has a handler.
local T = dofile("tests/harness.lua")

local ROOT = T.ROOT
local COMMANDS = ROOT .. "ws/sv_nbdebug.lua"

local function ReadFile(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- The game event names a text fires, listens to or defines, as a set.
local function Names(text, call)
	local found = {}
	for name in text:gmatch(call .. "%(\"([%w_]+)\"") do found[name] = true end
	return found
end

local controller, view = T.RealmSource("nbdebug", "sv"), T.RealmSource("nbdebug", "cl")
local shared = T.RealmSource("nbdebug", "sh")
local aiwar = T.RealmSource("aiwar", "sv")

-- What the nbdebug controller fires, and the AI war's overlay.
local function Fired()
	local fired = Names(controller, "Events%.Fire")
	fired.game_aiwar_debug = Names(aiwar, "Events%.Fire").game_aiwar_debug
	return fired
end

T.test("the view listens to every game event the controllers fire", function()
	local heard, count = Names(view, "Listen"), 0
	for name in pairs(Fired()) do
		count = count + 1
		T.eq(heard[name], true, "a listener for " .. name)
	end
	T.eq(count >= 7, true, "the events were found")
end)

T.test("every game event they fire is defined in the feature's shared part, for both realms", function()
	local defined = Names(shared, "Define")
	for name in pairs(Fired()) do T.eq(defined[name], true, name .. " defined in sh.lua") end
end)

T.test("the controller's game events are named game_nb_debug_<subject>", function()
	for name in pairs(Names(controller, "Events%.Fire")) do
		T.eq(name:match("^game_nb_debug_[a-z_]+$") ~= nil, true, name)
	end
end)

T.test("every command the realm file registers has a handler in the controller", function()
	local commands = ReadFile(COMMANDS)
	local count = 0
	for name in commands:gmatch('name = "(ws_nb_[%a_]+)"') do
		count = count + 1
		T.eq(controller:find("COMMANDS." .. name .. " = function", 1, true) ~= nil, true, name)
	end
	T.eq(count, 5, "five commands")
end)

T.finish()
