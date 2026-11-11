-- obj_sentrygun (CObjectSentrygun, tf_obj_sentrygun.cpp), level 1: built, it targets the nearest
-- enemy it sees within its range (gameplay.buildings' Target), turns its gun to it at its turn rate
-- and fires once on target, its bullets its builder's. Its aim is its own, as yaw and pitch from
-- its facing, shown by its model's aim_yaw and aim_pitch.
AddCSLuaFile ()

ENT.Base = "base_obj"
ENT.Kind = "sentry"
ENT.Model = "models/buildables/sentry1.mdl"
-- TF2's SENTRY_MODEL_LEVEL_1_UPGRADE: its level 1 holds no build animation.
ENT.BuildModel = "models/buildables/sentry1_heavy.mdl"
-- TF2's SENTRYGUN_MINS and SENTRYGUN_MAXS: its models have no collision shape for a bullet to hit.
ENT.HullMins, ENT.HullMaxs = Vector (-20, -20, 0), Vector (20, 20, 66)
ENT.PrintName = "Sentry Gun"
ENT.Spawnable = true
ENT.Category = "Sandcastle"
-- Soldiers fight it as they fight each other.
ENT.NSCombatant = true

local Buildings = gameplay.buildings

local FIRE_SOUND = "weapons/sentry_shoot.wav"
-- Where it fires from, without a muzzle attachment; and what it aims at on a body.
local MUZZLE_UP = Vector (0, 0, 40)
local SPREAD = Vector (0.02, 0.02, 0)

if SERVER then
	function ENT:ObjInitialize ()
		self.aimYaw, self.aimPitch = 0, 0
		self.nextFire = 0
	end

	function ENT:Muzzle ()
		local attachment = self:LookupAttachment ("muzzle")
		local at = attachment and attachment > 0 and self:GetAttachment (attachment)
		return at and at.Pos or self:GetPos () + MUZZLE_UP
	end

	-- Bodies near it that may be targets: living players, NPCs and NextBots, with their teams.
	function ENT:Candidates (from)
		local candidates = {}
		for _, ent in ipairs (ents.FindInSphere (from, Buildings.SENTRY_RANGE)) do
			if (ent:IsPlayer () or ent:IsNPC () or ent:IsNextBot ()) and ent:Health () > 0 then
				local at = ent:WorldSpaceCenter ()
				candidates [#candidates + 1] = { pos = { x = at.x, y = at.y, z = at.z }, team = WS.TeamNumber (ent), ent = ent }
			end
		end
		return candidates
	end

	function ENT:ObjThink ()
		local now, dt = CurTime (), FrameTime ()
		local from = self:Muzzle ()
		local function Sees (candidate)
			local tr = util.TraceLine ({ start = from, endpos = candidate.ent:WorldSpaceCenter (), mask = MASK_SHOT, filter = self })
			return tr.Entity == candidate.ent or not tr.Hit
		end
		local target = Buildings.Target ({ x = from.x, y = from.y, z = from.z }, self:Candidates (from), self:GetObjTeam (), Sees)
		if not target then return end
		local to = target.ent:WorldSpaceCenter ()
		local local_ = self:WorldToLocalAngles ((to - from):Angle ())
		self.aimYaw = Buildings.Turn (self.aimYaw, local_.y, dt)
		self.aimPitch = Buildings.Turn (self.aimPitch, local_.p, dt)
		self:SetPoseParameter ("aim_yaw", math.NormalizeAngle (self.aimYaw))
		self:SetPoseParameter ("aim_pitch", math.NormalizeAngle (self.aimPitch))
		if now < self.nextFire or not (Buildings.OnTarget (self.aimYaw, local_.y) and Buildings.OnTarget (self.aimPitch, local_.p)) then
			return
		end
		self.nextFire = now + Buildings.SENTRY_FIRE_INTERVAL
		local builder = self:GetBuilder ()
		self:FireBullets (
			{
				Attacker = IsValid (builder) and builder or self,
				Inflictor = self,
				Damage = Buildings.SENTRY_DAMAGE,
				Src = from,
				Dir = self:LocalToWorldAngles (Angle (self.aimPitch, self.aimYaw, 0)):Forward (),
				Spread = SPREAD,
				Num = 1,
				Tracer = 1,
				IgnoreEntity = self
			}
		)
		self:EmitSound (FIRE_SOUND, 85)
	end
end
