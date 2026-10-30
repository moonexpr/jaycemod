-- Part of the AI war controller (sv.lua): the soldier port over a DrGBase soldier; its gadgets are sv_gadgets.lua.
local Map = ...
local TFBot = WS.require("foundation.wetsands.path.tfbot")
local HL2Path = WS.require("foundation.wetsands.path.hl2")
local Random = math.weighted
local Debug = WS.require("features.nbdebug.model")
local Detour = nextsoldier.detour
local WALK_MINS, WALK_MAXS, WALK_LIFT, WALK_MAX_RISE = Map.WALK_MINS, Map.WALK_MAXS, Map.WALK_LIFT, Map.WALK_MAX_RISE
local Point, ToVector, Masks, IsDoor = Map.Point, Map.ToVector, Map.Masks, Map.IsDoor
local OnFloor, PassThrough = Map.OnFloor, Map.PassThrough

-------------------------------------------------------------------------------
-- The soldier port (nextsoldier.soldier) over a DrGBase soldier
-- (npc_nextsoldier): orders set its target and gait; it walks there on
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
	}, controller.Soldier)
end

function Soldier:Now() return CurTime() end

-- Healing: the target the controller's tick heals (Controller:ApplyHeal).
function Soldier:Heal(handle)
	if handle ~= nil and not IsValid(handle) then handle = nil end
	self.healTarget = handle
end
function Soldier:IsDisarmed() return self.disarmed == true end

-- The health kits it may take now (ws_pickup_base's ValidTouch: shown,
-- not respawning, of its team or none) and can reach (KitReachable).
local HEALTH_KITS = { "item_healthkit_small", "item_healthkit_medium", "item_healthkit_full" }

function Soldier:HealthKits()
	local kits = {}
	for _, class in ipairs(HEALTH_KITS) do
		for _, kit in ipairs(ents.FindByClass(class)) do
			if kit:ValidTouch(self.ent) and self.controller:KitReachable(kit) then kits[#kits + 1] = { pos = Point(kit:GetPos()), handle = kit } end
		end
	end
	return kits
end

function Soldier:Burning() return WS.InCondition(self.ent, WS.PlayerRules.COND.BURNING) end

-- MEDIC!: its side's medics answer it first for MEDIC_CALL_SHOWN seconds
-- (the field's patients' calling), its teammates see TF2's bubble over it
-- that long (ws_medic_call_end, ws/cl_medic_call.lua), and it calls out
-- if its voice has a line (features/aiwar/sv_speech.lua).
local MEDIC_CALL_SHOWN = 3

function Soldier:CallMedic()
	self.callingMedicUntil = CurTime() + MEDIC_CALL_SHOWN
	self.ent:SetNW2Float("ws_medic_call_end", self.callingMedicUntil)
	self.controller:CallMedicLine(self.ent)
end

-- Calls out what it is doing (falling back, going for health), if its voice
-- has a line (features/aiwar/sv_speech.lua).
function Soldier:Announce(concept)
	self.controller:AnnounceLine(self.ent, concept)
end

-- Its head looks at p a while (base_nextsoldier's LookAt; a DrGBase body
-- has no head of its own to turn, and looks as it faces).
function Soldier:LookAt(p, seconds)
	if self.ent.LookAt then self.ent:LookAt(ToVector(p), seconds) end
end

-- Plays a gesture (features/aiwar/sv_gestures.lua).
function Soldier:Gesture(occasion)
	self.controller:Gesture(self.ent, occasion, CurTime())
end

function Soldier:CallingMedic() return CurTime() < (self.callingMedicUntil or 0) end
function Soldier:Health() return self.ent:Health() end
function Soldier:MaxHealth() return self.ent:GetMaxHealth() end

-- Riding the cart: SEATS_PER_CART seats on top of each cart, SEAT_SPREAD
-- either side of its middle, taken by a soldier within SEAT_REACH of the
-- cart's edge. A seated soldier is carried along by the controller's tick
-- (Controller:CarrySeated), sits (WS.WarSoldier's WSSeated pose)
-- and fights from there; it gets off beside the cart (EjectFromCart). With
-- ws_aiwar_sitting_enabled 0 no seat is free, and turning it off
-- stands every seated soldier (Controller:StandSeated).
local SEATS_PER_CART, SEAT_SPREAD, SEAT_REACH = 2, 16, 72
local SITTING = CreateConVar("ws_aiwar_sitting_enabled", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
	"Whether the AI war's cart pushers sit on the cart; 0 gets every seated soldier off it")

-- What a soldier sits on, beside the train's brush: the solid things riding
-- it (the cart's model, where the map parents it), and its body, a prop the
-- map ties to it by a constraint (WS.TiedTo). Its triggers (capture area,
-- kill trigger) are not sat on, nor what nothing collides with (the debris
-- group: Sandcastle's own right-click proxy, ws_proxy).
local function CartParts(train)
	local parts = WS.TiedTo(train)
	for _, child in ipairs(train:GetChildren()) do
		if IsValid(child) and child:GetSolid() ~= SOLID_NONE and bit.band(child:GetSolidFlags(), FSOLID_TRIGGER) == 0
			and child:GetCollisionGroup() ~= COLLISION_GROUP_DEBRIS then
			parts[#parts + 1] = child
		end
	end
	return parts
end

function Soldier:IsSeated() return self.seat ~= nil end

function Soldier:Sit()
	if not SITTING:GetBool() then return false end
	if self.seat then return true end
	local controller = self.controller
	local train = controller.cartEntities and controller.cartEntities[self.team]
	if not IsValid(train) then return false end
	local mins, maxs = train:WorldSpaceAABB()
	local cart = CartParts(train)
	for _, part in ipairs(cart) do
		local _, partMaxs = part:WorldSpaceAABB()
		maxs.z = math.max(maxs.z, partMaxs.z)
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
			self.ent.NSTarget = nil
			self.ent.NSSeated = true
			-- the cart carries it through itself, not into it; the rest of the
			-- world, shots and sight still meet it where it sits
			PassThrough(self.ent, train)
			for _, part in ipairs(cart) do PassThrough(self.ent, part) end
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
	self.ent.NSSeated = nil
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
		roundWon = WS.State() == WS.STATE.TEAM_WIN,
		winningTeam = GetGlobal2Int("ws_round_winner", WS.TEAM_UNASSIGNED),
	}
end

-- Whether ent carries a flag (item_teamflag's published carrier).
local function CarriesFlag(ent)
	for _, flag in ipairs(ents.FindByClass("item_teamflag")) do
		if flag:GetNW2Entity("ws_flag_carrier") == ent then return true end
	end
	return false
end

function Soldier:RequestRoute(goal)
	self.ticket = self.ticket + 1
	self.result = nil
	local ticket, goalPos, npcs = self.ticket, ToVector(goal), WS.Feature("npc")
	local start = self.ent:GetPos()
	local controller = self.controller
	local team = self.team
	-- carrying the flag, its own spawn rooms too: the flag drops in them
	-- (features/flag's respawn room rule)
	local carrying = CarriesFlag(self.ent)
	npcs:RequestRoute({
		avoid = function(area)
			return controller:UnderCart(area) or controller:ShutDoorIn(area, team)
				or (carrying and npcs:SpawnRoomTeam(area) == team)
		end,
		from = start,
		to = goalPos,
		strategy = HL2Path,
		limits = HL2Path.SOLDIER_LIMITS,
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

function Soldier:CanWalkTo(p)
	local from, to = self.ent:GetPos(), ToVector(p)
	if math.abs(to.z - from.z) > WALK_MAX_RISE then return false end
	local tr = util.TraceHull({
		start = from + WALK_LIFT,
		endpos = to + WALK_LIFT,
		mins = WALK_MINS,
		maxs = WALK_MAXS,
		mask = Masks().solid,
		filter = self.ent,
	})
	return not tr.Hit
end

local HOP_MINS, HOP_MAXS = Vector(-13, -13, 0), Vector(13, 13, 72)
local HOP_LIFT = Vector(0, 0, 18)
local ARRIVED = 64

-- DrGBase paths on the nav mesh itself: every goal is its own to plan.
function Soldier:PlansRoutes() return true end
function Soldier:RouteStale() return false end

function Soldier:MoveTo(p, gait)
	if self.seat then self:Stand() end
	self:Unpose()
	self.moveTarget = p
	self.gait = gait or "run"
	self.ent.NSTarget = OnFloor(ToVector(p))
	self.ent.NSRun = self.gait ~= "walk"
end

function Soldier:Watch(p)
	self.ent.NSLook = p and ToVector(p) or nil
end

function Soldier:Release()
	self.moveTarget = nil
	self.walkSpeed = 0
	self.ent.NSTarget = nil
	self.ent.NSRun = nil
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
		self:Mark(Debug.MARK_DOOR, string.format("%s #%d held it %d s: blocked for its team", door:GetClass(), door:EntIndex(),
			DOOR_STUCK_TIME), nil)
		self.controller:NoteShutDoor(door, self.team)
		self.heldBy = nil
	end
end

-- For the report: the gait and pace, or why the soldier is not moving.
function Soldier:RunState()
	if self.moveTarget == nil then return nil end
	if self:RangeTo(self.moveTarget) <= ARRIVED then return "at its target" end
	if self.ent.NSMoveResult == "unreachable" then return "no nav mesh path to its target" end
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
	local hit = util.TraceHull({ start = from, endpos = to, mins = HOP_MINS, maxs = HOP_MAXS - HOP_LIFT, mask = Masks().solid, filter = NotSoldier })
	if not hit.Hit then return nil, false end
	-- map geometry (func_detail is compiled into it) is the world
	local blocker = hit.HitWorld and game.GetWorld() or hit.Entity
	local function OnlyBlocker(other) return other == blocker end
	local asPlayer = util.TraceHull({ start = from, endpos = to, mins = HOP_MINS, maxs = HOP_MAXS - HOP_LIFT, mask = MASK_PLAYERSOLID, filter = OnlyBlocker })
	if hit.HitWorld then return blocker, not asPlayer.HitWorld end
	return blocker, asPlayer.Entity ~= blocker
end

-- NextBot movement steers round what it can; nothing is let through.
function Soldier:PassBlocker() return false end

-- Where my movement heads now for p: DrGBase's path's next goal (it plans
-- the way on the nav mesh itself; p, where I am going, may lie far off past
-- walls), else p.
function Soldier:Heading(p)
	local path = self.ent:GetPath()
	local goal = IsValid(path) and path:GetCurrentGoal()
	return goal and goal.pos or ToVector(p)
end

-- Stuck against a solid entity the nav mesh does not know of (a crate
-- across a lane; not map geometry, nor a door, which the door watchdog
-- opens): the first point beside it (nextsoldier.detour) I can walk to
-- and that is on the nav mesh, or nil.
function Soldier:Detour(p)
	local heading = self:Heading(p)
	local blocker = self:Blocker(heading)
	if not IsValid(blocker) or blocker:IsWorld() or IsDoor(blocker) then return nil end
	local mins, maxs = blocker:OBBMins(), blocker:OBBMaxs()
	local extent = Vector(maxs.x - mins.x, maxs.y - mins.y, 0):Length() / 2
	local here = self.ent:GetPos()
	for _, side in ipairs(Detour.Beside(Point(here), Point(heading), Point(blocker:WorldSpaceCenter()), extent, HOP_MAXS.x)) do
		local at = ToVector(side)
		if self:CanWalkTo(side) and IsValid(navmesh.GetNearestNavArea(at, false, ARRIVED, true, true)) then return side end
	end
	return nil
end

-- Stuck where a player would jump (a railing, a crate): a hop the way I am
-- heading for p (the soldier's NSHop: a vault if one fits). Stuck at all:
-- a fresh path from where I stand (NSRepath).
function Soldier:Hop(p) return self.ent:NSHop(self:Heading(p)) end
function Soldier:Repath() self.ent:NSRepath() end

-- My orders stepped in on my movement (features.nbdebug.model's MARKS): told
-- through WSNpcMark, which the nbdebug feature sends whoever has me
-- selected. to: where I am sent, a point or a Vector, or nil.
function Soldier:Mark(kind, detail, to)
	hook.Run("WSNpcMark", self.ent, kind, detail, self.ent:GetPos(), to and ToVector(to))
end

-- A random spot on the nav mesh within radius of center, on open floor
-- (no crouch or jump areas: a patrol keeps to where it walks upright).
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
			local area = Random.PickWeighted(zone, AreaSize, math.random())
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

-- A battle stance where it stands (WS.WarSoldier's NSTakeStance), held
-- until Unpose or MoveTo; taking one, it may say it is ready (the
-- controller's AnnounceStance). Asking again keeps the stance it has.
function Soldier:Pose()
	local ent = self.ent
	if ent.NSStance then return ent.NSStance end
	ent:NSTakeStance()
	self.controller:AnnounceStance(ent)
	return ent.NSStance
end

function Soldier:Unpose() self.ent.NSStance = nil end

-- Following the cart is not yet made for DrGBase soldiers.
function Soldier:FollowCart() return false end
function Soldier:Unfollow() end
function Soldier:RemoveScript() end

return Soldier, ARRIVED
