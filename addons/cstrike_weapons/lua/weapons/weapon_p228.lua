AddCSLuaFile()

-- weapon_p228: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "228 COMPACT"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 1
SWEP.SlotPos = 1
SWEP.ViewModel = Model("models/weapons/cstrike/c_pist_p228.mdl")
SWEP.WorldModel = Model("models/weapons/w_pist_p228.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Pistol"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 600
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.2
SWEP.SingleShotSound = "Weapon_P228.Single"
SWEP.Primary = { ClipSize = 13, DefaultClip = 13, Automatic = false, Ammo = "BULLET_PLAYER_357SIG" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 40,
		BulletCount = 1,
		CycleTime = 0.15,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.8,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.00825,
		Fire = 0.03318,
		Jump = 0.285,
		Ladder = 0.019,
		Land = 0.057,
		Move = 0.0171,
		RecoveryCrouch = 0.23026,
		RecoveryStand = 0.27631,
		Spread = 0.004,
		Stand = 0.011,
	},
	Kick = {
		PunchMin = 2,
		PunchMax = 2,
	},
}
SWEP.SoldierClip = 13
SWEP.SoldierInterval = 0.15
SWEP.SoldierSpread = 0.85937224364468
SWEP.SoldierReload = 2.2
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_P228.Single"
SWEP.SoldierDamage = 40
SWEP.SoldierHoldType = "pistol"
SWEP.SoldierBullets = 1
SWEP.AIReach = 750
SWEP.AIChase = 500
SWEP.AIAvoid = 350
SWEP.AICone = 1.7187444872894
