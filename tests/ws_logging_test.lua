local T = dofile("tests/harness.lua")

local function Load()
	local callbacks, commands, output = {}, {}, {}
	local value = ""
	local ws = {}
	local consoleEnv = setmetatable({ WS = ws }, { __index = _G })
	local consoleChunk = assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sh_console.lua"))
	setfenv(consoleChunk, consoleEnv)()
	local env = setmetatable({
		WS = ws,
		FCVAR_ARCHIVE = 1,
		CreateConVar = function(name, default)
			value = default
			return { GetString = function() return value end }
		end,
		cvars = {
			AddChangeCallback = function(name, callback) callbacks[name] = callback end,
		},
		concommand = {
			Add = function(name, callback, autocomplete) commands[name] = { callback, autocomplete } end,
		},
		Msg = function(text) output[#output + 1] = text end,
	}, { __index = _G })
	local chunk = assert(loadfile("addons/sandcastle/gamemodes/sandcastle/gamemode/ws/sv_logging.lua"))
	setfenv(chunk, env)()
	return env.WS, callbacks, commands, output, function(nextValue)
		value = nextValue
		callbacks.con_spew("con_spew", "", nextValue)
	end
end

T.test("logging is silent until its subsystem is enabled", function()
	local WS, _, _, output = Load()
	WS.Logger("rounds")("PREROUND -> RND_RUNNING")
	T.eq(#output, 0, "disabled subsystem")
end)

T.test("logging filters by space-separated subsystem names and colors its prefix", function()
	local WS, _, _, output, SetSpew = Load()
	SetSpew("rounds capture")
	WS.Logger("rounds")("PREROUND -> RND_RUNNING")
	WS.Logger("capture")("point changed")
	WS.Logger("payload")("cart moved")
	T.eq(#output, 2, "only selected subsystems")
	T.eq(output[1], "\27[38;5;117m[rounds]\27[0m PREROUND -> RND_RUNNING\n", "colored subsystem prefix")
	T.eq(output[2]:find("[capture]", 1, true) ~= nil, true, "second selected subsystem")
end)

T.test("con_spew completes remaining subsystem names as a quoted value", function()
	local _, _, commands = Load()
	local complete = commands.con_spew[2]
	local suggestions = complete("con_spew", ' "rounds pay')
	T.eq(table.concat(suggestions, " "), 'con_spew "rounds payload"', "prefix and existing selection")
end)

T.finish()
