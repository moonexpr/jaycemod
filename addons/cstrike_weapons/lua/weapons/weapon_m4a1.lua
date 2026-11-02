AddCSLuaFile()

-- weapon_m4a1: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "MAVERICK M4A1 CARBINE"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_rif_m4a1.mdl")
SWEP.WorldModel = Model("models/weapons/w_rif_m4a1.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Rifle"
SWEP.CStrikeTeam = "CT"
SWEP.Price = 3100
SWEP.MaxPlayerSpeed = 230
SWEP.ReloadTime = 2.5
SWEP.SingleShotSound = "Weapon_M4A1.Single"
SWEP.SpecialSound1 = "Weapon_M4A1.Silenced"
SWEP.SpecialSound2 = "Weapon_M4A1.Silencer_Off"
SWEP.SpecialSound3 = "Weapon_M4A1.Silencer_On"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_556MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 33,
		BulletCount = 1,
		CycleTime = 0.09,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.97,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.00525,
		Fire = 0.01266,
		Jump = 0.34151,
		Ladder = 0.08538,
		Land = 0.0683,
		Move = 0.06872,
		RecoveryCrouch = 0.26973,
		RecoveryStand = 0.37762,
		Spread = 0.0006,
		Stand = 0.007,
	},
	AlternateAccuracy = {
		Fire = 0.01165,
		Jump = 0.34846,
		Ladder = 0.08712,
		Land = 0.06969,
		Move = 0.07039,
		Spread = 0.00054,
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
		Type = "silencer",
	},
}
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.09
SWEP.SoldierSpread = 0.43543954076593
SWEP.SoldierReload = 2.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_M4A1.Single"
SWEP.SoldierDamage = 33
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1500
SWEP.AIChase = 1000
SWEP.AIAvoid = 750
SWEP.AICone = 0.87087908153186
