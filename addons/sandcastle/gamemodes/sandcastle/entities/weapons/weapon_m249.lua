-- weapon_m249: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "M249"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_mach_m249para.mdl")
SWEP.WorldModel = Model("models/weapons/w_mach_m249para.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Machinegun"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 5750
SWEP.MaxPlayerSpeed = 220
SWEP.ReloadTime = 4.7
SWEP.SingleShotSound = "Weapon_M249.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 100, DefaultClip = 100, Automatic = true, Ammo = "BULLET_PLAYER_556MM_BOX" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 35,
		BulletCount = 1,
		CycleTime = 0.08,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.97,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.00763,
		Fire = 0.00427,
		Jump = 0.7083,
		Ladder = 0.13281,
		Land = 0.14166,
		Move = 0.10618,
		RecoveryCrouch = 0.5592,
		RecoveryStand = 0.78288,
		Spread = 0.002,
		Stand = 0.01017,
	},
	Kick = {
		UpBase = 0.8,
		LateralBase = 0.65,
		UpModifier = 0.45,
		LateralModifier = 0.125,
		UpMax = 5,
		LateralMax = 3.5,
		Flip = 8,
	},
}
SWEP.SoldierClip = 100
SWEP.SoldierInterval = 0.08
SWEP.SoldierSpread = 0.69725521479938
SWEP.SoldierReload = 4.7
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_M249.Single"
SWEP.SoldierDamage = 35
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1500
SWEP.AIChase = 1000
SWEP.AIAvoid = 750
SWEP.AICone = 1.3945104295988
