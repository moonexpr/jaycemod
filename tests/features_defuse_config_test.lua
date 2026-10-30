-- features.defuse.config: a map's bomb defusal settings, from its
-- cs_defuse_logic's keyvalues (CS:S's own defaults when left out): the
-- round's length, the bomb's timer, how long planting and defusing take,
-- and the blast's radius (the map's info_map_parameters bombradius when the
-- logic gives none). A value that is not one is refused, naming its key.
local T = dofile("tests/harness.lua")
local Config = T.require("features.defuse.config")

T.defined(Config.ROUND_TIME, "ROUND_TIME")
T.defined(Config.C4_TIMER, "C4_TIMER")
T.defined(Config.PLANT_TIME, "PLANT_TIME")
T.defined(Config.DEFUSE_TIME, "DEFUSE_TIME")
T.defined(Config.BOMB_RADIUS, "BOMB_RADIUS")
T.defined(Config.ARM_TIME, "ARM_TIME")

-- The plant is a fast capture, and arming the bomb after it holds those who
-- planted (armtime, the stun it puts on them).
T.test("planting is quick, arming holds the planters, and both before defusing would end", function()
	T.eq(Config.Parse({}, nil).armTime, Config.ARM_TIME, "the default arming")
	T.eq(Config.Parse({ armtime = "2" }, nil).armTime, 2, "set")
	T.eq(Config.PLANT_TIME < Config.ARM_TIME, true, "the capture is quicker than the arming")
	T.eq(pcall(Config.Parse, { armtime = "0" }, nil), false, "0 refused")
end)

T.test("no keyvalues: CS:S's defaults", function()
	local c = Config.Parse({}, nil)
	T.eq(c.roundTime, Config.ROUND_TIME, "round")
	T.eq(c.c4Timer, Config.C4_TIMER, "c4")
	T.eq(c.plantTime, Config.PLANT_TIME, "plant")
	T.eq(c.defuseTime, Config.DEFUSE_TIME, "defuse")
	T.eq(c.bombRadius, Config.BOMB_RADIUS, "radius")
end)

T.test("the bomb is defused more slowly than it is planted, and both before it blows", function()
	T.eq(Config.DEFUSE_TIME > Config.PLANT_TIME, true, "defusing is slower")
	T.eq(Config.C4_TIMER > Config.DEFUSE_TIME, true, "there is time to defuse")
end)

T.test("each is set by its key, in seconds or units", function()
	local c = Config.Parse({ roundtime = "120", c4timer = "35", planttime = "2", defusetime = "5", bombradius = "400" }, nil)
	T.eq(c.roundTime, 120, "round")
	T.eq(c.c4Timer, 35, "c4")
	T.eq(c.plantTime, 2, "plant")
	T.eq(c.defuseTime, 5, "defuse")
	T.eq(c.bombRadius, 400, "radius")
end)

T.test("the map's own bomb radius, unless the logic gives one", function()
	T.eq(Config.Parse({}, "300").bombRadius, 300, "the map's")
	T.eq(Config.Parse({ bombradius = "450" }, "300").bombRadius, 450, "the logic's")
end)

T.test("a value that is no positive number is refused, naming the key", function()
	for _, key in ipairs({ "roundtime", "c4timer", "planttime", "armtime", "defusetime", "bombradius" }) do
		local ok, err = pcall(Config.Parse, { [key] = "soon" }, nil)
		T.eq(ok, false, key .. " refused")
		T.eq(tostring(err):find(key, 1, true) ~= nil, true, key .. " named")
		T.eq(pcall(Config.Parse, { [key] = "0" }, nil), false, key .. " 0 refused")
	end
end)

T.finish()
