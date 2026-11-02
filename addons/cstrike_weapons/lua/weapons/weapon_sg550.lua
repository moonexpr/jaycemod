AddCSLuaFile()

-- weapon_sg550: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "KRIEG 550 COMMANDO"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_snip_sg550.mdl")
SWEP.WorldModel = Model("models/weapons/w_snip_sg550.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = false
SWEP.CStrikeType = "SniperRifle"
SWEP.CStrikeTeam = "CT"
SWEP.Price = 4200
SWEP.MaxPlayerSpeed = 210
SWEP.ReloadTime = 3.5
SWEP.SingleShotSound = "Weapon_SG550.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 30, DefaultClip = 30, Automatic = true, Ammo = "BULLET_PLAYER_556MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 70,
		BulletCount = 1,
		CycleTime = 0.25,
		Penetration = 2,
		Range = 8192,
		RangeModifier = 0.98,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.01928,
		Fire = 0.03829,
		Jump = 0.43727,
		Ladder = 0.10932,
		Land = 0.04373,
		Move = 0.21864,
		RecoveryCrouch = 0.2097,
		RecoveryStand = 0.29358,
		Spread = 0.0003,
		Stand = 0.0257,
	},
	AlternateAccuracy = {
		Crouch = 0.0015,
		Stand = 0.002,
	},
	Kick = {
		PunchMin = 0.75,
		PunchMax = 1.75,
	},
	Mode = {
		Type = "scope",
		Speed = 150,
		FOV = { 40, 15 },
	},
}
SWEP.SoldierClip = 30
SWEP.SoldierInterval = 0.25
SWEP.SoldierSpread = 1.4893547265514
SWEP.SoldierReload = 3.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_SG550.Single"
SWEP.SoldierDamage = 70
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 3000
SWEP.AIChase = 2000
SWEP.AIAvoid = 750
SWEP.AICone = 2.9787094531028
