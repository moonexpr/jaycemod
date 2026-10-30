-- features.hostage.config: a map's hostage settings, from its
-- cs_logic_hostage's keyvalues: the class of entity each hostage_entity
-- spawns as the hostage it observes, and whether one hostage a round is
-- armed. A map without the entity, or a key left out, takes the defaults;
-- a value that is not one is refused, naming the key.
local T = dofile("tests/harness.lua")
local Config = T.require("features.hostage.config")

T.test("no keyvalues: the defaults", function()
	local config = Config.Parse({})
	T.eq(config.bodyClass, Config.BODY_CLASS, "the default body")
	T.eq(config.bodyClass, "npc_civilian", "the civilian")
	T.eq(config.pistol, true, "one armed")
end)

T.test("the body may be any entity class", function()
	T.eq(Config.Parse({ bodyclass = "prop_physics" }).bodyClass, "prop_physics", "a prop")
	T.eq(Config.Parse({ bodyclass = "" }).bodyClass, Config.BODY_CLASS, "empty: the default")
end)

T.test("a body's model is given, or left to the body", function()
	T.eq(Config.Parse({}).bodyModel, nil, "left out: the body's own")
	T.eq(Config.Parse({ bodymodel = "" }).bodyModel, nil, "empty: the body's own")
	T.eq(Config.Parse({ bodymodel = "models/props_c17/oildrum001.mdl" }).bodyModel, "models/props_c17/oildrum001.mdl", "given")
	local ok, err = pcall(Config.Parse, { bodymodel = "props/drum" })
	T.eq(ok, false, "not a .mdl: refused")
	T.eq(tostring(err):find("bodymodel", 1, true) ~= nil, true, "naming the key")
end)

T.test("pistol is 0 or 1", function()
	T.eq(Config.Parse({ pistol = "0" }).pistol, false, "0: none armed")
	T.eq(Config.Parse({ pistol = "1" }).pistol, true, "1: one armed")
	local ok, err = pcall(Config.Parse, { pistol = "yes" })
	T.eq(ok, false, "anything else refused")
	T.eq(tostring(err):find("pistol", 1, true) ~= nil, true, "naming the key")
end)

T.test("a class with characters no entity class has is refused", function()
	local ok, err = pcall(Config.Parse, { bodyclass = "npc civilian;" })
	T.eq(ok, false, "refused")
	T.eq(tostring(err):find("bodyclass", 1, true) ~= nil, true, "naming the key")
end)

T.finish()
