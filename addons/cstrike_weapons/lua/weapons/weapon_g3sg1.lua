AddCSLuaFile()

-- weapon_g3sg1: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "D3/AU-1"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_snip_g3sg1.mdl")
SWEP.WorldModel = Model("models/weapons/w_snip_g3sg1.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = false
SWEP.CStrikeType = "SniperRifle"
SWEP.CStrikeTeam = "TERRORIST"
SWEP.Price = 5000
SWEP.MaxPlayerSpeed = 210
SWEP.ReloadTime = 3.5
SWEP.SingleShotSound = "Weapon_G3SG1.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 20, DefaultClip = 20, Automatic = true, Ammo = "BULLET_PLAYER_762MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 80,
		BulletCount = 1,
		CycleTime = 0.25,
		Penetration = 3,
		Range = 8192,
		RangeModifier = 0.98,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.01935,
		Fire = 0.04989,
		Jump = 0.46557,
		Ladder = 0.11639,
		Land = 0.04656,
		Move = 0.23279,
		RecoveryCrouch = 0.22245,
		RecoveryStand = 0.31142,
		Spread = 0.0003,
		Stand = 0.0258,
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
SWEP.SoldierClip = 20
SWEP.SoldierInterval = 0.25
SWEP.SoldierSpread = 1.4950804190287
SWEP.SoldierReload = 3.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_G3SG1.Single"
SWEP.SoldierDamage = 80
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIAutomatic = true
SWEP.AIReach = 3000
SWEP.AIChase = 2000
SWEP.AIAvoid = 750
SWEP.AICone = 2.9901608380574
