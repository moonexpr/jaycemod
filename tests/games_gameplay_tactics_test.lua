-- games.gameplay.tactics: the interface a fire team's tactics engine fills.
local T = dofile("tests/harness.lua")
local Tactics = gameplay.tactics
local Port = core.port

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

local function Engine()
	local engine = {}
	for _, method in ipairs(Tactics.ENGINE:Methods()) do engine[method] = function() end end
	return engine
end

T.test("the engine interface is a port", function()
	T.eq(Port.Is(Tactics.ENGINE), true, "a port")
end)

T.test("an engine with every method passes", function()
	local engine = Engine()
	T.eq(Tactics.Check(engine), engine, "handed back")
end)

T.test("an engine missing a method is refused, naming it", function()
	local engine = Engine()
	engine.ShouldFallBack = nil
	local err = Raises(Tactics.Check, engine)
	T.eq(err:find("tactics engine", 1, true) ~= nil, true, "names the interface")
	T.eq(err:find("ShouldFallBack", 1, true) ~= nil, true, "names the method")
end)

T.finish()
