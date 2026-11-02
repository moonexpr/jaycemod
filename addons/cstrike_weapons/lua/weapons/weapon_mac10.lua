AddCSLuaFile()

-- weapon_mac10: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "INGRAM MAC-10"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_smg_mac10.mdl")
SWEP.WorldModel = Model("models/weapons/w_smg_mac10.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "smg"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "SubMachinegun"
SWEP.CStrikeTeam = "TERRORIST"
SWEP.Price = 1400
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.6
SWEP.SingleShotSound = "Weapon_MAC10.Single"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_45ACP" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 29,
		BulletCount = 1,
		CycleTime = 0.075,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.82,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.01425,
		Fire = 0.00845,
		Jump = 0.13704,
		Ladder = 0.03426,
		Land = 0.02741,
		Move = 0.0062,
		RecoveryCrouch = 0.25263,
		RecoveryStand = 0.35368,
		Spread = 0.001,
		Stand = 0.019,
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
SWEP.SoldierInterval = 0.075
SWEP.SoldierSpread = 1.1457628381751
SWEP.SoldierReload = 2.6
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_MAC10.Single"
SWEP.SoldierDamage = 29
SWEP.SoldierHoldType = "smg"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1000
SWEP.AIChase = 700
SWEP.AIAvoid = 500
SWEP.AICone = 2.2915256763502
