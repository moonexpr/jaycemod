-- entities/base_obj.lua's SpawnFunction: what a building set down from the spawn menu costs, and
-- when it is refused (who it is for: games_gameplay_buildings_spawn_menu_test).
local T = dofile("tests/harness.lua")

local DIR = "addons/sandcastle/gamemodes/sandcastle/entities/entities/"
local RED = 2
local PRICES = gameplay.buildings.SPAWN_PRICE
local PRICE = PRICES.sentry

-- The classes as GMod holds them: each its own table, members read up its bases.
local function Stored(world)
	local stored = {}
	local function Load(class)
		local ENT = {}
		local env = setmetatable({
			ENT = ENT, SERVER = true, CLIENT = false, AddCSLuaFile = function() end, RENDERGROUP_BOTH = 0,
			WS = world.WS, net2 = world.net2,
			ents = world.ents, scripted_ents = world.scripted_ents, IsValid = world.IsValid,
			Angle = function(p, y, r) return { p = p, y = y, r = r } end,
			Vector = function(x, y, z) return { x = x, y = y, z = z } end,
			hook = { Add = function() end },
			sound = { Add = function() end }, util = { PrecacheSound = function() end },
		}, { __index = _G })
		setfenv(assert(loadfile(DIR .. class .. ".lua")), env)()
		stored[class] = ENT
		return ENT
	end
	for _, class in ipairs({ "base_obj", "obj_sentrygun", "obj_teleporter", "obj_door" }) do Load(class) end
	return stored
end

-- economy: nil for money switched off, else a player's balance.
local function World(fits, economy)
	local world = { placed = {}, fits = fits ~= false, spent = 0, told = {} }
	-- What its placer is told goes to their client, to word in their language.
	world.net2 = { Send = function(name, payload, options)
		world.told[#world.told + 1] = { name = name, payload = payload, to = options.to }
	end }
	world.WS = {
		TEAM_RED = RED, TEAM_BLUE = 3,
		require = function() return {} end,
		TeamNumber = function(ply) return ply.team end,
		EconomyEnabled = function() return economy ~= nil end,
		Money = function() return economy end,
		Affords = function(balance, price) return balance >= price end,
		SpendMoney = function(_, amount)
			assert(economy ~= nil, "refused: money is switched off")
			world.spent = world.spent + amount
		end,
	}
	world.IsValid = function(ent) return ent ~= nil and not ent.removed end
	world.scripted_ents = {
		GetMember = function(class, member)
			local t = world.stored[class]
			if t[member] ~= nil then return t[member] end
			if t.Base ~= "base_anim" then return world.scripted_ents.GetMember(t.Base, member) end
		end,
	}
	world.ents = {
		FindByClass = function(class)
			local found = {}
			for _, ent in ipairs(world.placed) do
				if ent.class == class and not ent.removed then found[#found + 1] = ent end
			end
			return found
		end,
		Create = function(class)
			local ent = setmetatable({ class = class }, { __index = function(_, key)
				return world.scripted_ents.GetMember(class, key)
			end })
			function ent:NetworkVar(kind, _, name)
				self["Get" .. name] = function(s)
					local v = s["nv" .. name]
					if v == nil and kind == "Bool" then return false end
					return v
				end
				self["Set" .. name] = function(s, v) s["nv" .. name] = v end
			end
			ent:SetupDataTables()
			ent.SetPos = function(s, pos) s.pos = pos end
			ent.SetAngles = function(s, ang) s.ang = ang end
			ent.Spawn = function(s) s.spawned = true s:ObjInitialize() end
			ent.Activate = function() end
			ent.Remove = function(s) s.removed = true end
			ent.Fits = function() return world.fits end
			world.placed[#world.placed + 1] = ent
			return ent
		end,
	}
	world.stored = Stored(world)
	return world
end

local function Player()
	local ply = { team = RED }
	function ply:EyeAngles() return { y = 90 } end
	return ply
end

local HIT = { Hit = true, HitPos = "the spot" }

-- SpawnFunction is read up the bases, as GMod reads it.
local function PlaceAs(world, ply, class, tr)
	return world.scripted_ents.GetMember(class, "SpawnFunction")(world.stored[class], ply, tr or HIT, class)
end

T.test("a building with no room is taken back and its placer told", function()
	local world, ply = World(false), Player()
	T.eq(PlaceAs(world, ply, "obj_sentrygun"), nil, "nothing to undo")
	T.eq(world.placed[1].removed, true, "taken back")
	T.eq(#world.told, 1, "told")
	T.eq(world.told[1].to, ply, "its placer")
	T.eq(world.told[1].payload.name, "#TF_Object_Sentry", "names it by TF2's token")
	T.eq(world.told[1].payload.price, nil, "no room, not the price")
end)

T.test("a class the menu does not list is not placed", function()
	local world, ply = World(), Player()
	T.eq(PlaceAs(world, ply, "obj_door"), nil, "the door")
	T.eq(#world.placed, 0)
end)

T.test("an exit left alone gets a new entrance", function()
	local world, ply = World(), Player()
	local entrance = PlaceAs(world, ply, "obj_teleporter")
	local exit = PlaceAs(world, ply, "obj_teleporter")
	entrance:Remove()
	exit:SetPartner(nil)
	local again = PlaceAs(world, ply, "obj_teleporter")
	T.eq(again:GetIsExit(), false, "an entrance")
	T.eq(again:GetPartner(), exit, "to the lone exit")
end)

T.test("with money on, a building placed is paid for", function()
	local world, ply = World(true, PRICE), Player()
	T.eq(PlaceAs(world, ply, "obj_sentrygun").class, "obj_sentrygun", "placed")
	T.eq(world.spent, PRICE, "charged")
end)

T.test("a placer who cannot pay is told the price and nothing is placed", function()
	local world, ply = World(true, PRICE - 1), Player()
	T.eq(PlaceAs(world, ply, "obj_sentrygun"), nil, "nothing")
	T.eq(#world.placed, 0, "none made")
	T.eq(world.spent, 0, "not charged")
	T.eq(world.told[1].payload.price, PRICE, "the price")
	T.eq(world.told[1].payload.name, "#TF_Object_Sentry", "names it")
end)

T.test("each kind of building has its own price", function()
	local world, ply = World(true, PRICES.teleporter), Player()
	T.eq(PlaceAs(world, ply, "obj_teleporter").class, "obj_teleporter", "placed")
	T.eq(world.spent, PRICES.teleporter, "the teleporter's")
end)

T.test("a building with no room costs nothing", function()
	local world, ply = World(false, PRICE), Player()
	T.eq(PlaceAs(world, ply, "obj_sentrygun"), nil, "not placed")
	T.eq(world.spent, 0, "not charged")
end)

T.test("with money switched off, a building is placed free", function()
	local world, ply = World(), Player()
	T.eq(PlaceAs(world, ply, "obj_sentrygun").class, "obj_sentrygun", "placed")
	T.eq(world.spent, 0, "not charged")
end)

T.finish()
