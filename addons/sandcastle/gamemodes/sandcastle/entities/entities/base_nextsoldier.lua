-- base_nextsoldier: NextSoldier's own NextBot base (issue #8 L1,
-- docs/base-nextsoldier-plan.md), implementing the interface our code keeps
-- of DrGBase's (nextsoldier.base) from scratch, organised as TF2's NextBot
-- in source-sdk-2013: the bot (life and relations) and its locomotion,
-- body, vision and intention, each a model or a thin binding to GMod's
-- NextBot, updated every tick from BehaveUpdate. No coroutine runs: TF2
-- runs none per bot.
--
-- A soldier class sets ENT.Base = "base_nextsoldier", its fields (the
-- profile: Models, Weapons, Factions, SpawnHealth, speeds and ranges) and
-- defines the hooks it wants (nextsoldier.base's HOOKS); the base raises
-- them and keeps its own defaults for the ones a class calls through.
AddCSLuaFile()

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"
ENT.PrintName = "NextSoldier"
ENT.Spawnable = false
ENT.IsNextSoldier = true

-- The profile's defaults (nextsoldier.base's FIELDS).
ENT.Models = { "models/player/kleiner.mdl" }
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
-- A path is computed again for a goal moved this far, or this old.
local REPATH_DISTANCE, REPATH_AGE = 64, 2
local PATH_LOOKAHEAD = 300
-- A path is followed every tick while its intention asked for it this
-- recently (FollowPath): its intention runs at the engine's NextBot rate,
-- slower with many bots, its locomotion every tick, as TF2's does.
local FOLLOW_HOLD = 0.5
-- A path segment's type (GMod's PathFollower goals, NextBot's SegmentType).
local CLIMB_UP = 2
-- A climb begins this near the ledge's foot.
local CLIMB_REACH = 48
-- It steps and jumps as a TF2 player (games.gameplay.movement): a stair
-- step, and as high as a crouch jump reaches (it does not tuck its legs).
local Movement = gameplay.movement
local STEP_HEIGHT, JUMP_HEIGHT = Movement.TF2.stepHeight, Movement.CrouchJump(Movement.TF2)
-- How fast it gets up to speed and stops, and turns (degrees a second).
local ACCELERATION, DECELERATION, MAX_YAW_RATE = 1000, 1000, 250

if CLIENT then
	-- Its head turns to what interests it apart from its aim (WS.GazeUpdate),
	-- here on the client and only while it is drawn: the server says only
	-- whether it fights (NSFighting) and where it was told to look, until
	-- when, and whether at once (NSGaze, NSGazeUntil, NSGazeUrgent: LookAt).
	-- Teammate players are looked at. Fighting, or told urgently, the head
	-- snaps.
	function ENT:Draw()
		local hint = self:GetNW2Float("NSGazeUntil", 0) > CurTime() and self:GetNW2Vector("NSGaze") or nil
		local fighting = self:GetNW2Bool("NSFighting")
		local urgent = fighting or (hint ~= nil and self:GetNW2Bool("NSGazeUrgent"))
		WS.GazeUpdate(self, self:GetAngles().y, fighting, hint, self:GetNW2Int("ws_team", TEAM_UNASSIGNED), urgent)
		self:DrawModel()
	end
	return
end

local Relations = nextsoldier.relations
local Gaze = nextsoldier.gaze
-- A point looked at along a path, at eye height.
local LOOK_HEIGHT = Vector(0, 0, 64)
-- The live bots on this base, which others' noises reach (DrGBase keeps
-- its own: DrGBase.GetNextbots).
WS.NextSoldierBots = WS.NextSoldierBots or setmetatable({}, { __mode = "k" })
local Vision = nextsoldier.vision
local Intention = nextsoldier.intention
local Weapons = nextsoldier.weapons
local Factions = WS.require("ws.factions")

-- Its sight: how far, how wide (the whole cone), and how often it looks
-- (TF2's IVision update), how soon it recognizes what it sees and how long
-- it remembers. Range and cone are near DrGBase's, which the war's orders
-- were tuned against.
local SIGHT_RANGE, FOV_COS = 15000, math.cos(math.rad(150 / 2))
local NOTICE_NEAR = 200
-- What any of them may look at: the players, NPCs and NextBots, gathered
-- once a COMBATANTS_EVERY seconds for every bot's looks.
local COMBATANTS_EVERY = 1
local combatants, combatantsAt = {}, -math.huge

local function Combatants(now)
	if now - combatantsAt < COMBATANTS_EVERY then return combatants end
	combatants, combatantsAt = {}, now
	for _, ent in ents.Iterator() do
		if ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot() then combatants[#combatants + 1] = ent end
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

-- Each team's faction, for a player's (a player's faction is its team's).
local function TeamFaction(team)
	for _, entry in ipairs(Factions.ALL) do
		if entry.team == team then return entry.faction end
	end
end

-- The factions another entity is in, for a disposition toward it.
local function FactionsOf(other)
	if other.nsRelations then return other.nsRelations:Factions() end
	if other:IsPlayer() then
		local faction = TeamFaction(WS.TeamOf(other))
		return faction and { faction } or {}
	end
	if other.GetFactions then return other:GetFactions() end
	return {}
end

-------------------------------------------------------------------------------
-- The bot: setup, life, relations

function ENT:Initialize()
	self:SetModel(self.Models[math.random(#self.Models)])
	self:SetHealth(self.SpawnHealth)
	self:SetMaxHealth(self.SpawnHealth)
	-- a profile's hull (its half width and height, as DrGBase's CollisionBounds), else a player's
	local bounds = self.CollisionBounds
	self.nsHullMins = bounds and Vector(-bounds.x, -bounds.y, 0) or HULL_MINS
	self.nsHullMaxs = bounds and Vector(bounds.x, bounds.y, bounds.z) or HULL_MAXS
	self:SetCollisionBounds(self.nsHullMins, self.nsHullMaxs)
	if self.BloodColor then self:SetBloodColor(self.BloodColor) end
	self.loco:SetStepHeight(STEP_HEIGHT)
	self.loco:SetJumpHeight(JUMP_HEIGHT)
	self.loco:SetDeathDropHeight(self.DeathDropHeight)
	self.loco:SetDesiredSpeed(self.WalkSpeed)
	self.loco:SetAcceleration(ACCELERATION)
	self.loco:SetDeceleration(DECELERATION)
	self.loco:SetMaxYawRate(MAX_YAW_RATE)
	-- an NPC to the map: a trigger flagged for NPCs (a spawn door's, which
	-- the AI war flags) sees it only so
	self:AddFlags(FL_NPC)
	self.nsAlive = true
	self.nsRelations = Relations.New({ default = self.DefaultRelationship or D_NU, ally = D_LI })
	for _, faction in ipairs(self.Factions) do self.nsRelations:Join(faction) end
	self.nsVision = Vision.New(VISION)
	self.nsBetter = function(a, b) return self:IsMoreDangerous(a, b) end
	self.nsNextLook = 0
	self.nsWeapons = {}
	self.nsMagazines = setmetatable({}, { __mode = "k" })
	self.nsNoticed = setmetatable({}, { __mode = "k" })
	WS.NextSoldierBots[self] = true
	self:ReadRanges()
	if #self.Weapons > 0 then self:SelectWeapon(self:GiveWeapon(self.Weapons[math.random(#self.Weapons)])) end
	self:CustomInitialize()
end

function ENT:IsAlive() return self.nsAlive == true end

-- The team it fights for: the one the war set (WS.SetTeamMember's ws_team),
-- which WS.TeamOf reads through Team as it does a player's.
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
function ENT:BehaveStart() self:Reset() end

function ENT:BehaveUpdate(interval)
	if not self:IsAlive() then return end
	self:CustomThink()
	if self:IsScrambling() then return end
	if self:IsAIDisabled() then return end
	self.loco:SetDesiredSpeed(self:ShouldRun() and self.RunSpeed or self.WalkSpeed)
	self:IntentionUpdate(interval)
end

-------------------------------------------------------------------------------
-- Locomotion (ILocomotion): the path followed, priced by the class

function ENT:GetPath() return self.nsPath end

-- The generic debug layer's behavior view. Classes with their own behavior
-- state can expose it through nsBehavior; AI-war soldiers supply their richer
-- action stack through WSNbDebugNpcs instead.
function ENT:NSDebugStack()
	local name = self.nsBehavior or self:GetClass()
	return self:GetClass(), {
		{ depth = 0, name = name, short = name },
	}
end

function ENT:NSDebugWatch(log)
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

	local Debug = WS.require("features.nbdebug.model")
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
		if path and path:IsValid() and CurTime() - (self.nsFollowedAt or 0) <= FOLLOW_HOLD then path:Update(self) end
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
-- done() }, its momentum stopped each step; nothing else moves it, and its
-- intention waits, until it ends.
function ENT:Scramble(motion)
	self.nsScramble = { duration = motion.duration, at = motion.at, done = motion.done, began = CurTime() }
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

-- A climb up its path's next goal, when the class climbs ledges, asks to
-- (OnStartClimbing) and begins one (CustomClimbing): whether it did.
function ENT:ClimbPathGoal(path)
	if not self.ClimbLedges then return false end
	local goal = path:GetCurrentGoal()
	if not goal or goal.type ~= CLIMB_UP then return false end
	local pos = self:GetPos()
	if (pos - goal.pos):Length2D() > CLIMB_REACH then return false end
	local height = goal.pos.z - pos.z
	if height > self.ClimbLedgesMaxHeight or not self:OnStartClimbing(goal.pos, height, false) then return false end
	self:CustomClimbing(goal.pos)
	return self:IsScrambling()
end

-- Follows a path to goal, computed again when the goal has moved or the path
-- has aged: "unreachable" (no path), "reached", "obstacle" (stuck against
-- something on its way) or "moving". A path made afresh (none, or for a
-- goal moved), not one merely aged, has it look PATH_LOOKAHEAD along its
-- new way a while (LookAt).
function ENT:FollowPath(goal, tolerance)
	if isentity(goal) then goal = goal:GetPos() end
	local path = self.nsPath
	local afresh = not (path and path:IsValid())
		or (self.nsPathGoal and self.nsPathGoal:DistToSqr(goal) > REPATH_DISTANCE * REPATH_DISTANCE)
	if afresh or path:GetAge() > REPATH_AGE then
		path = Path("Follow")
		path:SetMinLookAheadDistance(PATH_LOOKAHEAD)
		path:SetGoalTolerance(tolerance or 20)
		ComputeDebugPath(self, path, goal)
		self.nsPath, self.nsPathGoal = path, goal
		if not path:IsValid() then return "unreachable" end
		if afresh then self:LookAt(path:GetPositionOnPath(PATH_LOOKAHEAD) + LOOK_HEIGHT, Gaze.HINT_SECONDS) end
	end
	if self:ClimbPathGoal(path) then return "moving" end
	-- a taunt is played standing still (HoldStill)
	if CurTime() < (self.nsStillUntil or 0) then return "moving" end
	self.nsFollowedAt = CurTime()
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
	local stats = Weapons.STATS[class]
	if stats then self.nsMagazines[weapon] = Weapons.Magazine(stats) end
	return weapon
end

-- A weapon a soldier holds is no one else's to pick up.
hook.Add("PlayerCanPickupWeapon", "base_nextsoldier", function(_, weapon)
	local holder = weapon:GetOwner()
	if IsValid(holder) and WS.NextSoldierBots[holder] then return false end
end)

-- No longer one of the live bots others' noises reach.
function ENT:OnRemove() WS.NextSoldierBots[self] = nil end

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

-- Its hold type's act named prefix .. HOLD (ACT_HL2MP_RUN_AR2; calm, its
-- CALM_HOLDS one), or, for the
-- plain hold or one the model has no act of, the plain hold's (prefix
-- without its last _: ACT_HL2MP_RUN).
function ENT:HoldAct(prefix)
	local weapon = self:GetActiveWeapon()
	local hold = IsValid(weapon) and weapon:GetHoldType() or HOLD_DEFAULT
	if not self:HasEnemy() then hold = CALM_HOLDS[hold] or hold end
	local plain = prefix:sub(1, -2)
	local suffix = HOLD_ACT_NAMES[hold]
	if suffix == false then return _G[plain] end
	return _G[prefix .. (suffix or hold:upper())] or _G[plain]
end

-- Its animation each tick: the class's (OnUpdateAnimation -> act, rate),
-- else its own; moving, its feet keep to its speed. A death sequence plays
-- out alone.
function ENT:BodyUpdate()
	if self.nsDeathSequence then
		self:FrameAdvance()
		return
	end
	self:AimUpdate()
	local act, rate = self:OnUpdateAnimation()
	if act == nil then act, rate = self:DefaultAnimation() end
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
-- nextsoldier.gaze), if the head turns that far; urgent, it snaps there.
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
-- then the higher priority, then the nearer (nextsoldier.intention).
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
-- one of its gun's (nextsoldier.weapons) when the magazine is ready, from
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
	if stats.projectile then
		self:Throw(stats, src, enemy)
	else
		self:Shoot(stats, src, enemy, weapon)
	end
	weapon:EmitSound(stats.sound)
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
	local projectile = stats.projectile
	local aim = Weapons.Lead(src, enemy:WorldSpaceCenter(), VelocityOf(enemy), projectile.speed)
	local dir = (Vector(aim.x, aim.y, aim.z) - src):GetNormalized()
	local thrown = ents.Create(projectile.class)
	thrown:SetPos(src)
	thrown:SetAngles(dir:Angle())
	thrown:SetOwner(self)
	thrown:Fire("SetDamage", tostring(stats.damage))
	thrown:Spawn()
	thrown:SetVelocity(dir * projectile.speed)
end

-- A gun's bullets at the enemy's centre within its spread.
function ENT:Shoot(stats, src, enemy, weapon)
	local spread = math.tan(math.rad(stats.spread / 2))
	self:FireBullets({
		Attacker = self,
		Damage = stats.damage,
		Num = stats.bullets,
		Src = src,
		Dir = (enemy:WorldSpaceCenter() - src):GetNormalized(),
		Spread = Vector(spread, spread, 0),
		Tracer = 1,
		TracerName = stats.tracer,
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
-- The path's cost by default: the length of each link, with the class's
-- OnComputePath added (-1 refuses the link, as DrGBase's contract has it).
function ENT:GetPathGenerator()
	return function(area, fromArea, ladder, elevator, length)
		if not IsValid(fromArea) then return 0 end
		local extra = self:OnComputePath(fromArea, area)
		if extra ~= nil and extra < 0 then return -1 end
		local link = length and length > 0 and length or area:GetCenter():Distance(fromArea:GetCenter())
		return fromArea:GetCostSoFar() + link + (extra or 0)
	end
end
function ENT:OnComputePath(from, to) return nil end
function ENT:OnStartClimbing(ledge, height, down) return false end
function ENT:CustomClimbing(ledge) return false end
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
