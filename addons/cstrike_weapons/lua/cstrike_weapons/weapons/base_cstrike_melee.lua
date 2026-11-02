-- Shared hit simulation for CS:S melee weapons.

SWEP.Base = "weapon_base"
SWEP.Spawnable = false
SWEP.DrawAmmo = false

local HULL = Vector(16, 16, 18)

function SWEP:SetupDataTables()
	self:NetworkVar("Float", 0, "LastStrike")
end

function SWEP:Initialize()
	self:SetHoldType(self.HoldType)
end

function SWEP:Deploy()
	self:SetHoldType(self.HoldType)
	self:SendWeaponAnim(ACT_VM_DRAW)
	self:EmitSound("Weapon_Knife.Deploy")
	return true
end

function SWEP:PrimaryAttack()
	self:Strike(self.SlashReach, self.SlashInterval, self.SlashDamage, self.SlashFreshWindow,
		self.SlashFirstDamage, ACT_VM_PRIMARYATTACK, ACT_VM_PRIMARYATTACK, "Weapon_Knife.Hit")
end

function SWEP:SecondaryAttack()
	self:Strike(self.StabReach, self.StabInterval, self.StabDamage, nil, nil,
		ACT_VM_SECONDARYATTACK, ACT_VM_MISSCENTER, "Weapon_Knife.Stab")
end

local function Fighter(ent)
	return IsValid(ent) and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot())
end

local function Flat(v)
	v = Vector(v.x, v.y, 0)
	v:Normalize()
	return { x = v.x, y = v.y }
end

function SWEP:Strike(reach, interval, damage, freshWindow, firstDamage, hitAct, missAct, hitSound)
	local owner, now = self:GetOwner(), CurTime()
	local src, dir = owner:GetShootPos(), owner:GetAimVector()
	local to = src + dir * reach
	if owner:IsPlayer() then owner:LagCompensation(true) end
	local tr = util.TraceLine({ start = src, endpos = to, filter = owner, mask = MASK_SHOT_HULL })
	if not tr.Hit then
		tr = util.TraceHull({ start = src, endpos = to, filter = owner, mins = -HULL, maxs = HULL, mask = MASK_SHOT_HULL })
	end
	if owner:IsPlayer() then owner:LagCompensation(false) end
	local fresh = freshWindow ~= nil and now - self:GetLastStrike() >= freshWindow
	self:SetLastStrike(now)
	self:SetNextPrimaryFire(now + interval)
	self:SetNextSecondaryFire(now + interval)
	owner:SetAnimation(PLAYER_ATTACK1)
	if not tr.Hit then
		self:SendWeaponAnim(missAct)
		self:EmitSound("Weapon_Knife.Slash")
		return
	end
	self:SendWeaponAnim(hitAct)
	local victim = tr.Entity
	self:EmitSound(Fighter(victim) and hitSound or "Weapon_Knife.HitWall")
	if not Fighter(victim) then util.Decal("ManhackCut", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal) end
	if CLIENT or not IsValid(victim) then return end
	local facing = victim:IsPlayer() and victim:EyeAngles():Forward() or victim:GetForward()
	local back = false
	if Fighter(victim) then
		local toward, direction = Flat(victim:GetPos() - owner:GetPos()), Flat(facing)
		back = toward.x * direction.x + toward.y * direction.y > self.BackstabDot
	end
	local amount = fresh and firstDamage or damage
	if back then
		amount = amount * self.BackstabMultiplier
		WS.SkillShot(victim)
	end
	local info = DamageInfo()
	info:SetDamage(amount)
	info:SetAttacker(owner)
	info:SetInflictor(self)
	info:SetDamageType(DMG_SLASH)
	info:SetDamagePosition(tr.HitPos)
	info:SetDamageForce(dir * 1000)
	victim:DispatchTraceAttack(info, tr, dir)
end
