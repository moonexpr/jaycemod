-- The aiwar feature's controller: a payload round fought by DrGBase
-- NextBot soldiers (wetsand_drg_combine, wetsand_drg_rebel; the war needs
-- DrGBase). It owns the foundation.aiwar War, spawns each side's soldiers at
-- its team's spawns in TF2's respawn waves, enlists any soldier that
-- appears while the war runs (a player's included), gives each a
-- foundation.aiwar.orders Behavior over the soldier port below, and sets who
-- is friend or foe. The rules live in the models; this file only feeds them
-- the round and the carts and turns their answers into the soldiers' goals.
local AiWar = WETSAND.require("foundation.aiwar")
local Track = WETSAND.require("foundation.aiwar.track")
local Orders = WETSAND.require("foundation.aiwar.orders")
local NpcSystem = WETSAND.require("foundation.npc")
local TFBot = WETSAND.require("foundation.npc.path.tfbot")
local HL2Path = WETSAND.require("foundation.npc.path.hl2")
local Posts = WETSAND.require("foundation.aiwar.posts")
local Zone = WETSAND.require("foundation.aiwar.zone")
local Tactics = WETSAND.require("foundation.aiwar.tactics")
local Squad = WETSAND.require("foundation.aiwar.squad")
local Lanes = WETSAND.require("foundation.aiwar.lanes")

local ACTIVE_KEY = "wetsand.aiwar" -- Global2: the Utilities menu reads it
local THINK_INTERVAL = 0.25
local RELATIONSHIP_INTERVAL = 1
local RELATIONSHIP_PRIORITY = 99


-- CanWalkTo's sweep: a soldier's hull above its step height, so stairs and
-- slopes pass and walls do not.
local WALK_MINS, WALK_MAXS = Vector(-13, -13, 0), Vector(13, 13, 52)
local WALK_LIFT = Vector(0, 0, 20)
local WALK_MAX_RISE = 40

local SPAWN_MINS, SPAWN_MAXS = Vector(-16, -16, 0), Vector(16, 16, 72)
local SPAWN_LIFT = Vector(0, 0, 4)
local SPAWN_SPREAD, SPAWN_TRIES = 48, 8

local GROUND_PROBE = 256
local SF_TRIGGER_ALLOW_CLIENTS, SF_TRIGGER_ALLOW_NPCS, SF_TRIGGER_ALLOW_ALL = 1, 2, 64 -- CBaseTrigger (triggers.h)

local RED, BLUE = WETSAND.TEAM_RED, WETSAND.TEAM_BLUE

local function Point(v) return { x = v.x, y = v.y, z = v.z } end
local function ToVector(p) return Vector(p.x, p.y, p.z) end

local DOOR_CLASSES = { func_door = true, func_door_rotating = true, prop_door_rotating = true }

local function IsDoor(ent)
	return DOOR_CLASSES[ent:GetClass()] == true
end

-- Two entities that no longer collide, in physics or in an engine NPC's
-- movement checks (CTraceFilterNav skips pairs in the engine's collision
-- pair table, which logic_collision_pair fills, as Sandbox's No Collide
-- does). The pair goes with either entity.
local function PassThrough(a, b)
	local physA, physB = a:GetPhysicsObject(), b:GetPhysicsObject()
	if not (IsValid(physA) and IsValid(physB)) then return end
	local pair = ents.Create("logic_collision_pair")
	pair:SetKeyValue("startdisabled", "1")
	pair:SetPhysConstraintObjects(physA, physB)
	pair:Spawn()
	pair:Activate()
	pair:Input("DisableCollisions")
	a:DeleteOnRemove(pair)
	b:DeleteOnRemove(pair)
end

-------------------------------------------------------------------------------
-- The soldier port (foundation.aiwar.soldier) over a DrGBase soldier
-- (wetsand_drg_soldier): orders set its target and gait; it walks there on
-- the nav mesh as a NextBot, fighting on the way as DrGBase's human AI.

local Soldier = {}
Soldier.__index = Soldier

function Soldier.New(ent, controller, team)
	return setmetatable({
		ent = ent,
		controller = controller,
		team = team,
		ticket = 0,
		result = nil,
		moveTarget = nil,
		relations = {}, -- player -> disposition last set
	}, Soldier)
end

function Soldier:Now() return CurTime() end

-- Healing: the target the controller's tick heals (Controller:ApplyHeal).
function Soldier:Heal(handle)
	if handle ~= nil and not IsValid(handle) then handle = nil end
	self.healTarget = handle
end
function Soldier:IsDisarmed() return self.disarmed == true end
function Soldier:Health() return self.ent:Health() end
function Soldier:MaxHealth() return self.ent:GetMaxHealth() end

-- Riding the cart: SEATS_PER_CART seats on top of each cart, SEAT_SPREAD
-- either side of its middle, taken by a soldier within SEAT_REACH of the
-- cart's edge. A seated soldier is carried along by the controller's tick
-- (Controller:CarrySeated), sits (wetsand_drg_soldier's WetsandSeated pose)
-- and fights from there; it gets off beside the cart (EjectFromCart).
local SEATS_PER_CART, SEAT_SPREAD, SEAT_REACH = 2, 16, 72

function Soldier:IsSeated() return self.seat ~= nil end

function Soldier:Sit()
	if self.seat then return true end
	local controller = self.controller
	local train = controller.cartEntities and controller.cartEntities[self.team]
	if not IsValid(train) then return false end
	local mins, maxs = train:WorldSpaceAABB()
	for _, child in ipairs(train:GetChildren()) do
		-- the cart's model rides it too; its triggers (capture area, kill
		-- trigger) are not what one sits on
		if IsValid(child) and child:GetSolid() ~= SOLID_NONE and bit.band(child:GetSolidFlags(), FSOLID_TRIGGER) == 0 then
			local _, cMaxs = child:WorldSpaceAABB()
			maxs.z = math.max(maxs.z, cMaxs.z)
		end
	end
	local center = (mins + maxs) / 2
	local pos = self.ent:GetPos()
	if math.abs(pos.x - center.x) > (maxs.x - mins.x) / 2 + SEAT_REACH
		or math.abs(pos.y - center.y) > (maxs.y - mins.y) / 2 + SEAT_REACH then
		return false
	end
	controller.seats = controller.seats or {}
	local seats = controller.seats[train] or {}
	controller.seats[train] = seats
	for index = 1, SEATS_PER_CART do
		local holder = seats[index]
		if not (IsValid(holder) and controller.soldiers[holder] and controller.soldiers[holder].soldier.seat) then
			local side = index % 2 == 1 and 1 or -1
			local seatPos = Vector(center.x, center.y, maxs.z + 1) + train:GetRight() * (side * SEAT_SPREAD)
			seats[index] = self.ent
			self.seat = { train = train, index = index, side = side, offset = train:WorldToLocal(seatPos) }
			self.moveTarget = nil
			self.ent.WetsandTarget = nil
			self.ent.WetsandSeated = true
			self.seatGroup = self.ent:GetCollisionGroup()
			self.ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
			return true
		end
	end
	return false
end

function Soldier:Stand()
	local seat = self.seat
	if not seat then return end
	self.seat = nil
	local controller = self.controller
	local seats = controller.seats and controller.seats[seat.train]
	if seats and seats[seat.index] == self.ent then seats[seat.index] = nil end
	if not IsValid(self.ent) then return end
	self.ent.WetsandSeated = nil
	self.ent:SetCollisionGroup(self.seatGroup or COLLISION_GROUP_NPC)
	local entry = controller.soldiers[self.ent]
	if entry and IsValid(seat.train) then controller:EjectFromCart(self.ent, entry, seat.train, true) end
end
function Soldier:IsAlive() return IsValid(self.ent) and self.ent:Health() > 0 end
function Soldier:Position() return Point(self.ent:GetPos()) end
function Soldier:RangeTo(p) return self.ent:GetPos():Distance(ToVector(p)) end

function Soldier:HasEnemy()
	local ent = self.ent
	local enemy = ent:HasEnemy() and ent:GetEnemy() or nil
	return IsValid(enemy) and ent:Visible(enemy)
end

-- Every soldier takes the fastest route. TF2's DEFAULT_ROUTE weighs each
-- area by up to 101 times its length to spread bots over routes, which
-- leaves the straight-line estimate almost no guidance: the search floods
-- most of the mesh, and on a large map (plr_hightower_event) soldiers
-- waited on searches that gave up and walked to where they had got to.
function Soldier:Bot()
	return {
		entIndex = self.ent:EntIndex(),
		now = CurTime(),
		team = self.team,
		route = TFBot.FASTEST_ROUTE,
		miniBoss = false,
		roundWon = WETSAND.State() == WETSAND.STATE.TEAM_WIN,
		winningTeam = GetGlobal2Int("tf2.winner", WETSAND.TEAM_UNASSIGNED),
	}
end

function Soldier:RequestRoute(goal)
	self.ticket = self.ticket + 1
	self.result = nil
	local ticket, goalPos, npcs = self.ticket, ToVector(goal), WETSAND.Feature("npc")
	local start = self.ent:GetPos()
	local controller = self.controller
	local team = self.team
	self.routeGeneration = self:Generation()
	npcs:RequestRoute({
		avoid = function(area) return controller:UnderCart(area) or controller:ShutDoorIn(area, team) end,
		from = start,
		to = goalPos,
		strategy = HL2Path,
		limits = HL2Path.LIMITS,
		bot = self:Bot(),
		onDone = function(areas, found)
			if self.ticket ~= ticket then return end
			if not areas then
				self.result = false
				return
			end
			local points = {}
			for i, v in ipairs(npcs:RouteWaypoints(areas, goalPos, found, start)) do points[i] = Point(v) end
			self.result = points
		end,
	})
end

function Soldier:RouteResult()
	return self.result
end

-- What the route was planned under: the blockers' changes and the doors
-- found shut.
function Soldier:Generation()
	return WETSAND.Feature("npc"):BlockerGeneration() .. ":" .. (self.controller.shutDoorGeneration or 0)
end

function Soldier:RouteStale()
	return type(self.result) == "table" and self.routeGeneration ~= self:Generation()
end

function Soldier:CanWalkTo(p)
	local from, to = self.ent:GetPos(), ToVector(p)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = MASK_NPCSOLID,
		filter = self.ent,
	})
	return not tr.Hit
end

function Soldier:CanWalkTo(p)
	local from, to = self.ent:GetPos(), ToVector(p)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = MASK_NPCSOLID,
		filter = self.ent,
	})
	return not tr.Hit
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
		mask = MASK_NPCSOLID_BRUSHONLY,
	})
	if tr.StartSolid or not tr.Hit then return pos end
	return tr.HitPos + Vector(0, 0, FLOOR_CLEARANCE)
end

local HOP_MINS, HOP_MAXS = Vector(-13, -13, 0), Vector(13, 13, 72)
local HOP_LIFT = Vector(0, 0, 18)
local ARRIVED = 64

-- DrGBase paths on the nav mesh itself: every goal is its own to plan.
function Soldier:PlansRoutes() return true end
function Soldier:RouteStale() return false end

function Soldier:MoveTo(p, gait)
	if self.seat then self:Stand() end
	self.moveTarget = p
	self.gait = gait or "run"
	self.ent.WetsandTarget = OnFloor(ToVector(p))
	self.ent.WetsandRun = self.gait ~= "walk"
end

function Soldier:Release()
	self.moveTarget = nil
	self.walkSpeed = 0
	self.ent.WetsandTarget = nil
	self.ent.WetsandRun = nil
end

-- A soldier-sized box swept between two points above step height under
-- player movement's mask, teammates aside (the observer's recovery test).
function Soldier:Sweep(from, to)
	local controller, ent, team = self.controller, self.ent, self.team
	return util.TraceHull({
		start = from + HOP_LIFT,
		endpos = to + HOP_LIFT,
		mins = HOP_MINS,
		maxs = HOP_MAXS - HOP_LIFT,
		mask = MASK_PLAYERSOLID,
		filter = function(hit)
			if hit == ent then return false end
			local entry = controller.soldiers[hit]
			return not (entry and entry.soldier.team == team)
		end,
	})
end

-- Each tick of a move: the pace, from position (for the report), and the
-- door watchdog for a soldier held up by a door on its way.
local DOOR_HOLD_PROGRESS, DOOR_HOLD_TIME = 16, 1.5

function Soldier:Move(dt)
	local ent, now = self.ent, CurTime()
	local pos = ent:GetPos()
	self.walkSpeed = self.lastPos and pos:Distance(self.lastPos) / math.max(dt, 1e-3) or 0
	self.lastPos = pos
	local anchor = self.holdAnchor
	if not anchor or pos:Distance(anchor.pos) > DOOR_HOLD_PROGRESS then
		self.holdAnchor, self.heldBy = { pos = pos, since = now }, nil
	elseif now - anchor.since >= DOOR_HOLD_TIME then
		local door = self:DoorAhead(self.moveTarget)
		if door then self:HeldByDoor(door) end
	end
end

-- The door between me and p, if one stands in the way.
function Soldier:DoorAhead(p)
	local blocker = self:Blocker(p)
	return IsValid(blocker) and IsDoor(blocker) and blocker or nil
end

-- Stopped by a door: open it if my team may, and after DOOR_STUCK_TIME
-- held by it, label it blocked for my team (the door watchdog, with the
-- controller's shut doors).
local DOOR_STUCK_TIME = 3

function Soldier:HeldByDoor(door)
	local now, held = CurTime(), self.heldBy
	if not held or held.door ~= door then
		held = { door = door, since = now }
		self.heldBy = held
	end
	self.controller:OpenDoorFor(door, self.team)
	if now - held.since >= DOOR_STUCK_TIME then
		self.controller:NoteShutDoor(door, self.team)
		self.heldBy = nil
	end
end

-- For the report: the gait and pace, or why the soldier is not moving.
function Soldier:RunState()
	if self.moveTarget == nil then return nil end
	if self:RangeTo(self.moveTarget) <= ARRIVED then return "at its target" end
	if self.ent.WetsandMoveResult == "unreachable" then return "no nav mesh path to its target" end
	return string.format("%s at %d u/s", self.gait or "run", math.floor(self.walkSpeed or 0))
end

-- What stands between me and p for an NPC's movement (a soldier-sized box
-- above step height, under the NPC's mask, teammates and the enemy aside),
-- and whether a player would pass it (the same sweep under player
-- movement's mask does not hit it).
function Soldier:Blocker(p)
	local controller = self.controller
	local from, to = self.ent:GetPos() + HOP_LIFT, ToVector(p) + HOP_LIFT
	local function NotSoldier(hit) return controller.soldiers[hit] == nil end
	local hit = util.TraceHull({ start = from, endpos = to, mins = HOP_MINS, maxs = HOP_MAXS - HOP_LIFT, mask = MASK_NPCSOLID, filter = NotSoldier })
	if not hit.Hit then return nil, false end
	-- map geometry (func_detail is compiled into it) is the world
	local blocker = hit.HitWorld and game.GetWorld() or hit.Entity
	local function OnlyBlocker(other) return other == blocker end
	local asPlayer = util.TraceHull({ start = from, endpos = to, mins = HOP_MINS, maxs = HOP_MAXS - HOP_LIFT, mask = MASK_PLAYERSOLID, filter = OnlyBlocker })
	if hit.HitWorld then return blocker, not asPlayer.HitWorld end
	return blocker, asPlayer.Entity ~= blocker
end

-- NextBot movement steers round what it can; nothing is passed or hopped.
function Soldier:PassBlocker() return false end
function Soldier:Detour() return nil end
function Soldier:Hop() return false end

-- A random spot on the nav mesh within radius of center, on floor a
-- soldier can walk (no crouch or jump areas).
local PATROL_TRIES = 6

function Soldier:PatrolSpot(center, radius)
	local step = HL2Path.LIMITS.stepHeight
	local areas = navmesh.Find(ToVector(center), radius, step * 4, step * 4)
	if #areas == 0 then return nil end
	for _ = 1, PATROL_TRIES do
		local area = areas[math.random(#areas)]
		if bit.band(area:GetAttributes(), HL2Path.NAV_MESH_CROUCH + HL2Path.NAV_MESH_JUMP) == 0 and not self.controller:UnderCart(area) then
			return Point(area:GetRandomPoint())
		end
	end
	return nil
end

-- A random spot on the ground behind the setup gates (the controller's
-- SetupZone), by area size; else, with no zone to trust, one within
-- WANDER_RADIUS that I can walk to in a straight line, or nil after a few
-- tries.
local WANDER_RADIUS, WANDER_TRIES = 300, 6

local function AreaSize(area) return area:GetSizeX() * area:GetSizeY() end

function Soldier:WanderSpot()
	local zone = self.controller:SetupZone(self.team)
	if zone then
		for _ = 1, WANDER_TRIES do
			local area = Zone.PickWeighted(zone, AreaSize, math.random())
			if not self.controller:UnderCart(area) then return Point(area:GetRandomPoint()) end
		end
	end
	local step = HL2Path.LIMITS.stepHeight
	local areas = navmesh.Find(self.ent:GetPos(), WANDER_RADIUS, step, step)
	if #areas == 0 then return nil end
	for _ = 1, WANDER_TRIES do
		local spot = Point(areas[math.random(#areas)]:GetRandomPoint())
		if self:CanWalkTo(spot) then return spot end
	end
	return nil
end

function Soldier:Enemy()
	local enemy = self.ent:GetEnemy()
	return IsValid(enemy) and enemy or nil
end

function Soldier:EnemyHealth()
	local enemy = self.ent:GetEnemy()
	if not IsValid(enemy) or enemy:Health() <= 0 then return nil end
	return enemy:Health() / math.max(enemy:GetMaxHealth(), 1)
end

function Soldier:EnemyPosition()
	local enemy = self.ent:GetEnemy()
	return IsValid(enemy) and Point(enemy:GetPos()) or nil
end

function Soldier:HurtSince(t)
	return self.hurtAt ~= nil and self.hurtAt > (t or 0)
end

function Soldier:Hold()
	self:MoveTo(self:Position(), self.gait)
end

-- Cover: the nav mesh's hiding spots in cover (CNavArea::GetHidingSpots)
-- within radius of center, that the threat cannot see from eye height to
-- a crouching soldier's chest, nearest center first, COVER_EXCLUDE clear of
-- the spot to leave.
local HIDING_IN_COVER_SPOT = 1
local THREAT_EYE, COVER_CHEST = Vector(0, 0, 64), Vector(0, 0, 36)
local COVER_EXCLUDE = 96

function Soldier:CoverSpot(center, radius, threat, exclude, taken)
	local c, t = ToVector(center), ToVector(threat)
	local best, bestDistance
	for _, area in ipairs(navmesh.Find(c, radius, 96, 96)) do
		for _, spot in ipairs(area:GetHidingSpots(HIDING_IN_COVER_SPOT) or {}) do
			local d = spot:Distance(c)
			if d <= radius and (not bestDistance or d < bestDistance)
				and not (exclude and spot:Distance(ToVector(exclude)) < COVER_EXCLUDE)
				and not (taken and taken(Point(spot))) then
				local tr = util.TraceLine({ start = t + THREAT_EYE, endpos = spot + COVER_CHEST, mask = MASK_SOLID_BRUSHONLY })
				if tr.Hit then best, bestDistance = spot, d end
			end
		end
	end
	return best and Point(best) or nil
end

-- Poses and following the cart are not yet made for DrGBase soldiers.
function Soldier:Pose() return nil end
function Soldier:Unpose() end
function Soldier:FollowCart() return false end
function Soldier:Unfollow() end
function Soldier:RemoveScript() end

-- Gadgets: what a kit's soldier throws, deploys or sends (the kit's
-- gadgets, first ready first): a frag grenade lobbed at p when nothing
-- solid stands between (every time asked); a floor turret set down toward
-- p (one per soldier, standing until it dies); a manhack sent from its hand
-- (one per soldier at a time, gone after MANHACK_LIFE).
local GRENADE_FUSE, GRENADE_SPEED, GRENADE_MIN, GRENADE_MAX = 2.5, 700, 256, 1000
local TURRET_STEP, MANHACK_LIFE = 48, 45
local GADGET_CHEST = Vector(0, 0, 32)

local function ThrowAnimation(ent)
	if ent.AddGesture then ent:AddGesture(ACT_GMOD_GESTURE_ITEM_THROW) end
end

local GADGETS = {}

function GADGETS.grenade(soldier, target)
	local ent = soldier.ent
	local from = ent:EyePos()
	local distance = from:Distance(target)
	if distance < GRENADE_MIN or distance > GRENADE_MAX then return false end
	local tr = util.TraceLine({ start = from, endpos = target + GADGET_CHEST, mask = MASK_SOLID_BRUSHONLY })
	if tr.Hit then return false end
	local grenade = ents.Create("npc_grenade_frag")
	if not IsValid(grenade) then return false end
	grenade:SetPos(from + ent:GetForward() * 16)
	grenade:SetOwner(ent)
	grenade:Spawn()
	grenade:Activate()
	grenade:Fire("SetTimer", tostring(GRENADE_FUSE))
	-- a lob: across at GRENADE_SPEED, up enough to land on target
	local t = distance / GRENADE_SPEED
	local velocity = (target - from) / t
	velocity.z = velocity.z + 0.5 * physenv.GetGravity():Length() * t
	local phys = grenade:GetPhysicsObject()
	if IsValid(phys) then phys:SetVelocity(velocity) end
	ThrowAnimation(ent)
	soldier.controller:AddGadget(grenade, soldier, "grenade", CurTime() + GRENADE_FUSE + 1)
	return true
end

function GADGETS.turret(soldier, target)
	if soldier.controller:GadgetsOf(soldier, "turret") > 0 then return false end
	local ent = soldier.ent
	local dir = target - ent:GetPos()
	dir.z = 0
	if dir:IsZero() then return false end
	dir:Normalize()
	local pos = ent:GetPos() + dir * TURRET_STEP
	local tr = util.TraceHull({ start = pos + Vector(0, 0, 8), endpos = pos + Vector(0, 0, 8), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 64), mask = MASK_SOLID })
	if tr.Hit then return false end
	local turret = ents.Create("npc_turret_floor")
	if not IsValid(turret) then return false end
	turret:SetPos(pos)
	turret:SetAngles(Angle(0, dir:Angle().y, 0))
	turret:Spawn()
	turret:Activate()
	ThrowAnimation(ent)
	soldier.controller:AddGadget(turret, soldier, "turret")
	return true
end

function GADGETS.manhack(soldier)
	if soldier.controller:GadgetsOf(soldier, "manhack") > 0 then return false end
	local ent = soldier.ent
	local manhack = ents.Create("npc_manhack")
	if not IsValid(manhack) then return false end
	manhack:SetPos(ent:EyePos() + ent:GetForward() * 32)
	manhack:SetAngles(ent:GetAngles())
	manhack:Spawn()
	manhack:Activate()
	ThrowAnimation(ent)
	soldier.controller:AddGadget(manhack, soldier, "manhack", CurTime() + MANHACK_LIFE)
	return true
end

function Soldier:UseGadget(p)
	if not self.kit or not self.kit.gadgets or self.disarmed then return nil end
	local target = ToVector(p)
	for _, name in ipairs(self.kit.gadgets) do
		if GADGETS[name](self, target) then return name end
	end
	return nil
end

-------------------------------------------------------------------------------
-- Controller

local Controller = {
	war = nil, -- a foundation.aiwar War while the war runs
	soldiers = {}, -- NPC entity -> { soldier = port, npc = foundation.npc Npc }
	doorFlags = {}, -- trigger_multiple -> its spawnflags before the war
	tracks = setmetatable({}, { __mode = "k" }), -- a watcher's path node list -> Track
	nextThink = 0,
	nextRelations = 0,
}

local function TeamSize()
	return GetConVar("wetsand_aiwar_team_size"):GetInt()
end

function Controller:Active()
	return self.war ~= nil
end

-- Relationships ---------------------------------------------------------------

local DISPOSITION = { [AiWar.ALLY] = D_LI, [AiWar.ENEMY_OF] = D_HT, [AiWar.FEAR] = D_FR, [AiWar.NEUTRAL] = D_NU }

function Controller:Disposition(team, otherTeam)
	return DISPOSITION[AiWar.Relation(team, otherTeam, self.losers)]
end

function Controller:RelateSoldiers(ent, team)
	for other, entry in pairs(self.soldiers) do
		if other ~= ent and IsValid(other) then
			ent:AddEntityRelationship(other, self:Disposition(team, entry.soldier.team), RELATIONSHIP_PRIORITY)
			other:AddEntityRelationship(ent, self:Disposition(entry.soldier.team, team), RELATIONSHIP_PRIORITY)
		end
	end
end

-- Gadgets: the grenades, turrets and manhacks soldiers put in the field,
-- each { owner (the soldier's entity), team, kind, expires (or nil) }. They
-- fight for their owner's side, their damage is their owner's, and they do
-- none to its side.
function Controller:AddGadget(gadget, soldier, kind, expires)
	self.gadgets = self.gadgets or {}
	self.gadgets[gadget] = { owner = soldier.ent, team = soldier.team, kind = kind, expires = expires }
	if gadget:IsNPC() then self:RelateGadget(gadget) end
end

function Controller:GadgetsOf(soldier, kind)
	local n = 0
	for gadget, info in pairs(self.gadgets or {}) do
		if info.owner == soldier.ent and info.kind == kind and IsValid(gadget) and gadget:Health() > 0 then n = n + 1 end
	end
	return n
end

function Controller:RelateGadget(gadget)
	local info = self.gadgets[gadget]
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			gadget:AddEntityRelationship(ent, self:Disposition(info.team, entry.soldier.team), RELATIONSHIP_PRIORITY)
			ent:AddEntityRelationship(gadget, self:Disposition(entry.soldier.team, info.team), RELATIONSHIP_PRIORITY)
		end
	end
	for _, ply in ipairs(player.GetAll()) do
		gadget:AddEntityRelationship(ply, self:Disposition(info.team, WETSAND.TeamOf(ply)), RELATIONSHIP_PRIORITY)
	end
	for other, otherInfo in pairs(self.gadgets) do
		if other ~= gadget and IsValid(other) and other:IsNPC() then
			gadget:AddEntityRelationship(other, self:Disposition(info.team, otherInfo.team), RELATIONSHIP_PRIORITY)
			other:AddEntityRelationship(gadget, self:Disposition(otherInfo.team, info.team), RELATIONSHIP_PRIORITY)
		end
	end
end

-- Gone gadgets are forgotten, spent manhacks removed, and the rest related
-- again to soldiers and players that came since. owner: only that
-- soldier's (which leaves); all: every one (the war ends or the round resets).
function Controller:SweepGadgets(owner, all)
	if not self.gadgets then return end
	local now = CurTime()
	for gadget, info in pairs(self.gadgets) do
		local remove = all or (owner and info.owner == owner and info.kind ~= "grenade") or (info.expires and now >= info.expires)
		if not IsValid(gadget) then
			self.gadgets[gadget] = nil
		elseif remove then
			self.gadgets[gadget] = nil
			gadget:Remove()
		elseif not owner and gadget:IsNPC() then
			self:RelateGadget(gadget)
		end
	end
end

-- The team a damaged entity fights for, or nil.
function Controller:TeamOf(ent)
	if ent:IsPlayer() then return WETSAND.TeamOf(ent) end
	local entry = self.soldiers[ent]
	if entry then return entry.soldier.team end
	local info = self.gadgets and self.gadgets[ent]
	return info and info.team or nil
end

-- A gadget's damage: its owner's, and none to its own side. Returns true
-- to cancel it.
function Controller:GadgetDamage(target, dmg)
	local gadgets = self.gadgets
	if not gadgets then return false end
	local info = gadgets[dmg:GetInflictor()] or gadgets[dmg:GetAttacker()]
	if not info then return false end
	if IsValid(info.owner) then dmg:SetAttacker(info.owner) end
	return info.team == self:TeamOf(target)
end

-- TF2's NPCs (Sandcastle's wetsand_nextbot variants: tf_zombie's skeletons
-- and whatever joins them) take sides by their team: a RED or BLU one is
-- a teammate or an enemy as a player of that team is; any other (the
-- HALLOWEEN team's) is everyone's enemy. Soldiers and their gadgets are
-- related to each one they have not been yet, every relationship pass.
local function IsTFNpc(ent)
	return IsValid(ent) and ent:IsNextBot() and ent.Variant ~= nil and ent.GetTeamNumber ~= nil
end

function Controller:NoteMonster(ent)
	if not IsTFNpc(ent) then return end
	self.monsters = self.monsters or {}
	self.monsters[ent] = true
end

function Controller:MonsterDisposition(team, monster)
	local monsterTeam = monster:GetTeamNumber()
	if monsterTeam == RED or monsterTeam == BLUE then return self:Disposition(team, monsterTeam) end
	return team == self.losers and D_FR or D_HT
end

function Controller:RelateMonsters()
	if not self.monsters then return end
	for monster in pairs(self.monsters) do
		if not IsValid(monster) or monster:Health() <= 0 then
			self.monsters[monster] = nil
		else
			for ent, entry in pairs(self.soldiers) do
				local disposition = IsValid(ent) and self:MonsterDisposition(entry.soldier.team, monster)
				if disposition and entry.soldier.relations[monster] ~= disposition then
					entry.soldier.relations[monster] = disposition
					ent:AddEntityRelationship(monster, disposition, RELATIONSHIP_PRIORITY)
				end
			end
			for gadget, info in pairs(self.gadgets or {}) do
				if IsValid(gadget) and gadget:IsNPC() then
					gadget:AddEntityRelationship(monster, self:MonsterDisposition(info.team, monster), RELATIONSHIP_PRIORITY)
				end
			end
		end
	end
end

-- RED players fight beside the Combine, BLU beside the Resistance, and the
-- rest (spectators, the unassigned) are left alone.
function Controller:RelatePlayers()
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			for _, ply in ipairs(player.GetAll()) do
				local disposition = self:Disposition(entry.soldier.team, WETSAND.TeamOf(ply))
				if entry.soldier.relations[ply] ~= disposition then
					entry.soldier.relations[ply] = disposition
					ent:AddEntityRelationship(ply, disposition, RELATIONSHIP_PRIORITY)
				end
			end
		end
	end
end

-- Every soldier toward every other and every player, again (the losers changed).
function Controller:RelateEveryone()
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			self:RelateSoldiers(ent, entry.soldier.team)
			entry.soldier.relations = {}
		end
	end
	self.nextRelations = 0
end

-- Humiliation ------------------------------------------------------------------------
-- TF2's losers cannot attack while the winners celebrate (for players,
-- WETSAND.RestrictCommand). A losing soldier stops firing (the port's
-- IsDisarmed, which its orders answer ShouldAttack with) and fears its
-- enemies: DrGBase keeps away from what it fears. The winners hunt them.
function Controller:Disarm(ent, entry)
	if entry.disarmed then return end
	entry.disarmed = true
	entry.soldier.disarmed = true
end

function Controller:Rearm(ent, entry)
	if not entry.disarmed then return end
	entry.disarmed = nil
	entry.soldier.disarmed = nil
end

-- losers: the team humiliated, or nil for none.
function Controller:Humiliate(losers)
	self.losers = losers
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			if entry.soldier.team == losers then self:Disarm(ent, entry) else self:Rearm(ent, entry) end
		end
	end
	self:RelateEveryone()
end

-- Teammates pass through each other ---------------------------------------------------
-- An engine NPC's movement checks (CTraceFilterNav, ai_utils.cpp) skip any
-- entity it is paired with in the engine's collision pair table, which
-- logic_collision_pair fills (as Sandbox's No Collide does), so a teammate
-- in a doorway no longer blocks a soldier's run. Enemies still collide.
-- Each pair goes with either of its soldiers.

function Controller:PassTeammates(ent, team)
	for other, entry in pairs(self.soldiers) do
		if other ~= ent and IsValid(other) and entry.soldier.team == team then PassThrough(ent, other) end
	end
end

-- Enlisting ---------------------------------------------------------------------

-- fixed: the job it only ever does (a drafted medic); by default its
-- class's (the vortigaunt's).
function Controller:Enlist(ent, team, drafted, fixed)
	local member = self.war:Enlist(ent, team, drafted, fixed or AiWar.FixedRole(ent:GetClass()))
	local soldier = Soldier.New(ent, self, team)
	self.soldiers[ent] = {
		soldier = soldier,
		npc = NpcSystem.Npc.New(Orders, { war = self.war, member = member }, soldier),
	}
	-- DrGBase's hooks ask and tell the orders (wetsand_drg_soldier's bridge)
	ent.WetsandBrain = self.soldiers[ent].npc
	WETSAND.SetTeamMember(ent, team)
	self:RelateSoldiers(ent, team)
	self:PassTeammates(ent, team)
	self:JoinSquad(ent, member)
	if team == self.losers then self:Disarm(ent, self.soldiers[ent]) end
	self.nextRelations = 0
end

-- The member's fire team, for the report; DrGBase has no squads of its
-- own, so fire teams are the orders' alone.
function Controller:JoinSquad(ent, member)
	ent.wetsandSquad = member and member.fireTeam and member.fireTeam.squad or nil
end

-- Kits (wetsand_drg_soldier's WetsandKit), by side and role: blockers
-- carry the shotgun, hit harder and charge faster; raiders carry the
-- crossbow (the Resistance) and throw grenades; the Combine's support are
-- metrocops who deploy a turret and send manhacks, the Resistance's are its
-- heroes, who hit hard; the rest leave those weapons to them. Soldier:UseGadget
-- uses a kit's gadgets.
local BLOCKER_KIT = { name = "shotgunner", weapons = { "weapon_shotgun" }, damage = 1.5, runSpeed = 260 }
local KITS = {
	[RED] = {
		[AiWar.BLOCK] = BLOCKER_KIT,
		[AiWar.RAID] = { name = "grenadier", weapons = { "weapon_ar2" }, gadgets = { "grenade" } },
		[AiWar.SUPPORT] = {
			name = "metrocop", model = "models/player/police.mdl", weapons = { "weapon_smg1", "weapon_pistol" },
			gadgets = { "turret", "manhack" },
		},
		default = { avoid = { weapon_shotgun = true, weapon_pistol = true } },
	},
	[BLUE] = {
		[AiWar.BLOCK] = BLOCKER_KIT,
		[AiWar.RAID] = { name = "crossbow", weapons = { "weapon_crossbow" }, gadgets = { "grenade" } },
		default = { avoid = { weapon_shotgun = true, weapon_crossbow = true, weapon_357 = true } },
	},
}
-- Medics: the Combine's are metrocops, the Resistance's vortigaunts (their
-- own class, AiWar.FixedRole). They speak on taking a patient: HL2's lines,
-- those of the list the game has (MedicLines keeps only files that exist,
-- so a missing episode costs lines, not errors).
local MEDIC_KITS = {
	[RED] = {
		name = "metrocop medic", model = "models/player/police.mdl", weapons = { "weapon_pistol" },
		voice = {
			"npc/metropolice/vo/administer.wav", "npc/metropolice/vo/affirmative.wav",
			"npc/metropolice/vo/affirmative2.wav", "npc/metropolice/vo/tenfour.wav",
			"npc/metropolice/vo/ten8standingby.wav", "npc/metropolice/vo/copy.wav",
			"npc/metropolice/vo/rodgerthat.wav", "npc/metropolice/vo/officerneedshelp.wav",
		},
	},
	[BLUE] = {
		name = "vortigaunt medic",
		voice = {
			"vo/npc/vortigaunt/vques01.wav", "vo/npc/vortigaunt/vques02.wav", "vo/npc/vortigaunt/vques03.wav",
			"vo/npc/vortigaunt/vanswer01.wav", "vo/npc/vortigaunt/vanswer02.wav", "vo/npc/vortigaunt/vanswer03.wav",
			"vo/npc/vortigaunt/vanswer04.wav", "vo/npc/vortigaunt/vanswer05.wav",
			"vo/npc/vortigaunt/allowme.wav", "vo/npc/vortigaunt/certainly.wav",
		},
		-- the vortigaunt's charge as the beam starts
		beamSound = "npc/vort/attack_charge.wav",
	},
}

local medicLines = {}

local function MedicLines(kit)
	if medicLines[kit] == nil then
		local found = {}
		for _, path in ipairs(kit.voice or {}) do
			if file.Exists("sound/" .. path, "GAME") then found[#found + 1] = path end
		end
		medicLines[kit] = found
		print(string.format("AI war: %s voice: %d of %d lines found", kit.name, #found, #(kit.voice or {})))
	end
	return medicLines[kit]
end

-- The Resistance's heroes, one of each alive at a time; support beyond them
-- are veterans.
local HEROES = {
	{ name = "Alyx", hero = true, model = "models/player/alyx.mdl", weapons = { "weapon_357" }, health = 250, damage = 2 },
	{ name = "Barney", hero = true, model = "models/player/barney.mdl", weapons = { "weapon_ar2" }, health = 300, damage = 1.75 },
}
local VETERAN = { name = "veteran", weapons = { "weapon_ar2" }, health = 200, damage = 1.5 }

function Controller:HeroKit(ent)
	self.heroes = self.heroes or {}
	for _, hero in ipairs(HEROES) do
		local holder = self.heroes[hero.name]
		if holder == ent or not (IsValid(holder) and self.soldiers[holder]) then
			self.heroes[hero.name] = ent
			return hero
		end
	end
	return VETERAN
end

function Controller:Equip(ent, entry, member)
	local role = member and member.role or false
	if entry.equipped == role or not ent.WetsandKit then return end
	entry.equipped = role
	local team = entry.soldier.team
	if self.heroes then
		for name, holder in pairs(self.heroes) do
			if holder == ent then self.heroes[name] = nil end
		end
	end
	local kits = KITS[team] or {}
	local kit = (role == AiWar.MEDIC and MEDIC_KITS[team]) or kits[role] or (team == BLUE and role == AiWar.SUPPORT and self:HeroKit(ent)) or kits.default or {}
	entry.soldier.kit = kit
	-- a hero leads its squad (foundation.aiwar.squad)
	if member then member.hero = kit.hero == true or nil end
	ent:WetsandKit(kit)
end

-- A soldier died: OnOtherKilled(victim, its team) to every soldier within
-- OTHER_KILLED_RANGE (TF2's tactical monitor hears of every death).
local OTHER_KILLED_RANGE = 1500

function Controller:TellKilled(ent, entry)
	if not IsValid(ent) or ent:Health() > 0 then return end
	local pos = ent:GetPos()
	for other, otherEntry in pairs(self.soldiers) do
		if IsValid(other) and other:GetPos():DistToSqr(pos) <= OTHER_KILLED_RANGE * OTHER_KILLED_RANGE then
			otherEntry.npc:Event("OnOtherKilled", ent, entry.soldier.team)
		end
	end
end

function Controller:Discharge(ent)
	local entry = self.soldiers[ent]
	if not entry then return end
	entry.soldier:Stand()
	self.soldiers[ent] = nil
	if IsValid(ent) then ent.WetsandBrain = nil end
	self:TellKilled(ent, entry)
	self:SweepGadgets(ent)
	entry.soldier:Unpose()
	entry.soldier:RemoveScript()
	if IsValid(ent) then self:Rearm(ent, entry) end
	self.war:Discharge(ent)
	entry.npc:Destroy()
	WETSAND.SetTeamMember(ent, nil)
end

-- A Combine or Resistance NPC that appeared on its own (a player spawned
-- it) joins its side, once its spawn has finished.
function Controller:Consider(ent)
	if not self.war or self.soldiers[ent] or not IsValid(ent) or not (ent:IsNPC() or ent:IsNextBot()) then return end
	local team = AiWar.FactionTeam(ent:GetClass())
	if team and ent:Health() > 0 then self:Enlist(ent, team, false) end
end

-- Spawning ------------------------------------------------------------------------

local function Clear(pos)
	local tr = util.TraceHull({
		start = pos + SPAWN_LIFT,
		endpos = pos + SPAWN_LIFT,
		mins = SPAWN_MINS,
		maxs = SPAWN_MAXS,
		mask = MASK_NPCSOLID,
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

function Controller:Draft(team, pos, ang)
	local draft = self.war:Draft(team)
	local recruit = draft.recruit
	local ent = ents.Create(recruit.class)
	if not IsValid(ent) then return end
	ent:SetPos(pos + SPAWN_LIFT)
	ent:SetAngles(ang)
	ent:Spawn()
	ent:Activate()
	self:Enlist(ent, team, true, draft.role)
end

-- TF2's respawn wave for the team (0 during setup, when TF2 respawns at
-- once), or none without gamerules. With respawns stopped by an admin, the
-- first wave of a round is the last.
local function WaveLength(team)
	if not IsValid(WETSAND.Rules) then return 0 end
	if WETSAND.Rules:RespawnsDisabled() then return math.huge end
	if WETSAND.InSetup() then return 0 end
	return WETSAND.Rules:GetRespawnWaveMaxLength(team, true)
end

function Controller:Reinforce(now)
	for team, count in pairs(self.war:Reinforcements(now, TeamSize(), WaveLength)) do
		local spots = WETSAND.SpawnPoints(team)
		for i = 1, #spots > 0 and count or 0 do
			local spot = spots[(i - 1) % #spots + 1]
			local pos = ClearSpotNear(spot:GetPos())
			if pos then self:Draft(team, pos, spot:GetAngles()) end
		end
	end
end

-- A new round or stage: every soldier starts again from its side's spawn,
-- as TF2 respawns every player (RoundRespawn). The war's own soldiers are
-- replaced by a fresh wave; the ones players spawned are healed, rearmed
-- and moved to a spawn point (on a stage of a multi-stage map, the new
-- stage's), and their orders start over.
function Controller:RespawnAll()
	self:SweepGadgets(nil, true)
	self.lanePlans, self.laneSets = nil, nil
	self.gates = nil
	self.shutDoors = nil
	self.zones = nil
	self.postCache = nil
	self.losers = nil
	local entries = {}
	for ent, entry in pairs(self.soldiers) do entries[#entries + 1] = { ent = ent, entry = entry } end
	local spots, used = {}, {}
	for _, e in ipairs(entries) do
		local ent, team = e.ent, e.entry.soldier.team
		if IsValid(ent) then
			local drafted = self.war:Member(ent).drafted
			e.entry.soldier:Release()
			self:Discharge(ent)
			if drafted then
				ent:Remove()
			else
				spots[team] = spots[team] or WETSAND.SpawnPoints(team)
				used[team] = (used[team] or 0) + 1
				local spot = spots[team][(used[team] - 1) % math.max(#spots[team], 1) + 1]
				local pos = spot and ClearSpotNear(spot:GetPos())
				if pos then
					ent:SetPos(pos + SPAWN_LIFT)
					ent:SetAngles(spot:GetAngles())
				end
				ent:SetHealth(ent:GetMaxHealth())
				self:Enlist(ent, team, false)
			end
		end
	end
	self:RelateEveryone()
	self.war:ResetWaves()
end

-- The field ------------------------------------------------------------------------

local function GroundBelow(pos)
	local tr = util.TraceLine({
		start = pos + Vector(0, 0, 16),
		endpos = pos - Vector(0, 0, GROUND_PROBE),
		mask = MASK_NPCSOLID_BRUSHONLY,
	})
	return tr.Hit and tr.HitPos or pos
end

function Controller:TrackOf(watcher)
	local nodes = watcher:PathNodes()
	local track = self.tracks[nodes]
	if not track then
		local points = {}
		for i, node in ipairs(nodes) do points[i] = Point(node:GetPos()) end
		track = Track.New(points)
		self.tracks[nodes] = track
	end
	return track
end

-- Setup gates -------------------------------------------------------------------------
-- In setup the defending side lines up past the gates the attackers must
-- come through (foundation.aiwar.orders). A gate is the last door on the
-- attackers' route from their spawn to their cart's next checkpoint: the
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
	local spawns = WETSAND.SpawnPoints(team)
	local first, far, farthest = spawns[1], nil, -1
	for _, spawn in ipairs(spawns) do
		local d = spawn:GetPos():DistToSqr(first:GetPos())
		if d > farthest then far, farthest = spawn, d end
	end
	return first and { first:GetPos(), far:GetPos() } or {}
end

function Controller:FindGates(field)
	local gates = {}
	self.gates = gates
	local npcs = WETSAND.Feature("npc")
	for team, cart in pairs(field.carts) do
		-- an attacking team: the other side has no cart to push
		if not field.carts[AiWar.EnemyOf(team)] then
			local target = ToVector(cart.track:PointAt(cart.nextCheckpoint or cart.track:Length()))
			for _, from in ipairs(SpreadSpawns(team)) do
				npcs:RequestRoute({
					from = from,
					to = target,
					ignoreBlockers = true, -- the route is looked for through the shut gates
					strategy = HL2Path,
					limits = HL2Path.LIMITS,
					bot = { entIndex = 0, now = CurTime(), team = team, route = TFBot.FASTEST_ROUTE, miniBoss = false, roundWon = false, winningTeam = WETSAND.TEAM_UNASSIGNED },
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

-- A cart's reach for the orders (field.carts' radius): the half diagonal
-- of its footprint and a soldier's hull, so spots around it stand clear of
-- its body.
local CART_CLEARANCE = 24

local function CartRadius(train)
	local mins, maxs = train:WorldSpaceAABB()
	local size = maxs - mins
	return math.sqrt(size.x * size.x + size.y * size.y) / 2 + CART_CLEARANCE
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
			ent:SetPos(spot + SPAWN_LIFT)
			if not quiet then entry.soldier.cartRescues = (entry.soldier.cartRescues or 0) + 1 end
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
	local npcs = WETSAND.Feature("npc")
	local starts, outside = {}, {}
	for _, spot in ipairs(WETSAND.SpawnPoints(team)) do
		local area = AreaAt(spot:GetPos())
		if area then starts[#starts + 1] = area:GetID() end
	end
	if #starts == 0 then return nil end
	for _, spot in ipairs(WETSAND.SpawnPoints(AiWar.EnemyOf(team))) do
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
	local state = WETSAND.Feature("npc"):DoorState(door)
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
	self.shutDoorGeneration = (self.shutDoorGeneration or 0) + 1
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

-- The observer ---------------------------------------------------------------------------------
-- A soldier that fell out of the map, or is wedged where nothing gets it
-- out, is put back: one outside the world, or off the nav mesh for
-- OFF_MESH_TIME, where it last stood on the mesh (on its own side of any
-- wall; the nearest nav area may be beyond one), else at its spawn; one
-- that has tried to move for STRANDED_TIME without getting
-- STRANDED_PROGRESS from where it was, onto the next waypoint of its route
-- when a player could walk there. A soldier recovered again within
-- RELAPSE_TIME goes back to spawn. The mesh leaves gaps along walls and
-- round corners, which a soldier sliding along a wall walks into: it is
-- off the mesh only with no nav area it can see within OFF_MESH_REACH.
local WATCH_INTERVAL = 2
local STRANDED_TIME, STRANDED_PROGRESS = 15, 48
local OFF_MESH_BELOW, OFF_MESH_LIFT = 96, Vector(0, 0, 16)
local OFF_MESH_REACH, OFF_MESH_TIME = 48, 5
local RELAPSE_TIME = 60

local function OnMesh(pos)
	if IsValid(navmesh.GetNavArea(pos + OFF_MESH_LIFT, OFF_MESH_BELOW)) then return true end
	return IsValid(navmesh.GetNearestNavArea(pos + OFF_MESH_LIFT, false, OFF_MESH_REACH, true, true))
end

function Controller:SpawnSpot(team)
	local spots = WETSAND.SpawnPoints(team)
	if #spots == 0 then return nil end
	local spot = spots[math.random(#spots)]
	return ClearSpotNear(spot:GetPos())
end

function Controller:Recover(ent, entry, reason, pos)
	local soldier, now = entry.soldier, CurTime()
	local relapse = soldier.recoveredAt and now - soldier.recoveredAt < RELAPSE_TIME
	if relapse or not pos then
		pos = self:SpawnSpot(soldier.team)
		reason = reason .. (relapse and ", again: back to spawn" or ": back to spawn")
	end
	soldier.recoveredAt = now
	soldier.recoveries = (soldier.recoveries or 0) + 1
	soldier.recoveredWhy = reason
	soldier.watch = nil
	if not pos then
		-- nowhere to put it: the next wave replaces it
		ent:TakeDamage(ent:Health() + 1, game.GetWorld(), game.GetWorld())
		return
	end
	soldier:Release()
	ent:SetPos(pos + SPAWN_LIFT)
	if ent.loco then ent.loco:SetVelocity(vector_origin) end
end

function Controller:Watch(ent, entry, now)
	local soldier = entry.soldier
	local pos = ent:GetPos()
	local inWorld = util.IsInWorld(pos + OFF_MESH_LIFT)
	if inWorld and OnMesh(pos) then
		soldier.lastOnMesh = pos
		soldier.offMeshSince = nil
	else
		soldier.offMeshSince = soldier.offMeshSince or now
		if not inWorld or now - soldier.offMeshSince >= OFF_MESH_TIME then
			soldier.offMeshSince = nil
			local spot = soldier.lastOnMesh and ClearSpotNear(soldier.lastOnMesh)
			return self:Recover(ent, entry, inWorld and "off the nav mesh" or "out of the world", spot)
		end
	end
	local watch = soldier.watch
	if not soldier.moveTarget or not watch or pos:Distance(watch.pos) > STRANDED_PROGRESS then
		soldier.watch = { pos = pos, since = now }
		return
	end
	if now - watch.since < STRANDED_TIME then return end
	local state = entry.npc:State()
	local waypoint = state.route and state.route[math.min((state.routeIndex or 1) + 1, #state.route)]
	local spot = waypoint and ClearSpotNear(OnFloor(ToVector(waypoint)))
	-- never through what would stop a player: a shut door, a wall
	if spot and soldier:Sweep(pos, spot).Hit then spot = nil end
	self:Recover(ent, entry, "stranded", spot)
end

-- Posts: where soldiers establish their line ----------------------------------------------
-- foundation.aiwar.posts picks among the nav mesh's hiding spots (with
-- their cover and sniper flags) and the centres of areas well above or
-- below the place in question (high ground, pits), each tested for a
-- clear line from eye height:
-- - a team's defenders: near the checkpoint the enemy cart heads for,
--   seeing it; found once per checkpoint;
-- - a team's escorts: ahead of its own cart along the track, seeing the
--   cart; found again every FORWARD_STEP the cart moves, so the line is
--   pushed forward with it.
local HIDING_IN_COVER, HIDING_GOOD_SNIPER, HIDING_IDEAL_SNIPER = 1, 2, 4 -- CNavArea hiding spot flags
local POST_EYE, TARGET_EYE = Vector(0, 0, 64), Vector(0, 0, 48)
local HIGH_OR_LOW = 48 -- an area this far above or below the place is high or low ground
local SEARCH_HEIGHT = 1000
local FORWARD_STEP = 200

local function Sees(pos, target)
	local tr = util.TraceLine({ start = pos + POST_EYE, endpos = target + TARGET_EYE, mask = MASK_SOLID_BRUSHONLY })
	return not tr.Hit
end

-- Every candidate spot within radius of center, once each, with its flags.
local function CandidateSpots(center, radius)
	local spots, order = {}, {}
	local function Add(pos, cover, sniper)
		local key = string.format("%d %d %d", pos.x, pos.y, pos.z)
		local spot = spots[key]
		if not spot then
			spot = { pos = pos, cover = false, sniper = 0 }
			spots[key] = spot
			order[#order + 1] = spot
		end
		spot.cover = spot.cover or cover
		spot.sniper = math.max(spot.sniper, sniper)
	end
	for _, area in ipairs(navmesh.Find(center, radius, SEARCH_HEIGHT, SEARCH_HEIGHT)) do
		for _, pos in ipairs(area:GetHidingSpots(HIDING_IN_COVER) or {}) do Add(pos, true, 0) end
		for _, pos in ipairs(area:GetHidingSpots(HIDING_GOOD_SNIPER) or {}) do Add(pos, false, Posts.GOOD_SNIPER) end
		for _, pos in ipairs(area:GetHidingSpots(HIDING_IDEAL_SNIPER) or {}) do Add(pos, false, Posts.IDEAL_SNIPER) end
		local areaCenter = area:GetCenter()
		if math.abs(areaCenter.z - center.z) >= HIGH_OR_LOW then Add(areaCenter, false, 0) end
	end
	return order
end

function Controller:CachedPosts(kind, team, key, find)
	self.postCache = self.postCache or {}
	local cacheKey = kind .. team
	local cached = self.postCache[cacheKey]
	if cached and cached.key == key then return cached.posts end
	local posts = find()
	self.postCache[cacheKey] = { key = key, posts = posts }
	return posts
end

-- Where a team's defenders wait for the enemy cart.
function Controller:DefendersPosts(team, cart)
	if not cart.nextCheckpoint then return nil end
	return self:CachedPosts("defend", team, tostring(cart.track) .. "@" .. cart.nextCheckpoint, function()
		local objective = GroundBelow(ToVector(cart.track:PointAt(cart.nextCheckpoint)))
		local cartPos = ToVector(cart.pos)
		local candidates = {}
		for _, spot in ipairs(CandidateSpots(objective, Posts.MAX_RANGE)) do
			candidates[#candidates + 1] = {
				pos = Point(spot.pos),
				sees = Sees(spot.pos, objective),
				toObjective = spot.pos:Distance(objective),
				toCart = spot.pos:Distance(cartPos),
				elevation = spot.pos.z - objective.z,
				cover = spot.cover,
				sniper = spot.sniper,
			}
		end
		return Posts.Pick(candidates, AiWar.TEAM_SIZE_MAX)
	end)
end

-- Where a team's escorts push their line ahead of their own cart.
function Controller:ForwardPosts(team, cart)
	local step = math.floor(cart.distance / FORWARD_STEP)
	return self:CachedPosts("forward", team, tostring(cart.track) .. "@" .. step, function()
		local cartPos = ToVector(cart.pos)
		local ahead = GroundBelow(ToVector(cart.track:PointAt(cart.distance + Posts.MAX_LEAD / 2)))
		local candidates = {}
		for _, spot in ipairs(CandidateSpots(ahead, Posts.MAX_LEAD)) do
			local point = Point(spot.pos)
			candidates[#candidates + 1] = {
				pos = point,
				sees = Sees(spot.pos, cartPos),
				ahead = cart.track:DistanceOf(point) - cart.distance,
				toCart = spot.pos:Distance(cartPos),
				elevation = spot.pos.z - cartPos.z,
				cover = spot.cover,
				sniper = spot.sniper,
			}
		end
		return Posts.Pick(candidates, AiWar.TEAM_SIZE_MAX, Posts.ScoreForward)
	end)
end

-- The field -----------------------------------------------------------------------------

-- Each team's first active cart: its path, how far along it is, where its
-- next checkpoint is, and the ground under it.
function Controller:Field(phase)
	local carts = {}
	self.cartEntities = {}
	for _, watcher in ipairs(ents.FindByClass("team_train_watcher")) do
		local team = watcher.team
		if watcher:IsActive() and IsValid(watcher:Train()) and #watcher:PathNodes() > 0 and not carts[team] then
			self.cartEntities[team] = watcher:Train()
			carts[team] = {
				radius = CartRadius(watcher:Train()),
				track = self:TrackOf(watcher),
				distance = watcher:TrainDistanceAlongTrack(),
				nextCheckpoint = watcher:NextCheckpointDistance(),
				pos = Point(GroundBelow(watcher:Train():GetPos())),
			}
		end
	end
	local posts, forwardPosts = {}, {}
	for _, team in ipairs({ RED, BLUE }) do
		local enemyCart, ownCart = carts[AiWar.EnemyOf(team)], carts[team]
		if enemyCart then posts[team] = self:DefendersPosts(team, enemyCart) end
		if ownCart then forwardPosts[team] = self:ForwardPosts(team, ownCart) end
	end
	return {
		phase = phase,
		setup = WETSAND.Active() and WETSAND.InSetup(),
		carts = carts,
		gates = self.gates or {},
		posts = posts,
		forwardPosts = forwardPosts,
		patients = self:Patients(),
	}
end

-- Each side's soldiers and players, for its medics: { handle, pos, health
-- (a share of their most), player }.
function Controller:Patients()
	local patients = { [RED] = {}, [BLUE] = {} }
	local function Add(team, ent, player)
		local list = patients[team]
		if list and ent:Health() > 0 then
			list[#list + 1] = { handle = ent, pos = Point(ent:GetPos()), health = ent:Health() / math.max(ent:GetMaxHealth(), 1), player = player }
		end
	end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then Add(entry.soldier.team, ent, false) end
	end
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() then Add(WETSAND.TeamOf(ply), ply, true) end
	end
	return patients
end

-- Lanes (foundation.aiwar.lanes): each team's ways from its spawn out to
-- its front (its own cart, else the enemy's), planned one after the other,
-- each costing more through the areas the ones before took. A team's lanes
-- are planned again once its front has moved LANE_REPLAN from where they
-- led, and tried again after LANE_RETRY when no route was found (a shut
-- gate in setup); the last lanes found stand until new ones are ready.
local LANE_REPLAN, LANE_RETRY = 1024, 5

function Controller:UpdateLanes(field, now)
	self.lanePlans = self.lanePlans or {}
	self.laneSets = self.laneSets or {}
	field.lanes = {}
	for _, team in ipairs({ RED, BLUE }) do
		local own, theirs = field.carts[team], field.carts[AiWar.EnemyOf(team)]
		local front = (own and own.pos) or (theirs and theirs.pos)
		local plan = self.lanePlans[team]
		if front and not (plan and plan.planning) and now >= (plan and plan.retryAt or 0)
			and (not plan or Track.Distance(front, plan.to) > LANE_REPLAN) then
			self:PlanLanes(team, front, now)
		end
		if not front then self.laneSets[team] = nil end
		field.lanes[team] = self.laneSets[team]
	end
end

function Controller:PlanLanes(team, to, now)
	local target = ToVector(to)
	local from, best
	for _, spot in ipairs(WETSAND.SpawnPoints(team)) do
		local d = spot:GetPos():DistToSqr(target)
		if not best or d < best then from, best = spot:GetPos(), d end
	end
	if not from then return end
	local plan = { to = to, planning = true, tries = 0, penalized = {}, lanes = { key = team .. ":" .. now } }
	self.lanePlans[team] = plan
	local npcs = WETSAND.Feature("npc")
	local function Finish()
		plan.planning = false
		if #plan.lanes > 0 then
			self.laneSets[team] = plan.lanes
		else
			plan.retryAt = CurTime() + LANE_RETRY
			plan.to = { x = math.huge, y = 0, z = 0 } -- stale: plan again after the retry
		end
	end
	local function Try()
		plan.tries = plan.tries + 1
		npcs:RequestRoute({
			avoid = function(area) return self:UnderCart(area) end,
			from = from,
			to = target,
			strategy = Lanes.Strategy,
			limits = HL2Path.LIMITS,
			bot = { entIndex = 0, now = CurTime(), team = team, route = TFBot.FASTEST_ROUTE, miniBoss = false,
				roundWon = false, winningTeam = WETSAND.TEAM_UNASSIGNED, penalized = plan.penalized },
			onDone = function(areas, found)
				if self.lanePlans[team] ~= plan then return end
				if areas then
					local ids, raw = {}, {}
					for i, area in ipairs(areas) do ids[i] = area:GetID() end
					for i, v in ipairs(npcs:RouteWaypoints(areas, target, found, from)) do raw[i] = Point(v) end
					local points, length = Lanes.Thin(raw)
					local route = { ids = ids, points = points, length = length }
					plan.shortest = plan.shortest or length
					if Lanes.Accept(plan.lanes, route, plan.shortest) then plan.lanes[#plan.lanes + 1] = route end
					for _, id in ipairs(ids) do plan.penalized[id] = true end
				end
				if areas and #plan.lanes < Lanes.LANES_MAX and plan.tries < Lanes.LANE_TRIES then Try() else Finish() end
			end,
		})
	end
	Try()
end

-- The teams with a cart, how far along its track each cart is, and whether
-- it is close to its next checkpoint (the end of its track after the
-- last): what each team's defense share and stance are made of
-- (foundation.aiwar's DefenseShare and Stance).
function Controller:CartTeams(carts)
	local teams, close = {}, {}
	for team, cart in pairs(carts) do
		local target = cart.nextCheckpoint or cart.track:Length()
		close[team] = AiWar.CartClose(self.cartClose and self.cartClose[team], target - cart.distance)
		teams[team] = { close = close[team], progress = cart.distance / math.max(cart.track:Length(), 1) }
	end
	self.cartClose = close
	return teams
end

function Controller:Think(now)
	if now < self.nextThink then return end
	self.nextThink = now + THINK_INTERVAL
	local phase = AiWar.PhaseOf(WETSAND.Active(), WETSAND.State())
	local field = self:Field(phase)
	self:RefreshCartBounds()
	if field.setup and self.gates == nil then self:FindGates(field) end
	self.war:Assign(self:CartTeams(field.carts))
	self:UpdateLanes(field, now)
	self.war:SetField(field)
	if phase.reinforce then self:Reinforce(now) end
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then
			local member = self.war:Member(ent)
			self:JoinSquad(ent, member)
			self:Equip(ent, entry, member)
			entry.npc:Update(THINK_INTERVAL)
		end
	end
	if now >= self.nextRelations then
		self.nextRelations = now + RELATIONSHIP_INTERVAL
		self:RelatePlayers()
		self:SweepGadgets()
		self:RelateMonsters()
	end
	if now >= (self.nextWatch or 0) then
		self.nextWatch = now + WATCH_INTERVAL
		for ent, entry in pairs(self.soldiers) do
			if IsValid(ent) then self:Watch(ent, entry, now) end
		end
		self:CloseOpenedDoors()
	end
end

-- Spawn doors ---------------------------------------------------------------------

-- A team's spawn doors open through trigger_multiples filtered by
-- filter_activator_tfteam, other doors through a trigger_multiple around
-- them (TF2's nav mesh counts a door so overlapped as one anyone opens,
-- foundation.npc.doors), and NPCs only touch triggers flagged for them.
local function AroundADoor(trigger, doors)
	local mins, maxs = trigger:WorldSpaceAABB()
	for _, door in ipairs(doors) do
		local doorMins, doorMaxs = door:WorldSpaceAABB()
		if mins.x <= doorMaxs.x and doorMins.x <= maxs.x and mins.y <= doorMaxs.y and doorMins.y <= maxs.y
			and mins.z <= doorMaxs.z and doorMins.z <= maxs.z then
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
		if self.doorFlags[trigger] == nil and (teamDoor or AroundADoor(trigger, doors)) then
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

-- Starting and ending ------------------------------------------------------------------

-- Returns true, or false and why not.
function Controller:Start()
	if self.war then return false, "the war is already on" end
	if not DrGBase then return false, "the AI war needs DrGBase (Steam Workshop) for its soldiers" end
	if #ents.FindByClass("team_train_watcher") == 0 then return false, "this map has no payload cart" end
	WETSAND.Feature("npc"):CheckNavMesh()
	self.war = AiWar.War.New()
	self.gates = nil
	SetGlobal2Bool(ACTIVE_KEY, true)
	self:OpenDoorsToSoldiers()
	self:SetForcefieldsPassable(true)
	for _, ent in ipairs(ents.GetAll()) do
		self:Consider(ent)
		self:NoteMonster(ent)
	end
	if IsValid(WETSAND.Rules) then WETSAND.Rules:RestartRound() end
	return true
end

-- The war's own soldiers leave; the ones players spawned stay, back under
-- the engine's AI alone.
function Controller:End()
	if not self.war then return false, "no war is on" end
	local entries = {}
	for ent, entry in pairs(self.soldiers) do entries[#entries + 1] = { ent = ent, entry = entry } end
	for _, e in ipairs(entries) do
		if IsValid(e.ent) then
			local drafted = self.war:Member(e.ent).drafted
			e.entry.soldier:Release()
			self:Discharge(e.ent)
			if drafted then e.ent:Remove() end
		end
	end
	self.soldiers = {}
	self.losers = nil
	self:SweepGadgets(nil, true)
	self.heroes = nil
	self:CloseDoorsToSoldiers()
	self:SetForcefieldsPassable(false)
	self.war = nil
	SetGlobal2Bool(ACTIVE_KEY, false)
	return true
end

-- Debugging: wetsand_aiwar_report and wetsand_aiwar_debug ------------------------------

local DEBUG_NET = "wetsand_aiwar_debug"
local DEBUG_INTERVAL = 0.5
local DEBUG_MAX_POINTS = 24
util.AddNetworkString(DEBUG_NET)

local TEAM_LABEL = { [RED] = "RED", [BLUE] = "BLU" }

local function Round(n) return math.floor(n + 0.5) end

-- A soldier's action for reports: "SquadLeader …/Push/Travel", or the full
-- name when something above the job holds it (Humiliated).
-- A soldier's squad for reports: its place and its leader.
local function SquadLine(member)
	local fireTeam = member.fireTeam
	if not fireTeam then return "none" end
	local leader = Squad.Leader(fireTeam)
	local count = 0
	for _ in pairs(fireTeam.members) do count = count + 1 end
	local of = string.format("%s %d, %d strong", fireTeam.role, fireTeam.index, count)
	if leader == member then return "leads " .. of .. (member.hero and " (hero)" or "") end
	local handle = leader and leader.handle
	return string.format("in %s, led by #%s", of, IsValid(handle) and handle:EntIndex() or "?")
end

-- wetsand_aiwar_debug_full shows the whole action stack instead, one
-- level per step: SoldierAction > StrategyMonitor > ... > Travel.
local DEBUG_FULL = CreateConVar("wetsand_aiwar_debug_full", "0", FCVAR_ARCHIVE,
	"Show each soldier's whole action stack (the monitors too) in the AI war overlay and report")

local function ActionLine(fullName)
	if DEBUG_FULL:GetBool() then return (fullName:gsub("/", " > ")) end
	local job, role = Orders.JobOf(fullName)
	if not job then return fullName end
	return role .. " …/" .. job
end

-- A soldier described: a heading that says who it is ("BLU npc_citizen
-- #45"), and labelled lines on what it is for, what it is doing, and where
-- its route stands.
function Controller:Describe(ent, entry)
	local member = self.war:Member(ent)
	local state, soldier = entry.npc:State(), entry.soldier
	local route = "none"
	if soldier.result == nil and soldier.ticket > 0 then route = "searching" end
	if soldier.result == false then route = "off the nav mesh" end
	if state.route then route = string.format("waypoint %d of %d", state.routeIndex, #state.route) end
	local heading = string.format("%s %s #%d", TEAM_LABEL[soldier.team], ent:GetClass(), ent:EntIndex())
	local lines = {
		"Role: " .. (member.role and (member.role .. " " .. member.slot) or "none")
			.. string.format(" (team %d%% on defense)", math.floor((self.war.defense[soldier.team] or 0) * 100 + 0.5))
			.. ((member.role == AiWar.RAID or member.role == AiWar.SUPPORT) and self.war:Field()
				and (", working " .. ((Orders.Focus(self.war:Field(), member) == "defense") and "the enemy's cart" or "its own cart")) or ""),
		-- the monitors' chain is the same for everyone doing a job: only its
		-- squad role is shown
		"Action: " .. ActionLine(entry.npc:Describe()),
		"Squad: " .. SquadLine(member),
		"Lane: " .. (member.fireTeam and member.fireTeam.laneIndex and ("lane " .. member.fireTeam.laneIndex .. (state.onLane and ", walking it" or "")) or "none"),
		"Route: " .. route,
		"Goal: " .. (state.goal and (Round(soldier:RangeTo(state.goal)) .. " units away") or "none"),
		"Last trip: " .. (state.trip or "none"),
		"Movement: " .. (soldier:RunState() or "left to the engine's AI"),
		"Enemy: " .. (soldier:HasEnemy() and "in sight" or "none in sight"),
	}
	if state.wandering then lines[#lines + 1] = "Setup: wandering until it ends" end
	if state.following then lines[#lines + 1] = "Following: its cart" end
	if state.fighting then
		local fireTeam = member.fireTeam
		lines[#lines + 1] = string.format("Fighting: %s (fire team %s %d)", state.tactic or "?", fireTeam and fireTeam.role or "-", fireTeam and fireTeam.index or 0)
	end
	if state.patrolling then lines[#lines + 1] = "Patrol: walking its rounds near its post until the cart moves" end
	if entry.disarmed then lines[#lines + 1] = "Humiliated: cannot attack, fears the winners" end
	if soldier.failures then
		lines[#lines + 1] = string.format("Engine runs failed: %d refused, %d stalled; last target %s over the node graph",
			soldier.failures.refused or 0, soldier.failures.stalled or 0,
			soldier.graphPath == nil and "untested" or (soldier.graphPath and "had a path" or "had NO path"))
	end
	if soldier.recoveries then lines[#lines + 1] = string.format("Recovered: %d time(s), last %s", soldier.recoveries, soldier.recoveredWhy) end
	if soldier.kit and soldier.kit.name then
		lines[#lines + 1] = "Kit: " .. soldier.kit.name .. (state.gadget and ("; last used " .. state.gadget) or "")
	end
	if state.cleared then lines[#lines + 1] = "Raid: round the enemy's line" end
	if soldier.cartRescues then lines[#lines + 1] = "Pulled out of a cart: " .. soldier.cartRescues .. " time(s)" end
	if soldier.seat then lines[#lines + 1] = "Riding: seat " .. soldier.seat.index .. " on its cart" end
	if state.retreats then lines[#lines + 1] = "Retreated: " .. state.retreats .. " time(s)" end
	if state.chases then lines[#lines + 1] = "Chased: " .. state.chases .. " weakened enemies" end
	if state.hops then lines[#lines + 1] = "Hops: " .. state.hops end
	if state.passed then lines[#lines + 1] = "Let through: " .. state.passed .. " NPC-only blocker(s)" end
	local blocked = self:BlockedBy(soldier)
	if blocked then lines[#lines + 1] = "Blocked by: " .. blocked end
	return heading, lines
end

-- What holds a soldier that is running but barely moving, in words, or nil.
local SLOW_RUN = 20

local function DescribeBlocker(blocker)
	if blocker:IsWorld() then return "map geometry (world brushes, func_detail among them)" end
	local text = blocker:GetClass()
	if blocker:GetName() ~= "" then text = text .. " '" .. blocker:GetName() .. "'" end
	if blocker:GetClass() == "func_brush" then
		text = text .. string.format(" (solidity %s, excluded NPC '%s', inverted %s)",
			tostring(blocker:GetInternalVariable("m_iSolidity")), tostring(blocker:GetInternalVariable("m_iszExcludedClass")),
			tostring(blocker:GetInternalVariable("m_bInvertExclusion")))
	end
	local door = IsDoor(blocker) and WETSAND.Feature("npc"):DoorState(blocker)
	if door then
		local opener = door.controlled and ("a trigger" .. (door.owner and (" for " .. (TEAM_LABEL[door.owner] or door.owner)) or "")) or "none"
		local routes = door.blocks == nil and "open" or door.blocks == "any" and "closed to everyone" or ("closed to " .. (TEAM_LABEL[door.blocks] or door.blocks))
		text = text .. string.format(" (%s%s, opened by %s, routes: %s)", door.closed and "shut" or "open", door.locked and ", locked" or "", opener, routes)
		local noted = Controller.shutDoors and Controller.shutDoors[blocker]
		if noted then
			local teams = {}
			for team in pairs(noted.teams) do teams[#teams + 1] = TEAM_LABEL[team] or tostring(team) end
			text = text .. "; labelled blocked for " .. table.concat(teams, " and ") .. " this round"
		end
	end
	return text
end

function Controller:BlockedBy(soldier)
	local target = soldier.moveTarget
	if not target or soldier:RangeTo(target) <= ARRIVED then return nil end
	if (soldier.walkSpeed or 0) > SLOW_RUN then return nil end
	local blocker, playersPass = soldier:Blocker(target)
	if not blocker then return "nothing in the way (the floor ahead is too steep, too high a step or missing)" end
	return DescribeBlocker(blocker) .. (playersPass and "; a player would pass" or "; blocks players too")
end

function Controller:Report()
	local lines = {}
	local field = self.war:Field()
	lines[1] = string.format("AI war on %s: phase %s, %d nav areas, %d spawn-door triggers open to NPCs, %d route searches running",
		game.GetMap(), field and field.phase.name or "none", navmesh.GetNavAreaCount(), table.Count(self.doorFlags),
		WETSAND.Feature("npc"):SearchesRunning())
	for team, cart in pairs(field and field.carts or {}) do
		lines[#lines + 1] = string.format("  %s cart: %d of %d units along its track", TEAM_LABEL[team], Round(cart.distance), Round(cart.track:Length()))
	end
	for team, gates in pairs(self.gates or {}) do
		for _, gate in ipairs(gates) do
			lines[#lines + 1] = string.format("  %s must pass gate %s at (%d, %d, %d)", TEAM_LABEL[team], tostring(gate.door), Round(gate.pos.x), Round(gate.pos.y), Round(gate.pos.z))
		end
	end
	local list = {}
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then list[#list + 1] = { ent = ent, entry = entry } end
	end
	table.sort(list, function(a, b) return a.ent:EntIndex() < b.ent:EntIndex() end)
	for _, item in ipairs(list) do
		local heading, details = self:Describe(item.ent, item.entry)
		lines[#lines + 1] = "  " .. heading
		for _, detail in ipairs(details) do lines[#lines + 1] = "    " .. detail end
	end
	if #list == 0 then lines[#lines + 1] = "  no soldiers" end
	return lines
end

-- The overlay: each soldier's line, goal and remaining route, to the
-- admins who asked for it.
function Controller:SendDebug(now)
	if now < (self.nextDebug or 0) then return end
	self.nextDebug = now + DEBUG_INTERVAL
	local viewers = {}
	for _, ply in ipairs(player.GetAll()) do
		if ply.wetsandAiwarDebug then viewers[#viewers + 1] = ply end
	end
	if #viewers == 0 then return end
	local list = {}
	for ent, entry in pairs(self.soldiers) do
		if IsValid(ent) then list[#list + 1] = { ent = ent, entry = entry } end
	end
	-- fire teams in contact: where they last saw the enemy, their flank point
	local teams, teamIndex = {}, {}
	for _, fireTeam in ipairs(self.war.fireTeams) do
		local contact = Tactics.Contact(fireTeam, now)
		if contact and #teams < 255 then
			teams[#teams + 1] = { fireTeam = fireTeam, contact = contact }
			teamIndex[fireTeam] = #teams
		end
	end
	net.Start(DEBUG_NET)
	net.WriteUInt(#teams, 8)
	for _, item in ipairs(teams) do
		local fireTeam = item.fireTeam
		net.WriteUInt(fireTeam.team, 3)
		net.WriteString(string.format("%s %d", fireTeam.role, fireTeam.index))
		net.WriteVector(ToVector(item.contact.pos))
		net.WriteBool(fireTeam.flank ~= nil and not fireTeam.flankDone)
		if fireTeam.flank and not fireTeam.flankDone then net.WriteVector(ToVector(fireTeam.flank)) end
	end
	-- the support sphere of each team with a cart
	local spheres = {}
	local field = self.war:Field()
	for team, cart in pairs(field and field.carts or {}) do
		local center, radius = Orders.SupportSphere(cart)
		spheres[#spheres + 1] = { team = team, center = center, radius = radius, push = false }
	end
	net.WriteUInt(#spheres, 4)
	for _, sphere in ipairs(spheres) do
		net.WriteUInt(sphere.team, 3)
		net.WriteVector(ToVector(sphere.center))
		net.WriteFloat(sphere.radius)
		net.WriteBool(sphere.push)
	end
	-- each team's lanes
	local lanes = {}
	for team, set in pairs(field and field.lanes or {}) do
		for index, lane in ipairs(set) do lanes[#lanes + 1] = { team = team, index = index, points = lane.points } end
	end
	net.WriteUInt(math.min(#lanes, 15), 4)
	for i = 1, math.min(#lanes, 15) do
		local lane = lanes[i]
		net.WriteUInt(lane.team, 3)
		net.WriteUInt(lane.index, 3)
		local count = math.min(#lane.points, 63)
		net.WriteUInt(count, 6)
		for j = 1, count do net.WriteVector(ToVector(lane.points[j])) end
	end
	net.WriteUInt(#list, 8)
	for _, item in ipairs(list) do
		local state = item.entry.npc:State()
		net.WriteEntity(item.ent)
		net.WriteUInt(item.entry.soldier.team, 3)
		local heading, details = self:Describe(item.ent, item.entry)
		net.WriteString(heading)
		net.WriteUInt(#details, 4)
		for _, detail in ipairs(details) do net.WriteString(detail) end
		net.WriteBool(state.goal ~= nil)
		if state.goal then net.WriteVector(ToVector(state.goal)) end
		local route, first = state.route or {}, state.routeIndex or 1
		local last = math.min(#route, first + DEBUG_MAX_POINTS - 1)
		net.WriteUInt(math.max(0, last - first + 1), 8)
		for i = first, last do net.WriteVector(ToVector(route[i])) end
		-- its fight: fire team (1-based in the list above, 0 for none), element, cover
		local fireTeam = state.fighting and state.member and state.member.fireTeam
		net.WriteUInt(fireTeam and teamIndex[fireTeam] or 0, 8)
		net.WriteBool(state.element == "moving")
		net.WriteBool(state.coverSpot ~= nil)
		if state.coverSpot then net.WriteVector(ToVector(state.coverSpot)) end
	end
	net.Send(viewers)
end

local function Tell(ply, lines)
	for _, line in ipairs(lines) do
		print(line)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	end
end

concommand.Add("wetsand_aiwar_report", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	if not Controller.war then
		Tell(ply, { "AI war: not running" })
		return
	end
	Tell(ply, Controller:Report())
	if IsValid(ply) then ply:ChatPrint("AI war: report printed to your console") end
end, nil, "Print every AI war soldier's role, action, route and last trip to the console")

concommand.Add("wetsand_aiwar_debug", function(ply)
	if not IsValid(ply) or not ply:IsAdmin() then return end
	ply.wetsandAiwarDebug = not ply.wetsandAiwarDebug
	ply:ChatPrint("AI war overlay " .. (ply.wetsandAiwarDebug and "on" or "off"))
end, nil, "Toggle drawing each AI war soldier's route, goal and state")

-- Tracing a soldier's bridge (docs/aiwar-command.md §6): every query DrGBase
-- asks its orders, with the answer, and every event it tells them, printed
-- to the server console. Aim at a soldier (or give its entity index) to
-- toggle it; no soldier in sight turns all tracing off.
concommand.Add("wetsand_aiwar_trace", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local ent = args[1] and Entity(tonumber(args[1]) or -1) or (IsValid(ply) and ply:GetEyeTrace().Entity)
	local function Say(text)
		print(text)
		if IsValid(ply) then ply:ChatPrint(text) end
	end
	if not (IsValid(ent) and Controller.soldiers[ent]) then
		for other in pairs(Controller.soldiers) do
			if IsValid(other) then other.WetsandTrace = nil end
		end
		Say("AI war trace: off for every soldier")
		return
	end
	ent.WetsandTrace = not ent.WetsandTrace or nil
	Say(string.format("AI war trace: #%d %s (server console)", ent:EntIndex(), ent.WetsandTrace and "on" or "off"))
end, nil, "Trace the queries and events between an AI war soldier (aimed at, or by entity index) and its orders")

-- Hooks ------------------------------------------------------------------------------

hook.Add("Think", "wetsand_aiwar", function()
	if not Controller.war then return end
	Controller:Think(CurTime())
	Controller:SendDebug(CurTime())
end)

-- Each tick, a moving soldier's pace and the door watchdog.
-- A medic's beam: HEAL_RATE health a second (TF2's medigun) to its target
-- while it is alive, in reach (HEAL_REACH) and in sight, up to its most.
-- The beam is shown while it heals ("WetsandHealing", drawn on clients),
-- and the medic speaks on taking a new patient, at most every HEAL_VOICE.
local HEAL_RATE, HEAL_REACH, HEAL_VOICE = 24, 520, 10

function Controller:ApplyHeal(ent, entry, dt)
	local soldier, target = entry.soldier, entry.soldier.healTarget
	local member = self.war:Member(ent)
	local healing = IsValid(target) and target:Health() > 0 and member and member.role == AiWar.MEDIC
		and not soldier.disarmed and ent:GetPos():Distance(target:GetPos()) <= HEAL_REACH
	if healing then
		local tr = util.TraceLine({ start = ent:WorldSpaceCenter(), endpos = target:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY })
		healing = not tr.Hit
	end
	local shown = ent:GetNW2Entity("WetsandHealing")
	if not healing then
		if IsValid(shown) then ent:SetNW2Entity("WetsandHealing", NULL) end
		soldier.healCarry = 0
		return
	end
	if shown ~= target then
		ent:SetNW2Entity("WetsandHealing", target)
		local kit = soldier.kit or {}
		if kit.beamSound then ent:EmitSound(kit.beamSound, 70, 110) end
		local lines = MedicLines(kit)
		if #lines > 0 and CurTime() >= (soldier.voiceAt or 0) then
			soldier.voiceAt = CurTime() + HEAL_VOICE
			ent:EmitSound(lines[math.random(#lines)], 80)
		end
	end
	local most = target:GetMaxHealth()
	if target:Health() >= most then return end
	soldier.healCarry = (soldier.healCarry or 0) + HEAL_RATE * dt
	local whole = math.floor(soldier.healCarry)
	if whole > 0 then
		soldier.healCarry = soldier.healCarry - whole
		target:SetHealth(math.min(most, target:Health() + whole))
	end
end

-- A seated soldier rides its seat: moved with the cart every tick, facing
-- out over its side; a cart gone, it stands.
function Controller:CarrySeated(ent, soldier)
	local seat = soldier.seat
	if not IsValid(seat.train) then
		soldier:Stand()
		return
	end
	ent:SetPos(seat.train:LocalToWorld(seat.offset))
	ent:SetAngles(Angle(0, seat.train:GetAngles().y + 90 * seat.side, 0))
	if ent.loco then ent.loco:SetVelocity(vector_origin) end
end

hook.Add("Tick", "wetsand_aiwar_move", function()
	if not Controller.war then return end
	local dt = engine.TickInterval()
	for ent, entry in pairs(Controller.soldiers) do
		if IsValid(ent) and entry.soldier.seat then Controller:CarrySeated(ent, entry.soldier) end
		if IsValid(ent) then
			if entry.soldier.moveTarget then entry.soldier:Move(dt) end
			if entry.soldier.healTarget or IsValid(ent:GetNW2Entity("WetsandHealing")) then Controller:ApplyHeal(ent, entry, dt) end
		end
	end
end)

-- Serverside ragdolls that still appear while the war runs (DrGBase's,
-- with client ragdolls turned off, or a death DrGBase handles itself):
-- none made by a player; each fades after SERVER_RAGDOLL_LIFE, and past
-- SERVER_RAGDOLL_MAX the oldest goes at once. They cost every client memory.
local SERVER_RAGDOLL_MAX, SERVER_RAGDOLL_LIFE = 6, 15

function Controller:NoteServerRagdoll(ent)
	if IsValid(ent:GetCreator()) then return end
	self.serverRagdolls = self.serverRagdolls or {}
	local list = self.serverRagdolls
	for i = #list, 1, -1 do
		if not IsValid(list[i]) then table.remove(list, i) end
	end
	list[#list + 1] = ent
	ent:Fire("FadeAndRemove", "1", SERVER_RAGDOLL_LIFE)
	while #list > SERVER_RAGDOLL_MAX do
		local oldest = table.remove(list, 1)
		if IsValid(oldest) then oldest:Remove() end
	end
end

hook.Add("OnEntityCreated", "wetsand_aiwar", function(ent)
	if not Controller.war then return end
	timer.Simple(0, function()
		if not Controller.war or not IsValid(ent) then return end
		if ent:GetClass() == "prop_ragdoll" then Controller:NoteServerRagdoll(ent) return end
		if AiWar.FactionTeam(ent:GetClass()) then Controller:Consider(ent) else Controller:NoteMonster(ent) end
	end)
end)

hook.Add("EntityRemoved", "wetsand_aiwar", function(ent)
	if Controller.war then Controller:Discharge(ent) end
end)

hook.Add("EntityTakeDamage", "wetsand_aiwar", function(target, dmg)
	local soldier = Controller.war and Controller.soldiers[target]
	if soldier then
		local train = Controller:CartTrigger(dmg)
		if train then
			-- a rider sits over the cart's kill trigger: no harm, no rescue
			if not soldier.soldier.seat then Controller:EjectFromCart(target, soldier, train) end
			return true
		end
	end
	if Controller.war and Controller:GadgetDamage(target, dmg) then return true end
	local entry = Controller.war and Controller.soldiers[target]
	if entry and dmg:GetDamage() > 0 then entry.soldier.hurtAt = CurTime() end
end)

hook.Add("OnNPCKilled", "wetsand_aiwar", function(ent)
	if Controller.war then Controller:Discharge(ent) end
end)

-- A cleanup (every full round reset) removes the soldiers and remakes the
-- map's triggers: the doors are opened again and the first wave comes at once.
hook.Add("PostCleanupMap", "wetsand_aiwar", function()
	if not Controller.war then return end
	Controller.doorFlags = {}
	Controller:OpenDoorsToSoldiers()
	Controller:SetForcefieldsPassable(true)
	Controller.gates = nil
	Controller.zones = nil
	Controller.shutDoors = nil
	Controller.postCache = nil
	Controller.war:ResetWaves()
end)

-- Every round and every stage of a multi-stage map (pl_dustbowl,
-- pl_goldrush) starts with everyone back at spawn: a stage keeps the map
-- as it is, so without this the soldiers would stay where the last stage
-- left them.
hook.Add("TF2RoundActivate", "wetsand_aiwar", function()
	if Controller.war then Controller:RespawnAll() end
end)

hook.Add("TF2RoundWin", "wetsand_aiwar", function(winner)
	if Controller.war then Controller:Humiliate(AiWar.LosersOf(winner)) end
end)

-- The round keeps running with no human on a team while the war is on.
hook.Add("TF2HaveCombatants", "wetsand_aiwar", function()
	if Controller.war then return true end
end)

return Controller
