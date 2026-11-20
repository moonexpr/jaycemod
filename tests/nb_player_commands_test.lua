-- nextsoldier.player.commands: the console commands a CLuaNextBotPlayer runs,
-- split as Source's CCommand splits a line, and the +/- commands that hold a
-- player's keys.
local T = dofile ("tests/harness.lua")
local Commands = nextsoldier.player.commands
local Usercmd = nextsoldier.player.usercmd

T.test ("a line is its commands, split at semicolons and line ends", function ()
	local parsed = Commands.Parse ("say hello there; kill\nuse weapon_crowbar")
	T.eq (#parsed,             3,                "three")
	T.eq (parsed [1].name,     "say",            "first")
	T.eq (parsed [1].argStr,   "hello there",    "its argument string")
	T.eq (parsed [1].args [2], "there",          "its arguments")
	T.eq (parsed [2].name,     "kill",           "second")
	T.eq (#parsed [2].args,    0,                "none")
	T.eq (parsed [3].args [1], "weapon_crowbar", "third's")
end)

T.test ("a quoted argument is one, semicolons in it kept", function ()
	local parsed = Commands.Parse ('say "a; b" c')
	T.eq (#parsed,             1,          "one command")
	T.eq (parsed [1].args [1], "a; b",     "quoted")
	T.eq (parsed [1].args [2], "c",        "then the next")
	T.eq (parsed [1].argStr,   '"a; b" c', "the string as given")
end)

T.test ("blank commands are none", function ()
	T.eq (#Commands.Parse (""),          0, "empty")
	T.eq (#Commands.Parse (" ;; \n ; "), 0, "only separators")
end)

T.test ("a + command holds its key and its - lets it go; any other is not a hold", function ()
	local held = Commands.Hold (0, "+attack")
	T.eq (held, Usercmd.BUTTONS.attack, "held")
	held = Commands.Hold (held, "+DUCK")
	T.eq (Usercmd.Has (held, "duck"), true, "names are case-free")
	held = Commands.Hold (held, "-attack")
	T.eq (held,                          Usercmd.BUTTONS.duck, "let go")
	T.eq (Commands.Hold (held, "-jump"), held,                 "letting go of one not held")
	T.eq (Commands.Hold (held, "say"),   nil,                  "not a hold")
	T.eq (Commands.Hold (held, "+fly"),  nil,                  "no such key")
end)

T.finish ()
