-- weapon_fiveseven: a standard CS:S SWEP; its base owns shared behavior.
AddCSLuaFile()

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "ES FIVE-SEVEN"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 1
SWEP.SlotPos = 1
SWEP.ViewModel = Model("models/weapons/cstrike/c_pist_fiveseven.mdl")
SWEP.WorldModel = Model("models/weapons/w_pist_fiveseven.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Pistol"
SWEP.CStrikeTeam = "CT"
SWEP.Price = 750
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.2
SWEP.SingleShotSound = "Weapon_FiveSeven.Single"
SWEP.Primary = { ClipSize = 20, DefaultClip = 20, Automatic = false, Ammo = "BULLET_PLAYER_57MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 25,
		BulletCount = 1,
		CycleTime = 0.15,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.885,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.006,
		Fire = 0.05883,
		Jump = 0.25635,
		Ladder = 0.01709,
		Land = 0.05127,
		Move = 0.01538,
		RecoveryCrouch = 0.18628,
		RecoveryStand = 0.22353,
		Spread = 0.004,
		Stand = 0.01,
	},
	Kick = {
		PunchMin = 2,
		PunchMax = 2,
	},
}
SWEP.TwistCondition = 30
SWEP.TwistDuration = 3
SWEP.SoldierClip = 20
SWEP.SoldierInterval = 0.15
SWEP.SoldierSpread = 0.80208851280564
SWEP.SoldierReload = 2.2
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_FiveSeven.Single"
SWEP.SoldierDamage = 25
SWEP.SoldierHoldType = "pistol"
SWEP.SoldierBullets = 1
SWEP.AIReach = 750
SWEP.AIChase = 500
SWEP.AIAvoid = 350
SWEP.AICone = 1.6041770256113
