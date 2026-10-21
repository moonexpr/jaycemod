-- Part of the AI war controller (sv.lua): setup gates, forcefields, carts in the way, the setup zone, doors opened
-- and shut, and spawn doors.
local Controller, Map = ...
local Teams = WS.require("foundation.teams")
local Debug = WS.require("foundation.npc.debug")
local TFBot = WS.require("foundation.npc.path.tfbot")
local HL2Path = WS.require("foundation.npc.path.hl2")
local Zone = WS.require("foundation.aiwar.zone")
local Doors = WS.require("foundation.npc.doors")
local WALK_MAX_RISE, SPAWN_LIFT = Map.WALK_MAX_RISE, Map.SPAWN_LIFT
local Point, ToVector, SpawnSpots, IsDoor = Map.Point, Map.ToVector, Map.SpawnSpots, Map.IsDoor
local Clear, CartRadius = Map.Clear, Map.CartRadius

local SF_TRIGGER_ALLOW_CLIENTS, SF_TRIGGER_ALLOW_NPCS, SF_TRIGGER_ALLOW_ALL = 1, 2, 64 -- CBaseTrigger (triggers.h)

-- Setup gates -------------------------------------------------------------------------
-- In setup the defending side lines up past the gates the attackers must
-- come through (foundation.aiwar.orders). A gate is the last door on the
-- attackers' route from their spawn to what they head for: the
-- setup gate beyond a spawn door, or the spawn exit on maps whose exits
-- are the gates. Found once per round.

local DOOR_TRACE_LIFT = Vector(0, 0, 36)

-- The last door along the waypoints, where the route passes it.
function Controller:GateAlong(points)
	local gate = nil
	for i = 1, #points - 1 do
		local from, to = points[i] + DOOR_TRACE_LIFT, points[i + 1] + DOOR_TRACE_LIFT
		local tr = util.TraceLine({ start = from, endpos = to, mask = MASK_SOLID, filter = IsDoor })
		local door = tr.Entity
		if IsValid(door) and IsDoor(door) then
			local dir = to - from
			dir.z = 0
			dir:Normalize()
			gate = { pos = Point(tr.HitPos - DOOR_TRACE_LIFT), dir = { x = dir.x, y = dir.y }, door = door }
		end
	end
	return gate
end

-- A team's spawn points far apart: the first and the one farthest from it.
local function SpreadSpawns(team)
	local spawns = SpawnSpots(team)
	local first, far, farthest = spawns[1], nil, -1
	for _, spawn in ipairs(spawns) do
		local d = spawn:GetPos():DistToSqr(first:GetPos())
		if d > farthest then far, farthest = spawn, d end
	end
	return first and { first:GetPos(), far:GetPos() } or {}
end

-- The attacking teams and what each heads for are the scenario's
-- (SetupAttacks): on payload, a team with a cart the enemy lacks, toward
-- its next checkpoint.
function Controller:FindGates(field)
	local gates = {}
	self.gates = gates
	local npcs = WS.Feature("npc")
	for team, to in pairs(self.scenario:SetupAttacks(field)) do
		local target = ToVector(to)
		for _, from in ipairs(SpreadSpawns(team)) do
			npcs:RequestRoute({
				from = from,
				to = target,
				ignoreBlockers = true, -- the route is looked for through the shut gates
				strategy = HL2Path,
				limits = HL2Path.SOLDIER_LIMITS,
				bot = { entIndex = 0, now = CurTime(), team = team, route = TFBot.FASTEST_ROUTE, miniBoss = false, roundWon = false, winningTeam = WS.TEAM_UNASSIGNED },
				onDone = function(areas, found)
					if not areas or self.gates ~= gates then return end
					local gate = self:GateAlong(npcs:RouteWaypoints(areas, target, found))
					if not gate then return end
					gates[team] = gates[team] or {}
					for _, known in ipairs(gates[team]) do
						if known.door == gate.door then return end
					end
					table.insert(gates[team], gate)
				end,
			})
		end
	end
end

-- Forcefields -----------------------------------------------------------------------------

-- TF2's forcefields stop only players, but the engine NPCs' movement takes
-- a visualizer for a wall, so while the war runs they are not solid.
-- Soldiers still keep out of enemy spawn rooms: their routes refuse them.
function Controller:SetForcefieldsPassable(passable)
	for _, visualizer in ipairs(ents.FindByClass("func_respawnroomvisualizer")) do visualizer:SetNotSolid(passable) end
end

-- Carts in the way of routes -------------------------------------------------------------
-- The nav mesh does not know where the carts are, so routes led through
-- them. An area whose centre is under a cart (its bounds widened by
-- CART_MARGIN) counts as blocked for routes, the goal's area aside
-- (a pusher's spot is beside its cart). Refreshed every think.
local CART_MARGIN = Vector(24, 24, 64)

function Controller:RefreshCartBounds()
	local bounds, trains = {}, {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local train = watcher:IsActive() and watcher:Train()
		if IsValid(train) then
			local mins, maxs = train:WorldSpaceAABB()
			bounds[#bounds + 1] = { mins = mins - CART_MARGIN, maxs = maxs + CART_MARGIN }
			trains[train] = { mins = mins, maxs = maxs }
		end
	end
	self.cartBounds, self.trains = bounds, trains
end

-- Carts' kill triggers: maps put a trigger_hurt inside the cart, parented
-- to it, to kill players stuck in it. A soldier the cart drove over (a
-- NextBot is not pushed as a player is) is not killed by it but set down
-- beside the cart, on the nav mesh, on its own side first. Returns the
-- train when the damage came from one of these triggers.
local EJECT_TRIES = 8

function Controller:CartTrigger(dmg)
	for _, source in ipairs({ dmg:GetInflictor(), dmg:GetAttacker() }) do
		if IsValid(source) and source:GetClass() == "trigger_hurt" then
			local parent = source:GetParent()
			for _ = 1, 4 do
				if not IsValid(parent) then break end
				if self.trains and self.trains[parent] then return parent end
				parent = parent:GetParent()
			end
			local center = source:WorldSpaceCenter()
			for train, box in pairs(self.trains or {}) do
				if IsValid(train) and center:WithinAABox(box.mins, box.maxs) then return train end
			end
		end
	end
	return nil
end

-- quiet: getting off after a ride, not a rescue (not counted).
function Controller:EjectFromCart(ent, entry, train, quiet)
	local mins, maxs = train:WorldSpaceAABB()
	local center = (mins + maxs) / 2
	local out = ent:GetPos() - center
	out.z = 0
	if out:IsZero() then out = ent:GetForward() end
	out:Normalize()
	local radius = CartRadius(train) + 16
	local base = math.atan2(out.y, out.x)
	for i = 0, EJECT_TRIES - 1 do
		-- 0, then alternately either side, round to the far side
		local k = math.ceil(i / 2) * (i % 2 == 1 and 1 or -1)
		local angle = base + k * (math.pi * 2 / EJECT_TRIES)
		local candidate = Vector(center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius, ent:GetPos().z)
		local area = navmesh.GetNearestNavArea(candidate, false, 128, false, true)
		local spot = IsValid(area) and area:GetClosestPointOnArea(candidate) or candidate
		if spot:Distance2D(center) >= radius - 8 and Clear(spot) then
			if not quiet then
				entry.soldier:Mark(Debug.MARK_CART, "the cart drove over it", spot + SPAWN_LIFT)
				entry.soldier.cartRescues = (entry.soldier.cartRescues or 0) + 1
			end
			ent:SetPos(spot + SPAWN_LIFT)
			return true
		end
	end
	return false
end

function Controller:UnderCart(area)
	local center = area:GetCenter()
	for _, box in ipairs(self.cartBounds or {}) do
		if center:WithinAABox(box.mins, box.maxs) then return true end
	end
	return false
end

-- The setup zone -------------------------------------------------------------------------
-- The ground behind the setup gates, where the attackers wander in setup
-- (foundation.aiwar.zone): flooded over the nav mesh from the team's spawn
-- points, held back by the shut doors no trigger opens (the setup gates),
-- by what closes areas to routes (locked doors, solid brushes: the npc
-- feature's NavBlocks) and by rises
-- no soldier walks. A flood that reaches the checkpoint the team's cart
-- heads for, or the enemy's spawn, got past a gate standing open, and
-- gives no zone. Taken again every ZONE_REFRESH seconds.
local ZONE_LIMIT, ZONE_REFRESH = 4000, 10
local ZONE_SNAP = 256

local function AreaAt(pos)
	local area = navmesh.GetNearestNavArea(pos, false, ZONE_SNAP, false, true)
	return IsValid(area) and area or nil
end

function Controller:FloodZone(team)
	local npcs = WS.Feature("npc")
	local starts, outside = {}, {}
	for _, spot in ipairs(SpawnSpots(team)) do
		local area = AreaAt(spot:GetPos())
		if area then starts[#starts + 1] = area:GetID() end
	end
	if #starts == 0 then return nil end
	for _, spot in ipairs(SpawnSpots(Teams.EnemyOf(team))) do
		local area = AreaAt(spot:GetPos())
		if area then outside[area:GetID()] = true end
	end
	local field = self.war:Field()
	local cart = field and field.carts[team]
	if cart then
		local area = AreaAt(ToVector(cart.track:PointAt(cart.nextCheckpoint or cart.track:Length())))
		if area then outside[area:GetID()] = true end
	end
	local function Neighbors(id)
		local area, ids = navmesh.GetNavAreaByID(id), {}
		for _, next in ipairs(area:GetAdjacentAreas()) do
			if area:ComputeAdjacentConnectionHeightChange(next) <= WALK_MAX_RISE then ids[#ids + 1] = next:GetID() end
		end
		return ids
	end
	local function Blocked(id)
		local area = navmesh.GetNavAreaByID(id)
		return npcs:EngineBlocks(area, team) or npcs:NavBlocks(area, team) or npcs:DoorWallIn(area)
	end
	local ids, leaked = Zone.Flood(starts, Neighbors, Blocked, function(id) return outside[id] == true end, ZONE_LIMIT)
	if leaked then return nil end
	local areas = {}
	for i, id in ipairs(ids) do areas[i] = navmesh.GetNavAreaByID(id) end
	return areas
end

-- The team's setup zone, a list of nav areas, or nil.
function Controller:SetupZone(team)
	self.zones = self.zones or {}
	local cached, now = self.zones[team], CurTime()
	if not cached or now >= cached.expires then
		cached = { zone = self:FloodZone(team), expires = now + ZONE_REFRESH }
		self.zones[team] = cached
	end
	return cached.zone
end

-- Opening doors -------------------------------------------------------------------------------
-- The soldiers' own movement sets the ground under them, which touches no
-- trigger, so the trigger that opens a door for a player never sees them.
-- A soldier that walks into a door opens it as that trigger would: only a
-- door a trigger opens (not a setup gate, which map logic opens), not
-- locked, and whose trigger's filter admits the soldier's team (not the
-- enemy's spawn door). Many spawn doors close only when their trigger
-- sees everyone leave, which it never sees of a soldier, so a door a
-- soldier opened is closed again once no soldier or player is within
-- DOOR_CLOSE_RANGE of it.
local DOOR_OPEN_INTERVAL = 1
local DOOR_CLOSE_RANGE = 192

function Controller:OpenDoorFor(door, team)
	local state = WS.Feature("npc"):DoorState(door)
	if not state or state.locked or not state.controlled then return end
	if state.owner and state.owner ~= team then return end
	self.doorOpened = self.doorOpened or setmetatable({}, { __mode = "k" })
	local now = CurTime()
	if now < (self.doorOpened[door] or 0) then return end
	self.doorOpened[door] = now + DOOR_OPEN_INTERVAL
	self.openedDoors = self.openedDoors or setmetatable({}, { __mode = "k" })
	self.openedDoors[door] = true
	door:Fire("Open")
end

function Controller:CloseOpenedDoors()
	for door in pairs(self.openedDoors or {}) do
		if not IsValid(door) then
			self.openedDoors[door] = nil
		else
			local center, near = door:WorldSpaceCenter(), false
			for _, ent in ipairs(ents.FindInSphere(center, DOOR_CLOSE_RANGE)) do
				if self.soldiers[ent] or (ent:IsPlayer() and ent:Alive()) then
					near = true
					break
				end
			end
			if not near then
				self.openedDoors[door] = nil
				door:Fire("Close")
			end
		end
	end
end

-- Doors that stayed shut --------------------------------------------------------------------
-- The door watchdog: a soldier held up by the same door for DOOR_STUCK_TIME
-- (its own try at opening it included, Controller:OpenDoorFor) found it
-- impassable, whatever the blockers made of it (a door map logic shut, a
-- door the soldier's team may not open). The door is labelled blocked for
-- that team: its routes keep off the areas under it, and every route the
-- team planned before is planned again (Soldier:RouteStale). The labels
-- last the round: a new round or stage (RespawnAll, a cleanup) erases them.
local SHUT_DOOR_FLOOR = Vector(0, 0, 32)

function Controller:NoteShutDoor(door, team)
	self.shutDoors = self.shutDoors or {}
	local noted = self.shutDoors[door]
	if not noted then
		local mins, maxs = door:WorldSpaceAABB()
		local areas = {}
		for _, area in ipairs(navmesh.FindInBox(mins - SHUT_DOOR_FLOOR, maxs)) do areas[area:GetID()] = true end
		noted = { areas = areas, teams = {} }
		self.shutDoors[door] = noted
	end
	if noted.teams[team] then return end
	noted.teams[team] = true
end

function Controller:ShutDoorIn(area, team)
	if not self.shutDoors then return false end
	local id = area:GetID()
	for door, noted in pairs(self.shutDoors) do
		if not IsValid(door) then
			self.shutDoors[door] = nil
		elseif noted.areas[id] and noted.teams[team] then
			return true
		end
	end
	return false
end

-- Spawn doors ---------------------------------------------------------------------

-- A team's spawn doors open through trigger_multiples filtered by
-- filter_activator_tfteam, other doors through a trigger_multiple around
-- them that opens them (foundation.npc.doors Opens; an unnamed door, which
-- no output names, by any around it), and NPCs only touch triggers flagged
-- for them. A trigger beside a door that only closes it is left alone.
local function OpensADoor(trigger, doors)
	local mins, maxs = trigger:WorldSpaceAABB()
	local outputs = WS.KeyValues(trigger).outputs
	for _, door in ipairs(doors) do
		local doorMins, doorMaxs = door:WorldSpaceAABB()
		local name = door:GetName()
		if mins.x <= doorMaxs.x and doorMins.x <= maxs.x and mins.y <= doorMaxs.y and doorMins.y <= maxs.y
			and mins.z <= doorMaxs.z and doorMins.z <= maxs.z and (name == "" or Doors.Opens(outputs, name)) then
			return true
		end
	end
	return false
end

function Controller:OpenDoorsToSoldiers()
	local doors = ents.FindByClass("func_door*")
	for _, trigger in ipairs(ents.FindByClass("trigger_multiple")) do
		local filter = trigger:GetInternalVariable("m_hFilter")
		local teamDoor = IsValid(filter) and filter:GetClass() == "filter_activator_tfteam"
		if self.doorFlags[trigger] == nil and (teamDoor or OpensADoor(trigger, doors)) then
			local flags = trigger:GetSpawnFlags()
			self.doorFlags[trigger] = flags
			trigger:SetKeyValue("spawnflags", tostring(bit.bor(flags, SF_TRIGGER_ALLOW_NPCS)))
		end
	end
	-- Hazards: TF2 maps tick only "Clients" on their trigger_hurts (pits,
	-- saws, trains, the kill triggers inside carts), having no NPCs, so a
	-- soldier (a DrGBase NextBot: FL_NPC) fell through every one. They hurt
	-- soldiers as they hurt players; their filters (filter_activator_tfteam)
	-- already take a soldier as its team's player. Restored with the doors.
	for _, trigger in ipairs(ents.FindByClass("trigger_hurt")) do
		local flags = trigger:GetSpawnFlags()
		if self.doorFlags[trigger] == nil and bit.band(flags, SF_TRIGGER_ALLOW_CLIENTS) ~= 0
			and bit.band(flags, SF_TRIGGER_ALLOW_NPCS + SF_TRIGGER_ALLOW_ALL) == 0 then
			self.doorFlags[trigger] = flags
			trigger:SetKeyValue("spawnflags", tostring(bit.bor(flags, SF_TRIGGER_ALLOW_NPCS)))
		end
	end
end

function Controller:CloseDoorsToSoldiers()
	for trigger, flags in pairs(self.doorFlags) do
		if IsValid(trigger) then trigger:SetKeyValue("spawnflags", tostring(flags)) end
	end
	self.doorFlags = {}
end
