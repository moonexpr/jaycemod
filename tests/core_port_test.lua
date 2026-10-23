-- foundation.core.port: an interface, as the methods a value must have.
local T = dofile("tests/harness.lua")
local Port = core.port

local function Raises(fn, ...)
	local ok, err = pcall(fn, ...)
	T.eq(ok, false, "raises")
	return tostring(err)
end

local function Soldier()
	local soldier = { shots = 0 }
	function soldier:Now() return 5 end
	function soldier:Shoot() self.shots = self.shots + 1 end
	return soldier
end

local SHOOTER = Port.New("Shooter", { "Now", "Shoot" })

T.test("a value with every method passes its port's check", function()
	local soldier = Soldier()
	T.eq(SHOOTER:Check(soldier), soldier, "handed back")
	T.eq(SHOOTER:Name(), "Shooter", "its name")
	T.eq(Port.Is(SHOOTER), true, "a port")
	T.eq(Port.Is({}), false, "a table is not")
end)

T.test("a value missing a method is refused, naming all it lacks", function()
	local err = Raises(SHOOTER.Check, SHOOTER, {})
	T.eq(err:find("is not a Shooter", 1, true) ~= nil, true, "names the port")
	T.eq(err:find("Now, Shoot", 1, true) ~= nil, true, "names the methods")
end)

T.test("a facade carries only the port's methods, looked up at call time", function()
	local soldier = Soldier()
	soldier.Secret = function() return "hidden" end
	local me = SHOOTER:Facade(soldier)
	me:Shoot()
	T.eq(soldier.shots, 1, "calls through")
	T.eq(me.Secret, nil, "nothing else")
	function soldier:Now() return 9 end
	T.eq(me:Now(), 9, "a replaced method takes effect at once")
end)

T.test("a port needs a name and at least one method, each named once", function()
	Raises(Port.New, "Empty", {})
	Raises(Port.New, nil, { "Now" })
	Raises(Port.New, "Twice", { "Now", "Now" })
	Raises(Port.New, "Odd", { "Now", 3 })
end)

T.finish()
