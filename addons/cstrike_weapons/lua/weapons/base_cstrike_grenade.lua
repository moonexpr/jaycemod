AddCSLuaFile()

-- Shared pin, throw and projectile behavior for CS:S grenades.

SWEP.PrintName = "CS:S grenade"
SWEP.Spawnable = false
SWEP.DrawAmmo = false
SWEP.CStrikeWeapon = true
SWEP.UseHands = true
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

local RELEASE, FORWARD = 0.1, 16

function SWEP:SetupDataTables()
	self:NetworkVar("Bool", 0, "Pulled")
	self:NetworkVar("Float", 0, "ThrowAt")
end

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
	local view = owner:EyeAngles()
	local pitch = view.p
	if pitch > 90 then pitch = pitch - 360 elseif pitch < -90 then pitch = pitch + 360 end
	local thrown = -10 + pitch * 80 / 90
	local speed = math.min((90 - thrown) * 6, self.GrenadeSpeed)
	local aim = Angle(thrown, view.y, 0):Forward()
	local src = owner:GetShootPos() + aim * FORWARD
	local tr = util.TraceHull({
		start = owner:GetShootPos(),
		endpos = src,
		mins = Vector(-2, -2, -2),
		maxs = Vector(2, 2, 2),
		filter = owner,
	})
	local projectile = ents.Create(self.GrenadeProjectile)
	if not IsValid(projectile) then error("no grenade projectile " .. self.GrenadeProjectile) end
	projectile:SetPos(tr.HitPos)
	projectile:SetAngles(Angle(0, view.y, 0))
	projectile:SetOwner(owner)
	projectile.Thrower = owner
	projectile.GrenadeFuse = self.GrenadeFuse
	projectile.GrenadeDamage = self.GrenadeDamage
	projectile.GrenadeRadius = self.GrenadeRadius
	projectile.GrenadeBlind = self.GrenadeBlind
	projectile.GrenadeDuration = self.GrenadeDuration
	projectile:Spawn()
	local phys = projectile:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetVelocity(aim * speed + owner:GetVelocity())
		phys:AddAngleVelocity(Vector(600, math.random(-1200, 1200), 0))
	end
end
