-- weapon_galil: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "IDF DEFENDER"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_rif_galil.mdl")
SWEP.WorldModel = Model("models/weapons/w_rif_galil.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Rifle"
SWEP.CStrikeTeam = "TERRORIST"
SWEP.Price = 2000
SWEP.MaxPlayerSpeed = 215
SWEP.ReloadTime = 2.5
SWEP.SingleShotSound = "Weapon_Galil.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 35, DefaultClip = 35, Automatic = true, Ammo = "BULLET_PLAYER_556MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 30,
		BulletCount = 1,
		CycleTime = 0.09,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.98,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.00939,
		Fire = 0.00984,
		Jump = 0.45434,
		Ladder = 0.11358,
		Land = 0.09087,
		Move = 0.10561,
		RecoveryCrouch = 0.35197,
		RecoveryStand = 0.49275,
		Spread = 0.0006,
		Stand = 0.01253,
	},
	Kick = {
		UpBase = 1,
		LateralBase = 0.375,
		UpModifier = 0.175,
		LateralModifier = 0.0375,
		UpMax = 5.75,
		LateralMax = 1.75,
		Flip = 8,
	},
}
SWEP.SoldierClip = 35
SWEP.SoldierInterval = 0.09
SWEP.SoldierSpread = 0.75225035845064
SWEP.SoldierReload = 2.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_Galil.Single"
SWEP.SoldierDamage = 30
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1500
SWEP.AIChase = 1000
SWEP.AIAvoid = 750
SWEP.AICone = 1.5045007169013
