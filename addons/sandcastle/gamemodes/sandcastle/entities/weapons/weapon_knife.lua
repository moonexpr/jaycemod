-- weapon_knife: CS:S's knife (gameplay.cstrike_weapons' KNIFE_STATS). The
-- primary slashes (harder the first time in a while), the secondary stabs;
-- either hits three times as hard from behind. A strike traces a line from
-- the eye, then a hull as wide as a head when the line finds nothing, as
-- CS:S's does, lag compensated.
AddCSLuaFile()

local Css = gameplay.cstrike_weapons
local K = Css.KNIFE_STATS

WS.CSSWeapon(SWEP, "weapon_knife")
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

function SWEP:PrimaryAttack() self:Strike(K.slash, ACT_VM_PRIMARYATTACK, ACT_VM_PRIMARYATTACK, "Weapon_Knife.Hit") end
function SWEP:SecondaryAttack() self:Strike(K.stab, ACT_VM_SECONDARYATTACK, ACT_VM_MISSCENTER, "Weapon_Knife.Stab") end

local function Fighter(ent)
	return IsValid(ent) and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot())
end

-- The way an entity faces across the ground, as { x, y } of length 1.
local function Flat(v)
	v = Vector(v.x, v.y, 0)
	v:Normalize()
	return { x = v.x, y = v.y }
end

function SWEP:Strike(strike, hitAct, missAct, hitSound)
	local owner, now = self:GetOwner(), CurTime()
	local src, dir = owner:GetShootPos(), owner:GetAimVector()
	local to = src + dir * strike.reach
	if owner:IsPlayer() then owner:LagCompensation(true) end
	local tr = util.TraceLine({ start = src, endpos = to, filter = owner, mask = MASK_SHOT_HULL })
	if not tr.Hit then
		tr = util.TraceHull({ start = src, endpos = to, filter = owner, mins = -HULL, maxs = HULL, mask = MASK_SHOT_HULL })
	end
	if owner:IsPlayer() then owner:LagCompensation(false) end
	local fresh = now - self:GetLastStrike() >= (strike.fresh or math.huge)
	self:SetLastStrike(now)
	self:SetNextPrimaryFire(now + strike.interval)
	self:SetNextSecondaryFire(now + strike.interval)
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
	local back = Fighter(victim) and Css.Backstab(Flat(victim:GetPos() - owner:GetPos()), Flat(facing))
	local dmg = DamageInfo()
	dmg:SetDamage(Css.KnifeDamage(strike, back, fresh))
	dmg:SetAttacker(owner)
	dmg:SetInflictor(self)
	dmg:SetDamageType(DMG_SLASH)
	dmg:SetDamagePosition(tr.HitPos)
	dmg:SetDamageForce(dir * 1000)
	if Css.SkillShot(Css.WEAPONS.weapon_knife, { back = back }) then WS.SkillShot(victim) end
	victim:DispatchTraceAttack(dmg, tr, dir)
end
