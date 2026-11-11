-- ws/sv_demo_autorecord.lua: sv_demo_autorecord records every map through
-- SourceTV, one demo a map, for a playtest.
local T = dofile("tests/harness.lua")

local SOURCE = T.ROOT .. "sv_demo_autorecord.lua"

local function Server(on, sourcetv)
	local server = { commands = {}, warnings = {}, hooks = {} }
	local callback
	local convars = {
		sv_demo_autorecord = { GetBool = function() return on end, GetName = function() return "sv_demo_autorecord" end },
		tv_enable = { GetBool = function() return sourcetv end },
		tv_name = { GetString = function() return "SourceTV" end },
	}
	local env = setmetatable({
		WS = { require = T.require },
		CreateConVar = function(name) return convars[name] end,
		GetConVar = function(name) return convars[name] end,
		cvars = { AddChangeCallback = function(_, fn) callback = fn end },
		hook = { Add = function(event, _, fn) server.hooks[event] = fn end },
		timer = { Simple = function(_, fn) fn() end },
		game = {
			GetMap = function() return "pl_upward" end,
			ConsoleCommand = function(text) server.commands[#server.commands + 1] = text end,
		},
		os = { date = function() return "20261108_140501" end },
		MsgN = function(text) server.warnings[#server.warnings + 1] = text end,
		OBS_MODE_ROAMING = "roaming",
	}, { __index = _G })
	setfenv(assert(loadfile(SOURCE)), env)()
	function server.Set(value)
		on = value
		callback()
	end
	function server.Load() server.hooks.InitPostEntity() end
	return server
end

local RECORD = "tv_record playtest_pl_upward_20261108_140501\n"

T.test("on, a map's load starts its demo", function()
	local server = Server(true, true)
	server.Load()
	T.eq(table.concat(server.commands), RECORD)
end)

T.test("off, a map's load records nothing", function()
	local server = Server(false, true)
	server.Load()
	T.eq(#server.commands, 0)
end)

T.test("turned on mid-map it starts, and off it stops", function()
	local server = Server(false, true)
	server.Load()
	server.Set(true)
	T.eq(table.concat(server.commands), RECORD, "started")
	server.Set(false)
	T.eq(server.commands[2], "tv_stoprecord\n", "stopped")
end)

T.test("turned off with nothing recording sends nothing", function()
	local server = Server(false, true)
	server.Set(false)
	T.eq(#server.commands, 0)
end)

T.test("on without SourceTV says so and records nothing", function()
	local server = Server(true, false)
	server.Load()
	T.eq(#server.commands, 0, "no command")
	T.eq(#server.warnings, 1, "told once")
end)

-- GMod gives SourceTV's client a body like any bot's, solid at a spawn.
local function Client(isBot, nick)
	return {
		IsBot = function() return isBot end,
		Nick = function() return nick end,
		Spectate = function(self, mode) self.spectating = mode end,
	}
end

T.test("SourceTV's bot spawns a spectator, its body never set up", function()
	local server, tv = Server(false, true), Client(true, "SourceTV")
	T.eq(server.hooks.PlayerSpawn(tv), true, "the gamemode's spawn skipped")
	T.eq(tv.spectating, "roaming", "out of the world")
end)

T.test("any other player or bot spawns as ever", function()
	local server = Server(false, true)
	local human, bot = Client(false, "SourceTV"), Client(true, "Bot01")
	T.eq(server.hooks.PlayerSpawn(human), nil, "a player named like it")
	T.eq(human.spectating, nil, "left alone")
	T.eq(server.hooks.PlayerSpawn(bot), nil, "another bot")
	T.eq(bot.spectating, nil, "left alone")
end)

T.finish()
