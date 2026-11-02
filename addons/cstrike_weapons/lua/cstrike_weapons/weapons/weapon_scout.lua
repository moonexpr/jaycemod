-- weapon_scout: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "SCHMIDT SCOUT"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 0
SWEP.SlotPos = 0
SWEP.ViewModel = Model("models/weapons/cstrike/c_snip_scout.mdl")
SWEP.WorldModel = Model("models/weapons/w_snip_scout.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "ar2"
SWEP.DrawCrosshair = false
SWEP.CStrikeType = "SniperRifle"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 2750
SWEP.MaxPlayerSpeed = 260
SWEP.ReloadTime = 3.5
SWEP.SingleShotSound = "Weapon_Scout.Single"
SWEP.SpecialSound3 = "Default.Zoom"
SWEP.Primary = { ClipSize = 10, DefaultClip = 10, Automatic = false, Ammo = "BULLET_PLAYER_762MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 75,
		BulletCount = 1,
		CycleTime = 1.25,
		Penetration = 3,
		Range = 8192,
		RangeModifier = 0.98,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.02378,
		Fire = 0.06667,
		Jump = 0.38195,
		Ladder = 0.09549,
		Land = 0.03819,
		Move = 0.19097,
		RecoveryCrouch = 0.17681,
		RecoveryStand = 0.24753,
		Spread = 0.0003,
		Stand = 0.0317,
	},
	AlternateAccuracy = {
		Crouch = 0.003,
		Stand = 0.004,
	},
	Kick = {
		PunchMin = 2,
		PunchMax = 2,
	},
	Mode = {
		Type = "scope",
		Speed = 220,
		FOV = { 40, 15 },
	},
}
SWEP.SoldierClip = 10
SWEP.SoldierInterval = 1.25
SWEP.SoldierSpread = 1.8328395059421
SWEP.SoldierReload = 3.5
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_Scout.Single"
SWEP.SoldierDamage = 75
SWEP.SoldierHoldType = "ar2"
SWEP.SoldierBullets = 1
SWEP.AIReach = 3000
SWEP.AIChase = 2000
SWEP.AIAvoid = 750
SWEP.AICone = 3.6656790118841
