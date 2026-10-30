-- weapon_cstrike_grenade_base: CS:S's grenades (weapon_hegrenade,
-- weapon_flashbang, weapon_smokegrenade). Pressing attack pulls the pin;
-- letting go throws it (gameplay.cstrike_weapons' Throw: higher than aimed, to
-- the grenade's speed, with the thrower's own speed), as its projectile
-- (entities/entities/base_cstrike_grenade.lua). A grenade is thrown once: the
-- weapon goes with it.
AddCSLuaFile()

local Css = gameplay.cstrike_weapons

SWEP.PrintName = "CS:S grenade"
SWEP.Spawnable = false
SWEP.DrawAmmo = false
SWEP.UseHands = true
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

local RELEASE = 0.1 -- seconds from the throw's animation to the grenade leaving the hand
local FORWARD = 16 -- units ahead of the eye a grenade leaves from

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "Pulled")
	self:NetworkVar("Float", 0, "ThrowAt")
end

function SWEP:CSS() return Css.WEAPONS[self.CSSClass] end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
	self:SetHoldType(self.HoldType)
	self:SetPulled(false)
	self:SetThrowAt(0)
	self:SendWeaponAnim(ACT_VM_DRAW)
	return true
end

function SWEP:Holster()
	return self:GetThrowAt() == 0
end

function SWEP:PrimaryAttack()
	if self:GetPulled() then return end
	self:SetPulled(true)
	self:SendWeaponAnim(ACT_VM_PULLPIN)
	local vm = self:GetOwner():GetViewModel()
	self:SetNextPrimaryFire(CurTime() + (IsValid(vm) and vm:SequenceDuration() or 0))
end

function SWEP:SecondaryAttack() end

function SWEP:Think()
	local owner, now = self:GetOwner(), CurTime()
	if not IsValid(owner) then return end
	if self:GetPulled() and self:GetThrowAt() == 0 and not owner:KeyDown(IN_ATTACK) and now >= self:GetNextPrimaryFire() then
		self:SendWeaponAnim(ACT_VM_THROW)
		owner:SetAnimation(PLAYER_ATTACK1)
		self:SetThrowAt(now + RELEASE)
	elseif self:GetThrowAt() > 0 and now >= self:GetThrowAt() then
		self:SetThrowAt(0)
		self:SetPulled(false)
		if SERVER then
			self:Throw(owner)
			owner:StripWeapon(self:GetClass())
		end
	end
end

function SWEP:Throw(owner)
	local grenade = self:CSS().grenade
	local view = owner:EyeAngles()
	local pitch, speed = Css.Throw(grenade, view.p)
	local aim = Angle(pitch, view.y, 0):Forward()
	local src = owner:GetShootPos() + aim * FORWARD
	local tr = util.TraceHull({ start = owner:GetShootPos(), endpos = src, mins = Vector(-2, -2, -2), maxs = Vector(2, 2, 2), filter = owner })
	local projectile = ents.Create(grenade.projectile)
	if not IsValid(projectile) then error("no grenade projectile " .. grenade.projectile) end
	projectile:SetPos(tr.HitPos)
	projectile:SetAngles(Angle(0, view.y, 0))
	projectile:SetOwner(owner)
	projectile.Thrower = owner
	projectile:Spawn()
	local phys = projectile:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetVelocity(aim * speed + owner:GetVelocity())
		phys:AddAngleVelocity(Vector(600, math.random(-1200, 1200), 0))
	end
end
