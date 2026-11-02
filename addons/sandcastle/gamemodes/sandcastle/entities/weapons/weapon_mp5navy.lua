-- weapon_mp5navy: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "K&M SUB-MACHINE GUN"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_smg_mp5.mdl")
SWEP.WorldModel = Model("models/weapons/w_smg_mp5.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "smg"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "SubMachinegun"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 1500
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.6
SWEP.SingleShotSound = "Weapon_MP5Navy.Single"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_9MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 26,
		BulletCount = 1,
		CycleTime = 0.08,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.84,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.01289,
		Fire = 0.00638,
		Jump = 0.23025,
		Ladder = 0.05756,
		Land = 0.04605,
		Move = 0.01785,
		RecoveryCrouch = 0.2796,
		RecoveryStand = 0.39144,
		Spread = 0.001,
		Stand = 0.01718,
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
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.08
SWEP.SoldierSpread = 1.0415225362883
SWEP.SoldierReload = 2.6
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_MP5Navy.Single"
SWEP.SoldierDamage = 26
SWEP.SoldierHoldType = "smg"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1000
SWEP.AIChase = 700
SWEP.AIAvoid = 500
SWEP.AICone = 2.0830450725766
