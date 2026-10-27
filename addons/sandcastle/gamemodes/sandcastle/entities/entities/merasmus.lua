-- merasmus (CMerasmus): MERASMUS!, a halloween_base_boss bound to
-- features.haunting.merasmus, which holds every rule. This file implements his
-- port, flies him for the bomb rain (CMerasmusFlyingLocomotion, through
-- features.haunting.hover), plays the loop he floats with, forwards his props'
-- events to his Behavior, and networks the state his client effects follow
-- (C_Merasmus; the npc view draws them). pl_fifthcurve_event and
-- pl_rumble_event spawn him from a point_template (merasmus_triggered) and
-- Kill him at each round start.
AddCSLuaFile()

ENT.Base = "halloween_base_boss"
ENT.Type = "nextbot"
ENT.Spawnable = false
ENT.Variant = "features.haunting.merasmus"

-- C_Merasmus's networked flags.
function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Revealed")
	self:NetworkVar("Bool", 1, "AOEAttack")
	self:NetworkVar("Bool", 2, "Stunned")
end

if CLIENT then
	function ENT:Think()
		WS.Feature("npc"):UpdateMerasmus(self, {
			revealed = self:GetRevealed(),
			aoeAttack = self:GetAOEAttack(),
			stunned = self:GetStunned(),
		})
	end
	return
end

-- GMod looks up Entity and NextBot methods before the entity's own table,
-- so no port method here shares an engine method's name.
local Base = baseclass.Get("halloween_base_boss")

local STAFF_BODYGROUP = "staff"
local LINE_LEVEL = 95 -- SNDLVL_95dB, his voice lines' soundscripts'
local GROUND_PROBE = 2000 -- how far below him the flight looks for the ground
local NAV_BENEATH_LIMIT = 100 -- navmesh.GetNavArea's search below a player
local STEP_HEIGHT = 18 -- StepHeight, CollectSurroundingAreas' limits
local PREFER_CLASS = "func_nav_prefer"
local PLAYERS_ANY_TEAM = nil -- CollectPlayers: RED and BLU

-- One the boss timer did not spawn is the map's own: where the timer runs
-- (the boss_timer feature, loaded for his scenario), that stops it.
function ENT:Initialize()
	Base.Initialize(self)
	local configured = self.configured or {}
	if not configured.timerSpawned and WS.FeatureLoaded("boss_timer") then
		WS.Feature("boss_timer"):MapSpawned(self.Variant)
	end
	self.floatSound = CreateSound(self, WS.require(self.Variant).FLOAT_SOUND)
	self.floatSound:Play()
end

-- UpdateOnRemove: the behavior ends, then the model hides his bar, blows
-- the bomb heads and takes his props. One whose bind failed (ws_nextbot)
-- has neither model nor loop.
function ENT:OnRemove()
	if not self.npc then return Base.OnRemove(self) end
	self.floatSound:Stop()
	local state = self.npc:State()
	Base.OnRemove(self)
	WS.require(self.Variant).Removed(state, self)
end

-------------------------------------------------------------------------------
-- Flight (CMerasmusFlyingLocomotion): no collisions, he floats between the
-- areas at an altitude over the ground, turning at most 100 degrees a second.

local FlyingMotion = {}

function FlyingMotion.SetDesiredSpeed(self, u) end
function FlyingMotion.Approach(self, v) self.flight:Approach(v, self:GetPos()) end
function FlyingMotion.IsAttemptingToMove(self) return false end
function FlyingMotion.GetGroundSpeed(self) return self.flight:GetGroundSpeed() end

function FlyingMotion.GroundMotionVector(self)
	local v = self.flight:GetVelocity()
	v.z = 0
	return v:GetNormalized()
end

function FlyingMotion.FaceTowards(self, v)
	local angles = self:GetAngles()
	local step = self.flightYawRate * FrameTime()
	angles.y = angles.y + math.Clamp(math.AngleDifference((v - self:GetPos()):Angle().y, angles.y), -step, step)
	self:SetAngles(angles)
end

function FlyingMotion.Update(self, interval)
	local origin = self:GetPos()
	local ground = util.TraceLine({
		start = origin,
		endpos = origin - Vector(0, 0, GROUND_PROBE),
		mask = MASK_SOLID_BRUSHONLY,
		filter = self,
	})
	local _, move = self.flight:Step(interval, origin, ground.HitPos.z, true)
	self:SetPos(origin + move)
end

-------------------------------------------------------------------------------
-- Preferred areas: the nav areas inside the map's func_nav_prefer brushes
-- (CTFNavArea::HasFuncNavPrefer).

local function PreferBoxes()
	local boxes = {}
	for _, brush in ipairs(ents.FindByClass(PREFER_CLASS)) do
		local mins, maxs = brush:WorldSpaceAABB()
		boxes[#boxes + 1] = {
			mins = mins,
			maxs = maxs,
		}
	end
	return boxes
end

local function IsPreferred(area, boxes)
	local extent = area:GetExtentInfo()
	local lo, hi = extent.lo, extent.hi
	for _, box in ipairs(boxes) do
		if lo.x <= box.maxs.x and hi.x >= box.mins.x and lo.y <= box.maxs.y and hi.y >= box.mins.y
			and lo.z <= box.maxs.z + STEP_HEIGHT and hi.z >= box.mins.z - STEP_HEIGHT then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- His port (foundation.npc.merasmus.METHODS)

-- The Horsemann's: the master's points in order.
function ENT:ControlPoints() return baseclass.Get("headless_hatman").ControlPoints(self) end

-- A line everyone hears, wherever they are (SNDLVL_NONE).
function ENT:PlayHighPrioritySound(name) WS.BroadcastSoundscape(WS.TEAM_UNASSIGNED, name) end

-- A line those near hear, never over one he is already saying.
function ENT:PlayLowPrioritySound(name)
	self:EmitSound(name, LINE_LEVEL, PITCH_NORM, 1, CHAN_VOICE2, SND_DO_NOT_OVERWRITE_EXISTING_ON_CHANNEL)
end

function ENT:BroadcastGameSound(name) WS.BroadcastSoundscape(WS.TEAM_UNASSIGNED, name) end

function ENT:AddTimedGesture(act) return self:GetLayerDuration(self:AddGesture(act)) end
function ENT:SetStaff(n) self:SetBodygroup(self:FindBodygroupByName(STAFF_BODYGROUP), n) end
function ENT:AttachmentPosition(name) return self:GetAttachment(self:LookupAttachment(name)).Pos end

function ENT:DispatchParticleAttached(name, attachment)
	ParticleEffectAttach(name, PATTACH_POINT_FOLLOW, self, self:LookupAttachment(attachment))
end

function ENT:DispatchBeam(name, attachment, to)
	util.ParticleTracerEx(name, self:AttachmentPosition(attachment), to, false, self:EntIndex(), self:LookupAttachment(attachment))
end

function ENT:SetHidden(hidden) self:SetNoDraw(hidden) end
function ENT:SetCollidable(on) self:SetNotSolid(not on) end

function ENT:NetworkState(revealed, aoeAttack, stunned)
	self:SetRevealed(revealed)
	self:SetAOEAttack(aoeAttack)
	self:SetStunned(stunned)
end

function ENT:StartFlying()
	local Merasmus = WS.require(self.Variant)
	self.groundMotion = self.motion
	self.groundGravity = self.loco:GetGravity()
	self.flight = WS.require("features.haunting.hover").New(Merasmus.FLYING, Vector)
	self.flightYawRate = Merasmus.FLYING_MAX_YAW_RATE
	self.loco:SetGravity(0)
	self.motion = FlyingMotion
end

function ENT:StopFlying()
	self.motion = self.groundMotion
	self.loco:SetGravity(self.groundGravity)
end

function ENT:SetDesiredAltitude(h) self.flight:SetDesiredAltitude(h) end

-- CMerasmus::TriggerLogicRelay
function ENT:TriggerRelay(name)
	local relay = ents.FindByName(name)[1]
	if not IsValid(relay) then return nil end
	relay:Fire("Trigger", "", 0, self, self)
	return relay:GetPos()
end

-- The centres of the preferred areas at least minSize on each side, with
-- no RED or BLU player in them (CTFNavArea::GetPlayerCount).
function ENT:PreferredAreas(minSize)
	local boxes = PreferBoxes()
	local occupied = {}
	for _, ply in ipairs(self:CollectPlayers(PLAYERS_ANY_TEAM)) do
		local area = navmesh.GetNavArea(ply:GetPos(), NAV_BENEATH_LIMIT)
		if IsValid(area) then occupied[area:GetID()] = true end
	end
	local centers = {}
	for _, area in ipairs(navmesh.GetAllNavAreas()) do
		if area:GetSizeX() >= minSize and area:GetSizeY() >= minSize and not occupied[area:GetID()] and IsPreferred(area, boxes) then
			centers[#centers + 1] = area:GetCenter()
		end
	end
	return centers
end

-- CollectSurroundingAreas from the area at pos (GetControlPointCenterArea).
function ENT:AreasAround(pos, range)
	local start = navmesh.GetNearestNavArea(pos)
	if not IsValid(start) then return {} end
	local centers = {}
	for _, area in ipairs(navmesh.Find(start:GetCenter(), range, STEP_HEIGHT, STEP_HEIGHT)) do
		centers[#centers + 1] = area:GetCenter()
	end
	return centers
end

function ENT:IsInPreferredArea(t)
	local area = navmesh.GetNavArea(t:GetPos(), NAV_BENEATH_LIMIT)
	return IsValid(area) and IsPreferred(area, PreferBoxes())
end

-- RemoveAllGrenades: the bombs near him.
function ENT:RemoveGrenades(origin, radius)
	local class = WS.require(self.Variant).GRENADE_CLASS
	for _, ent in ipairs(ents.FindInSphere(origin, radius)) do
		if ent:GetClass() == class then ent:Remove() end
	end
end

function ENT:EndStun(t)
	if t:IsPlayer() then WS.EndStun(t) end
end

function ENT:RemoveCond(t, cond)
	if t:IsPlayer() then WS.RemoveCondition(t, cond) end
end

function ENT:RemoveEntity(t) t:Remove() end

-- InstancedScriptedScene: GMod's PlayScene plays it on a NextBot (a
-- CBaseFlex), as its nb_example does. TF2 ships its scenes only inside its
-- scenes/scenes.image, which GMod's scene cache must have loaded: our
-- servers put TF2's tf2_misc.vpk ahead of GMod's HL2 packs in gameinfo.txt.
-- A scene the server lacks plays nothing (no length), which is said once.
local SCENE_MISSING = "merasmus: %s is not among the server's scenes (TF2's scenes.image): put TF2's tf2_misc.vpk ahead of GMod's HL2 packs in garrysmod/gameinfo.txt"
local sceneMissingSaid = false

function ENT:PlayScriptedScene(name)
	local duration = self:PlayScene(name)
	if (duration or 0) > 0 or sceneMissingSaid then return end
	sceneMissingSaid = true
	print(string.format(SCENE_MISSING, name))
end

-- TFGameRules()->StartHalloweenBossTimer: only his scenario's map runs the
-- timer; elsewhere TF2 sets it and never reads it.
function ENT:StartBossTimer(seconds, variation)
	if not WS.FeatureLoaded("boss_timer") then return end
	WS.Feature("boss_timer"):Start(self.Variant, seconds, variation)
end

-------------------------------------------------------------------------------
-- His props' events (tf_merasmus_trick_or_treat_prop), to his Behavior

function ENT:OnPropKilled(prop, attacker) self.npc:Event("OnPropKilled", prop, attacker) end
function ENT:OnPropTouched(prop, toucher) self.npc:Event("OnPropTouched", prop, toucher) end
