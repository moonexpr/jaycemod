-- A module(...) file for harness_test.lua: T.require must pass it its name.
local string = string
module (...)

GREETING = "hello"

function Greet (who)
	return string.format ("%s, %s", GREETING, who)
end
