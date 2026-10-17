-- Part of the AI war controller (sv.lua): how the war reads the map: points, masks, spawn spots, hiding spots, doors
-- and the ground. Its helpers go to the other parts as Map.
local Spawns = WS.require("foundation.aiwar.spawns")
local Slots = WS.require("foundation.aiwar.slots")
local AiWar = WS.require("foundation.aiwar")

-- CanWalkTo's sweep: a soldier's hull above its step height, so stairs and
-- slopes pass and walls do not.
local WALK_MINS, WALK_MAXS = Vector(-13, -13, 0), Vector(13, 13, 52)
local WALK_LIFT = Vector(0, 0, 20)
local WALK_MAX_RISE = 40

local SPAWN_MINS, SPAWN_MAXS = Vector(-16, -16, 0), Vector(16, 16, 72)
local SPAWN_LIFT = Vector(0, 0, 4)
local SPAWN_SPREAD, SPAWN_TRIES = 48, 8

local GROUND_PROBE = 256

local RED, BLUE = WS.TEAM_RED, WS.TEAM_BLUE

local function Point(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(p) return Vector(p.x, p.y, p.z) end

-- The masks the soldiers move under on this map, and the walk traces take
-- (on a players' map, the player's clips: ws/sv_nav.lua).
local function Masks() return WS.ClipMasks() end

-- Where a team's soldiers join the fight: its TF2 team spawns; on a map
-- without any, its own HL2 deathmatch spawns, else its share of the nav
-- mesh's hiding spots, else the map's shared player starts
-- (foundation.aiwar.spawns). A hiding spot is a spot as a spawn entity is
-- one: GetPos and GetAngles.
local function Present(class) return #ents.FindByClass(class) > 0 end

local HidingSpot = {}
HidingSpot.__index = HidingSpot
function HidingSpot:GetPos() return ToVector(self.pos) end
function HidingSpot:GetAngles() return Angle(0, 0, 0) end

-- team -> its hiding spots, split once the nav mesh has any
local hidingSpots

local function HidingSpotsOf(team)
	if not hidingSpots then
		local all = {}
		for _, area in ipairs(navmesh.GetAllNavAreas()) do
			for _, pos in ipairs(area:GetHidingSpots() or {}) do all[#all + 1] = Point(pos) end
		end
		if #all == 0 then return {} end
		hidingSpots = {}
		for _, t in ipairs({ RED, BLUE }) do
			local list = {}
			for i, pos in ipairs(Spawns.Split(all, t)) do list[i] = setmetatable({ pos = pos }, HidingSpot) end
			hidingSpots[t] = list
		end
	end
	return hidingSpots[team]
end

local function EntitiesOf(classes)
	local spots = {}
	for _, class in ipairs(classes) do
		for _, ent in ipairs(ents.FindByClass(class)) do spots[#spots + 1] = ent end
	end
	return spots
end

local function SpawnSpots(team)
	local teamSpawns = WS.SpawnPoints(team)
	if #teamSpawns > 0 or Present("info_player_teamspawn") then return teamSpawns end
	local own = Spawns.Classes(team, Present)
	if #own > 0 then return EntitiesOf(own) end
	local hiding = HidingSpotsOf(team)
	if #hiding > 0 then return hiding end
	return EntitiesOf(Spawns.Shared(Present))
end

local DOOR_CLASSES = { func_door = true, func_door_rotating = true, prop_door_rotating = true }

local function IsDoor(ent)
	return DOOR_CLASSES[ent:GetClass()] == true
end

-- Two entities that no longer collide, in physics or in an engine NPC's
-- movement checks (CTraceFilterNav skips pairs in the engine's collision
-- pair table, which logic_collision_pair fills, as Sandbox's No Collide
-- does). The pair goes with either entity.
--
-- One pair for two soldiers, however often either is enlisted: a body the
-- reserve revives is enlisted again but never removed, and its pairs go only
-- with an entity's removal (DeleteOnRemove). Each keeps its pairs by
-- partner (NSPasses).
local function PassThrough(a, b)
	local known = a.NSPasses and a.NSPasses[b]
	if IsValid(known) then return end
	local physA, physB = a:GetPhysicsObject(), b:GetPhysicsObject()
	if not (IsValid(physA) and IsValid(physB)) then return end
	local pair = ents.Create("logic_collision_pair")
	a.NSPasses = a.NSPasses or setmetatable({}, { __mode = "k" })
	b.NSPasses = b.NSPasses or setmetatable({}, { __mode = "k" })
	a.NSPasses[b], b.NSPasses[a] = pair, pair
	pair:SetKeyValue("startdisabled", "1")
	pair:SetPhysConstraintObjects(physA, physB)
	pair:Spawn()
	pair:Activate()
	pair:Input("DisableCollisions")
	a:DeleteOnRemove(pair)
	b:DeleteOnRemove(pair)
end

-- Whether a soldier could walk straight from a to b past the world alone
-- (no NPCs or players: a lane is planned once, for the round).
local function WorldWalkClear(a, b)
	local from, to = ToVector(a), ToVector(b)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	return not util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = Masks().brushes,
	}).Hit
end


-- A nav area over stairs is a ramp, while the steps under it are not, so
-- a point taken from the mesh can lie inside a step. A point is dropped
-- onto the floor found by a trace down from above it, or kept when no
-- floor is found.
local FLOOR_ABOVE, FLOOR_BELOW, FLOOR_CLEARANCE = 32, 64, 2

local function OnFloor(pos)
	local tr = util.TraceLine({
		start = pos + Vector(0, 0, FLOOR_ABOVE),
		endpos = pos - Vector(0, 0, FLOOR_BELOW),
		mask = Masks().brushes,
	})
	if tr.StartSolid or not tr.Hit then return pos end
	return tr.HitPos + Vector(0, 0, FLOOR_CLEARANCE)
end

-- Held to the war's limits: the main menu may create the convar without them.
local function TeamSize()
	return Slots.TeamSize(GetConVar("mp_aiwar_team_size"):GetInt(), AiWar.TEAM_SIZE_MAX)
end

-- Another feature's controller when it is already loaded, else nil: the war
-- reads the round and the points only from features the map loaded itself.
local function LoadedFeature(name)
	for _, loaded in ipairs(WS.FeatureLoader:Loaded()) do
		if loaded == name then return WS.Feature(name) end
	end
	return nil
end

-- The rounds mode's NAME (foundation.rounds), which picks the scenario; nil
-- without rounds.
local function RoundsModeName()
	local rounds = LoadedFeature("rounds")
	return rounds and rounds:Mode().NAME
end

-- Whether the rounds mode fights its round in STALEMATE (arena) and the
-- round is that, not a sudden death after it (AiWar.PhaseOf).
local function StalemateIsRound()
	local rounds = LoadedFeature("rounds")
	return rounds ~= nil and rounds:Mode().STALEMATE_IS_ROUND and not rounds:InSuddenDeath()
end

local function Clear(pos)
	local tr = util.TraceHull({
		start = pos + SPAWN_LIFT,
		endpos = pos + SPAWN_LIFT,
		mins = SPAWN_MINS,
		maxs = SPAWN_MAXS,
		mask = Masks().solid,
	})
	return not tr.Hit
end

-- The spot itself, else the first clear point on a ring around it.
local function ClearSpotNear(pos)
	if Clear(pos) then return pos end
	for i = 1, SPAWN_TRIES do
		local angle = (i / SPAWN_TRIES) * math.pi * 2
		local candidate = pos + Vector(math.cos(angle), math.sin(angle), 0) * SPAWN_SPREAD
		if Clear(candidate) then return candidate end
	end
	return nil
end

local function GroundBelow(pos)
	local tr = util.TraceLine({
		start = pos + Vector(0, 0, 16),
		endpos = pos - Vector(0, 0, GROUND_PROBE),
		mask = Masks().brushes,
	})
	return tr.Hit and tr.HitPos or pos
end

-- A cart's reach for the orders (field.carts' radius): the half diagonal
-- of its footprint and a soldier's hull, so spots around it stand clear of
-- its body.
local CART_CLEARANCE = 24

local function CartRadius(train)
	local mins, maxs = train:WorldSpaceAABB()
	local size = maxs - mins
	return math.sqrt(size.x * size.x + size.y * size.y) / 2 + CART_CLEARANCE
end

return {
	WALK_MINS = WALK_MINS,
	WALK_MAXS = WALK_MAXS,
	WALK_LIFT = WALK_LIFT,
	WALK_MAX_RISE = WALK_MAX_RISE,
	SPAWN_LIFT = SPAWN_LIFT,
	GROUND_PROBE = GROUND_PROBE,
	RED = RED,
	BLUE = BLUE,
	Point = Point,
	ToVector = ToVector,
	Masks = Masks,
	SpawnSpots = SpawnSpots,
	IsDoor = IsDoor,
	PassThrough = PassThrough,
	WorldWalkClear = WorldWalkClear,
	OnFloor = OnFloor,
	TeamSize = TeamSize,
	LoadedFeature = LoadedFeature,
	RoundsModeName = RoundsModeName,
	StalemateIsRound = StalemateIsRound,
	Clear = Clear,
	ClearSpotNear = ClearSpotNear,
	GroundBelow = GroundBelow,
	CartRadius = CartRadius,
}
