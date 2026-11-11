-- entities/base_obj.lua: a building goes up playing its model's build animation, paced to its
-- construction time, and stands as its own model once built; a model with none is faded in.
local T = dofile("tests/harness.lua")
local Buildings = gameplay.buildings

local DIR = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"
local ASSEMBLING, RUNNING, BBOX = 462, 465, 2
local SENTRY, SENTRY_BUILD = "models/buildables/sentry1.mdl", "models/buildables/sentry1_heavy.mdl"
local TELEPORTER = "models/buildables/teleporter.mdl"

-- What each model answers for an activity: its sequence, and how long that runs.
local SEQUENCES = {
	[SENTRY] = { [RUNNING] = { 0, 1 } },
	[SENTRY_BUILD] = { [ASSEMBLING] = { 2, 5 }, [RUNNING] = { 1, 1 } },
	[TELEPORTER] = { [ASSEMBLING] = { 1, 10 }, [RUNNING] = { 0, 0 } },
}

local function Contains(list, value)
	for _, held in ipairs(list) do
		if held == value then return true end
	end
	return false
end

local function Load(file, world)
	local ENT = {}
	local env = setmetatable({
		ENT = ENT, SERVER = true, CLIENT = true, AddCSLuaFile = function() end, RENDERGROUP_BOTH = 0,
		SOLID_VPHYSICS = 6, SOLID_BBOX = BBOX, MOVETYPE_NONE = 0, MASK_SOLID = 1,
		ACT_OBJ_ASSEMBLING = ASSEMBLING, ACT_OBJ_RUNNING = RUNNING,
		util = { PrecacheSound = function() end, TraceHull = function(trace)
			local filter = type(trace.filter) == "table" and trace.filter.class == nil and trace.filter or { trace.filter }
			world.ignored = filter
			return { Hit = world.inTheWay ~= nil and not Contains(filter, world.inTheWay) }
		end },
		WS = {
			require = function() return {} end, TEAM_RED = 2, TEAM_BLUE = 3, TeamNumber = function(ent) return ent.team end,
			Localize = function(token) return ({ ["#TF_Object_Sentry"] = "Sentinelle" })[token] end,
		},
		net2 = { Receive = function(name, fn) world.receivers[name] = fn end },
		chat = { AddText = function(text) world.chat[#world.chat + 1] = text end },
		TF_TEAM_UNASSIGNED = 0,
		sound = { Add = function() end }, CHAN_WEAPON = 1, CHAN_ITEM = 3, CHAN_STATIC = 6,
		CurTime = function() return world.now end,
		IsValid = function() return false end,
		Vector = function(x, y, z) return { x = x, y = y, z = z } end,
		hook = { Add = function() end },
		navmesh = { Find = function() return {} end },
		render = { SetBlend = function(alpha) world.blends[#world.blends + 1] = alpha end },
		ents = { FindByClass = function() return {} end },
	}, { __index = _G })
	setfenv(assert(loadfile(DIR .. file .. ".lua")), env)()
	return ENT
end

-- A building as the engine holds it, its team RED.
local function Building(class)
	local world = { now = 100, blends = {}, receivers = {}, chat = {} }
	local base, sub = Load("base_obj", world), Load(class, world)
	sub.BaseClass = base
	local ent = setmetatable({ world = world, models = {}, thoughts = 0 }, { __index = setmetatable(sub, { __index = base }) })
	-- The engine sizes an entity to each model it is given, whatever it was set to before.
	function ent:SetModel(model) self.model = model self.models[#self.models + 1] = model self.bounds = nil end
	function ent:SetSolid(solid) self.solid = solid end
	function ent:SetCollisionBounds(mins, maxs) self.bounds = { mins, maxs } end
	function ent:GetPos() return {} end
	function ent:OBBMins() return { x = 0, y = 0, z = 0 } end
	function ent:OBBMaxs() return {} end
	function ent:SetSkin() end
	function ent:PhysicsInit() self.physics = true end
	function ent:SetMoveType() end
	function ent:GetPhysicsObject() end
	function ent:SetMaxHealth(health) self.maxHealth = health end
	function ent:GetMaxHealth() return self.maxHealth or 1 end
	function ent:SetHealth(health) self.health = health end
	function ent:Health() return self.health end
	function ent:SetObjHealth(health) self.shownHealth = health end
	function ent:SetObjMaxHealth(health) self.shownMaxHealth = health end
	function ent:SetCustomCollisionCheck() end
	function ent:WorldSpaceCenter() return {} end
	function ent:NextThink() end
	function ent:DrawModel() self.drawn = true end
	function ent:GetObjTeam() return 2 end
	function ent:SetBuiltAt(at) self.builtAt = at end
	function ent:GetBuiltAt() return self.builtAt end
	function ent:SetOpen() end
	function ent:GetOpen() return false end
	function ent:GetBuilder() end
	function ent:SelectWeightedSequence(activity)
		local found = (SEQUENCES[self.model] or {})[activity]
		return found and found[1] or -1
	end
	function ent:SequenceDuration(sequence)
		for _, found in pairs(SEQUENCES[self.model]) do
			if found[1] == sequence then return found[2] end
		end
	end
	function ent:ResetSequence(sequence) self.sequence = sequence end
	function ent:SetPlaybackRate(rate) self.rate = rate end
	function ent:ObjThink() self.thoughts = self.thoughts + 1 end
	function ent:EmitSound(name) self.sounds = self.sounds or {} self.sounds[#self.sounds + 1] = name end
	ent:Initialize()
	return ent, world
end

local function Built(ent, world)
	world.now = world.now + Buildings.BUILD_TIME[ent.Kind]
	ent:Think()
end

T.test("a sentry goes up on its build model, its animation paced to its construction", function()
	local ent = Building("obj_sentrygun")
	T.eq(ent.model, SENTRY_BUILD, "the model with the animation")
	T.eq(ent.sequence, 2, "assembling")
	T.eq(ent.rate, 5 / Buildings.BUILD_TIME.sentry, "paced")
end)

T.test("a sentry built stands as its own model, once, and goes to work", function()
	local ent, world = Building("obj_sentrygun")
	Built(ent, world)
	T.eq(ent.model, SENTRY, "its own")
	T.eq(ent.sequence, 0, "running")
	T.eq(ent.rate, 1, "at its own speed")
	T.eq(ent.thoughts, 1, "at work")
	T.eq(ent.sounds[1], "Building_Sentrygun.Built", "TF2's built sound")
	local swaps = #ent.models
	ent:Think()
	T.eq(#ent.models, swaps, "swapped once")
	T.eq(ent.thoughts, 2, "still at work")
end)

T.test("a sentry going up does no work and keeps its build model", function()
	local ent = Building("obj_sentrygun")
	ent:Think()
	T.eq(ent.model, SENTRY_BUILD)
	T.eq(ent.thoughts, 0)
end)

T.test("a teleporter plays its own model's animation, paced to its construction", function()
	local ent, world = Building("obj_teleporter")
	T.eq(ent.model, TELEPORTER, "its own model")
	T.eq(ent.sequence, 1, "assembling")
	T.eq(ent.rate, 10 / Buildings.BUILD_TIME.teleporter, "paced")
	Built(ent, world)
	T.eq(ent.sequence, 0, "running")
	T.eq(ent.rate, 1, "at its own speed")
end)

T.test("a building with a build animation is drawn whole as it goes up", function()
	local ent, world = Building("obj_sentrygun")
	T.eq(ent.Draw, nil, "no drawing of its own")
	T.eq(#world.blends, 0, "no fade")
end)

T.test("a door has no build animation: it plays nothing and fades in", function()
	local ent, world = Building("obj_door")
	T.eq(ent.sequence, nil, "nothing played")
	ent:Draw()
	T.eq(ent.drawn, true, "drawn")
	T.eq(world.blends[1] < 1, true, "faded going up")
	world.now = world.now + Buildings.BUILD_TIME.door
	world.blends = {}
	ent:Draw()
	T.eq(world.blends[1], 1, "whole once built")
end)

-- Its models carry no collision shape, so without a box bullets pass through it.
T.test("a sentry and a teleporter are solid boxes shots can hit, through each of their models", function()
	for _, class in ipairs({ "obj_sentrygun", "obj_teleporter" }) do
		local ent, world = Building(class)
		T.eq(ent.solid, BBOX, class .. ": a box")
		T.eq(ent.physics, nil, class .. ": not its model's shape")
		T.eq(ent.HullMins ~= nil and ent.bounds[1] == ent.HullMins, true, class .. ": sized going up")
		T.eq(ent.bounds[2], ent.HullMaxs, class .. ": sized going up")
		Built(ent, world)
		T.eq(ent.bounds[1], ent.HullMins, class .. ": sized again once built")
	end
end)

-- Its health is the server's alone: a copy goes to clients, for a teammate's target id.
T.test("a building shows clients its health, whole as it goes up and less once hurt", function()
	local ent = Building("obj_sentrygun")
	T.eq(ent.shownHealth, Buildings.HEALTH.sentry, "whole")
	ent:OnTakeDamage({ GetAttacker = function() end, GetDamage = function() return 40 end })
	T.eq(ent.shownHealth, Buildings.HEALTH.sentry - 40, "hurt")
end)

T.test("a teammate's wrench mends a built building; an enemy's, or one on a whole building, does nothing", function()
	local ent, world = Building("obj_sentrygun")
	Built(ent, world)
	ent.health = 50
	T.eq(ent:Wrench({ team = 2 }), true, "a teammate's mends")
	T.eq(ent.health, Buildings.Repaired(50, Buildings.HEALTH.sentry), "mended")
	T.eq(ent.shownHealth, ent.health, "shown mended")
	local mended = ent.health
	T.eq(ent:Wrench({ team = 3 }), false, "an enemy's does not")
	T.eq(ent.health, mended, "untouched")
	ent.health = Buildings.HEALTH.sentry
	T.eq(ent:Wrench({ team = 2 }), false, "nothing to mend")
end)

T.test("a teammate's wrench hurries a building going up", function()
	local ent, world = Building("obj_teleporter")
	T.eq(ent:Wrench({ team = 2 }), true, "hurried")
	T.eq(ent.builtAt, Buildings.Hurried("teleporter", 100, world.now), "begun earlier")
	T.eq(ent:Wrench({ team = 3 }), false, "never by the enemy")
end)

T.test("a placer's client words why its building was refused in its own language", function()
	local _, world = Building("obj_sentrygun")
	local refused = world.receivers.ws_obj_refused
	refused({ name = "#TF_Object_Sentry", price = 2000 })
	refused({ name = "#TF_Object_Sentry" })
	T.eq(world.chat[1], "A Sentinelle costs $2000", "the price")
	T.eq(world.chat[2], "There is no room for a Sentinelle here", "no room")
end)

T.test("a door stays on its model's own physics", function()
	local ent = Building("obj_door")
	T.eq(ent.physics, true, "its shape")
	T.eq(ent.solid, nil, "no box")
end)

-- A building is a solid box: whoever stands where it goes would be stuck inside it.
T.test("whoever stands where a building goes is in the way, its own builder too", function()
	local ent, world = Building("obj_sentrygun")
	local player = { IsPlayer = function() return true end }
	local soldier = { IsPlayer = function() return false end }
	world.inTheWay = player
	ent.GetBuilder = function() return player end
	T.eq(ent:Fits(), false, "the player")
	world.inTheWay = soldier
	ent.GetBuilder = function() return soldier end
	T.eq(ent:Fits(), false, "the soldier")
	world.inTheWay = nil
	T.eq(ent:Fits(), true, "nobody")
end)

T.finish()
