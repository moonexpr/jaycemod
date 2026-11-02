-- weapon_ak47: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "CV-47"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_rif_ak47.mdl")
SWEP.WorldModel = Model("models/weapons/w_rif_ak47.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Rifle"
SWEP.CStrikeTeam = "TERRORIST"
SWEP.Price = 2500
SWEP.MaxPlayerSpeed = 221
SWEP.ReloadTime = 2.5
SWEP.SingleShotSound = "Weapon_AK47.Single"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_762MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 36,
		BulletCount = 1,
		CycleTime = 0.1,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.98,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.00687,
		Fire = 0.01158,
		Jump = 0.43044,
		Ladder = 0.10761,
		Land = 0.08609,
		Move = 0.09222,
		RecoveryCrouch = 0.34868,
		RecoveryStand = 0.48815,
		Spread = 0.0006,
		Stand = 0.00916,
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
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.1
SWEP.SoldierSpread = 0.55918905282965
SWEP.SoldierReload = 2.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_AK47.Single"
SWEP.SoldierDamage = 36
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1500
SWEP.AIChase = 1000
SWEP.AIAvoid = 750
SWEP.AICone = 1.1183781056593
