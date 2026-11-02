AddCSLuaFile()

-- weapon_tmp: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "SCHMIDT MACHINE PISTOL"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_smg_tmp.mdl")
SWEP.WorldModel = Model("models/weapons/w_smg_tmp.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "smg"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "SubMachinegun"
SWEP.CStrikeTeam = "CT"
SWEP.Price = 1250
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.6
SWEP.SingleShotSound = "Weapon_TMP.Single"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_9MM" }
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
		Crouch = 0.015,
		Fire = 0.01594,
		Jump = 0.1118,
		Ladder = 0.02795,
		Land = 0.02236,
		Move = 0.00389,
		RecoveryCrouch = 0.15131,
		RecoveryStand = 0.21184,
		Spread = 0.001,
		Stand = 0.02,
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
SWEP.TwistCondition = 25
SWEP.TwistDuration = 2
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.07
SWEP.SoldierSpread = 1.203034544489
SWEP.SoldierReload = 2.6
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_TMP.Single"
SWEP.SoldierDamage = 26
SWEP.SoldierHoldType = "smg"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 1000
SWEP.AIChase = 700
SWEP.AIAvoid = 500
SWEP.AICone = 2.406069088978
