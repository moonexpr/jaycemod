-- includes.demo_autorecord: cl_demo_autorecord records a client's games for
-- a playtest, a demo a map, named so they sort by map and time.
local T = dofile("tests/harness.lua")
local Demo = T.require("includes.demo_autorecord")

T.test("a demo is named for its map and when it began", function()
	T.eq(Demo.Name("pl_upward", "20261108_140501"), "playtest_pl_upward_20261108_140501")
end)

T.test("turned on, a client not recording starts", function()
	T.eq(Demo.Action(true, false), Demo.RECORD)
end)

T.test("turned off, a client recording stops", function()
	T.eq(Demo.Action(false, true), Demo.STOP)
end)

T.test("a client already as asked does nothing", function()
	T.eq(Demo.Action(true, true), nil, "recording already")
	T.eq(Demo.Action(false, false), nil, "not recording")
end)

T.finish()
