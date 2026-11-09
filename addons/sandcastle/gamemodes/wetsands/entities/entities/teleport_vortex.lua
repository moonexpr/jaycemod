-- teleport_vortex (CTeleportVortex): the vortex MONOCULUS leaves behind, a
-- ±50 trigger bound to features.haunting.eyeball_boss's Vortex model. It
-- implements the vortex port (foundation.npc.eyeball_boss.VORTEX_METHODS;
-- the engine's Remove, EmitSound and WorldSpaceCenter already fit it).
--
-- Configure{ death, splitTeam } before Spawn: a death vortex shows the book
-- and leads to spawn_loot; otherwise it is hidden and leads to
-- spawn_purgatory. A split one (Merasmus's) sends each team to its own
-- spots (spawn_loot_red, spawn_loot_blue).
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = false

if CLIENT then return end

-- The client effect TF2 starts when the vortex opens (OnDataChanged).
local OPEN_EFFECTS = {
	[true] = {
		particle = "eyeboss_aura_angry",
		sound = "Halloween.TeleportVortex.EyeballDiedVortex",
	},
	[false] = {
		particle = "eyeboss_tp_vortex",
		sound = "Halloween.TeleportVortex.EyeballMovedVortex",
	},
}
local PARTICLE_FILE = "particles/eyeboss.pcf"
local particlesReady = false -- the file added and the effects precached, once per map
local SCREEN_FADE = Color(255, 255, 255, 100)
local SCREEN_FADE_TIME, SCREEN_FADE_HOLD = 0.25, 0.4

-- The server adds the file and precaches the names it sends; clients have
-- the file from the npc feature (features/npc/sh.lua).
local function ReadyParticles()
	if particlesReady then return end
	particlesReady = true
	game.AddParticles(PARTICLE_FILE)
	for _, effect in pairs(OPEN_EFFECTS) do PrecacheParticleSystem(effect.particle) end
end

function ENT:Configure(config)
	self.configured = config
end

function ENT:Initialize()
	local Eyeball = WS.require("features.haunting.eyeball_boss")
	local death = self.configured.death
	if death then
		self:SetModel(Eyeball.VORTEX_BOOK_MODEL)
	else
		self:SetNoDraw(true)
	end
	local half = Eyeball.VORTEX_HALF_WIDTH
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionBounds(Vector(-half, -half, -half), Vector(half, half, half))
	self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
	self:SetTrigger(true)
	ReadyParticles()
	local effect = OPEN_EFFECTS[death]
	ParticleEffectAttach(effect.particle, PATTACH_ABSORIGIN_FOLLOW, self, 0)
	self:EmitSound(effect.sound)
	self.vortex = Eyeball.Vortex.New(death, self, self.configured.splitTeam)
	self:NextThink(CurTime())
end

function ENT:Think()
	self.vortex:Think()
	self:NextThink(CurTime())
	return true
end

function ENT:Touch(other)
	if other:IsPlayer() and other:Alive() then self.vortex:Touch(other) end
end

-------------------------------------------------------------------------------
-- The vortex port (foundation.npc.eyeball_boss.VORTEX_METHODS)

function ENT:Now() return CurTime() end
function ENT:RandomInt(lo, hi) return math.random(lo, hi) end
function ENT:Vector(x, y, z) return Vector(x, y, z) end
function ENT:TeamOf(p) return p:Team() end
function ENT:TargetOrigin(p) return p:GetPos() end
function ENT:TargetCenter(p) return p:WorldSpaceCenter() end
function ENT:IsTargetOnGround(p) return p:IsOnGround() end

-- The living players of team; nil means RED and BLU.
function ENT:CollectPlayers(team)
	local found = {}
	for _, ply in ipairs(player.GetAll()) do
		local playerTeam = ply:Team()
		local wanted
		if team == nil then
			wanted = playerTeam == WS.TEAM_RED or playerTeam == WS.TEAM_BLUE
		else
			wanted = playerTeam == team
		end
		if wanted and ply:Alive() then found[#found + 1] = ply end
	end
	return found
end

-- CBaseCombatCharacter::IsLookingTowards: the aim within cosTolerance.
function ENT:IsLookingTowards(p, v, cosTolerance)
	local toTarget = (v - p:EyePos()):GetNormalized()
	return p:GetAimVector():Dot(toTarget) >= cosTolerance
end

-- From p's eyes to v, with no character in the way (IGNORE_ACTORS).
function ENT:IsLineOfSightClear(p, v)
	local tr = util.TraceLine({
		start = p:EyePos(),
		endpos = v,
		mask = MASK_OPAQUE,
		filter = function(ent) return ent ~= self and not (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()) end,
	})
	return tr.Fraction == 1
end

function ENT:SpawnPoints(name)
	local points = {}
	for _, ent in ipairs(ents.FindByName(name)) do points[#points + 1] = ent:GetPos() end
	return points
end

function ENT:ApplyImpulse(p, v)
	p:SetVelocity(v)
end

-- CTFPlayer::Teleport with no velocity, and TF2's white flash.
function ENT:Teleport(p, v)
	p:SetPos(v)
	p:SetLocalVelocity(vector_origin)
	p:ScreenFade(SCREENFADE.IN, SCREEN_FADE, SCREEN_FADE_TIME, SCREEN_FADE_HOLD)
end

function ENT:DealDamage(t, amount, dmgType, attacker)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(dmgType)
	dmg:SetAttacker(attacker)
	dmg:SetInflictor(self)
	dmg:SetDamagePosition(t:WorldSpaceCenter())
	t:TakeDamageInfo(dmg)
end
