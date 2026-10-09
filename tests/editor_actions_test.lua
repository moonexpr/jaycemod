-- WETSAND.EditorAction (wetsand/sh_editors.lua): a right-click entry for
-- admins on an editor's class, or on whatever its match(ent) accepts (a
-- payload cart). Run against a fake properties library.
local T = dofile("tests/harness.lua")

local function Load()
	local added = {}
	local env = setmetatable({
		WETSAND = {},
		properties = { Add = function(name, def) added[name] = def end },
		IsValid = function(v) return v ~= nil end,
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/gamemode/wetsand/sh_editors.lua")), env)()
	return env.WETSAND, added
end

local function Ent(class, cart) return { GetClass = function() return class end, cart = cart } end
local function Ply(admin) return { IsAdmin = function() return admin end } end

T.test("an action on a class shows on that class's entities, for admins", function()
	local W, added = Load()
	W.EditorAction("a", { class = "edit_gamerules", run = function() end })
	T.eq(added.a:Filter(Ent("edit_gamerules"), Ply(true)), true)
	T.eq(added.a:Filter(Ent("prop_physics"), Ply(true)), false, "another class")
	T.eq(added.a:Filter(Ent("edit_gamerules"), Ply(false)), false, "not an admin")
end)

T.test("an action with match shows on whatever it accepts, for admins", function()
	local W, added = Load()
	W.EditorAction("b", { match = function(ent) return ent.cart end, run = function() end })
	T.eq(added.b:Filter(Ent("prop_dynamic", true), Ply(true)), true, "a cart")
	T.eq(added.b:Filter(Ent("prop_dynamic", false), Ply(true)), false, "not a cart")
	T.eq(added.b:Filter(Ent("prop_dynamic", true), Ply(false)), false, "not an admin")
end)

T.test("the Game Rules Editor no longer moves carts: right-click the cart", function()
	local actions = {}
	local env = setmetatable({
		ENT = {},
		AddCSLuaFile = function() end,
		DEFINE_BASECLASS = function() end,
		WETSAND = { TEAM_RED = 2, TEAM_BLUE = 3, EditorAction = function(name) actions[name] = true end },
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/entities/entities/edit_gamerules.lua")), env)()
	T.eq(actions.wetsand_retract_cart, nil)
	T.eq(actions.wetsand_advance_cart, nil)
	T.eq(actions.wetsand_reset_round, true, "its other actions stay")
end)

T.finish()
