local T = dofile ("tests/harness.lua")

local ROOT = "addons/sandcastle/gamemodes/sandcastle/gamemode/"

-- logging.lua, then (on the server) the system feature's completion, in a
-- realm whose developer convar is at developer.
local function Load (realm, developer)
	local callbacks, commands, output, hooks = {}, {}, {}, {}
	local value = ""
	local ws = {}
	local consoleEnv = setmetatable ({ WS = ws }, { __index = _G })
	local consoleChunk = assert (loadfile (ROOT .. "sh_console.lua"))
	setfenv (consoleChunk, consoleEnv) ()
	local env = setmetatable (
		{
			WS = ws,
			SERVER = realm ~= "client",
			CLIENT = realm == "client",
			FCVAR_ARCHIVE = 1,
			CreateConVar = function (name, default)
				value = default
				return { GetString = function () return value end }
			end,
			GetConVar = function (name)
				if name == "developer" then return { GetInt = function () return developer or 0 end } end
			end,
			cvars =
			{
				AddChangeCallback = function (name, callback) callbacks [name] = callback end
			},
			concommand =
			{
				Add = function (name, callback, autocomplete) commands [name] = { callback, autocomplete } end
			},
			hook = { Add = function (name, id, fn) hooks [name] = fn end },
			Msg = function (text) output [#output + 1] = text end
		}, { __index = _G })
	setfenv (assert (loadfile (ROOT .. "logging.lua")), env) ()
	if realm ~= "client" then setfenv (assert (loadfile (ROOT .. "features/system/sv.lua")), env) () end
	return env.WS, callbacks, commands, output, function (nextValue)
		value = nextValue
		callbacks.con_spew ("con_spew", "", nextValue)
	end, hooks
end

T.test ("logging is silent until its subsystem is enabled", function ()
	local WS, _, _, output = Load ()
	WS.Logger ("rounds") ("PREROUND -> RND_RUNNING")
	T.eq (#output, 0, "disabled subsystem")
end)

T.test ("logging filters by space-separated subsystem names and colors its prefix", function ()
	local WS, _, _, output, SetSpew = Load ()
	SetSpew ("rounds capture")
	WS.Logger ("rounds") ("PREROUND -> RND_RUNNING")
	WS.Logger ("capture") ("point changed")
	WS.Logger ("payload") ("cart moved")
	T.eq (#output, 2, "only selected subsystems")
	T.eq (output [1], "\27[38;5;117m[rounds]\27[0m PREROUND -> RND_RUNNING\n", "colored subsystem prefix")
	T.eq (output [2]:find ("[capture]", 1, true) ~= nil, true, "second selected subsystem")
end)

T.test ("con_spew completes remaining subsystem names as a quoted value", function ()
	local _, _, commands = Load ()
	local complete = commands.con_spew [2]
	local suggestions = complete ("con_spew", ' "rounds pay')
	T.eq (table.concat (suggestions, " "), 'con_spew "rounds payload"', "prefix and existing selection")
end)

-- A client cannot set con_spew before the gamemode makes it, so the load's
-- trace prints with the engine's developer on, which it can join with.
T.test ("the boot trace prints while developer is on, con_spew or not; the rest still need con_spew", function ()
	local WS, _, _, output = Load ("client", 1)
	WS.Logger ("boot") ("include %s", "cl_hud.lua")
	WS.Logger ("rounds") ("PREROUND -> RND_RUNNING")
	T.eq (table.concat (output), "[boot] include cl_hud.lua\n", "boot alone, and a client's line plain")
	local _, _, _, quiet = Load ("client", 0)
	T.eq (#quiet, 0, "developer off: nothing")
end)

T.test ("the boot trace marks the gamemode's Initialize and InitPostEntity", function ()
	local _, _, _, output, _, hooks = Load ("client", 1)
	hooks.Initialize ()
	hooks.InitPostEntity ()
	T.eq (#output, 2, "both told")
end)

T.test ("an unknown subsystem is refused", function ()
	local WS = Load ()
	T.eq (pcall (WS.Logger, "nonsense"), false)
end)

T.finish ()
