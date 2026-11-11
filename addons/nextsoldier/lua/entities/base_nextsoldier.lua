-- base_nextsoldier: NextSoldier's own NextBot base (issue #8 L1,
-- docs/base-nextsoldier-plan.md), implementing the interface our code keeps
-- of DrGBase's (nextsoldier.base) from scratch, organised as TF2's NextBot
-- in source-sdk-2013: the bot (life and relations) and its locomotion,
-- body, vision and intention, each a model or a thin binding to GMod's
-- NextBot, updated every tick from BehaveUpdate. No coroutine runs: TF2
-- runs none per bot.
--
-- A soldier class sets ENT.Base = "base_nextsoldier", its fields (the
-- profile: Model, Weapons, Factions, SpawnHealth, speeds and ranges) and
-- defines the hooks it wants (nextsoldier.base's HOOKS); the base raises
-- them and keeps its own defaults for the ones a class calls through.
AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "NextSoldier"
ENT.Spawnable = false
ENT.IsNextSoldier = true

-- The profile's defaults (nextsoldier.base's FIELDS).
ENT.Model = "models/player/kleiner.mdl"
ENT.Weapons = {}
ENT.SpawnHealth = 100
ENT.WalkSpeed = 90
ENT.RunSpeed = 220
ENT.ClimbLedges = false
ENT.ClimbLedgesMaxHeight = 64
ENT.DeathDropHeight = 200
ENT.ReachEnemyRange = 600
ENT.AvoidEnemyRange = 0
ENT.RangeAttackRange = 1500
ENT.MeleeAttackRange = 60
ENT.RagdollOnDeath = true
ENT.Factions = {}

-- Its hull standing (half its width, its height), and crouching: DrGBase's
-- soldiers' size, which the war's routes and posts were tuned against.
local HULL_MINS, HULL_MAXS = Vector(-10, -10, 0), Vector(10, 10, 72)
local CROUCH_HEIGHT = 36
-- Routes measure it crouched in a crouch area (includes.nav_clearance).
ENT.NSCrouchHeight = CROUCH_HEIGHT
-- A path is computed again for a goal moved this far, or this old.
local REPATH_DISTANCE, REPATH_AGE = 64, 2
local PATH_LOOKAHEAD = 300
-- A path is followed every tick while its intention asked for it this
-- recently (FollowPath): its intention runs at the engine's NextBot rate,
-- slower with many bots, its locomotion every tick, as TF2's does.
local FOLLOW_HOLD = 0.5
-- A path segment's type (GMod's PathFollower goals, NextBot's SegmentType).
local CLIMB_UP, JUMP_OVER_GAP = 2, 3
-- A climb begins this near the ledge's foot.
local CLIMB_REACH = 48
-- What a body plays on a ladder, the first its model has: a player model's
-- climbing loop, an HL2 NPC's climb; TF2's bodies have no climb (TF2 has no
-- ladders), and hang as they do in a jump.
local LADDER_DOWN_ACT = ACT_CLIMB_DOWN
local LADDER_ACTS = { ACT_ZOMBIE_CLIMB_UP, ACT_CLIMB_UP, ACT_MP_JUMP_FLOAT_PRIMARY }
-- The mode hosting the soldier gives what NextSoldier does not read for itself.
local Host = nextsoldier.host
local Walkable = wetsands.path.Walkable
-- It steps and jumps as its host says: a stair step, and as high as a crouch
-- jump reaches (it does not tuck its legs).
local STEP_HEIGHT, JUMP_HEIGHT = Host.current:Movement()
-- How long off the ground its feet count as a jump, and how long of that it plays
-- the jump's start before the fall.
local AIRBORNE, JUMP_START_TIME = 0.1, 0.2
-- How fast it gets up to speed and stops, and turns (degrees a second).
local ACCELERATION, DECELERATION, MAX_YAW_RATE = 1000, 1000, 250

if CLIENT then
	-- Its head turns to what interests it apart from its aim (its host's
	-- GazeUpdate), here on the client and only while it is drawn: the server says only
	-- whether it fights (NSFighting) and where it was told to look, until
	-- when, and whether at once (NSGaze, NSGazeUntil, NSGazeUrgent: LookAt).
	-- Teammate players are looked at. Fighting, or told urgently, the head
	-- snaps.
	function ENT:Draw()
		local hint = self:GetNW2Float("NSGazeUntil", 0) > CurTime() and self:GetNW2Vector("NSGaze") or nil
		local fighting = self:GetNW2Bool("NSFighting")
		local urgent = fighting or (hint ~= nil and self:GetNW2Bool("NSGazeUrgent"))
		Host.current:GazeUpdate(self, self:GetAngles().y, fighting, hint, self:GetNW2Int("ws_team", TEAM_UNASSIGNED), urgent)
		self:DrawModel()
	end
	return
end

local Behavior = nextsoldier.behavior
local Action = nextsoldier.behavior.action
local Gaze = nextsoldier.body.gaze
local Ladder = nextsoldier.locomotion.ladder
local Locomotion = nextsoldier.locomotion
local Leap = nextsoldier.locomotion.leap
local JumpActs = nextsoldier.body.jump
-- A point looked at along a path, at eye height.
local LOOK_HEIGHT = Vector(0, 0, 64)
-- The live bots on this base, which others' noises reach (DrGBase keeps
-- its own: DrGBase.GetNextbots).
local Bots = nextsoldier.bots
local Vision = nextsoldier.senses.vision
local Intention = nextsoldier.behavior.intention
local Weapons = nextsoldier.body.weapons

-- Its sight: how far, how wide (the whole cone), and how often it looks
-- (TF2's IVision update), how soon it recognizes what it sees and how long
-- it remembers. Range and cone are near DrGBase's, which the war's orders
-- were tuned against.
local SIGHT_RANGE, FOV_COS = 15000, math.cos(math.rad(150 / 2))
local NOTICE_NEAR = 200
-- What any of them may look at: the players, NPCs and NextBots, and what
-- else a mode marks as fought (ent.NSCombatant: a team's sentry), gathered
-- once a COMBATANTS_EVERY seconds for every bot's looks.
local COMBATANTS_EVERY = 1
local combatants, combatantsAt = {}, -math.huge

local function Combatants(now)
	if now - combatantsAt < COMBATANTS_EVERY then return combatants end
	combatants, combatantsAt = {}, now
	for _, ent in ents.Iterator() do
		if ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() or ent.NSCombatant then combatants[#combatants + 1] = ent end
	end
	return combatants
end

-- How long a hostile noise it heard keeps its source noticed.
local HEARD_NOTICE = 2
-- Its eyes where its model has none (TF2's VEC_VIEW and VEC_DUCK_VIEW, near enough).
local EYE_HEIGHT, CROUCH_EYE_HEIGHT = 64, 28
local LOOK_INTERVAL = 0.2
-- It pursues an enemy out of sight, the most dangerous it remembers, and
-- remembers one for DrGBase's SpotDuration, which the war's orders were
-- tuned against.
local VISION = { reaction = 0.1, memory = 30, unseen = true }
-- A melee weapon's hold types.
local MELEE_HOLDS = { melee = true, melee2 = true, knife = true, fist = true }
-- A player model's acts for a hold type are named ACT_HL2MP_<MOVE>_<HOLD>,
-- the plain hold's (no weapon) ACT_HL2MP_<MOVE>; the hold types named
-- otherwise (false: the plain hold's name), and the hold with no weapon.
local HOLD_ACT_NAMES = { smg = "SMG1", normal = false }
local HOLD_DEFAULT = "normal"
-- Its hold with no enemy: a long gun carried low, a pistol or a melee
-- weapon as no weapon, as DrGBase's soldiers carry them.
local CALM_HOLDS = {
	ar2 = "passive", smg = "passive", shotgun = "passive",
	pistol = "normal", revolver = "normal", melee = "normal", melee2 = "normal", fist = "normal", knife = "normal", duel = "normal",
}
-- Faster than its walk by this, it runs (the run acts).
local RUN_OVER_WALK = 10

-- The factions another entity is in, for a disposition toward it.
local function FactionsOf(other)
	if other.nsRelations then return other.nsRelations:Factions() end
	if other:IsPlayer() then return Host.current:PlayerFactions(other) end
	if other.GetFactions then return other:GetFactions() end
	return {}
end

-------------------------------------------------------------------------------
-- The bot: setup, life, relations

function ENT:Initialize()
	self:SetModel(self.Model)
	self:SetHealth(self.SpawnHealth)
	self:SetMaxHealth(self.SpawnHealth)
	-- a profile's hull (its half width and height, as DrGBase's CollisionBounds), else a player's
	local bounds = self.CollisionBounds
	self.nsHullMins = bounds and Vector(-bounds.x, -bounds.y, 0) or HULL_MINS
	self.nsHullMaxs = bounds and Vector(bounds.x, bounds.y, bounds.z) or HULL_MAXS
	self:SetCollisionBounds(self.nsHullMins, self.nsHullMaxs)
	if self.BloodColor then self:SetBloodColor(self.BloodColor) end
	-- what it walks on: under the engine's NPC mask a body on a map built for
	-- players walks a stair's bare treads, not the clip laid over them
	self:SetSolidMask(Host.current:SolidMask())
	self.loco:SetStepHeight(STEP_HEIGHT)
	self.loco:SetJumpHeight(JUMP_HEIGHT)
	self.loco:SetDeathDropHeight(self.DeathDropHeight)
	-- it falls as a player falls (the engine's NextBots fall at 1000)
	self.loco:SetGravity(GetConVar("sv_gravity"):GetFloat())
	self.loco:SetDesiredSpeed(self.WalkSpeed)
	self.loco:SetAcceleration(ACCELERATION)
	self.loco:SetDeceleration(DECELERATION)
	self.loco:SetMaxYawRate(MAX_YAW_RATE)
	-- an NPC to the map: a trigger flagged for NPCs (a spawn door's, which
	-- the AI war flags) sees it only so
	self:AddFlags(FL_NPC)
	self.nsAlive = true
	self.nsRelations = Behavior.Relations({ default = self.DefaultRelationship or D_NU, ally = D_LI })
	for _, faction in ipairs(self.Factions) do
		self.nsRelations:Join(faction)
		local enemy = Host.current:FactionEnemy(faction)
		if enemy then self.nsRelations:SetFaction(enemy, D_HT) end
	end
	self.nsVision = Vision.New(VISION)
	self.nsBetter = function(a, b) return self:IsMoreDangerous(a, b) end
	self.nsNextLook = 0
	self.nsWeapons = {}
	self.nsMagazines = setmetatable({}, { __mode = "k" })
	self.nsNoticed = setmetatable({}, { __mode = "k" })
	Bots[self] = true
	self:ReadRanges()
	if #self.Weapons > 0 then self:SelectWeapon(self:GiveWeapon(self.Weapons[math.random(#self.Weapons)])) end
	self:CustomInitialize()
end

function ENT:IsAlive() return self.nsAlive == true end

-- The team it fights for: the one its host set (its ws_team), read through
-- Team as a player's is.
function ENT:Team() return self:GetNW2Int("ws_team", TEAM_UNASSIGNED) end

-- Hurt (the engine raises this before the damage is taken): whoever did it
-- is noticed at the next look, wherever it stands, and its head snaps to
-- them (LookAt).
function ENT:OnInjured(dmg)
	local attacker = dmg:GetAttacker()
	if IsValid(attacker) and attacker ~= self then
		self.nsAttacker = attacker
		self:LookAt(attacker:WorldSpaceCenter(), Gaze.HINT_SECONDS, true)
	end
end

-- Dead: the class's OnDeath, then the body: a ragdoll (RagdollOnDeath), or
-- removed once it has lingered (Linger: the clients' ragdoll handoff), with
-- no coroutine to pause, as TF2 keeps none.
function ENT:OnKilled(dmg)
	if not self.nsAlive then return end
	self.nsAlive = false
	self.nsEnemy, self.nsScramble, self.nsLinger = nil, nil, 0
	hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())
	self:OnDeath(dmg)
	if self.RagdollOnDeath then
		self:BecomeRagdoll(dmg)
	else
		SafeRemoveEntityDelayed(self, self.nsLinger)
	end
end

function ENT:Linger(seconds) self.nsLinger = math.max(self.nsLinger or 0, seconds) end

-- It stands still for seconds, its path waiting (a taunt played whole).
function ENT:HoldStill(seconds)
	self.nsStillUntil = math.max(self.nsStillUntil or 0, CurTime() + seconds)
end

-- Dying, its body plays sequence once, from the start, as its last (a canned
-- death), and nothing else; the sequence's length in seconds.
function ENT:DeathSequence(sequence)
	self.nsDeathSequence = sequence
	self:ResetSequence(sequence)
	self:SetCycle(0)
	self:SetPlaybackRate(1)
	return self:SequenceDuration(sequence)
end

-- Begins again (TF2's INextBot::Reset): alive, its senses, enemy, path and
-- scramble cleared.
function ENT:Reset()
	self.nsAlive = true
	self.nsEnemy, self.nsScramble, self.nsPath, self.nsAttacker = nil, nil, nil, nil
	self.nsDeathSequence = nil
	self.nsVision = Vision.New(VISION)
	self.nsNextLook = 0
end
function ENT:IsDead() return not self:IsAlive() end
function ENT:IsDown() return false end

function ENT:AddEntityRelationship(other, disposition, priority) self.nsRelations:SetEntity(other, disposition, priority) end
function ENT:SetFactionRelationship(faction, disposition, priority) self.nsRelations:SetFaction(faction, disposition, priority) end
function ENT:Disposition(other) return self.nsRelations:Disposition(other, FactionsOf) end
function ENT:JoinFaction(faction) self.nsRelations:Join(faction) end
function ENT:LeaveFaction(faction) self.nsRelations:Leave(faction) end
function ENT:GetFactions() return self.nsRelations:Factions() end

-- No coroutine: BehaveStart (the engine's, once at spawn) resets the bot,
-- and BehaveUpdate updates it each tick, as TF2's INextBot::Update does its
-- components.
function ENT:BehaveStart()
	self:Reset()
	local action = self:NSInitialAction()
	if action then
		nextsoldier.engine.Insert(self, action)
		self.nsEngineDebug = Action.DebugNpc(self, nextsoldier.engine.Stack, nextsoldier.engine.GroupStack)
	end
end

-- The first of this class's behaviours as the engine's own Actions (a table of
-- hooks, native/nextsoldier), which needs the binary; none by default.
function ENT:NSInitialAction() end

-- Whether an engine action may steer its body: the engine updates one whatever the body
-- is doing, where BehaveUpdate waits.
function ENT:NSMayAct()
	return self:IsAlive() and not self:IsScrambling() and not self:IsAIDisabled()
end

function ENT:BehaveUpdate(interval)
	if not self:IsAlive() then return end
	self:CustomThink()
	if self:IsScrambling() then return end
	if self:IsAIDisabled() then return end
	local gait = self:ShouldRun() and self.RunSpeed or self.WalkSpeed
	self.loco:SetDesiredSpeed(Locomotion.Recovering(gait, CurTime(), self.nsImpactUntil))
	self:IntentionUpdate(interval)
end

-------------------------------------------------------------------------------
-- Locomotion (ILocomotion): the path followed, priced by the class

function ENT:GetPath() return self.nsPath end

-- The generic debug layer's behavior view. Classes with their own behavior
-- state can expose it through nsBehavior; AI-war soldiers supply their richer
-- action stack through WSNbDebugNpcs instead.
function ENT:NSDebugStack()
	if self.nsEngineDebug then return self.nsEngineDebug:Stack() end
	local name = self.nsBehavior or self:GetClass()
	return self:GetClass(), {
		{ depth = 0, name = name, short = name },
	}
end

function ENT:NSDebugWatch(log)
	if self.nsEngineDebug then self.nsEngineDebug:Watch(log) end
	self.NSDebugBehaviorLog = log
end

function ENT:NSDebugBehaviorChanged(from, to)
	local log = self.NSDebugBehaviorLog
	if log and from ~= to then
		log:Event((from or "(none)") .. " -> " .. to)
	end
end

local function ComputeDebugPath(self, path, goal)
	local watch = self.NSDebugPathWatch
	if not watch then return path:Compute(self, goal, self:GetPathGenerator()) end

	local Debug = Host.current:PathDebug()
	local start = self:GetPos()
	local generator = self:GetPathGenerator()
	local recorder = watch.costs and generator and Debug.NewCostRecorder() or nil
	if recorder then
		local cost = generator
		generator = function(area, fromArea, ...)
			local result = cost(area, fromArea, ...)
			recorder:Record(area:GetID(), IsValid(fromArea) and fromArea:GetID() or nil, result)
			return result
		end
	end

	local began = SysTime()
	local found = path:Compute(self, goal, generator)
	local segments, points, areaIds, lastArea = path:GetAllSegments() or {}, {}, {}, nil
	for i, segment in ipairs(segments) do
		points[i] = { pos = segment.pos, move = Debug.MoveOfSegment(segment.type) }
		if IsValid(segment.area) then
			lastArea = segment.area
			areaIds[#areaIds + 1] = lastArea:GetID()
		end
	end
	hook.Run("WSNpcPathComputed", self, Debug.NewPathReport({
		source = Debug.SOURCE_ENGINE,
		strategy = generator and self:GetClass() .. ":GetPathGenerator()" or "engine default",
		start = start,
		goal = goal,
		found = found,
		points = points,
		areaIds = areaIds,
		totalCost = IsValid(lastArea) and lastArea:GetCostSoFar() or nil,
		microseconds = (SysTime() - began) * 1e6,
		nodesExpanded = recorder and recorder:Expanded() or nil,
		explored = recorder and recorder:Explored() or nil,
		computedAt = CurTime(),
	}))
	return found
end

-- Locomotion's update, every tick (TF2's ILocomotion::Update): a scramble
-- under way, else the path its intention follows.
function ENT:Think()
	if self.NSDebugDrawPath then
		local path = self.nsPath
		if path and path:IsValid() then path:Draw() end
	end
	if self:IsAlive() and not self:ScrambleUpdate() then
		local path = self.nsPath
		if path and path:IsValid() and CurTime() - (self.nsFollowedAt or 0) <= FOLLOW_HOLD
			and not self:ClimbPathLadder(path) then
			path:Update(self)
		end
		-- an enemy in sight is faced, the path walked sideways or backing
		-- (BodyMoveXY), as a player fights: the path's own turn comes first
		local enemy = self:GetEnemy()
		if enemy and self.nsVision:Visible(enemy) then self.loco:FaceTowards(enemy:GetPos()) end
	end
	self:NextThink(CurTime())
	return true
end

-- A scramble (TF2's ClimbUpToLedge, JumpAcrossGap: a locomotion process
-- carried out over ticks, no coroutine): { duration, at(t) -> position,
-- done(), act and rate (what its body plays, or its usual animation), jumps (it
-- plays its jump) }, its
-- momentum stopped each step; nothing else moves it, and its intention waits,
-- until it ends.
function ENT:Scramble(motion)
	self.nsScramble = {
		duration = motion.duration,
		at = motion.at,
		done = motion.done,
		act = motion.act,
		rate = motion.rate,
		jumps = motion.jumps,
		began = CurTime(),
	}
end

function ENT:IsScrambling() return self.nsScramble ~= nil end

-- One step of the scramble under way; whether one was.
function ENT:ScrambleUpdate()
	local scramble = self.nsScramble
	if not scramble then return false end
	local t = math.min(1, (CurTime() - scramble.began) / scramble.duration)
	self.loco:SetVelocity(vector_origin)
	self:SetPos(scramble.at(t))
	if t >= 1 then
		self.nsScramble = nil
		if scramble.done then scramble.done() end
	end
	return true
end

-- It hit the ground hard: slowed while it recovers (nextsoldier.locomotion).
function ENT:NSImpact()
	self.nsImpactUntil = CurTime() + Locomotion.IMPACT_RECOVERY
end

-- Its path planned again, from where a scramble has set it.
local function PathAgain(self)
	local path = self:GetPath()
	if path and path:IsValid() then path:Invalidate() end
end

-- A jump its path's next goal asks for, when the class jumps ledges (ClimbLedges),
-- asks to (OnStartClimbing) and begins one (CustomClimbing): up a ledge, or over a
-- gap to the goal after, as the engine's follower jumps it (JumpOverGaps). Whether
-- it did.
function ENT:ClimbPathGoal(path)
	if not self.ClimbLedges then return false end
	local goal = path:GetCurrentGoal()
	if not goal or (goal.type ~= CLIMB_UP and goal.type ~= JUMP_OVER_GAP) then return false end
	local pos = self:GetPos()
	if (pos - goal.pos):Length2D() > CLIMB_REACH then return false end
	local after = path:NextSegment(goal)
	if not after then return false end
	local onto = Leap.Landing(after, pos, goal.type == CLIMB_UP)
	local height = onto.z - pos.z
	if height > self.ClimbLedgesMaxHeight or not self:OnStartClimbing(onto, height, false) then return false end
	self:CustomClimbing(onto)
	return self:IsScrambling()
end

-- The ladder move its path comes to next: the goal it walks to, or the one
-- after, reached before the engine's follower would take hold of the ladder.
local function NextLadderMove(path)
	local goal = path:GetCurrentGoal()
	if not goal then return nil end
	if IsValid(goal.ladder) then return goal end
	local after = path:NextSegment(goal)
	return after and IsValid(after.ladder) and after or nil
end

-- A climb of the ladder its path has brought it to (nextsoldier.locomotion.ladder), onto
-- the area the move enters, crouched if that area asks it; its path planned
-- again from there: whether it began one. Facing the ladder all the way.
function ENT:ClimbPathLadder(path)
	local move = NextLadderMove(path)
	if not move then return false end
	local mins, maxs = self:GetCollisionBounds()
	if not Ladder.CanMount(self:GetPos(), move.pos, maxs.z - mins.z) then return false end
	local ladder, area = move.ladder, move.area
	local q = {
		from = self:GetPos(),
		bottom = ladder:GetBottom(),
		top = ladder:GetTop(),
		normal = ladder:GetNormal(),
		halfWidth = math.max(maxs.x, maxs.y),
		down = move.type == Ladder.DOWN,
	}
	local near = q.down and q.bottom or q.top
	q.landing = Ladder.Landing(area:GetClosestPointOnArea(near), area:GetCenter(), q.halfWidth)
	local climb = Ladder.Climb(q)
	local act, rate = Ladder.Animation(function(candidate) return self:SelectWeightedSequence(candidate) >= 0 end,
		LADDER_DOWN_ACT, LADDER_ACTS, q.down)
	self:SetAngles(Angle(0, (-q.normal):Angle().y, 0))
	self:Scramble({
		duration = climb.duration,
		at = function(t)
			local p = climb:At(t)
			return Vector(p.x, p.y, p.z)
		end,
		act = act,
		rate = rate,
		done = function()
			self:SetCrouching(area:HasAttributes(NAV_MESH_CROUCH))
			PathAgain(self)
		end,
	})
	return true
end

-- Follows a path to goal, computed again when the goal has moved or the path
-- has aged: "unreachable" (no path), "reached", "obstacle" (stuck against
-- something on its way) or "moving". A path made afresh (none, or for a
-- goal moved), not one merely aged, has it look PATH_LOOKAHEAD along its
-- new way a while (LookAt).
-- Its path to goal, planned again when the goal has moved or the path has aged, and whether
-- it was made afresh (none, or for a goal moved): planned only, not followed.
function ENT:PlanPath(goal, tolerance)
	local path = self.nsPath
	local afresh = not (path and path:IsValid())
		or (self.nsPathGoal and self.nsPathGoal:DistToSqr(goal) > REPATH_DISTANCE * REPATH_DISTANCE)
	if afresh or path:GetAge() > REPATH_AGE then
		path = Path("Follow")
		path:SetMinLookAheadDistance(PATH_LOOKAHEAD)
		path:SetGoalTolerance(tolerance or 20)
		ComputeDebugPath(self, path, goal)
		self.nsPath, self.nsPathGoal = path, goal
		return path, afresh, true
	end
	return path, false, false
end

function ENT:FollowPath(goal, tolerance)
	-- what asks may be the engine's action, updated whatever the body is doing
	if self:IsScrambling() then return "moving" end
	if isentity(goal) then goal = goal:GetPos() end
	local path, afresh, planned = self:PlanPath(goal, tolerance)
	if planned then
		if not path:IsValid() then return "unreachable" end
		if afresh then self:LookAt(path:GetPositionOnPath(PATH_LOOKAHEAD) + LOOK_HEIGHT, Gaze.HINT_SECONDS) end
	end
	if self:ClimbPathGoal(path) then return "moving" end
	-- a taunt is played standing still (HoldStill)
	if CurTime() < (self.nsStillUntil or 0) then return "moving" end
	self.nsFollowedAt = CurTime()
	if self:ClimbPathLadder(path) then return "moving" end
	path:Update(self)
	if not path:IsValid() then return "reached" end
	if self.loco:IsStuck() then
		-- reported once (the class may vault or hop), then cleared, its path
		-- planned again from where it stands: GMod's locomotion stays stuck
		-- until told otherwise, as TF2's ClearStuckStatus
		self.loco:ClearStuck()
		path:Invalidate()
		return "obstacle"
	end
	return "moving"
end

-------------------------------------------------------------------------------
-- Jumps: onto a ledge, across a gap, over a rail and a plain hop, on its path's asking
-- or on a command (NSHop)

-- A ledge jump (CustomClimbing): how far in from its hull a soldier checks
-- the way up and the landing, so the wall it stands against is not in the
-- way; how long after a jump it found no way for it does not try another.
local LEAP_INSET, LEAP_RETRY = 2, 1
-- A vault (NSVault) over what it cannot stand on, a railing: how far ahead
-- it looks for the obstacle; past its face, how far it looks for the floor
-- beyond, in steps of how much; and how far onto that floor it lands.
local VAULT_REACH, VAULT_SCAN, VAULT_SCAN_STEP, VAULT_LAND_IN = 48, 64, 8, 8
-- An obstacle's top is looked for along this far past where the hull met it,
-- this often: a rail a few units thick stands between lines farther apart.
local TOP_SCAN, TOP_SCAN_STEP = 16, 2
-- A plain hop when no vault fits: this fast the way it heads, up as high as
-- it climbs.
local HOP_SPEED = 200

-- A ledge it jumps: CustomClimbing; not again for LEAP_RETRY after a jump
-- with no way up.
function ENT:OnStartClimbing(ledge, height, down)
	if isvector(ledge) and not down then
		if CurTime() < (self.NSLeapRetry or 0) then return false end
		return true
	end
	return false
end

-- A motion along at(t) (t from 0 to 1 over duration seconds), facing
-- toward: a scramble its locomotion steps each tick (TF2's climbs and
-- jumps, no coroutine). done() runs as it ends.
local function Move(self, duration, at, toward, done)
	self:FaceTowards(toward)
	self:Scramble({ duration = duration, at = at, jumps = true, done = function()
		self.NSLeapt = true
		if done then done() end
	end })
end

-- Jumps onto the ledge along nextsoldier.locomotion.leap's arc (Move): if the way straight up to the arc's top and
-- across to its landing is clear (the arc stays inside that, and clears
-- the lip), else it stays.
function ENT:CustomClimbing(ledge)
	local from = self:GetPos()
	local mins, maxs = self:GetCollisionBounds()
	-- from step height up: a sloped floor is no wall
	local hull = {
		mins = Vector(mins.x + LEAP_INSET, mins.y + LEAP_INSET, self.loco:GetStepHeight()),
		maxs = maxs - Vector(LEAP_INSET, LEAP_INSET, LEAP_INSET),
	}
	local function Clear(a, b)
		hull.start = a
		return not self:TraceHull(b - a, hull).Hit
	end
	-- and its body fits where it lands, from step height up as the rest (a
	-- slope under it is no wall): a ledge that is a thin plate's edge (a
	-- stage over open space) would leave it set inside the plate
	local function Fits(p) return Clear(p, p) end
	local land = Leap.Arc(from, ledge, 1)
	land = Vector(land.x, land.y, land.z)
	local top = Vector(from.x, from.y, land.z)
	if not (Clear(from, top) and Clear(top, land) and Fits(land)) then
		self.NSLeapRetry = CurTime() + LEAP_RETRY
		return
	end
	Move(self, Leap.DURATION, function(t)
		local p = Leap.Arc(from, ledge, t)
		return Vector(p.x, p.y, p.z)
	end, ledge, function() PathAgain(self) end)
end

-- A vault over what stands toward dir (flat, of unit length) along
-- nextsoldier.locomotion.leap's arc: when the obstacle's top is no higher than it
-- climbs (ClimbLedgesMaxHeight), the floor beyond is on the nav mesh no
-- farther down than it falls (the death drop), and its hull clears the
-- way up, over and down (Leap.VaultFits). The plan, { from, top, land },
-- or nil and why there is no way over.
function ENT:NSVaultPlan(dir)
	local from = self:GetPos()
	-- what it collides with here: a players' map's player clips too (the
	-- rail along a walkway a bullet passes), which MASK_NPCSOLID misses
	local mask = Host.current:SolidMask()
	local mins, maxs = self:GetCollisionBounds()
	local step = self.loco:GetStepHeight()
	local hull = {
		mins = Vector(mins.x + LEAP_INSET, mins.y + LEAP_INSET, step),
		maxs = maxs - Vector(LEAP_INSET, LEAP_INSET, LEAP_INSET),
	}
	-- nil when the hull passes from a to b, else what it hit
	local function Sweep(a, b)
		return util.TraceHull({ start = a, endpos = b, mins = hull.mins, maxs = hull.maxs, mask = mask, filter = self })
	end
	local function Hits(a, b)
		local tr = Sweep(a, b)
		if not tr.Hit then return nil end
		return tr.HitWorld and "the map" or tostring(tr.Entity)
	end
	local blocked = Sweep(from, from + dir * VAULT_REACH)
	if not blocked.Hit then return nil, "nothing in the way" end
	-- the obstacle's face, and its top: the highest point of it above a
	-- step and within reach, over TOP_SCAN past the face, each line down
	-- from under whatever hangs above (a ceiling, a pipe)
	local face = from + dir * (blocked.Fraction * VAULT_REACH + maxs.x)
	local reach = self.ClimbLedgesMaxHeight
	local top
	for d = -LEAP_INSET, TOP_SCAN, TOP_SCAN_STEP do
		local p = face + dir * d
		local floorStep, ceiling = p + Vector(0, 0, step), p + Vector(0, 0, reach + 1)
		-- over the obstacle the line up starts inside it: down from reach
		local up = util.TraceLine({ start = floorStep, endpos = ceiling, mask = mask, filter = self })
		local start = (up.Hit and not up.StartSolid) and up.HitPos - Vector(0, 0, 1) or ceiling
		local down = util.TraceLine({ start = start, endpos = floorStep, mask = mask, filter = self })
		if down.Hit and not down.StartSolid and (not top or down.HitPos.z > top.z) then top = down.HitPos end
	end
	-- none (a rail whose bars no line found, a lip it cannot stand on):
	-- it hops anyway, as high as it jumps, rather than ram it, the floor
	-- beyond and the way over checked as for a vault
	if not top then top = face + Vector(0, 0, reach) end
	-- the floor beyond: the first lower than the top, landed on a hull's width in
	local drop = self.loco:GetDeathDropHeight()
	local land
	for d = VAULT_SCAN_STEP, VAULT_SCAN, VAULT_SCAN_STEP do
		local p = face + dir * d
		local floor = util.TraceLine({ start = Vector(p.x, p.y, top.z + Leap.CLEARANCE), endpos = Vector(p.x, p.y, from.z - drop - 1), mask = mask, filter = self })
		if floor.Hit and not floor.StartSolid and floor.HitPos.z < top.z - 1 then
			local q = p + dir * (maxs.x + VAULT_LAND_IN)
			local under = util.TraceLine({ start = Vector(q.x, q.y, top.z + Leap.CLEARANCE), endpos = Vector(q.x, q.y, from.z - drop - 1), mask = mask, filter = self })
			if under.Hit and not under.StartSolid then land = under.HitPos end
			break
		end
	end
	if not land then return nil, "no floor beyond" end
	if not Leap.VaultFits({ from = from, top = top, land = land, maxHeight = reach, maxDrop = drop }) then return nil, "too high or too far down" end
	if not IsValid(navmesh.GetNearestNavArea(land, false, VAULT_SCAN, true, true)) then return nil, "beyond is off the nav mesh" end
	local apex = Vector(from.x, from.y, top.z + Leap.CLEARANCE)
	local over = Leap.Vault(from, top, land, Leap.VAULT_CROSS)
	over = Vector(over.x, over.y, over.z)
	local up, across, down = Hits(from, apex), Hits(apex, over), Hits(over, land)
	if up then return nil, string.format("%s in the way up (%d above)", up, top.z + Leap.CLEARANCE - from.z) end
	if across then return nil, string.format("%s in the way across", across) end
	if down then return nil, string.format("%s in the way down (%d below)", down, from.z - land.z) end
	return { from = from, top = top, land = land }
end

-- A vault planned (NSVaultPlan), moved as CustomClimbing moves it (Move);
-- its path is planned again from where it lands.
function ENT:NSVaultRun(plan)
	local from, top, land = plan.from, plan.top, plan.land
	Move(self, Leap.VAULT_DURATION, function(t)
		local p = Leap.Vault(from, top, land, t)
		return Vector(p.x, p.y, p.z)
	end, land, function()
		local path = self:GetPath()
		if IsValid(path) then path:Invalidate() end
	end)
end

-- Its path held up by an obstacle it cannot stand on (a railing, where
-- its route drops to the floor beyond, as a player jumps it), it vaults
-- it toward its path's next goal (NSVaultPlan). Not again for LEAP_RETRY
-- after finding no way over. Whether it vaulted.
function ENT:NSVault()
	if CurTime() < (self.NSLeapRetry or 0) then return false end
	self.NSLeapRetry = CurTime() + LEAP_RETRY
	local path = self:GetPath()
	if not IsValid(path) then return false end
	local dir = path:GetCurrentGoal().pos - self:GetPos()
	dir.z = 0
	if dir:Length2DSqr() < 1 then return false end
	local plan = self:NSVaultPlan(dir:GetNormalized())
	if not plan then return false end
	self.NSLeapRetry = nil
	self:NSVaultRun(plan)
	return true
end

-- The orders' hop when stuck (features.aiwar.ns_behaviors' Unstick, through
-- the soldier port's Hop): toward p, a vault if one fits, else a plain hop
-- (a soldier hopping beats one ramming a wall), run at its next step
-- (NSSteer). NSHopWhy says why no vault fitted, for the AI war's report.
-- Whether it hops: always, but at p itself.
function ENT:NSHop(p)
	local dir = p - self:GetPos()
	dir.z = 0
	if dir:Length2DSqr() < 1 then return false end
	dir:Normalize()
	local vault, why = self:NSVaultPlan(dir)
	self.NSHopPlan = vault or { dir = dir }
	self.NSHopWhy = why
	return true
end

-- A plain hop the way dir points: up as high as it climbs, HOP_SPEED across.
function ENT:NSHopPlain(dir)
	local up = math.sqrt(2 * self.loco:GetGravity() * self.ClimbLedgesMaxHeight)
	self.loco:Jump()
	self.loco:SetVelocity(dir * HOP_SPEED + Vector(0, 0, up))
end

-- The hop asked for (NSHop), run at its next step: what became of it, or nil for
-- none asked.
function ENT:NSTakeHop()
	local plan = self.NSHopPlan
	if not plan then return nil end
	self.NSHopPlan = nil
	if plan.dir then
		self:NSHopPlain(plan.dir)
		return "hopped"
	end
	self:NSVaultRun(plan)
	return "vaulted"
end

function ENT:FaceTowards(target)
	if isentity(target) then target = target:GetPos() end
	self.loco:FaceTowards(target)
end

function ENT:IsMoving() return self.loco:GetVelocity():Length2DSqr() > 1 end
function ENT:Jump() self.loco:Jump() end
function ENT:GetStepHeight() return self.loco:GetStepHeight() end
function ENT:GetDeathDropHeight() return self.loco:GetDeathDropHeight() end
function ENT:IsOnGround() return self.loco:IsOnGround() end

-------------------------------------------------------------------------------
-- Body (IBody): weapons held, scale, posture

function ENT:GiveWeapon(class)
	local weapon = ents.Create(class)
	if not IsValid(weapon) then return nil end
	weapon:SetPos(self:GetPos())
	weapon:Spawn()
	-- spawned, a weapon lies ready to be picked up (a physics object and a
	-- pickup trigger): held, it has neither, follows its holder's hand
	-- (bonemerged) and stops no bullet, its holder's or anyone's
	weapon:PhysicsDestroy()
	weapon:SetMoveType(MOVETYPE_NONE)
	weapon:SetSolid(SOLID_NONE)
	weapon:SetTrigger(false)
	weapon:SetOwner(self)
	weapon:SetParent(self)
	weapon:SetLocalPos(vector_origin)
	weapon:SetLocalAngles(angle_zero)
	weapon:AddEffects(EF_BONEMERGE)
	weapon:SetNoDraw(true)
	self.nsWeapons[class] = weapon
	local stats = weapon.SoldierDamage and weapon or Weapons.STATS[class]
	if stats then self.nsMagazines[weapon] = Weapons.Magazine(stats) end
	return weapon
end

-- A weapon a soldier holds is no one else's to pick up.
hook.Add("PlayerCanPickupWeapon", "base_nextsoldier", function(_, weapon)
	local holder = weapon:GetOwner()
	if IsValid(holder) and Bots[holder] then return false end
end)

-- No longer one of the live bots others' noises reach.
function ENT:OnRemove() Bots[self] = nil end

-- DrGBase's helpers our code uses: fn(self, ...) after delay seconds, while
-- it is valid; a hull or line from data.start (else where it stands) along
-- offset, its own hull, solid mask and itself filtered unless data says.
function ENT:Timer(delay, fn, ...)
	local args = { ... }
	timer.Simple(delay, function() if IsValid(self) then fn(self, unpack(args)) end end)
end

function ENT:TraceHull(offset, data)
	data = data or {}
	local start = data.start or self:GetPos()
	return util.TraceHull({ start = start, endpos = start + offset, mins = data.mins or self.nsHullMins,
		maxs = data.maxs or self.nsHullMaxs, mask = data.mask or self:GetSolidMask(), filter = data.filter or self })
end

function ENT:TraceLine(offset, data)
	data = data or {}
	local start = data.start or self:GetPos()
	return util.TraceLine({ start = start, endpos = start + offset, mask = data.mask or self:GetSolidMask(),
		filter = data.filter or self })
end

-- Its weapons by class, as DrGBase's contract has them.
function ENT:GetWeapons()
	local held = {}
	for class, weapon in pairs(self.nsWeapons) do
		if IsValid(weapon) then held[class] = weapon end
	end
	return held
end

function ENT:GetActiveWeapon() return self.nsActive end

function ENT:SelectWeapon(weapon)
	if isstring(weapon) then weapon = self.nsWeapons[weapon] end
	if not IsValid(weapon) or weapon == self.nsActive then return end
	local old = self.nsActive
	if IsValid(old) then old:SetNoDraw(true) end
	weapon:SetNoDraw(false)
	self.nsActive = weapon
	self:OnWeaponChange(old, weapon)
	self:ReadRanges()
end

function ENT:RemoveWeapon(class)
	local weapon = self.nsWeapons[class]
	self.nsWeapons[class] = nil
	if weapon == self.nsActive then self.nsActive = nil end
	if IsValid(weapon) then weapon:Remove() end
end

function ENT:SetScale(scale) self:SetModelScale(scale) end

-- Posture (IBody's): crouched, the hull a crouching player's.
function ENT:IsCrouching() return self.nsCrouching == true end

function ENT:SetCrouching(crouching)
	crouching = crouching == true
	if crouching == self:IsCrouching() then return end
	self.nsCrouching = crouching
	local hull = self.nsHullMaxs
	self:SetCollisionBounds(self.nsHullMins, Vector(hull.x, hull.y, crouching and CROUCH_HEIGHT or hull.z))
end

-- The hold type it carries its weapon in, as its acts are chosen.
local function HoldOf(self)
	local weapon = self:GetActiveWeapon()
	local hold = IsValid(weapon) and weapon:GetHoldType() or HOLD_DEFAULT
	if not self:HasEnemy() then hold = CALM_HOLDS[hold] or hold end
	return hold
end

-- The act its model plays for this phase of a jump (nextsoldier.body.jump), holding
-- what it holds; nil for a model with none.
function ENT:JumpAct(phase)
	local name = JumpActs.Pick(HoldOf(self), phase, function(candidate)
		local act = _G[candidate]
		return act ~= nil and self:SelectWeightedSequence(act) >= 0
	end)
	return name and _G[name]
end

-- The sequence of that act, or nil.
function ENT:JumpSequence(phase)
	local act = self:JumpAct(phase)
	return act and self:SelectWeightedSequence(act)
end

-- Whether its feet off the ground are a jump: a class says when they are not.
function ENT:PlaysJump() return true end

-- What a body plays in the air: its jump's start at first, then the fall, off the
-- ground AIRBORNE or more (a step's bump is no jump), or in a scramble that jumps.
local function AirAct(self, scramble)
	local now = CurTime()
	local since
	if scramble then
		if not scramble.jumps then return nil end
		since = scramble.began
	elseif self.loco:IsOnGround() or not self:PlaysJump() then
		self.nsAirSince = nil
		return nil
	else
		self.nsAirSince = self.nsAirSince or now
		since = self.nsAirSince
		if now - since < AIRBORNE then return nil end
	end
	return self:JumpAct(now - since < JUMP_START_TIME and JumpActs.START or JumpActs.FLOAT)
end

-- Its hold type's act named prefix .. HOLD (ACT_HL2MP_RUN_AR2; calm, its
-- CALM_HOLDS one), or, for the
-- plain hold or one the model has no act of, the plain hold's (prefix
-- without its last _: ACT_HL2MP_RUN).
function ENT:HoldAct(prefix)
	local hold = HoldOf(self)
	local plain = prefix:sub(1, -2)
	local suffix = HOLD_ACT_NAMES[hold]
	if suffix == false then return _G[plain] end
	return _G[prefix .. (suffix or hold:upper())] or _G[plain]
end

-- Its animation each tick: a scramble's, its jump in the air, the class's
-- (OnUpdateAnimation -> act, rate), else its own; moving, its feet keep to its speed. A death sequence plays
-- out alone.
function ENT:BodyUpdate()
	if self.nsDeathSequence then
		self:FrameAdvance()
		return
	end
	self:AimUpdate()
	local scramble = self.nsScramble
	local act, rate
	if scramble and scramble.act then
		act, rate = scramble.act, scramble.rate
	else
		act, rate = AirAct(self, scramble), 1
		if act == nil then act, rate = self:OnUpdateAnimation() end
		if act == nil then act, rate = self:DefaultAnimation() end
	end
	if self:GetActivity() ~= act then self:StartActivity(act) end
	if rate then self:SetPlaybackRate(rate) end
	if self:IsMoving() then self:BodyMoveXY() else self:FrameAdvance() end
end

-- Its upper body aims at the enemy in sight (the model's aim_yaw and
-- aim_pitch, which hold them to their ranges) while it turns to it, as
-- TF2's body aims its head apart from its legs; with none, straight ahead.
function ENT:AimUpdate()
	local enemy = self:GetEnemy()
	local yaw, pitch = 0, 0
	local fighting = enemy ~= nil and self.nsVision:Visible(enemy)
	if fighting then
		local aim = (enemy:WorldSpaceCenter() - self:GetEyePosition()):Angle()
		yaw = math.NormalizeAngle(aim.y - self:GetAngles().y)
		pitch = math.NormalizeAngle(aim.p)
	end
	self:SetPoseParameter("aim_yaw", yaw)
	self:SetPoseParameter("aim_pitch", pitch)
	if fighting ~= self.nsFighting then
		self.nsFighting = fighting
		self:SetNW2Bool("NSFighting", fighting)
	end
end

-- Its head looks at pos for seconds unless it fights (the clients turn it:
-- nextsoldier.body.gaze), if the head turns that far; urgent, it snaps there.
function ENT:LookAt(pos, seconds, urgent)
	self:SetNW2Vector("NSGaze", pos)
	self:SetNW2Float("NSGazeUntil", CurTime() + seconds)
	self:SetNW2Bool("NSGazeUrgent", urgent == true)
end

-- Its own animation: a profile's IdleAnimation, WalkAnimation and
-- RunAnimation when it has them (a vortigaunt), else a player model's acts
-- for its hold type, crouched or standing, idle, walking or running.
function ENT:DefaultAnimation()
	local speed = self.loco:GetVelocity():Length2D()
	if self.IdleAnimation then
		if speed > self.WalkSpeed + RUN_OVER_WALK then return self.RunAnimation, 1 end
		if speed > 1 then return self.WalkAnimation, 1 end
		return self.IdleAnimation, 1
	end
	if self:IsCrouching() then
		return self:HoldAct(speed > 1 and "ACT_HL2MP_WALK_CROUCH_" or "ACT_HL2MP_IDLE_CROUCH_"), 1
	end
	if speed > self.WalkSpeed + RUN_OVER_WALK then return self:HoldAct("ACT_HL2MP_RUN_"), 1 end
	if speed > 1 then return self:HoldAct("ACT_HL2MP_WALK_"), 1 end
	return self:HoldAct("ACT_HL2MP_IDLE_"), 1
end

-------------------------------------------------------------------------------
-- Vision (IVision): hearing, range, being no one's target

function ENT:IsDeaf() return self.nsDeaf == true end
function ENT:GetHearingCoefficient() return self:IsDeaf() and 0 or 1 end

function ENT:GetRangeTo(target)
	if isentity(target) then target = target:GetPos() end
	return self:GetPos():Distance(target)
end

function ENT:SetNoTarget(none)
	if none then self:AddFlags(FL_NOTARGET) else self:RemoveFlags(FL_NOTARGET) end
end

-------------------------------------------------------------------------------
-- Intention (IIntention): the enemy, AI on or off

function ENT:GetEnemy() return IsValid(self.nsEnemy) and self.nsEnemy or nil end
function ENT:HasEnemy() return self:GetEnemy() ~= nil end
function ENT:SetAIDisabled(disabled) self.nsAIDisabled = disabled == true end
function ENT:IsAIDisabled() return self.nsAIDisabled == true end

-- The class's ranges (which OnWeaponChange may set), read again as its
-- weapon changes.
function ENT:ReadRanges()
	self.nsRanges = Intention.Ranges({
		reach = self.ReachEnemyRange, avoid = self.AvoidEnemyRange, range = self.RangeAttackRange, melee = self.MeleeAttackRange,
	})
end

-- A look around: the hostile entities (its relations' D_HT and D_FR) in its
-- field of view, near it, or that just hurt it, in a clear line, to its
-- vision; vision's events raise the class's hooks.
-- Where it looks from: its model's eyes, else a player's eye height (a
-- NextBot's EyePos is its hips).
function ENT:GetEyePosition()
	local attachment = self:LookupAttachment("eyes")
	if attachment and attachment > 0 then return self:GetAttachment(attachment).Pos end
	return self:GetPos() + Vector(0, 0, self:IsCrouching() and CROUCH_EYE_HEIGHT or EYE_HEIGHT)
end

-- Whether a known enemy is still there to fight.
local function Alive(ent) return IsValid(ent) and ent:Health() > 0 end

-- Whether the line from eye to point reaches other (or nothing).
local function Clear(eye, point, self, other)
	local tr = util.TraceLine({ start = eye, endpos = point, mask = MASK_SHOT, filter = self })
	return not tr.Hit or tr.Entity == other
end

-- Another's eyes: a soldier's own, else its EyePos.
local function EyesOf(other)
	if other.GetEyePosition then return other:GetEyePosition() end
	return other:EyePos()
end

-- A look around: its centre or its eyes in a clear line, as TF2's vision
-- tries more than one point of what it looks at.
function ENT:VisionUpdate(now)
	local eye, facing = self:GetEyePosition(), self:GetForward()
	local seen = {}
	for _, other in ipairs(Combatants(now)) do
		if other ~= self and IsValid(other) and other:Health() > 0 and not other:IsFlagSet(FL_NOTARGET)
			and other:GetPos():DistToSqr(eye) <= SIGHT_RANGE * SIGHT_RANGE then
			local disposition = self:Disposition(other)
			if disposition == D_HT or disposition == D_FR then
				local center = other:WorldSpaceCenter()
				local to = center - eye
				local distance = to:Length()
				-- its enemy it looks for wherever it walks, as TF2's head aims at its threat
				if (distance <= NOTICE_NEAR or other == self.nsEnemy or other == self.nsAttacker or (self.nsNoticed[other] or 0) > now
					or to:Dot(facing) >= FOV_COS * distance)
					and (Clear(eye, center, self, other) or Clear(eye, EyesOf(other), self, other)) then
					seen[other] = other:GetPos()
				end
			end
		end
	end
	self:VisionTell(self.nsVision:Update(now, seen, self.nsBetter))
end

-- Vision's events as the class's hooks: sight, and the contact as its enemy.
function ENT:VisionTell(events)
	for _, event in ipairs(events) do
		if event.kind == Vision.SIGHT then
			self:OnSpotted(event.handle)
		elseif event.kind == Vision.LOST_SIGHT then
			self:OnLost(event.handle)
		elseif event.kind == Vision.CONTACT then
			local old = self:GetEnemy()
			self.nsEnemy = event.handle
			-- a first enemy is new; another after it is a change (DrGBase's split)
			if old then self:OnEnemyChange(old, event.handle) else self:OnNewEnemy(event.handle) end
		elseif event.kind == Vision.CONTACT_LOST then
			self.nsEnemy = nil
			self:OnLastEnemy(event.handle)
		end
	end
end

-- Which of two threats is the more dangerous: the class's OnFetchEnemy,
-- then the higher priority, then the nearer (nextsoldier.behavior.intention).
function ENT:IsMoreDangerous(a, b)
	return Intention.Better(a, b,
		function(x, y) return self:OnFetchEnemy(x, y) end,
		function(x) local _, priority = self:Disposition(x) return priority end,
		function(x) return self:GetRangeTo(x) end)
end

function ENT:IsMeleeWeapon(weapon)
	return IsValid(weapon) and MELEE_HOLDS[weapon:GetHoldType()] == true
end

-- Each tick with the AI on: a look every LOOK_INTERVAL; with no enemy, the
-- idle hook; with one, the stage of fighting it by its distance (the
-- class's hook, else the base's own: chase it, back away, or face it), then
-- an attack if it is in sight and in range (the class's hook, else the
-- body's).
function ENT:IntentionUpdate(interval)
	local now = CurTime()
	if now >= self.nsNextLook then
		self.nsNextLook = now + LOOK_INTERVAL
		-- the removed and the dead are forgotten before any is ranked
		self:VisionTell(self.nsVision:Prune(Alive, self.nsBetter))
		self:VisionUpdate(now)
	end
	local enemy = self:GetEnemy()
	if not enemy then
		self:OnIdle()
		return
	end
	local ranges = self.nsRanges
	local distance = self:GetRangeTo(enemy)
	local stage = Intention.Stage(distance, ranges)
	if stage == Intention.CHASE then
		if not self:OnChaseEnemy(enemy) then self:FollowPath(enemy) end
	elseif stage == Intention.AVOID then
		if not self:OnAvoidEnemy(enemy) then
			local away = self:GetPos() + (self:GetPos() - enemy:GetPos()):GetNormalized() * ranges.avoid
			self:FollowPath(away)
		end
	elseif not self:OnIdleEnemy(enemy) then
		self:FaceTowards(enemy)
	end
	local weapon = self:GetActiveWeapon()
	local visible = self.nsVision:Visible(enemy) and self.nsVision:Recognized(enemy, now)
	local attack = Intention.Attack(distance, ranges, visible, self:IsMeleeWeapon(weapon))
	if attack == Intention.MELEE then
		if not self:OnMeleeAttack(enemy, weapon) then self:MeleeAttack(enemy, weapon) end
	elseif attack == Intention.RANGED then
		if not self:OnRangeAttack(enemy) then self:RangeAttack(enemy, weapon) end
	end
end

-- The body's own shot (TF2's split: the intention decides, the body fires):
-- one of its gun's (nextsoldier.body.weapons) when the magazine is ready, from
-- the muzzle, its bullets (Shoot) or its projectile (Throw), with the gun's
-- sound, flash and the hold type's firing gesture. A weapon that is not one
-- of NextSoldier's guns is not fired.
function ENT:RangeAttack(enemy, weapon)
	if not IsValid(weapon) then return end
	local magazine = self.nsMagazines[weapon]
	if not magazine then return end
	local now = CurTime()
	if not magazine:Ready(now) then return end
	self:FaceTowards(enemy)
	local muzzle = weapon:LookupAttachment("muzzle")
	local src = muzzle and muzzle > 0 and weapon:GetAttachment(muzzle).Pos or self:GetEyePosition()
	if not self:LineOfFire(src, enemy, weapon) then return end
	magazine:Fire(now)
	local stats = magazine.stats
	if Weapons.Stat(stats, "projectile") then
		self:Throw(stats, src, enemy)
	else
		self:Shoot(stats, src, enemy, weapon)
	end
	weapon:EmitSound(Weapons.Stat(stats, "sound"))
	weapon:MuzzleFlash()
	self:AddGesture(self:HoldAct("ACT_HL2MP_GESTURE_RANGE_ATTACK_"), true)
	-- the last round: it reloads, the hold type's reload played
	if magazine:Reloading(now) then self:AddGesture(self:HoldAct("ACT_HL2MP_GESTURE_RELOAD_"), true) end
end

-- Whether a shot from src reaches the enemy before anything else (a small
-- hull, as DrGBase's soldiers check before firing): a wall or a teammate in
-- the way holds the shot.
local FIRE_HULL = Vector(5, 5, 5)
function ENT:LineOfFire(src, enemy, weapon)
	local tr = util.TraceHull({ start = src, endpos = enemy:WorldSpaceCenter(), mins = -FIRE_HULL, maxs = FIRE_HULL,
		mask = MASK_SHOT, filter = { self, weapon } })
	return tr.Entity == enemy
end

-- How fast something moves: a NextBot's locomotion's, else its own.
local function VelocityOf(ent)
	if ent.loco then return ent.loco:GetVelocity() end
	return ent:GetVelocity()
end

-- A gun's projectile (HL2's crossbow's bolt), aimed where the enemy will be
-- (Weapons.Lead), owned by the soldier so the hit is its.
function ENT:Throw(stats, src, enemy)
	local projectile = Weapons.Stat(stats, "projectile")
	local aim = Weapons.Lead(src, enemy:WorldSpaceCenter(), VelocityOf(enemy), projectile.speed)
	local dir = (Vector(aim.x, aim.y, aim.z) - src):GetNormalized()
	local thrown = ents.Create(projectile.class)
	thrown:SetPos(src)
	thrown:SetAngles(dir:Angle())
	thrown:SetOwner(self)
	thrown:Fire("SetDamage", tostring(Weapons.Stat(stats, "damage")))
	thrown:Spawn()
	thrown:SetVelocity(dir * projectile.speed)
end

-- A gun's bullets at the enemy's centre within its spread.
function ENT:Shoot(stats, src, enemy, weapon)
	local spread = math.tan(math.rad(Weapons.Stat(stats, "spread") / 2))
	self:FireBullets({
		Attacker = self,
		Damage = Weapons.Stat(stats, "damage"),
		Num = Weapons.Stat(stats, "bullets"),
		Src = src,
		Dir = (enemy:WorldSpaceCenter() - src):GetNormalized(),
		Spread = Vector(spread, spread, 0),
		Tracer = 1,
		TracerName = Weapons.Stat(stats, "tracer"),
		IgnoreEntity = weapon,
		-- struck by its gun, as a player's shot is (the kill feed's icon)
		Callback = function(_, _, dmg) dmg:SetInflictor(weapon) end,
	})
end

-- A melee strike is the class's (OnMeleeAttack): the base has none of its own.
function ENT:MeleeAttack(enemy, weapon) end

-------------------------------------------------------------------------------
-- The hooks' defaults (nextsoldier.base's HOOKS), for a class that does not
-- define one or calls this one through.

function ENT:CustomInitialize() end
function ENT:CustomThink() end
function ENT:OnIdle() end
function ENT:OnNewEnemy(enemy) end
function ENT:OnEnemyChange(old, new) end
function ENT:OnLastEnemy(enemy) end
function ENT:OnFetchEnemy(a, b) return nil end
function ENT:OnChaseEnemy(enemy) return false end
function ENT:OnAvoidEnemy(enemy) return false end
function ENT:OnIdleEnemy(enemy) return false end
function ENT:OnRangeAttack(enemy) return false end
function ENT:OnMeleeAttack(enemy, weapon) return false end
function ENT:ShouldRun() return false end
function ENT:OnSpotted(ent) end
-- A noise heard (DrGBase's OnSound: sound = { Entity, Pos, SoundLevel,
-- Volume }): a hostile source is known where it was heard, noticed for its
-- next looks wherever it stands, and one with no enemy turns toward it.
function ENT:OnSound(ent, sound)
	if not IsValid(ent) then return end
	local disposition = self:Disposition(ent)
	if disposition ~= D_HT and disposition ~= D_FR then return end
	local now = CurTime()
	self.nsNoticed[ent] = now + HEARD_NOTICE
	if not self:HasEnemy() then self:FaceTowards(sound.Pos) end
	-- known where it was heard, as TF2's OnSound adds a known entity
	self:VisionTell(self.nsVision:Hear(now, ent, sound.Pos, self.nsBetter))
end
function ENT:OnLost(ent) end

-- The path's cost by default: the length of each link (or the ladder it
-- climbs), with the class's OnComputePath added (-1 refuses the link, as
-- DrGBase's contract has it; ladder, a third argument, when it climbs one).
-- A link rising past its jump or falling past its death drop is refused: the
-- mesh links a slope up to a deck beside it that no body climbs.
-- Lua traces the engine's collision hull through each destination and
-- opening, then passes that verdict to the native or Lua-twin cost function.
function ENT:GetPathGenerator(cost)
	local clearance = Host.current:PathClearance(self)
	local limits = { jumpHeight = self.loco:GetJumpHeight(), deathDropHeight = self.loco:GetDeathDropHeight() }
	cost = cost or function(area, fromArea, ladder, elevator, length, fits)
		if not IsValid(fromArea) then return 0 end
		if fits == false then return -1 end
		if not IsValid(ladder) and not Walkable(fromArea:ComputeAdjacentConnectionHeightChange(area), limits) then return -1 end
		local extra = self:OnComputePath(fromArea, area, ladder)
		if extra ~= nil and extra < 0 then return -1 end
		local link = IsValid(ladder) and ladder:GetLength()
			or length and length > 0 and length or area:GetCenter():Distance(fromArea:GetCenter())
		return fromArea:GetCostSoFar() + link + (extra or 0)
	end
	return function(area, fromArea, ladder, elevator, length)
		local fits
		if IsValid(fromArea) then
			fits = clearance:Area(area)
			if fits and not IsValid(ladder) then fits = clearance:Link(fromArea, area) end
		end
		return cost(area, fromArea, ladder, elevator, length, fits)
	end
end
function ENT:OnComputePath(from, to, ladder) return nil end
function ENT:OnWeaponChange(old, new) end
function ENT:OnUpdateAnimation() return nil end
function ENT:OnAnimEvent(event, ...) end
function ENT:OnTakeDamage(dmg, hitgroup) return nil end
function ENT:OnTraceAttack(dmg, dir, trace) self.nsHitGroup = trace.HitGroup end
function ENT:OnDealtDamage(victim, dmg) end
function ENT:OnDeath(dmg) end

-- What a soldier deals, scaled by its class's OnDealtDamage (a number, else
-- as dealt).
hook.Add("EntityTakeDamage", "base_nextsoldier_dealt", function(victim, dmg)
	local attacker = dmg:GetAttacker()
	if not (IsValid(attacker) and attacker.IsNextSoldier) then return end
	local scale = attacker:OnDealtDamage(victim, dmg)
	if isnumber(scale) then dmg:ScaleDamage(scale) end
end)
