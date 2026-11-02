-- weapon_aug: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "BULLPUP"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_rif_aug.mdl")
SWEP.WorldModel = Model("models/weapons/w_rif_aug.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Rifle"
SWEP.CStrikeTeam = "CT"
SWEP.Price = 3500
SWEP.MaxPlayerSpeed = 221
SWEP.ReloadTime = 2.5
SWEP.SingleShotSound = "Weapon_AUG.Single"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_762MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 32,
		BulletCount = 1,
		CycleTime = 0.09,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.96,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.00412,
		Fire = 0.0109,
		Jump = 0.36936,
		Ladder = 0.09234,
		Land = 0.07387,
		Move = 0.07268,
		RecoveryCrouch = 0.30263,
		RecoveryStand = 0.42368,
		Spread = 0.0006,
		Stand = 0.00549,
	},
	AlternateAccuracy = {
		Crouch = 0.00288,
		Stand = 0.00385,
	},
	Kick = {
		UpBase = 0.65,
		LateralBase = 0.325,
		UpModifier = 0.175,
		LateralModifier = 0.0325,
		UpMax = 3.5,
		LateralMax = 2,
		Flip = 8,
	},
	Mode = {
		Type = "scope",
		Speed = 221,
		FOV = { 55 },
	},
}
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.09
SWEP.SoldierSpread = 0.34892698359771
SWEP.SoldierReload = 2.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_AUG.Single"
SWEP.SoldierDamage = 32
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1500
SWEP.AIChase = 1000
SWEP.AIAvoid = 750
SWEP.AICone = 0.69785396719543
