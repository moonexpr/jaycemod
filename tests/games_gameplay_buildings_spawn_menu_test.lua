-- base_obj's SpawnFunction: a sentry or teleporter from the spawn menu is the
-- spawning player's, on the team they are on; a teleporter's second end is the
-- exit of the first.
local T = dofile("tests/harness.lua")
local Teams = gameplay.teams

local DIR = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"

local function Load(file, world)
	local ENT = {}
	local env = setmetatable({
		ENT = ENT,
		SERVER = true,
		CLIENT = false,
		AddCSLuaFile = function() end,
		RENDERGROUP_BOTH = 0,
		WS = setmetatable({
			require = T.require,
			TEAM_RED = Teams.RED,
			TEAM_BLUE = Teams.BLUE,
			TEAM_UNASSIGNED = Teams.UNASSIGNED,
			TeamNumber = function(ply) return ply.team end,
		}, { __index = function() return function() end end }),
		Vector = function() return {} end,
		Angle = function(_, yaw) return { yaw = yaw } end,
		IsValid = function(ent) return ent ~= nil end,
		ents = world,
		scripted_ents = { GetMember = function(_, member) return world.class[member] end },
		sound = { Add = function() end },
		util = { PrecacheSound = function() end },
	}, { __index = _G })
	setfenv(assert(loadfile(DIR .. file)), env)()
	return ENT
end

-- A world whose entities note what is set on them, and when they spawned.
local function World()
	local world = { made = {} }
	function world.Create(class)
		local ent = setmetatable({ class = class }, { __index = world.class })
		function ent:SetPos(pos) self.pos = pos end
		function ent:SetAngles(ang) self.ang = ang end
		function ent:SetObjTeam(team) self.objTeam = team end
		function ent:SetBuilder(builder) self.builder = builder end
		function ent:GetBuilder() return self.builder end
		function ent:SetIsExit(on) self.exit = on end
		function ent:GetIsExit() return self.exit == true end
		function ent:GetPartner() return self.partner end
		function ent:Spawn() self.spawnedTeam, self.spawnedBuilder, self.spawnedExit = self.objTeam, self.builder, self.exit end
		function ent:Activate() self.activated = true end
		function ent:Fits() return true end
		world.made[#world.made + 1] = ent
		return ent
	end
	function world.FindByClass() return world.made end
	return world
end

local PLAYER = { team = Teams.RED, EyeAngles = function() return { y = 90 } end }
local HIT = { Hit = true, HitPos = "there" }

local function Spawner(file, world)
	local base, sub = Load("base_obj.lua", world), Load(file, world)
	-- GMod's spawn menu calls SpawnFunction on the class's own table, inherited or not;
	-- what it makes is a whole entity, with its base's methods.
	world.class = setmetatable(sub, { __index = base })
	return { SpawnFunction = base.SpawnFunction }
end

T.test("sentries and teleporters are in the spawn menu; a building base is not", function()
	local world = World()
	T.eq(Load("base_obj.lua", world).Spawnable, false, "the base")
	for _, file in ipairs({ "obj_sentrygun.lua", "obj_teleporter.lua" }) do
		local ent = Load(file, world)
		T.eq(ent.Spawnable, true, file)
		T.eq(ent.Category, "Sandcastle", file .. " category")
	end
end)

T.test("a building is its spawner's, on their team, before it spawns, where they look", function()
	local world = World()
	local ent = Spawner("obj_sentrygun.lua", world):SpawnFunction(PLAYER, HIT, "obj_sentrygun")
	T.eq(ent.spawnedTeam, Teams.RED, "the team")
	T.eq(ent.spawnedBuilder, PLAYER, "the builder")
	T.eq(ent.pos, "there", "at the trace")
	T.eq(ent.ang.yaw, 90, "facing as they face")
	T.eq(ent.activated, true, "activated")
end)

T.test("spawning at nothing makes nothing", function()
	local world = World()
	T.eq(Spawner("obj_sentrygun.lua", world):SpawnFunction(PLAYER, { Hit = false }, "obj_sentrygun"), nil)
	T.eq(#world.made, 0, "none made")
end)

T.test("a player's first teleporter is the entrance, the next its exit", function()
	local world = World()
	local spawner = Spawner("obj_teleporter.lua", world)
	local entrance = spawner:SpawnFunction(PLAYER, HIT, "obj_teleporter")
	T.eq(entrance.spawnedExit, nil, "the first")
	local exit = spawner:SpawnFunction(PLAYER, HIT, "obj_teleporter")
	T.eq(exit.spawnedExit, true, "the second")
end)

T.test("a pair already linked, or another player's entrance, starts a new entrance", function()
	local world = World()
	local spawner = Spawner("obj_teleporter.lua", world)
	local entrance = spawner:SpawnFunction(PLAYER, HIT, "obj_teleporter")
	local other = { team = Teams.RED, EyeAngles = PLAYER.EyeAngles }
	T.eq(spawner:SpawnFunction(other, HIT, "obj_teleporter").spawnedExit, nil, "someone else's")
	entrance.partner = {}
	T.eq(spawner:SpawnFunction(PLAYER, HIT, "obj_teleporter").spawnedExit, nil, "already paired")
end)

T.finish()
