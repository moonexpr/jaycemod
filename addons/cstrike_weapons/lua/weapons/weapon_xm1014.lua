AddCSLuaFile()

-- weapon_xm1014: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "LEONE YG1265 AUTO SHOTGUN"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_shot_xm1014.mdl")
SWEP.WorldModel = Model("models/weapons/w_shot_xm1014.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "shotgun"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Shotgun"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 3000
SWEP.MaxPlayerSpeed = 240
SWEP.ReloadTime = 3.5
SWEP.SingleShotSound = "Weapon_XM1014.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 7, DefaultClip = 7, Automatic = true, Ammo = "BULLET_PLAYER_BUCKSHOT" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 22,
		BulletCount = 6,
		CycleTime = 0.25,
		Penetration = 1,
		Range = 3000,
		RangeModifier = 0.7,
		FullAuto = true,
	},
	Accuracy = {
		Crouch = 0.0075,
		Fire = 0.03644,
		Jump = 0.41176,
		Ladder = 0.07721,
		Land = 0.08235,
		Move = 0.03544,
		RecoveryCrouch = 0.32894,
		RecoveryStand = 0.46052,
		Spread = 0.04,
		Stand = 0.01,
	},
	Kick = {
		PunchMin = 3,
		PunchMax = 5,
	},
}
SWEP.SoldierClip = 7
SWEP.SoldierInterval = 0.25
SWEP.SoldierSpread = 2.8624052261117
SWEP.SoldierReload = 3.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_XM1014.Single"
SWEP.SoldierDamage = 22
SWEP.SoldierHoldType = "shotgun"
SWEP.SoldierBullets = 6
SWEP.AIAutomatic = true
SWEP.AIReach = 325
SWEP.AIChase = 250
SWEP.AIAvoid = 175
SWEP.AICone = 5.7248104522235
