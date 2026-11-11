local T = dofile ("tests/harness.lua")

local WS = {}
local env = setmetatable ({ WS = WS }, { __index = _G })
local chunk = assert (loadfile ("addons/sandcastle/gamemodes/sandcastle/gamemode/sh_console.lua"))
setfenv (chunk, env) ()

T.test ("completion filters by the current word and preserves earlier arguments", function ()
	local suggestions = WS.CompleteOptions ("test_cmd", " alpha be", { {}, { "beta", "blue", "red" } })
	T.eq (table.concat (suggestions, " "), "test_cmd alpha beta", "matching full commands")
end)

T.test ("completion after a space starts the next argument", function ()
	local suggestions = WS.CompleteOptions ("test_cmd", " alpha ", { {}, { "beta", "blue" } })
	T.eq (table.concat (suggestions, " "), "test_cmd alpha beta test_cmd alpha blue", "next argument")
end)

T.test ("unique completions exclude previously selected values", function ()
	local suggestions = WS.CompleteOptions ("test_cmd", " alpha ", function () return { "alpha", "beta" } end, true)
	T.eq (table.concat (suggestions, " "), "test_cmd alpha beta", "no duplicate option")
end)

T.finish ()
