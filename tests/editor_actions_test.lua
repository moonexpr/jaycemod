-- WS.EditorAction (ws/sh_editors.lua): a right-click entry on an editor's
-- class, or on whatever its match(ent) accepts (a payload cart), for players
-- holding its privilege: tampering unless it names another. Run against a
-- fake properties library and a fake WS.Can.
local T = dofile("tests/harness.lua")
local Permissions = T.require("foundation.permissions")

local function Load()
	local added = {}
	local env = setmetatable({
		WS = {
			require = T.require,
			Can = function(ply, name) return ply.held[name] == true end,
		},
		properties = { Add = function(name, def) added[name] = def end },
		IsValid = function(v) return v ~= nil end,
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/gamemode/ws/sh_editors.lua")), env)()
	return env.WS, added
end

local function Ent(class, cart) return { GetClass = function() return class end, cart = cart } end
-- An admin holds every privilege an action may name; anyone else none.
local function Ply(admin)
	return {
		held = admin and {
			[Permissions.TAMPER] = true,
			[Permissions.ROUND] = true,
		} or {},
	}
end

T.test("an action needs the tampering privilege unless it names another", function()
	local W, added = Load()
	W.EditorAction("tamper", { class = "edit_roundtimer", run = function() end })
	W.EditorAction("round", { class = "edit_gamerules", privilege = Permissions.ROUND, run = function() end })
	local tamperOnly = { held = { [Permissions.TAMPER] = true } }
	local roundOnly = { held = { [Permissions.ROUND] = true } }
	T.eq(added.tamper:Filter(Ent("edit_roundtimer"), tamperOnly), true)
	T.eq(added.tamper:Filter(Ent("edit_roundtimer"), roundOnly), false)
	T.eq(added.round:Filter(Ent("edit_gamerules"), roundOnly), true)
	T.eq(added.round:Filter(Ent("edit_gamerules"), tamperOnly), false)
end)

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
		WS = { TEAM_RED = 2, TEAM_BLUE = 3, require = T.require, EditorAction = function(name) actions[name] = true end },
	}, { __index = _G })
	setfenv(assert(loadfile("addon/gamemodes/sandcastle/entities/entities/edit_gamerules.lua")), env)()
	T.eq(actions.ws_retract_cart, nil)
	T.eq(actions.ws_advance_cart, nil)
	T.eq(actions.ws_reset_round, true, "its other actions stay")
end)

T.finish()
