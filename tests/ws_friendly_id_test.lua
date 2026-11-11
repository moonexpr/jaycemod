-- includes.friendly_id and ws/cl_friendly_id.lua: while teams play, friends
-- wear an outline in their team's colour and an enemy under the crosshair
-- shows no name.
local T = dofile("tests/harness.lua")
local Teams = gameplay.teams
local Id = T.require("includes.friendly_id")
local RED, BLUE, SPECTATOR = Teams.RED, Teams.BLUE, Teams.SPECTATOR

T.test("a friend is on the player's own playing team, while teams play", function()
	T.eq(Id.Friendly(true, RED, RED), true, "the same team")
	T.eq(Id.Friendly(true, RED, BLUE), false, "the other team")
	T.eq(Id.Friendly(false, RED, RED), false, "Sandbox mode has no sides")
	T.eq(Id.Friendly(true, SPECTATOR, SPECTATOR), false, "spectators have no friends to tell apart")
end)

T.test("an enemy is on the other playing team, while teams play", function()
	T.eq(Id.Enemy(true, RED, BLUE), true, "the other team")
	T.eq(Id.Enemy(true, RED, RED), false, "the same team")
	T.eq(Id.Enemy(false, RED, BLUE), false, "Sandbox mode has no sides")
	T.eq(Id.Enemy(true, SPECTATOR, BLUE), false, "a spectator may read every name")
end)

T.test("a building's target id is for its team and its builder", function()
	T.eq(Id.SeesBuilding(true, RED, RED, false), true, "a teammate")
	T.eq(Id.SeesBuilding(true, RED, BLUE, false), false, "the enemy")
	T.eq(Id.SeesBuilding(false, 1001, 1001, true), true, "its builder, without sides")
	T.eq(Id.SeesBuilding(false, 1001, 1001, false), false, "anyone else, without sides")
end)

T.test("a building's target id names it and tells its health, or how far up it is", function()
	local up = Id.BuildingLines("Sentry Gun", 143, 150, 1)
	T.eq(up[1], "Sentry Gun", "its name")
	T.eq(up[2], "Health: 143 / 150", "its health")
	T.eq(Id.BuildingLines("Teleporter", 150, 150, 0.4)[2], "Building: 40%", "going up")
	T.eq(Id.BuildingLines("Teleporter", 150, 150, 0.999)[2], "Building: 99%", "not whole until built")
end)

local SOURCE = T.ROOT .. "cl_friendly_id.lua"

local function Player(team)
	return {
		Team = function() return team end,
		Alive = function() return true end,
		IsDormant = function() return false end,
		IsPlayer = function() return true end,
	}
end

local function Client(me, others, teamPlay, outlinesOn)
	local client = { hooks = {}, halos = {}, texts = {} }
	me.GetEyeTrace = function() return { Entity = client.looking } end
	local all = { me }
	for _, ply in ipairs(others) do all[#all + 1] = ply end
	local env = setmetatable({
		WS = { require = T.require, Localize = function(token) return ({ ["#TF_Object_Sentry"] = "Sentry Gun" })[token] end, TeamPlay = function() return teamPlay end, TeamColor = { [RED] = "red", [BLUE] = "blue" } },
		CreateClientConVar = function() return { GetBool = function() return outlinesOn end } end,
		hook = { Add = function(event, _, fn) client.hooks[event] = fn end },
		LocalPlayer = function() return me end,
		IsValid = function(ent) return ent ~= nil end,
		player = { GetAll = function() return all end },
		halo = { Add = function(list, color) client.halos[#client.halos + 1] = { list = list, color = color } end },
		draw = { SimpleText = function(text) client.texts[#client.texts + 1] = text end },
		ScrW = function() return 800 end,
		ScrH = function() return 600 end,
		TEXT_ALIGN_CENTER = 1,
		TEXT_ALIGN_TOP = 3,
	}, { __index = _G })
	setfenv(assert(loadfile(SOURCE)), env)()
	return client
end

T.test("an enemy under the crosshair shows no name; anyone else keeps the game's", function()
	local enemy, friend = Player(BLUE), Player(RED)
	local client = Client(Player(RED), { enemy, friend }, true, true)
	client.looking = enemy
	T.eq(client.hooks.HUDDrawTargetID(), true, "hidden")
	client.looking = friend
	T.eq(client.hooks.HUDDrawTargetID(), nil, "a friend's stays")
	client.looking = nil
	T.eq(client.hooks.HUDDrawTargetID(), nil, "nothing there")
end)

-- A building as a client sees it: a base_obj, its health shown as GetObjHealth.
local function Building(team, builder)
	return {
		PrintName = "#TF_Object_Sentry",
		Kind = "sentry",
		GetObjTeam = function() return team end,
		GetObjHealth = function() return 100 end,
		GetObjMaxHealth = function() return gameplay.buildings.HEALTH.sentry end,
		GetBuilder = function() return builder end,
		Constructed = function() return 1 end,
		IsPlayer = function() return false end,
	}
end

T.test("a teammate's building under the crosshair shows its target id in place of the game's", function()
	local me = Player(RED)
	local client = Client(me, {}, true, true)
	client.looking = Building(RED)
	T.eq(client.hooks.HUDDrawTargetID(), true, "drawn in place of the game's")
	T.eq(client.texts[1], "Sentry Gun", "its name")
	T.eq(client.texts[2], "Health: 100 / " .. gameplay.buildings.HEALTH.sentry, "its health")
	client.texts = {}
	client.looking = Building(BLUE)
	client.hooks.HUDDrawTargetID()
	T.eq(#client.texts, 0, "the enemy's shows nothing")
end)

T.test("friends are outlined in the team's colour, never the player or an enemy", function()
	local enemy, friend = Player(BLUE), Player(RED)
	local client = Client(Player(RED), { enemy, friend }, true, true)
	client.hooks.PreDrawHalos()
	T.eq(#client.halos, 1, "one outline")
	T.eq(#client.halos[1].list, 1, "the friend alone")
	T.eq(client.halos[1].list[1], friend, "the friend")
	T.eq(client.halos[1].color, "red", "the team's colour")
end)

T.test("no friends, or outlines turned off, draws none", function()
	local alone = Client(Player(RED), { Player(BLUE) }, true, true)
	alone.hooks.PreDrawHalos()
	T.eq(#alone.halos, 0, "no friend in the game")
	local off = Client(Player(RED), { Player(RED) }, true, false)
	off.hooks.PreDrawHalos()
	T.eq(#off.halos, 0, "turned off")
end)

T.finish()
