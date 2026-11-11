-- obj_sentrygun (CObjectSentrygun, tf_obj_sentrygun.cpp): built, it targets the nearest enemy it
-- sees within its range (gameplay.buildings' Target), turns its gun to it at its turn rate and fires
-- once on target, from its muzzle at the target, its fire animation a gesture, its bullets its
-- builder's; with none, it sweeps its arc, scanning. Its aim is its own, as yaw and pitch from its
-- facing, shown by its model's aim_yaw and aim_pitch. Its level (SetLevel, before Spawn; 1 unless
-- set) is TF2's: level 3 wears sentry3, fires its two miniguns by turns at twice the rate, and a
-- rocket every SENTRY_LEVELS[3].rocketInterval (ent_projectile_rocket).
AddCSLuaFile ()

ENT.Base = "base_obj"
ENT.Kind = "sentry"
ENT.Model = "models/buildables/sentry1.mdl"
-- TF2's SENTRY_MODEL_LEVEL_1_UPGRADE: its level 1 holds no build animation.
ENT.BuildModel = "models/buildables/sentry1_heavy.mdl"
-- TF2's SENTRYGUN_MINS and SENTRYGUN_MAXS: its models have no collision shape for a bullet to hit.
ENT.HullMins, ENT.HullMaxs = Vector (-20, -20, 0), Vector (20, 20, 66)
ENT.PrintName = "#TF_Object_Sentry"
ENT.Spawnable = true
ENT.Category = "Sandcastle"

local Buildings = gameplay.buildings

-- TF2's game sounds for its sentries (scripts/game_sounds_buildings.txt), by their names.
for name, entry in pairs (
	{
		["Building_Sentrygun.Fire"]       = { CHAN_WEAPON, 94, 0.7, ")weapons/sentry_shoot.wav" },
		["Building_Sentrygun.Fire3"]      = { CHAN_WEAPON, 94, 0.7, ")weapons/sentry_shoot3.wav" },
		["Building_Sentrygun.FireRocket"] = { CHAN_STATIC, 94, 0.7, ")weapons/sentry_rocket.wav" },
		["Building_Sentrygun.Alert"]      = { CHAN_WEAPON, 88, 0.7, "weapons/sentry_spot.wav" },
		["Building_Sentrygun.Idle"]       = { CHAN_ITEM, 84, 0.525, "weapons/sentry_scan.wav" },
		["Building_Sentrygun.Idle3"]      = { CHAN_ITEM, 84, 0.525, "weapons/sentry_scan3.wav" },
		["Building_Sentrygun.Built"]      = { CHAN_STATIC, 74, 0.7, ")weapons/sentry_finish.wav" }
	}
) do
	sound.Add ({ name = name, channel = entry [1], level = entry [2], volume = entry [3], sound = entry [4] })
	util.PrecacheSound (name)
end

-- What differs by level: its model, its eye (SENTRYGUN_EYE_OFFSET_LEVEL_*), its muzzles (fired by
-- turns), its sounds; its health and rates are gameplay.buildings' SENTRY_LEVELS.
local LEVELS =
{
	[1] =
	{
		model = "models/buildables/sentry1.mdl", eye = Vector (0, 0, 32), muzzles = { "muzzle" },
		fire = "Building_Sentrygun.Fire", idle = "Building_Sentrygun.Idle"
	},
	[3] =
	{
		model = "models/buildables/sentry3.mdl", eye = Vector (0, 0, 46), muzzles = { "muzzle_l", "muzzle_r" },
		fire = "Building_Sentrygun.Fire3", idle = "Building_Sentrygun.Idle3", rocket = "rocket"
	}
}
local ROCKET_MODEL = "models/buildables/sentry3_rockets.mdl"
local SPREAD = Vector (0.02, 0.02, 0)

if SERVER then
	-- Its level, before it spawns: 1 or 3.
	function ENT:SetLevel (level)
		if not LEVELS [level] then error ("no sentry of level " .. tostring (level), 2) end
		self.Level = level
		self.Model = LEVELS [level].model
	end

	function ENT:LevelOf () return LEVELS [self.Level or 1], Buildings.SENTRY_LEVELS [self.Level or 1] end

	function ENT:ObjMaxHealth ()
		local _, stats = self:LevelOf ()
		return stats.health
	end

	function ENT:ObjInitialize ()
		self.aimYaw, self.aimPitch = 0, 0
		self.nextFire, self.nextRocket, self.shot = 0, 0, 0
		-- CObjectSentrygun::OnGoActive: it starts searching toward its right bound
		self.searchYaw = -Buildings.SENTRY_SEARCH_ARC
	end

	function ENT:ObjBuilt ()
		self:EmitSound ("Building_Sentrygun.Built")
	end

	function ENT:EyePos ()
		local level = self:LevelOf ()
		return self:LocalToWorld (level.eye)
	end

	-- Its next barrel's end, by turns: the model's muzzle attachment, which the engine moves with its
	-- aim's pose.
	function ENT:Muzzle ()
		local level = self:LevelOf ()
		self.shot = self.shot % #level.muzzles + 1
		return self:GetAttachment (self:LookupAttachment (level.muzzles [self.shot])).Pos
	end

	-- A gesture over its idle, begun again only once the last has played out (CObjectSentrygun's
	-- AddGesture(ACT_RANGE_ATTACK1), and ACT_RANGE_ATTACK2 for a rocket).
	function ENT:PlayGesture (activity)
		if self:IsPlayingGesture (activity) then return end
		self:AddGesture (activity)
	end

	-- CObjectSentrygun::SentryRotate: with no target, it sweeps SENTRY_SEARCH_ARC either side of its
	-- facing at its search rate, level, scanning aloud at each end of a sweep.
	function ENT:Search (dt)
		self.aimPitch = Buildings.Turn (self.aimPitch, 0, dt)
		local turned = Buildings.Turn (self.aimYaw, self.searchYaw, dt * Buildings.SENTRY_SEARCH_SHARE)
		if turned == self.aimYaw or math.abs (math.AngleDifference (turned, self.searchYaw)) < 0.5 then
			self.searchYaw = -self.searchYaw
			self:EmitSound (self:LevelOf ().idle)
		end
		self.aimYaw = turned
	end

	function ENT:Pose ()
		local poseYaw, posePitch = Buildings.Pose (self.aimYaw, self.aimPitch)
		self:SetPoseParameter ("aim_yaw",   poseYaw)
		self:SetPoseParameter ("aim_pitch", posePitch)
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

	function ENT:Attacker ()
		local builder = self:GetBuilder ()
		return IsValid (builder) and builder or self
	end

	-- CObjectSentrygun::FireRocket: from its rocket attachment, straight at the target.
	function ENT:FireRocket (to, stats, level)
		local at = self:GetAttachment (self:LookupAttachment (level.rocket))
		local rocket = ents.Create ("ent_projectile_rocket")
		rocket:SetPos (at.Pos)
		rocket:SetAngles ((to - at.Pos):Angle ())
		rocket:Configure (
			{
				damage = stats.rocketDamage, team = self:GetObjTeam (), launcher = self,
				-- TF2's: the builder its scorer, never hurt by it
				attacker = self:Attacker (), spareAttacker = true,
				velocity = (to - at.Pos):GetNormalized () * stats.rocketSpeed, model = ROCKET_MODEL,
				sound = "Building_Sentrygun.FireRocket"
			}
		)
		rocket:Spawn ()
		self:PlayGesture (ACT_RANGE_ATTACK2)
	end

	-- CObjectSentrygun::Attack: from its eye, the aim it turns toward (its pitch held within
	-- SENTRY_PITCH_MAX); on target, a shot from its muzzle straight at the target's middle.
	function ENT:ObjThink ()
		local now, dt = CurTime (), FrameTime ()
		local level, stats = self:LevelOf ()
		local eye = self:EyePos ()
		local function Sees (candidate)
			local tr = util.TraceLine ({ start = eye, endpos = candidate.ent:WorldSpaceCenter (), mask = MASK_SHOT, filter = self })
			return tr.Entity == candidate.ent or not tr.Hit
		end
		local target = Buildings.Target ({ x = eye.x, y = eye.y, z = eye.z }, self:Candidates (eye), self:GetObjTeam (), Sees)
		if not target then
			self.target = nil
			self:Search (dt)
			self:Pose ()
			return
		end
		-- CObjectSentrygun::FoundTarget: a new target is told aloud
		if target.ent ~= self.target then
			self.target = target.ent
			self:EmitSound ("Building_Sentrygun.Alert")
		end
		local to = target.ent:WorldSpaceCenter ()
		local goal = self:WorldToLocalAngles ((to - eye):Angle ())
		local goalPitch = math.Clamp (math.NormalizeAngle (goal.p), -Buildings.SENTRY_PITCH_MAX, Buildings.SENTRY_PITCH_MAX)
		self.aimYaw = Buildings.Turn (self.aimYaw, goal.y, dt)
		self.aimPitch = Buildings.Turn (self.aimPitch, goalPitch, dt)
		self:Pose ()
		if not (Buildings.OnTarget (self.aimYaw, goal.y) and Buildings.OnTarget (self.aimPitch, goalPitch)) then return end
		if level.rocket and now >= self.nextRocket then
			self.nextRocket = now + stats.rocketInterval
			self:FireRocket (to, stats, level)
		end
		if now < self.nextFire then return end
		self.nextFire = now + stats.interval
		local from = self:Muzzle ()
		self:FireBullets (
			{
				Attacker = self:Attacker (),
				Inflictor = self,
				Damage = Buildings.SENTRY_DAMAGE,
				Src = from,
				Dir = (to - from):GetNormalized (),
				Spread = SPREAD,
				Num = 1,
				Tracer = 1,
				IgnoreEntity = self
			}
		)
		self:EmitSound (level.fire)
		self:PlayGesture (ACT_RANGE_ATTACK1)
	end
end
