-- weapon_wrench (tf_weapon_wrench): the engineer's wrench. A swing at a teammate's building (base_obj)
-- hurries it going up or mends it once built (its Wrench); anything else it hits as a club. Its
-- reach, pace, damage and what a hit mends are gameplay.buildings'.
AddCSLuaFile ()

SWEP.PrintName = "Wrench"
SWEP.Category = "Sandcastle"
SWEP.Spawnable = true
SWEP.Slot = 2
SWEP.ViewModel = "models/weapons/v_models/v_wrench_engineer.mdl"
SWEP.WorldModel = "models/weapons/w_models/w_wrench.mdl"
SWEP.ViewModelFOV = 54
SWEP.HoldType = "melee"
SWEP.DrawAmmo = false
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }

local Buildings = gameplay.buildings

-- TF2's melee hull (its half size), swept where a line from the eyes finds nothing.
local HULL = 18
local SWING_SOUND = "weapons/wrench_swing.wav"
local TENDED_SOUNDS = { "weapons/wrench_hit_build_success1.wav", "weapons/wrench_hit_build_success2.wav" }
local WHOLE_SOUND = "weapons/wrench_hit_build_fail.wav"
local FLESH_SOUND = "weapons/cbar_hitbod1.wav"
local WORLD_SOUND = "weapons/wrench_hit_world.wav"
-- How hard its hit pushes what it hits, per point of damage.
local FORCE = 300

function SWEP:Initialize ()
	self:SetHoldType (self.HoldType)
end

-- What a swing from owner meets within its reach.
local function Swing (owner)
	local start = owner:GetShootPos ()
	local trace = { start = start, endpos = start + owner:GetAimVector () * Buildings.WRENCH_RANGE, filter = owner, mask = MASK_SHOT_HULL }
	local tr = util.TraceLine (trace)
	if tr.Hit then return tr end
	trace.mins, trace.maxs = Vector (-HULL, -HULL, -HULL), Vector (HULL, HULL, HULL)
	return util.TraceHull (trace)
end

local function Club (self, owner, ent, tr)
	local info = DamageInfo ()
	info:SetDamage (Buildings.WRENCH_DAMAGE)
	info:SetDamageType (DMG_CLUB)
	info:SetAttacker (owner)
	info:SetInflictor (self)
	info:SetDamagePosition (tr.HitPos)
	info:SetDamageForce (owner:GetAimVector () * Buildings.WRENCH_DAMAGE * FORCE)
	ent:TakeDamageInfo (info)
end

function SWEP:PrimaryAttack ()
	local owner = self:GetOwner ()
	if not IsValid (owner) then return end
	self:SetNextPrimaryFire (CurTime () + Buildings.WRENCH_INTERVAL)
	owner:SetAnimation (PLAYER_ATTACK1)
	owner:LagCompensation (true)
	local tr = Swing (owner)
	owner:LagCompensation (false)
	self:SendWeaponAnim (tr.Hit and ACT_VM_HITCENTER or ACT_VM_MISSCENTER)
	if not tr.Hit then
		self:EmitSound (SWING_SOUND)
		return
	end
	if not SERVER then return end
	local ent = tr.Entity
	if IsValid (ent) and ent.Wrench and Buildings.Tends (ent:GetObjTeam (), WS.TeamNumber (owner)) then
		self:EmitSound (ent:Wrench (owner) and TENDED_SOUNDS [math.random (#TENDED_SOUNDS)] or WHOLE_SOUND)
		return
	end
	if not IsValid (ent) then
		self:EmitSound (WORLD_SOUND)
		return
	end
	Club (self, owner, ent, tr)
	self:EmitSound ((ent:IsPlayer () or ent:IsNPC ()) and FLESH_SOUND or WORLD_SOUND)
end

function SWEP:SecondaryAttack () end
