-- npc_pathfollower: NextSoldier's probe. Console errands report their route
-- and remove themselves; tool-managed followers (the Path Follower stool)
-- stay, driven by one of three (NSSetDriver):
--   "path": its bench, between Idle and Travel, optionally following the AI
--     war's active lanes, sent to a goal and retargeted (NSSetGoal);
--   "legs": NextLegs alone, told an order and its place in it
--     (NSLegsGive), heading where its squad's mode says;
--   "war": enlisted in the AI war (a bench war, when none runs), under the
--     war's own orders.
-- Its feet may be held (NSHoldFeet, the war soldier's): whatever drives it,
-- it then plans and shows its path but does not walk it. The stool draws its
-- path, its local movement command, its place and spot on orders, its
-- spacing and its held target.
--
-- follower:NSErrand(goal, seconds) sends a spawned one. From the console:
-- ns_pathfollower_send fromX fromY fromZ toX toY toZ [seconds].
AddCSLuaFile ()

ENT.Base = "base_nextsoldier"
ENT.Type = "nextbot"
ENT.PrintName = "Path Follower"
ENT.Category = "Sandcastle"
ENT.Spawnable = false
ENT.Model = "models/player/combine_soldier.mdl"
ENT.Weapons = {}
ENT.Factions = {}
ENT.DefaultRelationship = D_NU
ENT.RagdollOnDeath = false

WS.WarSoldier (ENT)
local WarSoldierUpdateAnimation = ENT.OnUpdateAnimation

if CLIENT then
	local LANE_COLOR = Color (255, 190, 60)
	local COMMAND_COLOR = Color (255, 90, 210)
	local TARGET_COLOR = Color (120, 255, 120)
	local BEAM_MATERIAL = Material ("models/wireframe")

	local function DrawLine (from, to, color, width)
		render.DrawLine (from, to, color)
	end

	local function DrawPoints (points, color, radius, width)
		for i, point in ipairs (points) do
			if points [i + 1] then DrawLine (point, points [i + 1], color, width) end
			render.DrawWireframeSphere (point, radius, 5, 5, color, false)
		end
	end

	local ORDER_COLORS = { Muster = Color (120, 255, 120), FallBack = Color (255, 170, 60), Assault = Color (190, 120, 255) }
	local CANNOT_STAND_COLOR, HELD_COLOR = Color (255, 70, 70), Color (255, 220, 60)
	local SELECTED_COLOR = Color (90, 220, 255)
	local RING_COLOR, CROWDED_COLOR = Color (160, 160, 160), Color (255, 90, 210)
	local CROSS_SIZE, SELECTED_RADIUS, FEET = 16, 22, Vector (0, 0, 3)
	-- where its squad's mode sends it now, when that is not its place
	local SPOT_COLOR, SPOT_RADIUS = Color (255, 255, 255), 10
	local RING_STEPS = 32

	local function Cross (at, color)
		render.DrawLine (at - Vector (CROSS_SIZE, 0, 0), at + Vector (CROSS_SIZE, 0, 0),     color)
		render.DrawLine (at - Vector (0, CROSS_SIZE, 0), at + Vector (0, CROSS_SIZE, 0),     color)
		render.DrawLine (at,                             at + Vector (0, 0, CROSS_SIZE * 2), color)
	end

	local function Ring (center, radius, color)
		local last = center + Vector (radius, 0, 0)
		for i = 1, RING_STEPS do
			local angle = i / RING_STEPS * 2 * math.pi
			local point = center + Vector (math.cos (angle) * radius, math.sin (angle) * radius, 0)
			render.DrawLine (last, point, color)
			last = point
		end
	end

	-- Drawn apart from the model, so a place shows with its follower out of view: its place on
	-- orders and where its squad's mode sends it, its selection, its spacing, its held target.
	hook.Add ("PostDrawTranslucentRenderables", "npc_pathfollower", function (_, sky)
		if sky then return end
		local showSpacing = GetConVar ("ns_pathfollower_spacing")
		for _, follower in ipairs (ents.FindByClass ("npc_pathfollower")) do
			local feet = follower:GetPos () + FEET
			local kind = follower:GetNW2String ("NSLegsOrder", "")
			if kind ~= "" then
				local place = follower:GetNW2Vector ("NSLegsPlace", vector_origin)
				Cross (place, follower:GetNW2Bool ("NSLegsStands", false) and ORDER_COLORS [kind] or CANNOT_STAND_COLOR)
				local spot = follower:GetNW2Vector ("NSLegsSpot", vector_origin)
				if spot ~= vector_origin and spot:DistToSqr (place) > 1 then Ring (spot + FEET, SPOT_RADIUS, SPOT_COLOR) end
			end
			if follower:GetNW2String ("NSProbeDriver", "path") == "war" and follower:GetNW2Bool ("NSFeetHeld", false) then
				local target = follower:GetNW2Vector ("NSHeldTarget", vector_origin)
				if target ~= vector_origin then Cross (target, HELD_COLOR) end
			end
			if follower:GetNW2Bool ("NSProbeSelected", false) then Ring (feet, SELECTED_RADIUS, SELECTED_COLOR) end
			if showSpacing and showSpacing:GetBool () and follower:GetNW2String ("NSProbeDriver", "path") == "legs" then
				local spacing = follower:GetNW2Float ("NSLegsSpacing", 0)
				local push = follower:GetNW2Vector ("NSLegsPush", vector_origin)
				local crowded = push:LengthSqr () > 0
				Ring (feet, spacing, crowded and CROWDED_COLOR or RING_COLOR)
				if crowded then render.DrawLine (feet, feet + push * spacing, CROWDED_COLOR) end
			end
		end
	end)

	function ENT:Draw ()
		self:DrawModel ()
		if not self:GetNW2Bool ("NSPathFollowerDebug", false) then return end

		DrawPoints (self.nsDebugLanePoints or {}, LANE_COLOR, 5, 8)

		local origin = self:GetPos () + Vector (0, 0, 3)
		local direction = self:GetNW2Vector ("NSPathFollowerCommand", vector_origin)
		direction.z = 0
		if direction:Length2DSqr () > 0 then
			direction:Normalize ()
			local tip = origin + direction * 80
			local side = Vector (-direction.y, direction.x, 0) * 9
			DrawLine (origin, tip,                         COMMAND_COLOR, 6)
			DrawLine (tip,    tip - direction * 16 + side, COMMAND_COLOR, 6)
			DrawLine (tip,    tip - direction * 16 - side, COMMAND_COLOR, 6)
		end

		if self:GetNW2String ("NSPathFollowerBehavior", "Idle") == "Travel" then
			render.DrawWireframeSphere (self:GetNW2Vector ("NSPathFollowerGoal", vector_origin), 12, 8, 8, TARGET_COLOR, false)
		end
	end
	return
end

-- Within ARRIVE of its goal it has arrived.
local ARRIVE = 48
-- Moving less than PROGRESS in RECOVER_AFTER seconds, it recovers: its path
-- planned again; after NUDGE_AFTER recoveries running, it is nudged as well
-- (a hop or a vault toward its path's next waypoint). Headway is movement,
-- not nearing the goal: a stairway winding away from the goal is headway.
local PROGRESS, RECOVER_AFTER, NUDGE_AFTER = 32, 3, 2
-- A fall of more than this between two updates is marked.
local DROP_MARK = 64
local DEFAULT_SECONDS = 60
local REPORTS = "sandcastle/pathfollower/"
local DEBUG_COMMAND_SYNC = 0.1
local MAX_DEBUG_POINTS = 2047
local debugEventWarningSent = false
local RUN_ACTIVITY_MODELS =
{
	["models/player/scout.mdl"] = true,
	["models/bots/headless_hatman.mdl"] = true
}

local function Point (v) return { x = math.Round (v.x), y = math.Round (v.y), z = math.Round (v.z) } end
local function AsVector (p) return Vector (p.x, p.y, p.z) end

-- A path's waypoints by kind (the engine's segment types).
local SEGMENT_KINDS = { [0] = "ground", "drop", "climb", "gap", "ladder up", "ladder down" }
local Lanes = wartactics.lanes
local Locomotion = nextsoldier.locomotion
local Behavior = nextsoldier.behavior
local GroupIdentity = nextsoldier.behavior.group_identity
local GIB = nextsoldier.behavior.gib_behaviors
local Radio = nextsoldier.squad.comms.radio
local Command = nextsoldier.squad.interactions.command
-- A place is looked for from this far above it to this far below, a body's own hull fitting; its
-- way there is swept a stair's step above the floor, so a step does not wall it off.
local SEARCH_ABOVE, SEARCH_BELOW, STEP = 64, 256, 18
local LIFT = Vector (0, 0, 1)
local SoldierSteer = ENT.NSSteer

function ENT:OnUpdateAnimation ()
	local act, rate = WarSoldierUpdateAnimation (self)
	if act ~= nil then return act, rate end
	if RUN_ACTIVITY_MODELS [self:GetModel ()] then
		if self.loco:GetVelocity ():Length2D () > 1 then
			return ACT_MP_RUN_PRIMARY, 1.0
		else
			return ACT_MP_STAND_PRIMARY, 1.0
		end
	end
end

local function NearestPoint (points, position)
	local best, distance
	for i, point in ipairs (points) do
		local candidate = position:DistToSqr (AsVector (point))
		if not distance or candidate < distance then best, distance = i, candidate end
	end
	return best, distance and math.sqrt (distance) or math.huge
end

local function LaneRoute (team, from, goal)
	local aiwar = WS.Feature ("aiwar")
	if not aiwar.war then return nil, aiwar end
	local lanes = aiwar.laneSets and aiwar.laneSets [team]
	if not lanes then return nil, aiwar end

	local best, bestCost
	for _, lane in ipairs (lanes) do
		if #lane.points > 1 then
			local first, fromDistance = NearestPoint (lane.points, from)
			local last, goalDistance = NearestPoint (lane.points, goal)
			if last >= first then
				local distance = fromDistance + goalDistance
				for i = first + 1, last do
					distance = distance + AsVector (lane.points [i - 1]):Distance (AsVector (lane.points [i]))
				end
				if not bestCost or distance < bestCost then
					best, bestCost = { kind = lane.kind, points = {} }, distance
					for i = first, last do best.points [#best.points + 1] = lane.points [i] end
				end
			end
		end
	end
	return best, aiwar
end

local function EventPoints (points)
	local result = {}
	for i = 1, math.min (#points, MAX_DEBUG_POINTS) do result [i] = AsVector (points [i]) end
	return result
end

local function SendLaneDebug (self)
	if not WS.PathFollowerDebugEventReady then
		if not debugEventWarningSent then
			ErrorNoHalt ("[npc_pathfollower] debug event is not loaded; the overlay needs the gamemode's shared files to reload\n")
			debugEventWarningSent = true
		end
		return
	end
	WS.Events.Fire ("game_ns_pathfollower_debug",
		{
			follower = self,
			-- Keep the event shape stable; PathFollower:Draw handles the live path.
			path = {},
			lane = EventPoints (self.nsDebugLanePoints or {})
		}, self:GetPos ())
end

local function NearestLaneTarget (route, position, index)
	if not route then return nil, index end
	index = Lanes.Next (route, { x = position.x, y = position.y, z = position.z }, index)
	local point = Lanes.Target (route, { x = position.x, y = position.y, z = position.z }, index)
	return point, index
end

local function PathKinds (path)
	local kinds = {}
	for _, segment in ipairs (path:GetAllSegments ()) do
		local kind = SEGMENT_KINDS [segment.type] or tostring (segment.type)
		kinds [kind] = (kinds [kind] or 0) + 1
	end
	return kinds
end

-- Where a path leaves the ground (a drop, climb, gap or ladder), each with
-- its kind and waypoint, in order: the steps an errand fails on.
local function PathSteps (path)
	local steps = {}
	for _, segment in ipairs (path:GetAllSegments ()) do
		if segment.type ~= 0 then
			steps [#steps + 1] = { kind = SEGMENT_KINDS [segment.type] or tostring (segment.type), pos = Point (segment.pos) }
		end
	end
	return steps
end

local SoldierInitialize = ENT.CustomInitialize

-- Each follower's name on its squad's radio, by the entity, which outlives its fields once removed.
local RadioNames = setmetatable ({}, { __mode = "k" })

function ENT:CustomInitialize ()
	SoldierInitialize (self)
	RadioNames [self] = self.NSRadioName or ("#" .. self:EntIndex ())
	self:SetNoTarget (true)
	self.NSRun = true
	if self.NSToolManaged then
		self:SetNW2Bool ("NSPathFollowerDebug", true)
		-- followers pass through each other, as TF2's teammates do: two walking one way would hold
		-- each other where they met. A NextBot's own movement asks the engine's collision groups (not
		-- GMod's collision hook, nor the war's collision pairs, which need a physics object), and
		-- scripted NPCs' is the one whose members pass, every other body and every shot meeting them
		self:SetCollisionGroup (COLLISION_GROUP_NPC_SCRIPTED)
		self.nsResponder = Behavior.Responder ()
		-- its main stack, asked and told as a brain is, while it is on its legs
		local engine = nextsoldier.engine
		self.nsStackBrain =
		{
			Query = function (_, name, ...) return engine.Query (self, name, ...) end,
			Event = function (_, name, ...) engine.Event (self, name, ...) end
		}
		self.NSBrain = self.nsResponder
		self:NSSetBehavior ("Idle")
	end
end

-- What a tool follower answers a query (its stool's checkboxes), and shows it
-- answers: ShouldHurry yes runs, no walks. The war asks its own, while it is in it.
function ENT:NSRespond (name, yes)
	self.nsResponder:Set (name, yes)
	self:SetNW2Bool ("NSQuery" .. name, yes)
end

-- The team it is of: the stool's, or none. It is the team's member, as a soldier is, so its
-- doors open for it and its forcefields let it by.
function ENT:NSTeam () return self.NSLaneTeam or WS.TEAM_UNASSIGNED end

function ENT:NSSetTeam (team)
	self.NSLaneTeam = team
	WS.SetTeamMember (self, team ~= WS.TEAM_UNASSIGNED and team or nil)
	WS.Feature ("aiwar"):RelateToFactions (self, team)
end

-- Within this of a seat it rests on, it crouches there.
local REST_REACH = 24
-- On its legs it walks to within LEGS_REACH of a spot, inside the reach they count it there and past
-- its path's end: the soldier's own tolerance would stop it short of its stack or its seat.
local LEGS_REACH = math.min (GIB.STAGE_REACH, REST_REACH) * 3 / 4

-- What drives it: "path", "legs" or "war" (above).
local DRIVERS = { path = true, legs = true, war = true }

function ENT:NSDriver () return self.nsDriver or "path" end

-- Driven by another: it lets go of what drove it (stops travelling, leaves its squad's order,
-- is discharged from the war), its tree is ended and the driver's put in, and into the war it is
-- enlisted, a bench war started for it when none runs. Returns true, or false and why not.
function ENT:NSSetDriver (driver)
	if not DRIVERS [driver] then error ("no path follower driver " .. tostring (driver), 2) end
	local was = self:NSDriver ()
	if was == driver then return true end
	local controller = WS.Feature ("aiwar")
	if driver == "war" and not controller.war then
		local ok, why = controller:Start ({ bench = true })
		if not ok then return false, why end
	end
	if was == "path" then
		self:NSSetBehavior ("Idle")
	elseif was == "legs" then
		self:NSLegsGive (nil)
	elseif was == "war" then
		controller:Discharge (self)
		self.NSBrain = self.nsResponder
		self:NSSetTeam (self:NSTeam ())
	end
	self.NSTarget = nil
	self.nsDriver = driver
	-- on its legs, its main stack answers what the soldier asks (ShouldAttack), else its stool's boxes
	if driver == "legs" then
		self.NSBrain = self.nsStackBrain
	elseif driver == "path" then
		self.NSBrain = self.nsResponder
	end
	-- on its bench it is no one's target, as it is no one's to hurt; on its legs or in the war, it is
	self:SetNoTarget (self.NSToolManaged and driver == "path")
	self.NSGoalTolerance = driver == "legs" and LEGS_REACH or nil
	self:SetNW2String ("NSProbeDriver", driver)
	-- not started yet (spawned this tick), its start puts the driver's tree in
	if self.nsStarted then
		nextsoldier.engine.End (self)
		local action = self:NSInitialAction ()
		if action then nextsoldier.engine.Insert (self, action) end
		if driver == "legs" then self:NSPutOnLeggings () end
	end
	if driver == "war" then controller:Enlist (self, self:NSTeam (), false) end
	if was == "war" then controller:EndBenchWhenEmpty (self) end
	return true
end

function ENT:NSSetBehavior (name)
	local previous = self.nsBehavior
	self.nsBehavior = name
	self:NSDebugBehaviorChanged (previous, name)
	self:SetNW2String ("NSPathFollowerBehavior", name)
	if name == "Idle" then
		self.NSTarget = nil
		self.nsGoal = nil
		self.nsLaneRoute = nil
		self.nsLaneIndex = nil
		self.NSPathCost = nil
		self:SetNW2Vector ("NSPathFollowerGoal",    vector_origin)
		self:SetNW2Vector ("NSPathFollowerCommand", vector_origin)
		self.nsDebugLanePoints = {}
		SendLaneDebug (self)
		self:NSRepath ()
		self.nsFollowedAt = 0
	elseif name ~= "Travel" then
		error ("unknown path follower behavior " .. tostring (name), 2)
	end
end

function ENT:NSSetGoal (goal)
	local route, aiwar = LaneRoute (self.NSLaneTeam, self:GetPos (), goal)
	local previous = self.nsBehavior
	self.nsGoal = goal
	self.nsLaneRoute = route
	self.nsLaneIndex = 1
	self.nsBehavior = "Travel"
	self:NSDebugBehaviorChanged (previous, "Travel")
	self:SetNW2String ("NSPathFollowerBehavior", "Travel")
	self:SetNW2Vector ("NSPathFollowerGoal", goal)
	self.nsDebugLanePoints = route and route.points or {}
	self:SetNW2Vector ("NSPathFollowerCommand", vector_origin)
	SendLaneDebug (self)
	self.NSPathCost = nil
	if aiwar and self.NSLaneTeam ~= nil then
		local TFBot = WS.require ("foundation.wetsands.path.tfbot")
		local team = self.NSLaneTeam
		self.NSPathCost = aiwar:SoldierPathCost (team, function ()
			return
			{
				entIndex = self:EntIndex (),
				now = CurTime (),
				team = team,
				route = TFBot.FASTEST_ROUTE,
				miniBoss = false,
				roundWon = false,
				winningTeam = WS.TEAM_UNASSIGNED
			}
		end)
	end
	self.NSPathGoal = nil
	self:NSRepath ()
end

local function StopAt (self)
	self:NSSetBehavior ("Idle")
	local velocity = self.loco:GetVelocity ()
	self.loco:SetVelocity (Vector (0, 0, velocity.z))
end

local function HoldStill (self)
	local velocity = self.loco:GetVelocity ()
	if velocity.x ~= 0 or velocity.y ~= 0 then self.loco:SetVelocity (Vector (0, 0, velocity.z)) end
end

function ENT:NSUpdateToolBehavior ()
	if self.nsBehavior == "Idle" then
		HoldStill (self)
		return
	end
	local target = self.nsGoal
	local lanePoint
	lanePoint, self.nsLaneIndex = NearestLaneTarget (self.nsLaneRoute, self:GetPos (), self.nsLaneIndex)
	if lanePoint then
		target = AsVector (lanePoint)
	else
		self.nsLaneRoute = nil
	end
	self.NSTarget = target
	self:NSSteer ()

	if Locomotion.Arrived (self:GetPos (), self.nsGoal, ARRIVE, self.nsHullMaxs.z) then
		StopAt (self)
	end
end

function ENT:NSSyncDebug ()
	local now = CurTime ()
	local path = self:GetPath ()
	if path and path:IsValid () then path:Draw () end

	if now >= (self.nsNextDebugCommand or 0) then
		self.nsNextDebugCommand = now + DEBUG_COMMAND_SYNC
		local goal = path and path:IsValid () and path:GetCurrentGoal ()
		local target = goal and goal.pos or self.NSTarget
		local direction = target and (target - self:GetPos ()) or vector_origin
		direction.z = 0
		if direction:Length2DSqr () > 0 then direction:Normalize () end
		self:SetNW2Vector ("NSPathFollowerCommand", direction)
	end
end

function ENT:NSSteer (enemy)
	local result = SoldierSteer (self, enemy)
	if self.NSToolManaged then self:NSSyncDebug () end
	return result
end

-- One entry of the report's lists, with when (seconds into the errand) and
-- where.
function ENT:NSNote (list, what, detail)
	local errand = self.nsErrand
	errand [list] [#errand [list] + 1] = { at = math.Round (CurTime () - errand.started, 2), pos = Point (self:GetPos ()), what = what, detail = detail }
end

function ENT:NSErrand (goal, seconds)
	local now = CurTime ()
	self.nsErrand =
	{
		goal = goal,
		from = self:GetPos (),
		started = now,
		deadline = now + (seconds or DEFAULT_SECONDS),
		nearest = self:GetPos ():Distance (goal),
		progressAt = now,
		progressPos = self:GetPos (),
		recoveriesRunning = 0,
		failures = {}, recoveries = {}, nudges = {}, marks = {}
	}
	self.NSTarget = goal
end

-- The soldier base, reached as it is called: baseclass.Get at the top of this file would make it
-- this class's base (as DEFINE_BASECLASS does).
local function Soldier () return baseclass.Get ("base_nextsoldier") end

-- The base's intention: its looks, then its idle or fighting hooks, then its attack. In the war,
-- the war's orders answer the hooks. On its legs, they walk it (NSLegsHeadFor steers), so the
-- hooks only say its feet are taken and it fights where they take it, as L4D2's main tree fights
-- while its legs walk. On its bench, none: an errand's probe neither looks nor fights.
function ENT:IntentionUpdate (interval)
	local driver = self:NSDriver ()
	if driver == "path" then return end
	return Soldier ().IntentionUpdate (self, interval)
end

local SoldierHooks = { OnIdle = ENT.OnIdle, OnChaseEnemy = ENT.OnChaseEnemy, OnAvoidEnemy = ENT.OnAvoidEnemy,
	OnIdleEnemy = ENT.OnIdleEnemy }
for name, hook in pairs (SoldierHooks) do
	ENT [name] = function (self, enemy)
		if self:NSDriver () == "legs" then return true end
		return hook (self, enemy)
	end
end

-- Started (the engine's BehaveStart, its first think): its driver's tree is put in, by the base,
-- and on its legs, its leggings beside it.
function ENT:BehaveStart ()
	Soldier ().BehaveStart (self)
	self.nsStarted = true
	if self:NSDriver () == "legs" then self:NSPutOnLeggings () end
end

-- Its leggings (NextLegs): the tree beside its main one that puts its feet where its
-- squad's order says, once for its life, at ease while it has no order.
function ENT:NSPutOnLeggings ()
	if self.nsLeggings then return end
	nextsoldier.engine.InsertGroup (self, GroupIdentity.InitialAction (nextsoldier.engine, GIB.LegsAtEase:New ()))
	self.nsLeggings = true
end

-- Each tick, after the base's update, its leggings, while they drive it.
function ENT:BehaveUpdate (interval)
	Soldier ().BehaveUpdate (self, interval)
	if self.nsLeggings and self:NSDriver () == "legs" and self:IsAlive () then nextsoldier.engine.UpdateGroup (self) end
end

-- Its driver's first action, or none in the war, whose orders are its behaviour. On its legs, its
-- main stack is a squad member's, which fights while its leggings walk it (nextsoldier.squad.behaviors.member).
function ENT:NSInitialAction ()
	local driver = self:NSDriver ()
	if driver == "legs" then return nextsoldier.squad.behaviors.member.SquadMember:New () end
	if driver == "war" then return nil end
	return nextsoldier.behavior.pathfollower.InitialAction (self.NSToolManaged)
end

-- A bench war started for followers ends with the last soldier in it; it leaves its squad.
function ENT:OnRemove ()
	if self.nsLeggings then nextsoldier.engine.EndGroup (self) end
	Soldier ().OnRemove (self)
	if self.nsLegsOrder then self.nsLegsOrder:Leave (self) end
	if self:NSDriver () == "war" then WS.Feature ("aiwar"):EndBenchWhenEmpty (self) end
end

-- A tool's follower on its bench is not hurt: a stray shot would take it off it. Its legs' and
-- the war's are, so a squad takes casualties.
hook.Add ("EntityTakeDamage", "npc_pathfollower", function (ent)
	if ent:GetClass () == "npc_pathfollower" and ent.NSToolManaged and ent:NSDriver () == "path" then return true end
end)

-- Its way kept out of the areas its legs say (NSLegsHeadFor's keepOut), else the war soldier's cost.
local SoldierComputePath = ENT.OnComputePath

-- An access door not its team's closes the areas it stands in (obj_door's ClosedTo).
function ENT:OnComputePath (from, to, ladder)
	if self.nsLegsKeepOut and self.nsLegsKeepOut [to:GetID ()] then return -1 end
	local door = scripted_ents.GetStored ("obj_door")
	if door and door.t.ClosedTo (to:GetID (), self:NSTeam ()) then return -1 end
	return SoldierComputePath (self, from, to, ladder)
end

-- Killed on orders, a casualty of its squad's.
local SoldierDeath = ENT.OnDeath

function ENT:OnDeath (dmg)
	if self.nsLegsOrder then
		Command.Casualty (self.nsLegsOrder, self, self:NSLegsAt ())
		self.nsLegsOrder:Casualty (self)
	end
	return SoldierDeath (self, dmg)
end

-- Its legs (driven by them): its squad's order and its place in it, the map's word on a spot,
-- the seats near its place, its way to where its squad's mode sends it, and what it calls out.

function ENT:NSLegsOrder () return self.nsLegsOrder end
function ENT:NSLegsPlace () return self.nsLegsPlace end
function ENT:Now () return CurTime () end
function ENT:NSLegsDraw () return math.random () end

function ENT:NSLegsAt ()
	local at = self:GetPos ()
	return { x = at.x, y = at.y, z = at.z }
end

-- Whether it is fighting an enemy now, the base's own; where that enemy is; and whether it has
-- been hurt.
function ENT:NSLegsContact () return self:HasEnemy () end

function ENT:NSLegsEnemyAt ()
	local enemy = self:GetEnemy ()
	if not enemy then return nil end
	local at = enemy:GetPos ()
	return { x = at.x, y = at.y, z = at.z }
end

function ENT:NSLegsHurt () return self:Health () < self:GetMaxHealth () end

-- A danger marked for its team near its squad's point (the stool's Annotate), or nil.
function ENT:NSLegsDanger (point) return WS.Feature ("aiwar"):DangerNear (self:NSTeam (), point) end

-- Its name on its squad's radio: the one it is given (NSRadioName), else its entity's number; kept
-- by the entity (RadioNames, set as it starts), so one killed and gone is still named.
function ENT:NSLegsNameOf (member)
	if member == Radio.DIRECTOR then return self:NSDirector () end
	if member == Radio.SQUAD then return "squad" end
	return RadioNames [member] or "?"
end

-- Who its squad's leader answers to: Overwatch, for the Combine; else Command.
function ENT:NSDirector ()
	return self:GetModel ():find ("combine", 1, true) and "Overwatch" or "Command"
end

-- The alarms (ent_room_alarm) in the room an order holds, raised.
local function RaiseAlarms (order)
	local room = order and order.room
	if not (room and room.lo and room.hi) then return end
	for _, alarm in ipairs (ents.FindByClass ("ent_room_alarm")) do
		local at = alarm:GetPos ()
		if at.x >= room.lo.x and at.x <= room.hi.x and at.y >= room.lo.y and at.y <= room.hi.y then alarm:Raise () end
	end
end

-- Its squad's call over the radio (call: nextsoldier.squad.comms.radio's entry; a line its leggings
-- call out aloud is its leader's to the squad, Radio.Line), to everyone's chat and the server's
-- console, as "[RED radio] red 1 -> red 4: Status report."; stacking up, the room's alarms.
function ENT:NSLegsSay (line, call)
	call = call or Radio.Line (self:NSLegsOrder (), self, line)
	local said = line
	if call then
		said = string.format ("[%s radio] %s -> %s: %s", team.GetName (self:NSTeam ()), self:NSLegsNameOf (call.from),
			self:NSLegsNameOf (call.to), line)
	end
	PrintMessage (HUD_PRINTTALK, said)
	MsgN (said)
	if call and call.call == "STACK_UP" then RaiseAlarms (self:NSLegsOrder ()) end
end

-- The ground under a slot where its body fits there, or nil: the map's, not who stands there now.
local function Ground (self, slot)
	local at = Vector (slot.x, slot.y, slot.z)
	local floor = util.TraceLine (
		{
			start = at + Vector (0, 0, SEARCH_ABOVE),
			endpos = at - Vector (0, 0, SEARCH_BELOW),
			mask = MASK_NPCSOLID_BRUSHONLY
		}
	)
	if not floor.Hit or floor.StartSolid then return nil end
	local mins, maxs = self:GetCollisionBounds ()
	local fit = util.TraceHull (
		{
			start = floor.HitPos + LIFT,
			endpos = floor.HitPos + LIFT,
			mins = mins,
			maxs = maxs,
			mask = MASK_NPCSOLID_BRUSHONLY
		}
	)
	if fit.Hit then return nil end
	return floor.HitPos
end

-- What an order around point may give a body of its size: admit(slot) -> the ground it would
-- stand on, where it fits and no wall stands between it and point; nil elsewhere.
function ENT:NSLegsAdmit (point)
	local mins, maxs = self:GetCollisionBounds ()
	local from = Ground (self, point)
	local sweepMins, sweepMaxs = Vector (mins.x, mins.y, 0), Vector (maxs.x, maxs.y, maxs.z - STEP)
	return function (slot)
		local ground = from and Ground (self, slot)
		if not ground then return nil end
		local reach = util.TraceHull (
			{
				start = from + Vector (0, 0, STEP),
				endpos = ground + Vector (0, 0, STEP),
				mins = sweepMins,
				maxs = sweepMaxs,
				mask = MASK_NPCSOLID_BRUSHONLY
			}
		)
		if reach.Hit then return nil end
		return { x = ground.x, y = ground.y, z = ground.z }
	end
end

-- Its order and its place in it: nil, it has no room near; no order dissolves it. It leaves
-- the squad it was in, and stands up at its own pace.
function ENT:NSLegsGive (order, place)
	local was = self.nsLegsOrder
	if was and was ~= order then was:Leave (self) end
	self.nsLegsOrder = order
	self:SetNW2String ("NSLegsOrder", order and order.kind or "")
	if not order then
		self.NSTarget, self.NSStance, self.NSRun = nil, nil, true
		return
	end
	self.nsLegsPlace = place
	self:SetNW2Bool ("NSLegsStands", place ~= nil)
	self:SetNW2Vector ("NSLegsPlace", place and Vector (place.x, place.y, place.z) or self:GetPos ())
end

-- The hiding spots near its place it could reach from there: a nav area's own, by a wall or in
-- a corner, where a body rests out of the way.
function ENT:NSLegsSeats (place, radius)
	local at = Vector (place.x, place.y, place.z)
	local admit = self:NSLegsAdmit (at)
	local seats = {}
	for _, area in ipairs (navmesh.Find (at, radius, SEARCH_BELOW, SEARCH_ABOVE)) do
		for _, spot in ipairs (area:GetHidingSpots ()) do
			local seat = spot:Distance (at) <= radius and admit ({ x = spot.x, y = spot.y, z = spot.z })
			if seat then seats [#seats + 1] = seat end
		end
	end
	return seats
end

-- What it builds for its squad (nextsoldier.squad.behaviors.fortify): on its bench, every kind of
-- object; set down for its team at, facing toward facing, on the floor there or, where a boxed object
-- does not fit, at the nearest spot round it that it fits (Seat). A teleporter's
-- two ends link as they are built (obj_teleporter).
local OBJECTS =
{
	-- a sentry of its NSSentryLevel (obj_sentrygun's SetLevel), else level 1
	sentry = { "obj_sentrygun", setup = function (object, me) if me.NSSentryLevel then object:SetLevel (me.NSSentryLevel) end end },
	dispenser = { "obj_dispenser" },
	door = { "obj_door" },
	teleporter_entrance = { "obj_teleporter", false },
	teleporter_exit = { "obj_teleporter", true }
}

function ENT:NSLegsBuilds (kind) return OBJECTS [kind] ~= nil end

-- Where an object may stand near a spot: on the floor under it, then, for an object with a box of its
-- own (base_obj's HullMins and HullMaxs), round it, nearest first. A door has none: it goes in its
-- doorway or not at all.
local SEAT_RINGS, SEAT_STEPS, FLOOR_LOOK = { 32, 64, 96 }, 8, Vector (0, 0, 64)
-- base_obj's: how far above its origin the space it needs starts.
local FLOOR_CLEAR = 2

local function Floor (spot)
	local tr = util.TraceLine ({ start = spot + FLOOR_LOOK, endpos = spot - FLOOR_LOOK, mask = MASK_SOLID_BRUSHONLY })
	return tr.Hit and not tr.StartSolid and tr.HitPos or nil
end

-- The first spot near pos where class's box stands clear (as its Fits asks, by a trace alone, so
-- nothing is made to be tried), or pos's floor for a class with no box of its own.
local function Seat (class, pos)
	local mins, maxs = scripted_ents.GetMember (class, "HullMins"), scripted_ents.GetMember (class, "HullMaxs")
	if not mins then return Floor (pos) end
	local clearMins = Vector (mins.x, mins.y, FLOOR_CLEAR)
	local function Clear (seat)
		return seat and not util.TraceHull ({ start = seat, endpos = seat, mins = clearMins, maxs = maxs, mask = MASK_SOLID }).Hit
	end
	local seat = Floor (pos)
	if Clear (seat) then return seat end
	for _, radius in ipairs (SEAT_RINGS) do
		for i = 0, SEAT_STEPS - 1 do
			local angle = i / SEAT_STEPS * 2 * math.pi
			seat = Floor (pos + Vector (math.cos (angle) * radius, math.sin (angle) * radius, 0))
			if Clear (seat) then return seat end
		end
	end
	return nil
end

function ENT:NSLegsBuild (kind, at, facing)
	local entry = OBJECTS [kind]
	if not entry then error ("no object of kind " .. tostring (kind), 2) end
	local pos = Vector (at.x, at.y, at.z)
	local seat = Seat (entry [1], pos)
	if not seat then return nil end
	local object = ents.Create (entry [1])
	if entry [2] ~= nil then object:SetIsExit (entry [2]) end
	if entry.setup then entry.setup (object, self) end
	object:SetObjTeam (self:NSTeam ())
	object:SetBuilder (self)
	object:SetPos (seat)
	object:SetAngles (Angle (0, (Vector (facing.x, facing.y, pos.z) - pos):Angle ().y, 0))
	object:Spawn ()
	object:Activate ()
	if object:Fits () then return object end
	object:Remove ()
	return nil
end

-- Whether what it set down still stands.
function ENT:NSLegsStands (object) return IsValid (object) end

-- Whether what stands is its own: it built it (base_obj's Builder).
function ENT:NSLegsOwns (object) return IsValid (object) and object:GetBuilder () == self end

-- Its team's buildings within TEND_REACH, the one needing it most (gameplay.buildings' Upkeep), looked
-- over every TEND_LOOK: where it stands, or nil with all whole.
local TEND_LOOK = 0.5
local WRENCH_SOUND = "weapons/wrench_hit_build_success1.wav"

function ENT:NSLegsTend ()
	local Buildings, now = gameplay.buildings, CurTime ()
	if now >= (self.nsTendLook or 0) then
		self.nsTendLook = now + TEND_LOOK
		local team, near = self:NSTeam (), {}
		for _, ent in ipairs (ents.FindInSphere (self:GetPos (), Buildings.TEND_REACH)) do
			if ent.Wrench and Buildings.Tends (ent:GetObjTeam (), team) then
				near [#near + 1] = { constructed = ent:Constructed (), health = ent:Health (), max = ent:GetMaxHealth (), ent = ent }
			end
		end
		local worst = Buildings.Upkeep (near)
		self.nsTending = worst and worst.ent
	end
	if not IsValid (self.nsTending) then return nil end
	local at = self.nsTending:GetPos ()
	return { x = at.x, y = at.y, z = at.z }
end

-- Its wrench on the building it tends: whether that is within reach, struck at the wrench's pace.
function ENT:NSLegsWrench ()
	local Buildings, building = gameplay.buildings, self.nsTending
	if not IsValid (building) then return false end
	local eye = self:EyePos ()
	if building:NearestPoint (eye):Distance (eye) > Buildings.WRENCH_RANGE then return false end
	local now = CurTime ()
	if now >= (self.nsNextSwing or 0) then
		self.nsNextSwing = now + Buildings.WRENCH_INTERVAL
		if building:Wrench (self) then self:EmitSound (WRENCH_SOUND) end
	end
	return true
end

-- Where its squad's mode sends it, at the gait it says, its way there kept out of keepOut's nav areas
-- (id -> true; nil for none): walked there, or, its feet held, its path planned and shown. At the
-- seat it rests on, it crouches.
function ENT:NSLegsHeadFor (spot, gait, keepOut)
	if keepOut ~= self.nsLegsKeepOut then
		self.nsLegsKeepOut = keepOut
		local path = self:GetPath ()
		if IsValid (path) then path:Invalidate () end
	end
	local at = Vector (spot.x, spot.y, spot.z)
	self:SetNW2Vector ("NSLegsSpot", at)
	self:SetNW2Int ("NSLegsMode", self.nsLegsOrder.mode)
	self.NSRun = gait == GIB.GAIT.RUN
	self.NSStance = gait == GIB.GAIT.REST and self:GetPos ():Distance2D (at) <= REST_REACH and "crouched" or nil
	self.NSTarget = at
	self:NSSteer ()
end

-- What its team's spacing would do to it where it stands, as a soldier's tree works it out,
-- among the followers its legs drive.
function ENT:NSLegsSense ()
	local engine = nextsoldier.engine
	local pos = self:GetPos ()
	local others = {}
	for _, other in ipairs (ents.FindByClass ("npc_pathfollower")) do
		if other ~= self and other:NSDriver () == "legs" and other:NSTeam () == self:NSTeam () then
			local at = other:GetPos ()
			others [#others + 1] = { x = at.x, y = at.y, z = at.z }
		end
	end
	local x, y = engine.Separation ({ x = pos.x, y = pos.y, z = pos.z }, others, self:EntIndex ())
	self:SetNW2Float ("NSLegsSpacing", engine.GroupSpacing ())
	self:SetNW2Vector ("NSLegsPush", Vector (x, y, 0))
end

function ENT:NSWantedBehavior () return self.nsBehavior end

function ENT:NSUpdateErrand ()
	local errand = self.nsErrand
	if not errand or errand.done then return end
	local now, pos = CurTime (), self:GetPos ()
	local distance = pos:Distance (errand.goal)
	if distance < errand.nearest then errand.nearest = distance end
	if Locomotion.Arrived (pos, errand.goal, ARRIVE, self.nsHullMaxs.z) then return self:NSFinish ("arrived") end
	if now >= errand.deadline then return self:NSFinish ("timed out") end
	if errand.lastZ and errand.lastZ - pos.z > DROP_MARK then self:NSNote ("marks", "dropped", string.format ("%.0f units", errand.lastZ - pos.z)) end
	errand.lastZ = pos.z
	if self.NSRappelling and not errand.rappelling then self:NSNote ("marks", "rappelled") end
	errand.rappelling = self.NSRappelling
	self.NSTarget = errand.goal
	self:NSSteer ()
	-- a path planned again marked only when it goes another way (its waypoints' kinds)
	local path = self:GetPath ()
	if path ~= errand.path and path and path:IsValid () then
		errand.path = path
		local kinds = PathKinds (path)
		local shape = util.TableToJSON (kinds)
		if shape ~= errand.shape then
			errand.shape = shape
			self:NSNote ("marks", "path planned", { kinds = kinds, steps = PathSteps (path) })
		end
	end
	local result = self.NSMoveResult
	if result ~= errand.result then
		errand.result = result
		if result == "unreachable" then
			self:NSNote ("failures", "no path to the goal")
		elseif result == "vaulted" or result == "hopped" then
			self:NSNote ("nudges", result)
		elseif result == "obstacle" then
			self:NSNote ("marks", "held by an obstacle")
		end
	end
	if pos:Distance (errand.progressPos) >= PROGRESS then
		errand.progressAt, errand.progressPos, errand.recoveriesRunning = now, pos, 0
	elseif now - errand.progressAt >= RECOVER_AFTER then
		errand.progressAt = now
		errand.recoveriesRunning = errand.recoveriesRunning + 1
		self:NSRepath ()
		self:NSNote ("recoveries", "no headway: path planned again", string.format ("%.0f units from the goal", distance))
		if errand.recoveriesRunning >= NUDGE_AFTER then
			local waypoint = path and path:IsValid () and path:GetCurrentGoal ()
			if waypoint then
				self:NSHop (waypoint.pos)
				self:NSNote ("nudges", "hop toward the next waypoint", self.NSHopWhy)
			end
		end
	end
end

-- Arrived or out of time: the report, printed, saved and told; then it goes.
function ENT:NSFinish (status)
	local errand = self.nsErrand
	errand.done = true
	if status ~= "arrived" then self:NSNote ("failures", status, string.format ("%.0f units from the goal", self:GetPos ():Distance (errand.goal))) end
	local report =
	{
		map = game.GetMap (),
		status = status,
		seconds = math.Round (CurTime () - errand.started, 2),
		from = Point (errand.from),
		goal = Point (errand.goal),
		ended = Point (self:GetPos ()),
		nearest = math.Round (errand.nearest),
		failures = errand.failures,
		recoveries = errand.recoveries,
		nudges = errand.nudges,
		marks = errand.marks
	}
	local json = util.TableToJSON (report, true)
	MsgN ("[npc_pathfollower] " .. status .. ":\n" .. json)
	file.CreateDir (REPORTS)
	file.Write (string.format ("%s%s_%d_%d.json", REPORTS, report.map, self:EntIndex (), os.time ()), json)
	self.nsReport = report
	hook.Run ("NSPathFollowerDone", self, report)
	SafeRemoveEntityDelayed (self, 0)
end

concommand.Add ("ns_pathfollower_send", function (ply, _, args)
	if IsValid (ply) and not ply:IsSuperAdmin () then return end
	local n = {}
	for i = 1, 7 do n [i] = tonumber (args [i]) end
	if not (n [1] and n [2] and n [3] and n [4] and n [5] and n [6]) then
		print ("ns_pathfollower_send fromX fromY fromZ toX toY toZ [seconds]")
		return
	end
	local follower = ents.Create ("npc_pathfollower")
	follower:SetPos (Vector (n [1], n [2], n [3]))
	follower:Spawn ()
	follower:NSErrand (Vector (n [4], n [5], n [6]), n [7])
	ply:AddCleanup ("NPC", follower)
	print (string.format ("ns_pathfollower_send: #%d sent", follower:EntIndex ()))
end, nil, "Send a path follower (NextSoldier's base, no fighting) from one point to another; it reports how it went when it arrives or its time runs out")
