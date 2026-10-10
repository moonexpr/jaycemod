-- The hazards feature's controller. It owns one foundation.hazards model per
-- hazard entity (tf_pumpkin_bomb, tf_generic_bomb, halloween_zapper,
-- func_croc), gives the model what happens to the entity (damage with the
-- attacker's team, inputs, touches, time) and carries out what the model
-- answers: a blast through the combat controller, goop, gibs, outputs, a
-- zap's beam, or a croc and its bite.
local Hazards = WS.require("foundation.hazards")

local TRIGGER_HURT = "trigger_hurt"
local PROJECTILE_BASE = "ws_projectile"
local SCORCH_DECAL = "Scorch"

-- CTFPumpkinBomb::Event_Killed's scorch trace: 8 above the origin to 24
-- below it.
local SCORCH_TRACE_UP, SCORCH_TRACE_DOWN = 8, 32

local NO_ATTACHMENT = -1 -- a beam from a point, not an attachment

local ANIMATED_PROP = "prop_dynamic"
local NOT_SOLID = "0" -- prop_dynamic's solid keyvalue: SOLID_NONE

local Controller = {
	combat = WS.Feature("combat"),
	hazards = {},
}

local function SetUpBody(ent, body)
	ent:SetModel(body.model)
	ent:SetSkin(body.skin)
	ent:SetModelScale(body.scale)
	if body.move == Hazards.MOVE_PHYSICS then
		-- A still prop that bullets and blasts hit, as TF2's pumpkins stand.
		ent:PhysicsInit(SOLID_VPHYSICS)
		local phys = ent:GetPhysicsObject()
		-- A mapper's model may have no collision model.
		if IsValid(phys) then phys:EnableMotion(false) end
	else
		ent:SetSolid(SOLID_BBOX)
		ent:SetMoveType(MOVETYPE_FLYGRAVITY)
		ent:SetMoveCollide(MOVECOLLIDE_FLY_BOUNCE)
	end
end

-- The model for a hazard entity; its variant is a foundation.hazards part.
-- A hazard with a body gets its model, skin, scale and movement here.
function Controller:Bind(ent, variantName, config)
	local hazard = Hazards.New(WS.require(variantName), config, CurTime())
	self.hazards[ent] = hazard
	local body = hazard:Body()
	if body then SetUpBody(ent, body) end
	return hazard
end

function Controller:Unbind(ent)
	self.hazards[ent] = nil
end

-- UTIL_Remove (a map's Kill, or a pumpkin's own blast) unbinds at once, but
-- the entity lives out the frame: it may still think, be touched, or take a
-- chained blast. Those callbacks find no hazard and do nothing.

-- No attacker is the world.
local function Credited(hazard, attacker)
	if not IsValid(attacker) then return game.GetWorld() end
	if hazard:CreditsOwner() and IsValid(attacker:GetOwner()) then return attacker:GetOwner() end
	return attacker
end

-- OnTakeDamage
function Controller:Damaged(ent, dmg)
	local hazard = self.hazards[ent]
	if not hazard then return end
	local attacker = Credited(hazard, dmg:GetAttacker())
	self:Apply(ent, hazard:Damaged({
		team = self.combat:TeamOf(attacker),
		amount = dmg:GetDamage(),
	}), attacker)
end

-- TF2 asks FL_GRENADE; GMod's own grenades set it, Sandcastle's
-- projectiles are ws_projectile.
local function IsProjectile(other)
	return other:IsFlagSet(FL_GRENADE) or scripted_ents.IsBasedOn(other:GetClass(), PROJECTILE_BASE)
end

-- A touch. A projectile counts as its thrower's.
function Controller:Touched(ent, other)
	local hazard = self.hazards[ent]
	if not hazard then return end
	local projectile = IsProjectile(other)
	local credited = other
	if projectile and IsValid(other:GetOwner()) then credited = other:GetOwner() end
	self:Apply(ent, hazard:Touch({
		target = other,
		team = self.combat:TeamOf(credited),
		projectile = projectile,
		triggerHurt = other:GetClass() == TRIGGER_HURT,
		leaving = false,
		now = CurTime(),
	}), credited)
end

-- The end of a touch; other may be gone already (a player who left).
function Controller:Left(ent, other)
	local hazard = self.hazards[ent]
	if not hazard then return end
	self:Apply(ent, hazard:Touch({
		target = other,
		leaving = true,
	}), nil)
end

-- An input the hazard accepts (Hazard:Accepts); inputs carry no attacker.
function Controller:Input(ent, name, value)
	local hazard = self.hazards[ent]
	if not hazard then return end
	self:Apply(ent, hazard:Input(name, value), nil)
end

function Controller:Think(ent)
	local hazard = self.hazards[ent]
	if not hazard then return end
	self:Apply(ent, hazard:Tick(CurTime()), nil)
end

-- Where a blast starts: the named attachment when the model has it.
local function BlastPoint(ent, attachment)
	if attachment then
		local id = ent:LookupAttachment(attachment)
		if id > 0 then
			local at = ent:GetAttachment(id)
			return at.Pos, at.Ang
		end
	end
	return ent:GetPos(), ent:GetAngles()
end

local function PlayParticles(names, origin, angles)
	for _, name in ipairs(names) do ParticleEffect(name, origin, angles) end
end

-- Players are not decalled with scorch.
local function Scorch(ent)
	local spot = ent:GetPos() + Vector(0, 0, SCORCH_TRACE_UP)
	local tr = util.TraceLine({
		start = spot,
		endpos = spot - Vector(0, 0, SCORCH_TRACE_DOWN),
		mask = MASK_SHOT_HULL,
		filter = ent,
	})
	if tr.Hit and not (IsValid(tr.Entity) and tr.Entity:IsPlayer()) then
		util.Decal(SCORCH_DECAL, tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal, ent)
	end
end

local APPLY = {
	[Hazards.NONE] = function() end,

	-- Event_Killed: effects, the blast (which may set off other hazards; a
	-- spent one ignores the echo), gibs, the output, then gone.
	[Hazards.EXPLODE] = function(self, ent, outcome, attacker)
		local origin, angles = BlastPoint(ent, outcome.attachment)
		PlayParticles(outcome.particles, origin, angles)
		if outcome.sound then ent:EmitSound(outcome.sound) end
		Scorch(ent)
		ent:SetSolid(SOLID_NONE)
		self.combat:Explode({
			origin = origin,
			radius = outcome.radius,
			damage = outcome.damage,
			attackerTeam = outcome.team,
			attacker = attacker,
			inflictor = ent,
			halfFalloff = outcome.halfFalloff,
			forceFriendlyFire = outcome.forceFriendlyFire,
			crit = false,
		})
		if outcome.gibs then ent:GibBreakClient(vector_origin) end
		if outcome.output then
			local activator = ent
			if outcome.activatorIsAttacker then activator = attacker end
			ent:TriggerOutput(outcome.output, activator)
		end
		ent:Remove()
	end,

	[Hazards.FIZZLE] = function(self, ent, outcome)
		PlayParticles(outcome.particles, ent:GetPos(), angle_zero)
		ent:Remove()
	end,

	-- ZapAllTouching: a beam from the zapper's centre to each target's.
	[Hazards.ZAP] = function(self, ent, outcome)
		local from = ent:WorldSpaceCenter()
		for _, target in ipairs(outcome.targets) do
			if IsValid(target) then
				util.ParticleTracerEx(outcome.particle, from, target:WorldSpaceCenter(), false, ent:EntIndex(), NO_ATTACHMENT)
			end
		end
	end,

	-- CEntityCroc::InitCroc: a prop that is not solid, gone when its
	-- sequence ends (at once when the model lacks it).
	[Hazards.ANIMATE] = function(self, ent, outcome)
		if not IsValid(outcome.target) then return end
		local prop = ents.Create(ANIMATED_PROP)
		prop:SetModel(outcome.model)
		prop:SetKeyValue("DefaultAnim", outcome.sequence)
		prop:SetKeyValue("solid", NOT_SOLID)
		prop:SetPos(outcome.target:GetPos())
		prop:SetAngles(angle_zero)
		prop:Spawn()
		local sequence = prop:LookupSequence(outcome.sequence)
		if sequence < 0 then
			prop:Remove()
			return
		end
		SafeRemoveEntityDelayed(prop, prop:SequenceDuration(sequence))
	end,

	-- The hazard is both attacker and inflictor, and the outputs' activator.
	[Hazards.HURT] = function(self, ent, outcome)
		for _, hit in ipairs(outcome.hits) do
			if IsValid(hit.target) then
				local dmg = DamageInfo()
				dmg:SetDamage(outcome.damage)
				dmg:SetDamageType(outcome.dmgType)
				dmg:SetAttacker(ent)
				dmg:SetInflictor(ent)
				hit.target:TakeDamageInfo(dmg)
				for _, output in ipairs(hit.outputs) do ent:TriggerOutput(output, ent) end
			end
		end
	end,
}

function Controller:Apply(ent, outcome, attacker)
	APPLY[outcome.kind](self, ent, outcome, attacker)
end

return Controller
