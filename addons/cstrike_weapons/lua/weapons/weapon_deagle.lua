AddCSLuaFile()

-- weapon_deagle: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "NIGHT HAWK .50C"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 1
SWEP.SlotPos = 1
SWEP.ViewModel = Model("models/weapons/cstrike/c_pist_deagle.mdl")
SWEP.WorldModel = Model("models/weapons/w_pist_deagle.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Pistol"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 650
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.2
SWEP.SingleShotSound = "Weapon_DEagle.Single"
SWEP.Primary = { ClipSize = 7, DefaultClip = 7, Automatic = false, Ammo = "BULLET_PLAYER_50AE" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 54,
		BulletCount = 1,
		CycleTime = 0.225,
		Penetration = 2,
		Range = 4096,
		RangeModifier = 0.81,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.00975,
		Fire = 0.055,
		Jump = 0.345,
		Ladder = 0.023,
		Land = 0.069,
		Move = 0.0207,
		RecoveryCrouch = 0.32236,
		RecoveryStand = 0.38683,
		Spread = 0.004,
		Stand = 0.013,
	},
	Kick = {
		PunchMin = 2,
		PunchMax = 2,
	},
}
SWEP.SoldierClip = 7
SWEP.SoldierInterval = 0.225
SWEP.SoldierSpread = 0.97393443660116
SWEP.SoldierReload = 2.2
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_DEagle.Single"
SWEP.SoldierDamage = 54
SWEP.SoldierHoldType = "pistol"
SWEP.SoldierBullets = 1
SWEP.AIReach = 750
SWEP.AIChase = 500
SWEP.AIAvoid = 350
SWEP.AICone = 1.9478688732023
