-- A module(...) file that loads a sibling, for harness_test.lua: the loader
-- gives the chunk a require that resolves under the same root.
local Greeting = require ("fixtures.greeting")
module (...)

function Greeter ()
	return Greeting
end
