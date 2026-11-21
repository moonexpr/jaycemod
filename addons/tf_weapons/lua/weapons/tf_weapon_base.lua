-- A TF2 weapon held in the player's own hands: the class arms are its viewmodel, playing the
-- sequences its TFAnimations name by activity, and tf_weapons/cl_hands.lua draws the c_model and
-- the hands over them. A weapon fills in the class arms, the c_model, the activities and the stats.
AddCSLuaFile ()

SWEP.Base         = "weapon_base"
SWEP.PrintName    = "TF2 weapon"
SWEP.Category     = "Team Fortress 2"
SWEP.Spawnable    = false
SWEP.UseHands     = false
SWEP.ViewModelFOV = 54
SWEP.DrawAmmo     = true
SWEP.Slot         = 0

-- The class arms that animate (the viewmodel) and the weapon's c_model bone-merged onto them
SWEP.ViewModel  = "models/weapons/c_models/c_scout_arms.mdl"
SWEP.TFModel    = "models/weapons/c_models/c_scattergun.mdl"
SWEP.WorldModel = SWEP.TFModel

-- The arms' activity names for what the weapon does; reloadStart and reloadEnd for one shell a loop
SWEP.TFAnimations = {}
SWEP.TFReloadsSingly = false

SWEP.Primary.ClipSize    = 6
SWEP.Primary.DefaultClip = 32
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "Buckshot"
SWEP.Primary.Damage      = 6
SWEP.Primary.Bullets     = 1
SWEP.Primary.Spread      = 0
SWEP.Primary.Delay       = 0.5
SWEP.Primary.Sound       = ""

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

local RELOAD_NONE, RELOAD_START, RELOAD_LOOP, RELOAD_END = 0, 1, 2, 3

function SWEP:SetupDataTables ()
	self:NetworkVar ("Int",   0, "ReloadStage")
	self:NetworkVar ("Float", 0, "NextIdle")
	self:NetworkVar ("Float", 1, "NextReloadStep")
end

function SWEP:Initialize ()
	self:SetHoldType (self.HoldType or "shotgun")
end

-- Plays the activity named by TFAnimations [key] on the viewmodel; returns its length in seconds
function SWEP:PlayTF (key)
	local owner = self:GetOwner ()
	if not IsValid (owner) or not owner:IsPlayer () then return 0 end
	local vm = owner:GetViewModel ()
	local name = self.TFAnimations [key]
	local sequence = name and TFWeapons.Activities.Sequence (vm, name)
	if not sequence then return 0 end

	vm:SendViewModelMatchingSequence (sequence)
	vm:SetPlaybackRate (1)
	local duration = vm:SequenceDuration (sequence)
	self:SetNextIdle (CurTime () + duration)
	return duration
end

function SWEP:Deploy ()
	self:SetReloadStage (RELOAD_NONE)
	local duration = self:PlayTF ("draw")
	self:SetNextPrimaryFire (CurTime () + (self.DeployTime or duration))
	return true
end

function SWEP:Holster ()
	self:SetReloadStage (RELOAD_NONE)
	return true
end

function SWEP:PrimaryAttack ()
	if self:GetReloadStage () ~= RELOAD_NONE then
		-- a shell reload gives way to firing, as TF2's does
		if self:Clip1 () <= 0 then return end
		self:SetReloadStage (RELOAD_NONE)
	end
	if self:Clip1 () <= 0 then
		self:Reload ()
		return
	end
	local primary = self.Primary
	self:ShootBullet (primary.Damage, primary.Bullets, primary.Spread, primary.Ammo)
	self:TakePrimaryAmmo (1)
	if primary.Sound ~= "" then self:EmitSound (primary.Sound) end
	self:PlayTF ("fire")
	self:GetOwner ():SetAnimation (PLAYER_ATTACK1)
	self:SetNextPrimaryFire (CurTime () + primary.Delay)
end

-- weapon_base's plays ACT_VM_PRIMARYATTACK, which the class arms have not
function SWEP:ShootEffects ()
	self:GetOwner ():MuzzleFlash ()
end

function SWEP:SecondaryAttack ()
end

function SWEP:CanLoad ()
	local owner = self:GetOwner ()
	return self:Clip1 () < self.Primary.ClipSize and owner:GetAmmoCount (self.Primary.Ammo) > 0
end

function SWEP:Reload ()
	if self:GetReloadStage () ~= RELOAD_NONE or not self:CanLoad () then return end
	if CurTime () < self:GetNextPrimaryFire () then return end
	if not self.TFReloadsSingly then
		self:LoadAll ()
		return
	end
	self:SetReloadStage (RELOAD_START)
	self:SetNextReloadStep (CurTime () + self:PlayTF ("reloadStart"))
end

function SWEP:LoadAll ()
	local owner = self:GetOwner ()
	local taken = math.min (self.Primary.ClipSize - self:Clip1 (), owner:GetAmmoCount (self.Primary.Ammo))
	local duration = self:PlayTF ("reload")
	self:SetClip1 (self:Clip1 () + taken)
	owner:RemoveAmmo (taken, self.Primary.Ammo)
	self:SetNextPrimaryFire (CurTime () + duration)
end

-- One shell a loop: start, a loop a shell until full or out, end
function SWEP:StepReload ()
	local stage = self:GetReloadStage ()
	if stage == RELOAD_NONE or CurTime () < self:GetNextReloadStep () then return end
	if stage == RELOAD_LOOP then
		self:SetClip1 (self:Clip1 () + 1)
		self:GetOwner ():RemoveAmmo (1, self.Primary.Ammo)
	end
	if stage == RELOAD_END then
		self:SetReloadStage (RELOAD_NONE)
		return
	end
	if self:CanLoad () then
		self:SetReloadStage (RELOAD_LOOP)
		self:SetNextReloadStep (CurTime () + self:PlayTF ("reload"))
		return
	end
	self:SetReloadStage (RELOAD_END)
	self:SetNextReloadStep (CurTime () + self:PlayTF ("reloadEnd"))
end

function SWEP:Think ()
	self:StepReload ()
	if self:GetReloadStage () == RELOAD_NONE and CurTime () >= self:GetNextIdle () then
		local duration = self:PlayTF ("idle")
		if duration <= 0 then self:SetNextIdle (math.huge) end
	end
end

if CLIENT then
	function SWEP:PreDrawViewModel (vm, weapon, ply)
		TFWeapons.Hands.PreDraw (self, vm)
	end

	function SWEP:PostDrawViewModel (vm, weapon, ply)
		TFWeapons.Hands.Draw (self, vm, ply)
	end
end
