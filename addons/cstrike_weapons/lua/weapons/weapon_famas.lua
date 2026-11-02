AddCSLuaFile()

-- weapon_famas: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "CLARION 5.56"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_rif_famas.mdl")
SWEP.WorldModel = Model("models/weapons/w_rif_famas.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Rifle"
SWEP.CStrikeTeam = "CT"
SWEP.Price = 2250
SWEP.MaxPlayerSpeed = 220
SWEP.ReloadTime = 2.5
SWEP.SingleShotSound = "Weapon_FAMAS.Single"
SWEP.Primary = { ClipSize = 25, DefaultClip = 25, Automatic = true, Ammo = "BULLET_PLAYER_556MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 30,
		BulletCount = 1,
		CycleTime = 0.09,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.96,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.00412,
		Fire = 0.01186,
		Jump = 0.36527,
		Ladder = 0.09132,
		Land = 0.07305,
		Move = 0.0698,
		RecoveryCrouch = 0.30328,
		RecoveryStand = 0.4246,
		Spread = 0.0006,
		Stand = 0.00549,
	},
	AlternateAccuracy = {
		Fire = 0.00593,
	},
	Kick = {
		UpBase = 0.65,
		LateralBase = 0.35,
		UpModifier = 0.25,
		LateralModifier = 0.015,
		UpMax = 3.5,
		LateralMax = 2.25,
		Flip = 7,
	},
	Mode = {
		Type = "burst",
		Burst = {
			Rounds = 3,
			Gap = 0.075,
			After = 0.55,
		},
	},
}
SWEP.SoldierClip = 25
SWEP.SoldierInterval = 0.09
SWEP.SoldierSpread = 0.34892698359771
SWEP.SoldierReload = 2.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_FAMAS.Single"
SWEP.SoldierDamage = 30
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1500
SWEP.AIChase = 1000
SWEP.AIAvoid = 750
SWEP.AICone = 0.69785396719543
