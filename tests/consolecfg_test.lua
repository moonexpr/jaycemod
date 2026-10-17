-- foundation.consolecfg: a cfg file's text as the console commands it runs,
-- for configs an addon ships, which exec cannot reach.
local T = dofile("tests/harness.lua")
local Cfg = T.require("foundation.consolecfg")

T.test("each command line is kept, as written; comments and blank lines are not", function()
	local commands = Cfg.Commands(table.concat({
		"// a heading",
		"",
		'sv_gameplay_enabled "0"',
		"   ns_tactics_reset   ",
		'// tf_max_active_zombie "30"',
		'mp_chattime "10" // the vote time',
	}, "\n"))
	T.eq(#commands, 3, "three commands")
	T.eq(commands[1], 'sv_gameplay_enabled "0"', "a convar")
	T.eq(commands[2], "ns_tactics_reset", "a bare command, trimmed")
	T.eq(commands[3], 'mp_chattime "10"', "a trailing comment dropped")
end)

T.test("Windows line endings and a comment marker inside quotes are read as text", function()
	local commands = Cfg.Commands('hostname "a // b"\r\nsv_cheats "0"\r\n')
	T.eq(#commands, 2, "two commands")
	T.eq(commands[1], 'hostname "a // b"', "the quoted // kept")
	T.eq(commands[2], 'sv_cheats "0"', "no carriage return")
end)

T.test("a line chaining commands with ; is refused, so one line runs one command", function()
	local commands, refused = Cfg.Commands('sv_cheats "0"; quit\nmp_chattime "10"')
	T.eq(#commands, 1, "only the plain line")
	T.eq(refused[1], 'sv_cheats "0"; quit', "the chained line, reported")
end)

T.test("the defaults cfg the addon ships parses with nothing refused", function()
	local f = assert(io.open("addons/sandcastle/cfg/sandcastle_defaults.cfg", "r"))
	local commands, refused = Cfg.Commands(f:read("*a"))
	f:close()
	T.eq(#refused, 0, "nothing refused")
	T.eq(#commands >= 30, true, "its commands: " .. #commands)
end)

T.finish()
