-- addons/ulx_luadev's ulx/modules/sh/add_map.lua: `ulx addmap` asks the host's
-- add_map.py through the watch log, and tells the game if nothing answers.
-- Run against fake ULX, ULib, Watch and timers.
local T = dofile("tests/harness.lua")

local function Load(humans)
	local s = { emitted = {}, logged = {}, timers = {}, said = {} }
	local command = { params = {} }
	function command:addParam(param) self.params[#self.params + 1] = param end
	function command:defaultAccess(access) self.access = access end
	function command:help(text) self.helpText = text end
	s.command = command
	local env = setmetatable({
		ulx = {
			command = function(_, name, fn, chat)
				s.name, s.fn, s.chat = name, fn, chat
				return command
			end,
			fancyLogAdmin = function(_, format, item) s.logged[#s.logged + 1] = { format, item } end,
		},
		ULib = {
			ACCESS_SUPERADMIN = "superadmin",
			cmds = { StringArg = "string", BoolArg = "bool", optional = "optional" },
			tsay = function(_, text) s.said[#s.said + 1] = text end,
		},
		Watch = { Emit = function(name, text) s.emitted[#s.emitted + 1] = { name = name, text = text } end },
		util = { TableToJSON = function(t) return t end },
		player = { GetHumans = function() return humans end },
		timer = { Create = function(name, seconds, _, fn) s.timers[name] = { seconds = seconds, fn = fn } end },
	}, { __index = _G })
	setfenv(assert(loadfile("addons/ulx_luadev/lua/ulx/modules/sh/add_map.lua")), env)()
	return s
end

local ME, OTHER = {}, {}

T.test("it is ulx addmap, !addmap, for superadmins", function()
	local s = Load({ ME })
	T.eq(s.name, "ulx addmap")
	T.eq(s.chat, "!addmap")
	T.eq(s.command.access, "superadmin")
end)

T.test("alone on the server, the map changes", function()
	local s = Load({ ME })
	s.fn(ME, "3632274158", "", false)
	T.eq(s.emitted[1].name, "add_map_request")
	T.eq(s.emitted[1].text.item, "3632274158")
	T.eq(s.emitted[1].text.change, true)
end)

T.test("from the server's console with nobody on, the map changes", function()
	local s = Load({})
	s.fn(nil, "3632274158", "", false)
	T.eq(s.emitted[1].text.change, true)
end)

T.test("with others on, it does not unless asked", function()
	local s = Load({ ME, OTHER })
	s.fn(ME, "3632274158", "", false)
	T.eq(s.emitted[1].text.change, false)
	s.fn(ME, "3632274158", "gm_b", true)
	T.eq(s.emitted[2].text.change, true)
	T.eq(s.emitted[2].text.map, "gm_b")
end)

T.test("XGUI's box, left as it is, sends its hint: that names no map", function()
	local s = Load({ ME })
	local hint = s.command.params[2].hint
	s.fn(ME, "3632274158", hint, false)
	T.eq(s.emitted[1].text.map, "")
end)

T.test("nothing answering on the host is told in game", function()
	local s = Load({ ME })
	s.fn(ME, "3632274158", "", false)
	T.eq(#s.said, 0)
	local ack = s.timers.ws_add_map_ack
	T.eq(ack ~= nil, true)
	ack.fn()
	T.eq(s.said[1]:find("dt add_map --serve", 1, true) ~= nil, true)
end)

T.finish()
