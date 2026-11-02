-- weapon_p90: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "ES C90"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_smg_p90.mdl")
SWEP.WorldModel = Model("models/weapons/w_smg_p90.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "smg"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "SubMachinegun"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 2350
SWEP.MaxPlayerSpeed = 245
SWEP.ReloadTime = 2.6
SWEP.SingleShotSound = "Weapon_P90.Single"
SWEP.Primary = { ClipSize = 50, DefaultClip = 50, Automatic = true, Ammo = "BULLET_PLAYER_57MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 26,
		BulletCount = 1,
		CycleTime = 0.07,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.84,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.01463,
		Fire = 0.00732,
		Jump = 0.16494,
		Ladder = 0.04124,
		Land = 0.03299,
		Move = 0.01062,
		RecoveryCrouch = 0.23289,
		RecoveryStand = 0.32605,
		Spread = 0.001,
		Stand = 0.01951,
	},
	Kick = {
		UpBase = 0.45,
		LateralBase = 0.3,
		UpModifier = 0.2,
		LateralModifier = 0.03,
		UpMax = 3,
		LateralMax = 2.5,
		Flip = 10,
	},
}
SWEP.SoldierClip = 50
SWEP.SoldierInterval = 0.07
SWEP.SoldierSpread = 1.1749717017196
SWEP.SoldierReload = 2.6
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_P90.Single"
SWEP.SoldierDamage = 26
SWEP.SoldierHoldType = "smg"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1000
SWEP.AIChase = 700
SWEP.AIAvoid = 500
SWEP.AICone = 2.3499434034392
