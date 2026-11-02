-- weapon_glock: a standard CS:S SWEP; its base owns shared behavior.

SWEP.Base = "base_cstrike"
SWEP.CStrikeWeapon = true
SWEP.PrintName = "9X19MM SIDEARM"
SWEP.Category = "Counter-Strike: Source"
SWEP.Spawnable = true
SWEP.Slot = 1
SWEP.SlotPos = 1
SWEP.ViewModel = Model("models/weapons/cstrike/c_pist_glock18.mdl")
SWEP.WorldModel = Model("models/weapons/w_pist_glock18.mdl")
SWEP.ViewModelFOV = 54
SWEP.ViewModelFlip = false
SWEP.UseHands = true
SWEP.HoldType = "pistol"
SWEP.DrawCrosshair = true
SWEP.CStrikeType = "Pistol"
SWEP.CStrikeTeam = "ANY"
SWEP.Price = 400
SWEP.MaxPlayerSpeed = 250
SWEP.ReloadTime = 2.2
SWEP.SingleShotSound = "Weapon_Glock.Single"
SWEP.Primary = { ClipSize = 20, DefaultClip = 20, Automatic = false, Ammo = "BULLET_PLAYER_9MM" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Stats = {
	Ballistics = {
		Damage = 25,
		BulletCount = 1,
		CycleTime = 0.15,
		Penetration = 1,
		Range = 4096,
		RangeModifier = 0.75,
		FullAuto = false,
	},
	Accuracy = {
		Crouch = 0.0075,
		Fire = 0.03167,
		Jump = 0.2775,
		Ladder = 0.0185,
		Land = 0.0555,
		Move = 0.01665,
		RecoveryCrouch = 0.21875,
		RecoveryStand = 0.26249,
		Spread = 0.004,
		Stand = 0.01,
	},
	AlternateAccuracy = {
		Fire = 0.02217,
	},
	Kick = {
		PunchMin = 1,
		PunchMax = 1,
	},
	Mode = {
		Type = "burst",
		Burst = {
			Rounds = 3,
			Gap = 0.05,
			After = 0.5,
		},
	},
}
SWEP.SoldierClip = 20
SWEP.SoldierInterval = 0.15
SWEP.SoldierSpread = 0.80208851280564
SWEP.SoldierReload = 2.2
SWEP.SoldierTracer = "Tracer"
SWEP.SoldierSound = "Weapon_Glock.Single"
SWEP.SoldierDamage = 25
SWEP.SoldierHoldType = "pistol"
SWEP.SoldierBullets = 1
SWEP.AIReach = 750
SWEP.AIChase = 500
SWEP.AIAvoid = 350
SWEP.AICone = 1.6041770256113
