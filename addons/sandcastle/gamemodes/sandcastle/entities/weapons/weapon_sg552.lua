-- weapon_sg552: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "KRIEG 552"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_rif_sg552.mdl")
SWEP.WorldModel = Model("models/weapons/w_rif_sg552.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Rifle"
SWEP.CStrikeTeam = "TERRORIST"
SWEP.Price = 3500
SWEP.MaxPlayerSpeed = 235
SWEP.ReloadTime = 2.5
SWEP.SingleShotSound = "Weapon_SG552.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_556MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 33,
		BulletCount = 1,
		CycleTime = 0.09,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.955,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.00405,
		Fire = 0.01227,
		Jump = 0.33464,
		Ladder = 0.08366,
		Land = 0.06693,
		Move = 0.06132,
		RecoveryCrouch = 0.27631,
		RecoveryStand = 0.38683,
		Spread = 0.0006,
		Stand = 0.0054,
	},
	AlternateAccuracy = {
		Crouch = 0.00284,
		Fire = 0.00859,
		Stand = 0.00378,
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
	Mode = {
		Type = "scope",
		Speed = 235,
		FOV = { 55 },
	},
}
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.09
SWEP.SoldierSpread = 0.34377055187147
SWEP.SoldierReload = 2.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_SG552.Single"
SWEP.SoldierDamage = 33
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1500
SWEP.AIChase = 1000
SWEP.AIAvoid = 750
SWEP.AICone = 0.68754110374295
